import Darwin
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

struct BrowserCookieExportResult: Sendable {
    var cookieText: String?
    var errorMessage: String?
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

/// Whether this app process can read the OS-protected browser cookie store.
/// `.denied` almost always means the app is missing Full Disk Access.
enum FullDiskAccessStatus: Equatable {
    case granted
    case denied
    case unknown
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
    /// A silent on-launch yt-dlp update is in flight. Unlike `.downloading`, this
    /// does NOT block downloads — the existing working binary stays usable.
    var isAutoUpdatingYTDLP = false
    var diagnosticsLog: String
    var lastBrowserCookieReadAt: Date?
    var browserCookiesPreview: String = ""
    var browserCookiesPreviewError: String = ""
    var isFetchingBrowserCookiesPreview = false
    var browserCookiesCachedAt: Date?

    /// Guards the once-per-launch yt-dlp update check (`onAppear` can fire more
    /// than once for the same window).
    @ObservationIgnored var didCheckForUpdateOnLaunch = false

    enum YTDLPSetupStatus: Equatable {
        case unknown
        case downloading
        case ready
        case failed(String)
    }

    nonisolated static let ytdlpDownloadURL = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
    nonisolated static let diagnosticsLogDefaultsKey = "diagnosticsLog"
    nonisolated static let lastBrowserCookieReadAtDefaultsKey = "lastBrowserCookieReadAt"
    nonisolated static let browserCookiesPreviewDefaultsKey = "browserCookiesPreview"
    nonisolated static let browserCookiesCachedAtDefaultsKey = "browserCookiesCachedAt"

    nonisolated static var bundledYTDLPDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("yt-dlp-mac").path()
    }

    nonisolated static var bundledYTDLPPath: String {
        bundledYTDLPDirectory + "/yt-dlp"
    }

    nonisolated static var browserCookiesCachePath: String {
        bundledYTDLPDirectory + "/browser-cookies.txt"
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
        self.diagnosticsLog = defaults.string(forKey: Self.diagnosticsLogDefaultsKey) ?? ""
        self.browserCookiesPreview = defaults.string(forKey: Self.browserCookiesPreviewDefaultsKey) ?? ""
        if let timestamp = defaults.object(forKey: Self.lastBrowserCookieReadAtDefaultsKey) as? TimeInterval {
            self.lastBrowserCookieReadAt = Date(timeIntervalSince1970: timestamp)
        } else {
            self.lastBrowserCookieReadAt = nil
        }
        if let timestamp = defaults.object(forKey: Self.browserCookiesCachedAtDefaultsKey) as? TimeInterval {
            self.browserCookiesCachedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            self.browserCookiesCachedAt = nil
        }

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
        defaults.set(diagnosticsLog, forKey: Self.diagnosticsLogDefaultsKey)
        defaults.set(lastBrowserCookieReadAt?.timeIntervalSince1970, forKey: Self.lastBrowserCookieReadAtDefaultsKey)
        defaults.set(browserCookiesPreview, forKey: Self.browserCookiesPreviewDefaultsKey)
        defaults.set(browserCookiesCachedAt?.timeIntervalSince1970, forKey: Self.browserCookiesCachedAtDefaultsKey)
        ytdlpFound = FileManager.default.isExecutableFile(atPath: ytdlpPath)
        ytdlpSetupStatus = ytdlpFound ? .ready : .unknown
    }

