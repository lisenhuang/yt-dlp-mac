import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(DownloadManager.self) private var manager

    @State private var urlText = ""
    @State private var isDropTargeted = false
    @State private var showSettings = false

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
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(manager)
        }
        .onAppear {
            manager.ensureYTDLPAvailable()
            manager.fetchYTDLPVersion()
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                TextField("Paste YouTube URLs here — one per line…", text: $urlText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...6)

                pasteButton
                    .padding(.top, 2)

                qualityPicker

                downloadButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.fill.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            hintRow
        }
        .padding(16)
    }

    private var hintRow: some View {
        HStack(spacing: 4) {
            if urlCount > 1 {
                Image(systemName: "list.bullet")
                    .font(.caption2)
                Text("\(urlCount) links ready")
                    .font(.caption)
            } else {
                Text("Tip: add several links, one per line")
                    .font(.caption)
            }

            Spacer()

            Text("⌘↩ to download")
                .font(.caption)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
    }

    private var urlCount: Int {
        urlText
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
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
        Group {
            if manager.ytdlpSetupStatus == .downloading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Setting up…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(action: startDownload) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !manager.ytdlpFound)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
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
                        onReveal: { manager.revealInFinder(item) },
                        onShare: { manager.shareFile(item) },
                        onGrantAccess: { manager.openFullDiskAccessSettings() }
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

                Text("Paste YouTube URLs above — one per line — or drag & drop links")
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
                Text("Drop YouTube URLs")
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

        withAnimation {
            manager.addDownload(url: url)
        }
        urlText = ""
    }

    private func pasteFromClipboard() {
        guard let content = NSPasteboard.general.string(forType: .string) else { return }
        let found = DownloadManager.extractYouTubeURLs(from: content)
        let textToAdd = found.isEmpty
            ? content.trimmingCharacters(in: .whitespacesAndNewlines)
            : found.joined(separator: "\n")
        appendURLText(textToAdd)
    }

    /// Appends URL text on its own line, preserving anything already typed.
    private func appendURLText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            urlText = trimmed
        } else {
            urlText += "\n" + trimmed
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
                        appendURLText(url.absoluteString)
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor in
                        let found = DownloadManager.extractYouTubeURLs(from: text)
                        appendURLText(found.isEmpty ? text : found.joined(separator: "\n"))
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
