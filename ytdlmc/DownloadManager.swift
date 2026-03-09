import Foundation
import SwiftUI
import UserNotifications

struct ParsedLine: Sendable {
    var progress: Double?
    var speed: String?
    var eta: String?
    var fileSize: String?
    var filePath: String?
    var isMerging = false
    var stage: String?

    nonisolated init(
        progress: Double? = nil, speed: String? = nil, eta: String? = nil,
        fileSize: String? = nil, filePath: String? = nil,
        isMerging: Bool = false, stage: String? = nil
    ) {
        self.progress = progress; self.speed = speed; self.eta = eta
        self.fileSize = fileSize; self.filePath = filePath
        self.isMerging = isMerging; self.stage = stage
    }
}

@Observable
final class DownloadManager {
    var downloads: [DownloadItem] = []
    var downloadPath: String
    var ytdlpPath: String
    var cookiesPath: String
    var maxConcurrentDownloads: Int
    var selectedQuality: VideoQuality
    var ytdlpFound: Bool = false

    init() {
        let defaults = UserDefaults.standard
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        self.downloadPath = defaults.string(forKey: "downloadPath") ?? "\(home)/Downloads"
        self.ytdlpPath = defaults.string(forKey: "ytdlpPath") ?? ""
        self.cookiesPath = defaults.string(forKey: "cookiesPath") ?? ""
        self.maxConcurrentDownloads = max(1, defaults.integer(forKey: "maxConcurrent") == 0 ? 3 : defaults.integer(forKey: "maxConcurrent"))
        self.selectedQuality = VideoQuality(rawValue: defaults.string(forKey: "quality") ?? "") ?? .best

        if ytdlpPath.isEmpty {
            ytdlpPath = Self.findYTDLP()
        }
        ytdlpFound = FileManager.default.isExecutableFile(atPath: ytdlpPath)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(downloadPath, forKey: "downloadPath")
        defaults.set(ytdlpPath, forKey: "ytdlpPath")
        defaults.set(cookiesPath, forKey: "cookiesPath")
        defaults.set(maxConcurrentDownloads, forKey: "maxConcurrent")
        defaults.set(selectedQuality.rawValue, forKey: "quality")
        ytdlpFound = FileManager.default.isExecutableFile(atPath: ytdlpPath)
    }

    // MARK: - yt-dlp Discovery