    func copyDiagnosticsLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsLog, forType: .string)
    }

    func clearDiagnosticsLog() {
        diagnosticsLog = ""
        saveSettings()
    }

    func noteBrowserCookiesRead(at date: Date = Date()) {
        lastBrowserCookieReadAt = date
        saveSettings()
    }

    func copyBrowserCookiesPreview() {
        guard !browserCookiesPreview.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(browserCookiesPreview, forType: .string)
    }

    func invalidateBrowserCookiesCache() {
        browserCookiesPreview = ""
        browserCookiesPreviewError = ""
        browserCookiesCachedAt = nil
        lastBrowserCookieReadAt = nil
        try? FileManager.default.removeItem(atPath: Self.browserCookiesCachePath)
        saveSettings()
    }

    func fetchBrowserCookiesPreview() {
        if !browserCookiesPreview.isEmpty {
            browserCookiesPreviewError = ""
            return
        }

        guard ytdlpFound else {
            browserCookiesPreviewError = "yt-dlp is not available."
            return
        }
        guard cookieSource == .browser else {
            browserCookiesPreviewError = "Cookie Source must be set to From Browser."
            return
        }

        isFetchingBrowserCookiesPreview = true
        browserCookiesPreviewError = ""

        let ytdlpPath = self.ytdlpPath
        let browser = self.cookiesBrowser
        let urlHint = downloads.first?.url ?? "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let cachePath = Self.browserCookiesCachePath

        Task.detached {
            if let cachedPreview = Self.readBrowserCookiesCacheSync(path: cachePath) {
                await MainActor.run {
                    self.browserCookiesPreview = cachedPreview.text
                    self.browserCookiesCachedAt = cachedPreview.cachedAt
                    self.browserCookiesPreviewError = ""
                    self.isFetchingBrowserCookiesPreview = false
                    self.saveSettings()
                }
                return
            }

            let result = Self.exportBrowserCookiesSync(
                ytdlpPath: ytdlpPath,
                browser: browser,
                outputPath: cachePath,
                urlHint: urlHint
            )

            await MainActor.run {
                if let cookieText = result.cookieText {
                    self.browserCookiesPreview = cookieText
                    self.browserCookiesCachedAt = Date()
                    self.browserCookiesPreviewError = ""
                    self.noteBrowserCookiesRead()
                } else {
                    self.browserCookiesPreview = ""
                    self.browserCookiesCachedAt = nil
                    self.browserCookiesPreviewError = result.errorMessage ?? "Failed to export browser cookies."
                }
                self.isFetchingBrowserCookiesPreview = false
                self.saveSettings()
            }
        }
    }

    func appendDiagnosticsEntry(
        title: String,
        url: String,
        message: String,
        rawError: String = "",
        cookieSource: CookieSource,
        cookieBrowser: BrowserChoice,
        cookieFile: String
    ) {
        let entry = Self.makeDiagnosticsEntry(
            title: title,
            url: url,
            message: message,
            rawError: rawError,
            cookieSource: cookieSource,
            cookieBrowser: cookieBrowser,
            cookieFile: cookieFile
        )
        diagnosticsLog = diagnosticsLog.isEmpty ? entry : "\(entry)\n\n\(diagnosticsLog)"
        saveSettings()
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

    // MARK: - Full Disk Access

    /// Safari's cookie store lives in OS-protected locations that require Full Disk Access.
    nonisolated static var safariCookiePaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        return [
            "\(home)/Library/Cookies/Cookies.binarycookies",
            "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
        ]
    }

    /// Probes whether this app process can actually read Safari's cookie store.
    ///
    /// When yt-dlp is launched by this app, macOS evaluates Full Disk Access against the
    /// responsible process — this app — so a child yt-dlp benefits from the app's grant
    /// (the same reason `yt-dlp --cookies-from-browser safari` works from a Terminal that
    /// already has Full Disk Access). This probe therefore reflects what that command will
    /// be able to do. A `.denied` result means the app itself needs Full Disk Access;
    /// granting it to the yt-dlp binary alone has no effect, because the app is the
    /// responsible process macOS checks.
    nonisolated static func safariCookieAccess() -> FullDiskAccessStatus {
        var sawProtectedFile = false
        for path in safariCookiePaths {
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return .granted
            }
            // EPERM / EACCES → the file is there but TCC blocked the read.
            // ENOENT → the file simply doesn't exist on this machine.
            if errno != ENOENT {
                sawProtectedFile = true
            }
        }
        return sawProtectedFile ? .denied : .unknown
    }

    /// Opens System Settings → Privacy & Security → Full Disk Access, falling back to the
    /// general Privacy & Security pane if the deep-linked anchor isn't accepted.
    func openFullDiskAccessSettings() {
        let fullDiskAccessPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        let privacyPane = "x-apple.systempreferences:com.apple.preference.security"
        if let url = URL(string: fullDiskAccessPane), NSWorkspace.shared.open(url) {
            return
        }
        if let fallback = URL(string: privacyPane) {
            NSWorkspace.shared.open(fallback)
        }
    }

    /// Recognizes the macOS Full Disk Access failure that blocks reading Safari's cookie
    /// store, e.g. `ERROR: [Errno 1] Operation not permitted: '…/Cookies.binarycookies'`.
    ///
    /// Deliberately scoped to Safari's protected cookie file: Chrome/Firefox keep cookies in
    /// `~/Library/Application Support`, which doesn't require Full Disk Access, so their
    /// permission or keychain errors must not be misreported as an FDA problem.
    nonisolated static func isCookiePermissionError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        let isPermissionDenied = lowered.contains("operation not permitted")
            || lowered.contains("errno 1")      // EPERM
            || lowered.contains("errno 13")     // EACCES
            || lowered.contains("permission denied")
        let mentionsSafariCookieStore = lowered.contains("binarycookies")
            || lowered.contains("library/cookies")
            || (lowered.contains("safari") && lowered.contains("cookie"))
        return isPermissionDenied && mentionsSafariCookieStore
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
    ///
    /// When `background` is true (the on-launch auto-update), the fetch is silent:
    /// it does NOT enter the `.downloading` state that hides the Download button,
    /// so the existing working binary stays usable, and a failure is swallowed
    /// rather than surfaced as an error. When false (first-time install or a
    /// user-tapped Install/Update), it shows the normal setup UI.
    func installOrUpdateYTDLP(background: Bool = false) {
        if background {
            isAutoUpdatingYTDLP = true
        } else {
            ytdlpSetupStatus = .downloading
        }

        Task.detached {
            do {
                let dir = Self.bundledYTDLPDirectory
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

                let url = URL(string: Self.ytdlpDownloadURL)!
                let (tempURL, response) = try await URLSession.shared.download(from: url)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    await MainActor.run {
                        if background {
                            self.isAutoUpdatingYTDLP = false
                        } else {
                            self.ytdlpSetupStatus = .failed("Download failed (bad response)")
                        }
                    }
                    return
                }

                // Atomically swap the binary in so a download launched mid-update
                // never sees a missing or half-written executable.
                let destination = URL(fileURLWithPath: Self.bundledYTDLPPath)
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                }

                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: Self.bundledYTDLPPath
                )

                await MainActor.run {
                    self.ytdlpPath = Self.bundledYTDLPPath
                    self.ytdlpFound = true
                    if background {
                        self.isAutoUpdatingYTDLP = false
                    } else {
                        self.ytdlpSetupStatus = .ready
                    }
                    self.saveSettings()
                    self.fetchYTDLPVersion()
                }
            } catch {
                await MainActor.run {
                    if background {
                        self.isAutoUpdatingYTDLP = false
                    } else {
                        self.ytdlpSetupStatus = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    /// Called on launch: installs yt-dlp if missing, otherwise checks GitHub for a
    /// newer release and updates the app-managed binary automatically. Runs once
    /// per launch.
    ///
    /// Only the app's own bundled binary is auto-updated. A Homebrew/system or
    /// user-chosen custom binary is left untouched (we just read its version),
    /// because silently replacing a package-manager install would be wrong — and
    /// `yt-dlp -U` refuses on those anyway.
    func autoUpdateYTDLPIfNeeded() {
        if didCheckForUpdateOnLaunch { return }
        didCheckForUpdateOnLaunch = true

        guard ytdlpFound else {
            installOrUpdateYTDLP()
            return
        }

        let path = ytdlpPath
        let isAppManaged = (path == Self.bundledYTDLPPath)

        Task.detached {
            let installed = Self.getVersionSync(ytdlpPath: path)
            await MainActor.run { self.ytdlpVersion = installed }

            guard isAppManaged,
                  let latest = await Self.fetchLatestYTDLPVersion(),
                  !latest.isEmpty, !installed.isEmpty, latest != installed
            else { return }

            await MainActor.run { self.installOrUpdateYTDLP(background: true) }
        }
    }

    /// Fetches the latest stable yt-dlp release tag (e.g. "2026.06.09") from GitHub.
    /// Returns `nil` on any network/parse error so callers can simply keep the
    /// currently installed binary.
    nonisolated static func fetchLatestYTDLPVersion() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("yt-dlp-mac", forHTTPHeaderField: "User-Agent")  // GitHub requires a UA
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else {
            return nil
        }
        return tag.trimmingCharacters(in: .whitespacesAndNewlines)
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

        if cookieSrc == .browser {
            noteBrowserCookiesRead()
        }

        let workerTask = Task.detached {
            // Read cookies straight from the browser on every download (exactly
            // like `yt-dlp --cookies-from-browser …`) so YouTube always sees a
            // fresh, unexpired session. We deliberately do NOT reuse an exported
            // snapshot file: a cached cookies.txt goes stale within hours and is
            // what was causing "Sign in to confirm you're not a bot" / 403
            // failures even with a logged-in browser.
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
                "-o", "\(dest)/%(title)s_%(timestamp>%Y%m%d_%H%M%S)s.%(ext)s",
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
                    let message = "Cannot start yt-dlp: \(error.localizedDescription)"
                    item.status = .failed(message)
                    self.appendDiagnosticsEntry(
                        title: item.title,
                        url: item.url,
                        message: message,
                        cookieSource: cookieSrc,
                        cookieBrowser: cookieBrowser,
                        cookieFile: cookieFile
                    )
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

                    // Parsing happens on this background reader thread. Hop to the
                    // main actor on any stage/merge transition, or on a rate-limited
                    // progress tick (~4/sec) that carries the latest progress, speed,
                    // ETA and file size together. This avoids the per-line flood that
                    // saturates the UI thread while keeping the live stats fresh.
                    let hasStageChange = parsed.isMerging || parsed.stage != nil
                    let emitProgress = parsed.progress.map { state.shouldEmitProgress($0) } ?? false
                    guard hasStageChange || emitProgress else { continue }

                    Task { @MainActor in
                        guard item.activityToken == activityToken else { return }
                        if emitProgress, let p = parsed.progress {
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
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            if exitCode != 0 {
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
                    let message = finalError ?? "yt-dlp exited with code \(exitCode)"
                    item.status = .failed(message)
                    self.appendDiagnosticsEntry(
                        title: item.title,
                        url: item.url,
                        message: message,
                        rawError: errStr,
                        cookieSource: cookieSrc,
                        cookieBrowser: cookieBrowser,
                        cookieFile: cookieFile
                    )
                }
                item.process = nil
                item.workerTask = nil
                self.saveSettings()
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

    nonisolated static func exportBrowserCookiesSync(
        ytdlpPath: String,
        browser: BrowserChoice,
        outputPath: String,
        urlHint: String
    ) -> BrowserCookieExportResult {
        let parentDirectory = URL(fileURLWithPath: outputPath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = [
            "--cookies-from-browser", browser.rawValue,
            "--cookies", outputPath,
            "--skip-download",
            urlHint,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        process.environment = shellEnvironment()

        do {
            try process.run()
            process.waitUntilExit()

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus == 0,
               let cookieData = try? Data(contentsOf: URL(fileURLWithPath: outputPath)),
               let cookieText = String(data: cookieData, encoding: .utf8),
               !cookieText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return BrowserCookieExportResult(cookieText: cookieText, errorMessage: nil)
            }

            let message = errorText
                .components(separatedBy: .newlines)
                .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                ?? "Failed to export browser cookies."
            return BrowserCookieExportResult(cookieText: nil, errorMessage: message)
        } catch {
            return BrowserCookieExportResult(cookieText: nil, errorMessage: error.localizedDescription)
        }
    }

    nonisolated static func readBrowserCookiesCacheSync(path: String) -> (text: String, cachedAt: Date?)? {
        guard FileManager.default.fileExists(atPath: path),
              let cookieData = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let cookieText = String(data: cookieData, encoding: .utf8)
        else {
            return nil
        }

        let trimmed = cookieText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cachedAt: Date?
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let modified = attrs[.modificationDate] as? Date
        {
            cachedAt = modified
        } else {
            cachedAt = nil
        }

        return (cookieText, cachedAt)
    }

    nonisolated static func makeDiagnosticsEntry(
        title: String,
        url: String,
        message: String,
        rawError: String = "",
        cookieSource: CookieSource,
        cookieBrowser: BrowserChoice,
        cookieFile: String,
        timestamp: Date = Date()
    ) -> String {
        var lines = [
            "[\(timestamp.formatted(date: .numeric, time: .standard))] \(title)",
            "URL: \(url)",
            "Error: \(message)",
            "Cookies: \(cookieDescription(source: cookieSource, browser: cookieBrowser, filePath: cookieFile))",
        ]

        if let hint = failureHint(message: message, cookieSource: cookieSource) {
            lines.append("Hint: \(hint)")
        }

        let trimmedError = rawError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            lines.append("Raw yt-dlp output:")
            lines.append(trimmedError)
        }

        return lines.joined(separator: "\n")
    }

    nonisolated static func cookieDescription(source: CookieSource, browser: BrowserChoice, filePath: String) -> String {
        switch source {
        case .none:
            return "None"
        case .browser:
            return "From Browser (\(browser.displayName), fetched fresh on each download)"
        case .file:
            let filename = filePath.isEmpty ? "No file selected" : URL(fileURLWithPath: filePath).lastPathComponent
            return "From File (\(filename))"
        }
    }

    nonisolated static func failureHint(message: String, cookieSource: CookieSource) -> String? {
        let lowered = message.lowercased()

        if isCookiePermissionError(message) {
            return "macOS blocked this app from reading the browser's cookies. Open System Settings → Privacy & Security → Full Disk Access, add and enable \"yt-dlp-mac\", then FULLY QUIT (⌘Q) and reopen the app — the permission only applies to a freshly launched app. Granting access to the yt-dlp binary alone does not work: macOS checks the app that launches yt-dlp, so the app itself needs the permission. Safari in particular keeps its cookies in a protected location, so Full Disk Access is required."
        }

        if lowered.contains("403") || lowered.contains("forbidden") {
            switch cookieSource {
            case .browser:
                return "This often means the browser session is no longer logged in or YouTube blocked the current request. Close and reopen the browser, confirm you can play the video there, then retry."
            case .file:
                return "This often means the exported cookies file is stale. Re-export cookies.txt and select it again in Settings before retrying."
            case .none:
                return "This often needs cookies. Switch Cookie Source to From Browser in Settings and retry."
            }
        }

        if lowered.contains("sign in") || lowered.contains("age-restricted") || lowered.contains("private") {
            return "This video likely needs an authenticated session. Using From Browser is the most reliable option."
        }

        return nil
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
        extractYouTubeURLs(from: text).first
    }

    /// Returns every YouTube URL found in the text, in order of appearance.
    nonisolated static func extractYouTubeURLs(from text: String) -> [String] {
        let pattern = #"https?://(?:www\.)?(?:youtube\.com/(?:watch\?[^\s]+|shorts/[^\s]+|live/[^\s]+|playlist\?[^\s]+)|youtu\.be/[^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
