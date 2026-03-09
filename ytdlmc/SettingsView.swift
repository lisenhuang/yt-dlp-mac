import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DownloadManager.self) private var manager

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
                    TextField("yt-dlp Path", text: $manager.ytdlpPath)
                        .textFieldStyle(.roundedBorder)

                    if manager.ytdlpFound {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    Button("Browse…") {
                        chooseYTDLPPath()
                    }

                    Button("Auto-detect") {
                        manager.ytdlpPath = DownloadManager.findYTDLP()
                        manager.ytdlpFound = FileManager.default.isExecutableFile(atPath: manager.ytdlpPath)
                    }
                }

                if !manager.ytdlpFound {
                    Label(
                        "yt-dlp not found. Install it with: brew install yt-dlp",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("Authentication") {
                HStack {
                    TextField("Cookies File (optional)", text: $manager.cookiesPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse…") {
                        chooseCookiesFile()
                    }
                }

                Text("Export cookies from your browser for age-restricted or private videos. Use a browser extension like \"Get cookies.txt LOCALLY\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 380)
        .onChange(of: manager.downloadPath) { _, _ in manager.saveSettings() }
        .onChange(of: manager.ytdlpPath) { _, _ in manager.saveSettings() }
        .onChange(of: manager.cookiesPath) { _, _ in manager.saveSettings() }
        .onChange(of: manager.maxConcurrentDownloads) { _, _ in manager.saveSettings() }
        .onChange(of: manager.selectedQuality) { _, _ in manager.saveSettings() }
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
