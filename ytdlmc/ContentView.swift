import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(DownloadManager.self) private var manager

    @State private var urlText = ""
    @State private var isDropTargeted = false
    @State private var showSettings = false
    @State private var showYTDLPMissing = false

    var body: some View {
        VStack(spacing: 0) {
            inputArea
            Divider()
            pathBar
            Divider()
            downloadListArea
        }
        .frame(minWidth: 580, minHeight: 420)
        .background(.background)
        .onDrop(of: [.url, .text, .plainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
        .alert("yt-dlp Not Found", isPresented: $showYTDLPMissing) {
            Button("Open Settings") { showSettings = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text("yt-dlp is required to download videos.\n\nInstall it with: brew install yt-dlp\n\nOr set the path manually in Settings.")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(manager)
        }
        .onAppear {
            if !manager.ytdlpFound {
                showYTDLPMissing = true
            }
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)

                TextField("Paste YouTube URL here…", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { startDownload() }

                pasteButton

                qualityPicker

                downloadButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.fill.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
    }

    private var pasteButton: some View {
        Button(action: pasteFromClipboard) {
            Image(systemName: "doc.on.clipboard")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Paste from clipboard")
    }

    private var qualityPicker: some View {
        @Bindable var mgr = manager
        return Picker("", selection: $mgr.selectedQuality) {
            ForEach(VideoQuality.allCases) { q in
                Label(q.rawValue, systemImage: q.icon).tag(q)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 100)
    }

    private var downloadButton: some View {
        Button(action: startDownload) {
            Label("Download", systemImage: "arrow.down.circle.fill")
                .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .keyboardShortcut(.return, modifiers: .command)
    }

    // MARK: - Path Bar

    private var pathBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)

            Text(shortenedPath(manager.downloadPath))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(manager.downloadPath)

            Spacer()

            Button("Change…") {
                chooseDownloadFolder()
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Button {
                manager.openDownloadFolder()
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open download folder")

            Divider()
                .frame(height: 16)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.background.secondary)
    }

    // MARK: - Download List

    private var downloadListArea: some View {
        Group {
            if manager.downloads.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    listHeader
                    Divider()
                    downloadList
                }
            }
        }
    }

    private var listHeader: some View {
        HStack {
            Text("Downloads")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("(\(manager.downloads.count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if manager.activeCount > 0 {
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(manager.activeCount) active")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }

            Spacer()

            if manager.downloads.contains(where: { if case .completed = $0.status { return true }; return false }) {
                Button("Clear Completed") {
                    withAnimation { manager.clearCompleted() }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var downloadList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(manager.downloads) { item in
                    DownloadRowView(
                        item: item,
                        onCancel: { withAnimation { manager.cancelDownload(item) } },
                        onRetry: { withAnimation { manager.retryDownload(item) } },
                        onRemove: { withAnimation { manager.removeDownload(item) } },
                        onOpen: { manager.openFile(item) },
                        onReveal: { manager.revealInFinder(item) }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            VStack(spacing: 4) {
                Text("No Downloads Yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Paste a YouTube URL above or drag & drop a link")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        ZStack {
            Color.blue.opacity(0.08)
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                Text("Drop YouTube URL")
                    .font(.headline)
                    .foregroundStyle(.blue)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.blue, style: StrokeStyle(lineWidth: 2, dash: [8]))
        )
        .padding(8)
    }

    // MARK: - Actions

    private func startDownload() {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        if !manager.ytdlpFound {
            showYTDLPMissing = true
            return
        }

        withAnimation {
            manager.addDownload(url: url)
        }
        urlText = ""
    }

    private func pasteFromClipboard() {
        guard let content = NSPasteboard.general.string(forType: .string) else { return }
        if let extracted = DownloadManager.extractYouTubeURL(from: content) {
            urlText = extracted
        } else {
            urlText = content
        }
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose where to save downloaded videos"
        panel.directoryURL = URL(fileURLWithPath: manager.downloadPath)
        if panel.runModal() == .OK, let url = panel.url {
            manager.downloadPath = url.path()
            manager.saveSettings()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        urlText = url.absoluteString
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor in
                        if let extracted = DownloadManager.extractYouTubeURL(from: text) {
                            urlText = extracted
                        } else {
                            urlText = text
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func shortenedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
