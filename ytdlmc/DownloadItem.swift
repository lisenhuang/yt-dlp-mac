import Foundation

enum DownloadStatus: Equatable {
    case queued
    case fetchingInfo
    case downloading
    case merging
    case completed
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .fetchingInfo, .downloading, .merging: return true
        default: return false
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable, Codable {
    case best = "Best"
    case hd1080 = "1080p"
    case hd720 = "720p"
    case sd480 = "480p"
    case audioOnly = "Audio Only"

    var id: String { rawValue }

    var formatString: String {
        // Prefer QuickTime-friendly H.264 (avc1) video + AAC (m4a) audio, but
        // always fall back to *any* bestvideo+bestaudio pair before dropping to a
        // single muxed stream, so videos that only offer AV1/VP9/Opus still
        // download at full quality instead of failing or grabbing a ≤720p mux.
        switch self {
        case .best:
            "bestvideo[vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo+bestaudio/best"
        case .hd1080:
            "bestvideo[height<=1080][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<=1080]+bestaudio/best[height<=1080]/best"
        case .hd720:
            "bestvideo[height<=720][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best[height<=720]/best"
        case .sd480:
            "bestvideo[height<=480][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<=480]+bestaudio/best[height<=480]/best"
        case .audioOnly:
            "bestaudio[ext=m4a]/bestaudio"
        }
    }

    var outputFormat: String {
        self == .audioOnly ? "m4a" : "mp4"
    }

    var icon: String {
        switch self {
        case .best: "sparkles"
        case .hd1080: "4k.tv"
        case .hd720: "tv"
        case .sd480: "tv.fill"
        case .audioOnly: "music.note"
        }
    }
}

@Observable
final class DownloadItem: Identifiable {
    let id = UUID()
    let url: String
    let quality: VideoQuality
    let addedAt = Date()

    var title: String = "Fetching info…"
    var status: DownloadStatus = .queued
    var progress: Double = 0
    var speed: String = ""
    var eta: String = ""
    var duration: String = ""
    var fileSize: String = ""
    var filePath: String?
    var downloadStage: String = ""
    var completedAt: Date?

    @ObservationIgnored var process: Process?
    @ObservationIgnored var workerTask: Task<Void, Never>?
    @ObservationIgnored var activityToken = UUID()

    init(url: String, quality: VideoQuality) {
        self.url = url
        self.quality = quality
    }
}

/// Thread-safe state container for tracking download process output.
final class ProcessOutputState: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var _buffer = ""
    nonisolated(unsafe) private var _lastFilePath: String?
    nonisolated(unsafe) private var _errorMessage: String?
    nonisolated(unsafe) private var _lastEmittedProgress: Double = -1

    nonisolated init() {}

    /// Coalesces the flood of `[download] N%` lines yt-dlp emits (often dozens
    /// per second per download). Returns `true` only when the progress has moved
    /// enough to be worth a hop to the main actor, keeping the UI responsive even
    /// with several concurrent downloads. Completion (`>= 1.0`) always emits.
    nonisolated func shouldEmitProgress(_ progress: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if progress >= 1.0 || abs(progress - _lastEmittedProgress) >= 0.005 {
            _lastEmittedProgress = progress
            return true
        }
        return false
    }

    nonisolated func appendToBuffer(_ string: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        _buffer += string
        var lines = _buffer.components(separatedBy: "\n")
        _buffer = lines.removeLast()
        return lines
    }

    nonisolated func flushBuffer() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let remaining = _buffer
        _buffer = ""
        return remaining.isEmpty ? [] : [remaining]
    }

    nonisolated var lastFilePath: String? {
        get { lock.lock(); defer { lock.unlock() }; return _lastFilePath }
        set { lock.lock(); defer { lock.unlock() }; _lastFilePath = newValue }
    }

    nonisolated var errorMessage: String? {
        get { lock.lock(); defer { lock.unlock() }; return _errorMessage }
        set { lock.lock(); defer { lock.unlock() }; _errorMessage = newValue }
    }
}
