import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DownloadManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @State private var showCookiePreviewSheet = false
    @State private var didCopyCookieContent = false

    var body: some View {
        @Bindable var manager = manager

        Form {
            Section("General") {
                HStack {
                    TextField("Download Folder", text: $manager.downloadPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Choose…") {
                        chooseDownloadFolder()
                    }
                }

                Picker("Default Quality", selection: $manager.selectedQuality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Label(quality.rawValue, systemImage: quality.icon)
                            .tag(quality)
                    }
                }
                .pickerStyle(.menu)

                Stepper(
                    "Max Concurrent Downloads: \(manager.maxConcurrentDownloads)",
                    value: $manager.maxConcurrentDownloads,
                    in: 1...10
                )
            }

            Section("yt-dlp") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if manager.ytdlpFound {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("yt-dlp installed")
                                    .fontWeight(.medium)
                            } else if manager.ytdlpSetupStatus == .downloading {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Downloading yt-dlp…")
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("yt-dlp not found")
                                    .fontWeight(.medium)
                            }
                        }

                        if !manager.ytdlpVersion.isEmpty {
                            Text("Version \(manager.ytdlpVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(manager.ytdlpPath)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if manager.ytdlpFound {
                        Button("Update") {
                            manager.installOrUpdateYTDLP()
                        }
                        .disabled(manager.ytdlpSetupStatus == .downloading)
                    } else {
                        Button("Install") {
                            manager.installOrUpdateYTDLP()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manager.ytdlpSetupStatus == .downloading)
                    }
                }

                if case .failed(let msg) = manager.ytdlpSetupStatus {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                DisclosureGroup("Advanced") {
                    HStack {
                        TextField("Custom yt-dlp path", text: $manager.ytdlpPath)
                            .textFieldStyle(.roundedBorder)

                        Button("Browse…") {
                            chooseYTDLPPath()
                        }
                    }

                    Text("Override the yt-dlp binary path if you have a custom installation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Cookies") {
                Picker("Cookie Source", selection: $manager.cookieSource) {
                    ForEach(CookieSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                switch manager.cookieSource {
                case .none:
                    Text("No cookies — some age-restricted or private videos may not work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .browser:
                    Picker("Browser", selection: $manager.cookiesBrowser) {
                        ForEach(BrowserChoice.allCases) { browser in
                            Label(browser.displayName, systemImage: browser.icon)
                                .tag(browser)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("yt-dlp will read cookies directly from the selected browser. The browser may ask for permission on first use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("The app uses a cached browser-cookie snapshot first, and refreshes that cache only when needed, such as after a failure or when no cache exists yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let cachedAt = manager.browserCookiesCachedAt {
                        Text("Last cookie cached: \(cachedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Last cookie cached: Never")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button {
                            didCopyCookieContent = false
                            if manager.browserCookiesPreview.isEmpty {
                                manager.fetchBrowserCookiesPreview()
                            } else {
                                showCookiePreviewSheet = true
                            }
                        } label: {
                            if manager.isFetchingBrowserCookiesPreview {
                                Label("Reading Cookies...", systemImage: "hourglass")
                            } else {
                                Text("View Cookie Content")
                            }
                        }
                        .disabled(manager.isFetchingBrowserCookiesPreview)

                        Spacer()
                    }

                    if !manager.browserCookiesPreviewError.isEmpty {
                        Text(manager.browserCookiesPreviewError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                case .file:
                    HStack {
                        TextField("Cookies File", text: $manager.cookiesPath)
                            .textFieldStyle(.roundedBorder)

                        Button("Browse…") {
                            chooseCookiesFile()
                        }
                    }

                    Text("Use a manually exported cookies.txt file. If downloads start failing with 403 or Forbidden, you usually need to export a fresh file and select it again here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Diagnostics") {
                HStack {
                    Button("Copy Error Log") {
                        manager.copyDiagnosticsLog()
                    }
                    .disabled(manager.diagnosticsLog.isEmpty)

                    Button("Clear Log") {
                        manager.clearDiagnosticsLog()
                    }
                    .disabled(manager.diagnosticsLog.isEmpty)

                    Spacer()
                }

                if manager.diagnosticsLog.isEmpty {
                    Text("Recent download failures will be recorded here so they can be copied for debugging.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(manager.diagnosticsLog)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 140, maxHeight: 180)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 480)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showCookiePreviewSheet) {
            cookiePreviewSheet
        }
        .onChange(of: manager.downloadPath) { _, _ in manager.saveSettings() }
        .onChange(of: manager.ytdlpPath) { _, _ in manager.saveSettings() }
        .onChange(of: manager.cookiesPath) { _, _ in manager.saveSettings() }
        .onChange(of: manager.cookieSource) { _, newValue in
            if newValue != .browser {
                manager.invalidateBrowserCookiesCache()
            } else {
                manager.saveSettings()
            }
        }
        .onChange(of: manager.cookiesBrowser) { _, _ in manager.invalidateBrowserCookiesCache() }
        .onChange(of: manager.maxConcurrentDownloads) { _, _ in manager.saveSettings() }
        .onChange(of: manager.selectedQuality) { _, _ in manager.saveSettings() }
        .onChange(of: manager.browserCookiesPreview) { _, newValue in
            if !newValue.isEmpty {
                showCookiePreviewSheet = true
            }
        }
    }

    private var cookiePreviewSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cookie Content")
                .font(.headline)

            TextEditor(text: .constant(manager.browserCookiesPreview))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            HStack {
                Button {
                    manager.copyBrowserCookiesPreview()
                    didCopyCookieContent = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        didCopyCookieContent = false
                    }
                } label: {
                    if didCopyCookieContent {
                        Label("Copied", systemImage: "checkmark")
                    } else {
                        Text("Copy Cookie Content")
                    }
                }

                Spacer()

                Button("Done") {
                    showCookiePreviewSheet = false
                }
            }

            Text("This exports and displays browser cookies for inspection. Treat it as sensitive data.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 420)
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose where to save downloaded videos"
        if panel.runModal() == .OK, let url = panel.url {
            manager.downloadPath = url.path()
            manager.saveSettings()
        }
    }

    private func chooseYTDLPPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the yt-dlp executable"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            manager.ytdlpPath = url.path()
            manager.saveSettings()
            manager.fetchYTDLPVersion()
        }
    }

    private func chooseCookiesFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.text, .plainText]
        panel.message = "Select your cookies.txt file"
        if panel.runModal() == .OK, let url = panel.url {
            manager.cookiesPath = url.path()
            manager.saveSettings()
        }
    }
}