    nonisolated static func findYTDLP() -> String {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "yt-dlp"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.environment = shellEnvironment()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !result.isEmpty && FileManager.default.isExecutableFile(atPath: result) {
                return result
            }
        } catch {}
        return "/opt/homebrew/bin/yt-dlp"
    }

    nonisolated static func shellEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
        return env
    }

    // MARK: - Download Management

    var activeCount: Int {
        downloads.filter { $0.status.isActive }.count
    }

    func addDownload(url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let urls = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for u in urls {
            let item = DownloadItem(url: u, quality: selectedQuality)
            downloads.insert(item, at: 0)
        }
        startNextDownloads()
    }

    func cancelDownload(_ item: DownloadItem) {
        item.status = .cancelled
        item.process?.terminate()
        item.process = nil
        startNextDownloads()
    }

    func retryDownload(_ item: DownloadItem) {
        item.status = .queued
        item.progress = 0
        item.speed = ""
        item.eta = ""
        item.fileSize = ""
        item.downloadStage = ""
        startNextDownloads()
    }

    func removeDownload(_ item: DownloadItem) {
        if item.status.isActive {
            item.process?.terminate()
            item.process = nil
        }
        downloads.removeAll { $0.id == item.id }
        startNextDownloads()
    }

    func clearCompleted() {
        downloads.removeAll {
            if case .completed = $0.status { return true }
            return false
        }
    }

    func openFile(_ item: DownloadItem) {
        guard let path = item.filePath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func revealInFinder(_ item: DownloadItem) {
        if let path = item.filePath {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: downloadPath))
        }
    }

    func openDownloadFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: downloadPath))
    }

    // MARK: - Download Execution

    func startNextDownloads() {
        let slotsAvailable = maxConcurrentDownloads - activeCount
        guard slotsAvailable > 0 else { return }

        let queued = downloads.filter { $0.status == .queued }
        for item in queued.prefix(slotsAvailable) {
            beginDownload(item)
        }
    }

    private func beginDownload(_ item: DownloadItem) {
        item.status = .fetchingInfo

        let url = item.url
        let ytdlp = self.ytdlpPath
        let dest = self.downloadPath
        let cookies = self.cookiesPath
        let formatStr = item.quality.formatString
        let outputFmt = item.quality.outputFormat
        let isAudioOnly = item.quality == .audioOnly

        Task.detached {
            let title = Self.fetchTitleSync(url: url, ytdlpPath: ytdlp)
            await MainActor.run {
                item.title = title
                item.status = .downloading
                item.downloadStage = "Starting…"
            }

            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: ytdlp)
            process.environment = Self.shellEnvironment()

            var args: [String] = []
            if !cookies.isEmpty && FileManager.default.fileExists(atPath: cookies) {
                args += ["--cookies", cookies]
            }
            args += [
                "-f", formatStr,
                "--newline",
                "--no-colors",
                "--no-overwrites",
                "-o", "\(dest)/%(title)s.%(ext)s",
            ]
            if !isAudioOnly {
                args += ["--merge-output-format", outputFmt]
            }
            args.append(url)

            process.arguments = args
            process.standardOutput = pipe
            process.standardError = errorPipe

            await MainActor.run {
                item.process = process
            }

            do {
                try process.run()
            } catch {
                await MainActor.run {
                    item.status = .failed("Cannot start yt-dlp: \(error.localizedDescription)")
                    item.process = nil
                    self.startNextDownloads()
                }
                return
            }

            let state = ProcessOutputState()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }

                let lines = state.appendToBuffer(str)
                for line in lines {
                    let parsed = Self.parseLine(line)
                    if let path = parsed.filePath {
                        state.lastFilePath = path
                    }

                    Task { @MainActor in
                        if let p = parsed.progress {
                            item.progress = p
                        }
                        if let s = parsed.speed { item.speed = s }
                        if let e = parsed.eta { item.eta = e }
                        if let f = parsed.fileSize { item.fileSize = f }
                        if parsed.isMerging {
                            item.status = .merging
                            item.downloadStage = "Merging video & audio…"
                            item.progress = 0.95
                        }
                        if let stage = parsed.stage {
                            item.downloadStage = stage
                        }
                    }
                }
            }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let str = String(data: remaining, encoding: .utf8), !str.isEmpty {
                        let lines = state.appendToBuffer(str) + state.flushBuffer()
                        for line in lines {
                            let parsed = Self.parseLine(line)
                            if let path = parsed.filePath {
                                state.lastFilePath = path
                            }
                        }
                    }
                    continuation.resume()
                }
            }

            let exitCode = process.terminationStatus
            if exitCode != 0 {
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                state.errorMessage = errStr
                    .components(separatedBy: .newlines)
                    .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            }

            let finalPath = state.lastFilePath
            let finalError = state.errorMessage

            await MainActor.run {
                if exitCode == 0 {
                    item.status = .completed
                    item.progress = 1.0
                    item.speed = ""
                    item.eta = ""
                    item.downloadStage = ""
                    if let fp = finalPath {
                        item.filePath = fp.hasPrefix("/") ? fp : "\(dest)/\(fp)"
                    }
                    self.sendNotification(title: "Download Complete", body: item.title)
                } else if item.status != .cancelled {
                    item.status = .failed(finalError ?? "yt-dlp exited with code \(exitCode)")
                }
                item.process = nil
                self.startNextDownloads()
            }
        }
    }

    // MARK: - Output Parsing

    nonisolated static func parseLine(_ line: String) -> ParsedLine {
        var result = ParsedLine()

        if line.contains("[download]") && line.contains("%") {
            let pattern = #"\[download\]\s+([\d.]+)%\s+of\s+~?\s*([\d.]+\S+)\s+at\s+(\S+)\s+ETA\s+(\S+)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
            {
                if let r = Range(match.range(at: 1), in: line), let p = Double(line[r]) {
                    result.progress = p / 100.0
                }
                if let r = Range(match.range(at: 2), in: line) {
                    result.fileSize = String(line[r])
                }
                if let r = Range(match.range(at: 3), in: line) {
                    let s = String(line[r])
                    result.speed = s == "Unknown" ? "" : s
                }
                if let r = Range(match.range(at: 4), in: line) {
                    let e = String(line[r])
                    result.eta = e == "Unknown" ? "" : e
                }
            }
        }

        if line.contains("[download] Destination:") {
            let dest = line
                .replacingOccurrences(of: "[download] Destination: ", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !dest.isEmpty {
                result.filePath = dest
            }
            if dest.contains(".f") && (dest.hasSuffix(".mp4") || dest.hasSuffix(".webm")) {
                result.stage = "Downloading video…"
            } else if dest.hasSuffix(".m4a") || dest.hasSuffix(".webm") || dest.hasSuffix(".opus") {
                result.stage = "Downloading audio…"
            }
        }

        if line.contains("[Merger] Merging formats into") {
            result.isMerging = true
            if let start = line.range(of: "\""), let end = line[start.upperBound...].range(of: "\"") {
                result.filePath = String(line[start.upperBound..<end.lowerBound])
            }
        }

        if line.contains("has already been downloaded") {
            result.progress = 1.0
            result.stage = "Already downloaded"
        }

        return result
    }

    // MARK: - Title Fetching

    nonisolated static func fetchTitleSync(url: String, ytdlpPath: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = ["--print", "title", "--no-download", "--no-warnings", url]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.environment = shellEnvironment()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let title = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? "Unknown Title" : title
        } catch {
            return "Unknown Title"
        }
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - URL Validation

    nonisolated static func isValidYouTubeURL(_ url: String) -> Bool {
        let patterns = [
            #"youtube\.com/watch\?.*v="#,
            #"youtu\.be/"#,
            #"youtube\.com/shorts/"#,
            #"youtube\.com/playlist\?"#,
            #"youtube\.com/live/"#,
        ]
        let lowered = url.lowercased()
        return patterns.contains { (try? NSRegularExpression(pattern: $0))?.firstMatch(
            in: lowered, range: NSRange(lowered.startIndex..., in: lowered)
        ) != nil }
    }

    nonisolated static func extractYouTubeURL(from text: String) -> String? {
        let pattern = #"https?://(?:www\.)?(?:youtube\.com/(?:watch\?[^\s]+|shorts/[^\s]+|live/[^\s]+|playlist\?[^\s]+)|youtu\.be/[^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return String(text[range])
    }
}
