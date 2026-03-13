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

struct VideoMetadata: Sendable {
    var title: String
    var duration: String
    var fileSize: String
}

enum CookieSource: String, CaseIterable, Identifiable {
    case none = "None"
    case browser = "From Browser"
    case file = "From File"

    var id: String { rawValue }
}

enum BrowserChoice: String, CaseIterable, Identifiable {
    case chrome = "chrome"
    case firefox = "firefox"
    case safari = "safari"
    case edge = "edge"
    case brave = "brave"
    case opera = "opera"
    case chromium = "chromium"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        case .safari: "Safari"
        case .edge: "Edge"
        case .brave: "Brave"
        case .opera: "Opera"
        case .chromium: "Chromium"
        }
    }

    var icon: String {
        switch self {
        case .chrome: "globe"
        case .firefox: "flame"
        case .safari: "safari"
        case .edge: "globe"
        case .brave: "shield"
        case .opera: "globe"
        case .chromium: "globe"
        }
    }
}

@Observable
final class DownloadManager {
    var downloads: [DownloadItem] = []
    var downloadPath: String
    var ytdlpPath: String
    var cookiesPath: String
    var cookieSource: CookieSource
    var cookiesBrowser: BrowserChoice
    var maxConcurrentDownloads: Int
    var selectedQuality: VideoQuality
    var ytdlpFound: Bool = false
    var ytdlpSetupStatus: YTDLPSetupStatus = .unknown
    var ytdlpVersion: String = ""

    enum YTDLPSetupStatus: Equatable {
        case unknown
        case downloading
        case ready
        case failed(String)
    }

    nonisolated static let ytdlpDownloadURL = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

