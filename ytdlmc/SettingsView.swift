import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DownloadManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

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
        .frame(width: 520, height: 420)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
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