    nonisolated static var bundledYTDLPDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("yt-dlp-mac").path()
    }

    nonisolated static var bundledYTDLPPath: String {
        bundledYTDLPDirectory + "/yt-dlp"
    }

    init() {
        let defaults = UserDefaults.standard
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        self.downloadPath = defaults.string(forKey: "downloadPath") ?? "\(home)/Downloads"
        self.ytdlpPath = defaults.string(forKey: "ytdlpPath") ?? ""
        self.cookiesPath = defaults.string(forKey: "cookiesPath") ?? ""
        self.cookieSource = CookieSource(rawValue: defaults.string(forKey: "cookieSource") ?? "") ?? .none
        self.cookiesBrowser = BrowserChoice(rawValue: defaults.string(forKey: "cookiesBrowser") ?? "") ?? .chrome
        self.maxConcurrentDownloads = max(1, defaults.integer(forKey: "maxConcurrent") == 0 ? 3 : defaults.integer(forKey: "maxConcurrent"))
        self.selectedQuality = VideoQuality(rawValue: defaults.string(forKey: "quality") ?? "") ?? .best

        // Migrate: if user had a cookiesPath set but no cookieSource, default to .file
        if !cookiesPath.isEmpty && cookieSource == .none {
            cookieSource = .file
        }

        if ytdlpPath.isEmpty {
            ytdlpPath = Self.resolveYTDLPPath()
        }
        ytdlpFound = FileManager.default.isExecutableFile(atPath: ytdlpPath)
        ytdlpSetupStatus = ytdlpFound ? .ready : .unknown

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(downloadPath, forKey: "downloadPath")
        defaults.set(ytdlpPath, forKey: "ytdlpPath")
        defaults.set(cookiesPath, forKey: "cookiesPath")
        defaults.set(cookieSource.rawValue, forKey: "cookieSource")
        defaults.set(cookiesBrowser.rawValue, forKey: "cookiesBrowser")
        defaults.set(maxConcurrentDownloads, forKey: "maxConcurrent")
        defaults.set(selectedQuality.rawValue, forKey: "quality")
        ytdlpFound = FileManager.default.isExecutableFile(atPath: ytdlpPath)
        ytdlpSetupStatus = ytdlpFound ? .ready : .unknown
    }

    /// Builds cookie arguments based on user's chosen cookie source.
    nonisolated static func cookieArgs(source: CookieSource, browser: BrowserChoice, filePath: String) -> [String] {
        switch source {
        case .none:
            return []
        case .browser:
            return ["--cookies-from-browser", browser.rawValue]
        case .file:
            if !filePath.isEmpty && FileManager.default.fileExists(atPath: filePath) {
                return ["--cookies", filePath]
            }
            return []
        }
    }

    // MARK: - yt-dlp Discovery & Auto-Install

    /// Priority: bundled (Application Support) → Homebrew → system PATH
    nonisolated static func resolveYTDLPPath() -> String {
        if FileManager.default.isExecutableFile(atPath: bundledYTDLPPath) {
            return bundledYTDLPPath
        }
        return findSystemYTDLP()
    }

    nonisolated static func findSystemYTDLP() -> String {
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
        return bundledYTDLPPath
    }

    /// Downloads the latest yt-dlp binary from GitHub to Application Support.
    func installOrUpdateYTDLP() {
        ytdlpSetupStatus = .downloading

        Task.detached {
            do {
                let dir = Self.bundledYTDLPDirectory
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

                let url = URL(string: Self.ytdlpDownloadURL)!
                let (tempURL, response) = try await URLSession.shared.download(from: url)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    await MainActor.run {
                        self.ytdlpSetupStatus = .failed("Download failed (bad response)")
                    }
                    return
                }

                let destination = URL(fileURLWithPath: Self.bundledYTDLPPath)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: tempURL, to: destination)

                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: Self.bundledYTDLPPath
                )

                await MainActor.run {
                    self.ytdlpPath = Self.bundledYTDLPPath
                    self.ytdlpFound = true
                    self.ytdlpSetupStatus = .ready
                    self.saveSettings()
                    self.fetchYTDLPVersion()
                }
            } catch {
                await MainActor.run {
                    self.ytdlpSetupStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Ensures yt-dlp is available, downloading if needed.
    func ensureYTDLPAvailable() {
        if ytdlpFound { return }
        installOrUpdateYTDLP()
    }

    func fetchYTDLPVersion() {
        guard ytdlpFound else { return }
        let path = ytdlpPath
        Task.detached {
            let version = Self.getVersionSync(ytdlpPath: path)
            await MainActor.run {
                self.ytdlpVersion = version
            }
        }
    }

    nonisolated static func getVersionSync(ytdlpPath: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
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
        item.activityToken = UUID()
        item.status = .cancelled
        item.workerTask?.cancel()
        item.process?.terminate()
        item.process = nil
        item.workerTask = nil
        item.downloadStage = ""
        startNextDownloads()
    }

    func retryDownload(_ item: DownloadItem) {
        item.activityToken = UUID()
        item.workerTask?.cancel()
        item.process?.terminate()
        item.process = nil
        item.workerTask = nil
        item.status = .queued
        item.progress = 0
        item.speed = ""
        item.eta = ""
        item.duration = ""
        item.fileSize = ""
        item.downloadStage = ""
        startNextDownloads()
    }

    func removeDownload(_ item: DownloadItem) {
        item.activityToken = UUID()
        item.workerTask?.cancel()
        if item.status.isActive {
            item.process?.terminate()
            item.process = nil
        }
        item.workerTask = nil
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

    func shareFile(_ item: DownloadItem) {
        guard let path = item.filePath else { return }
        let url = URL(fileURLWithPath: path)
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            let frame = contentView.bounds
            let point = NSRect(x: frame.midX, y: frame.midY, width: 1, height: 1)
            picker.show(relativeTo: point, of: contentView, preferredEdge: .minY)
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
        let activityToken = UUID()
        item.activityToken = activityToken

        let url = item.url
        let ytdlp = self.ytdlpPath
        let dest = self.downloadPath
        let cookieSrc = self.cookieSource
        let cookieBrowser = self.cookiesBrowser
        let cookieFile = self.cookiesPath
        let formatStr = item.quality.formatString
        let outputFmt = item.quality.outputFormat
        let isAudioOnly = item.quality == .audioOnly

        let workerTask = Task.detached {
            let metadata = Self.fetchMetadataSync(
                url: url,
                ytdlpPath: ytdlp,
                formatString: formatStr,
                cookieSource: cookieSrc,
                cookieBrowser: cookieBrowser,
                cookieFile: cookieFile
            )
            let isStillCurrent = await MainActor.run {
                item.activityToken == activityToken
            }
            guard isStillCurrent, !Task.isCancelled else { return }

            await MainActor.run {
                guard item.activityToken == activityToken else { return }
                item.title = metadata.title
                item.duration = metadata.duration
                item.fileSize = metadata.fileSize
                item.status = .downloading
                item.downloadStage = "Starting…"
            }

            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: ytdlp)
            process.environment = Self.shellEnvironment()

            var args: [String] = Self.cookieArgs(source: cookieSrc, browser: cookieBrowser, filePath: cookieFile)
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

            let canStartProcess = await MainActor.run {
                item.activityToken == activityToken
            }
            guard canStartProcess, !Task.isCancelled else { return }

            do {
                try process.run()
            } catch {
                await MainActor.run {
                    guard item.activityToken == activityToken else { return }
                    item.status = .failed("Cannot start yt-dlp: \(error.localizedDescription)")
                    item.process = nil
                    item.workerTask = nil
                    self.startNextDownloads()
                }
                return
            }

            let shouldKeepProcess = await MainActor.run {
                guard item.activityToken == activityToken else { return false }
                item.process = process
                return true
            }
            guard shouldKeepProcess else {
                process.terminate()
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
                        guard item.activityToken == activityToken else { return }
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
                guard item.activityToken == activityToken else { return }
                if exitCode == 0 {
                    item.status = .completed
                    item.progress = 1.0
                    item.speed = ""
                    item.eta = ""
                    item.downloadStage = ""
                    item.completedAt = Date()
                    if let fp = finalPath {
                        let resolvedPath = fp.hasPrefix("/") ? fp : "\(dest)/\(fp)"
                        item.filePath = resolvedPath
                        if let fileSize = Self.fileSizeForPath(resolvedPath) {
                            item.fileSize = fileSize
                        }
                    }
                    self.sendNotification(title: "Download Complete", body: item.title)
                } else if item.status != .cancelled {
                    item.status = .failed(finalError ?? "yt-dlp exited with code \(exitCode)")
                }
                item.process = nil
                item.workerTask = nil
                self.startNextDownloads()
            }
        }

        item.workerTask = workerTask
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

    nonisolated static func fetchMetadataSync(
        url: String,
        ytdlpPath: String,
        formatString: String,
        cookieSource: CookieSource = .none, cookieBrowser: BrowserChoice = .chrome, cookieFile: String = ""
    ) -> VideoMetadata {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        var args = cookieArgs(source: cookieSource, browser: cookieBrowser, filePath: cookieFile)
        args += [
            "-f", formatString,
            "--print", "title",
            "--print", "duration_string",
            "--print", "filesize",
            "--print", "filesize_approx",
            "--no-download",
            "--no-warnings",
            url,
        ]
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.environment = shellEnvironment()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return parseMetadataOutput(output)
        } catch {
            return VideoMetadata(title: "Unknown Title", duration: "", fileSize: "")
        }
    }

    nonisolated static func parseMetadataOutput(_ output: String) -> VideoMetadata {
        let lines = output.components(separatedBy: .newlines)
        let title = sanitizedMetadataValue(lines[safe: 0]) ?? "Unknown Title"
        let duration = sanitizedMetadataValue(lines[safe: 1]) ?? ""
        let fileSize = [lines[safe: 2], lines[safe: 3]]
            .compactMap(sanitizedMetadataValue)
            .compactMap(formattedByteCount)
            .first ?? ""

        return VideoMetadata(title: title, duration: duration, fileSize: fileSize)
    }

    nonisolated static func sanitizedMetadataValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "NA"
        else {
            return nil
        }
        return trimmed
    }

    nonisolated static func formattedByteCount(_ rawValue: String) -> String? {
        guard let bytes = Int64(rawValue) else {
            return nil
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    nonisolated static func fileSizeForPath(_ path: String) -> String? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let fileSize = attributes[.size] as? NSNumber
        else {
            return nil
        }

        return formattedByteCount(fileSize.stringValue)
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
