import SwiftUI

struct DownloadRowView: View {
    let item: DownloadItem
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                statusIcon
                    .font(.title3)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)

                    Link(item.url, destination: URL(string: item.url)!)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }

                    if !item.fileSize.isEmpty || !item.duration.isEmpty {
                        HStack(spacing: 10) {
                            if !item.fileSize.isEmpty {
                                Label(item.fileSize, systemImage: "internaldrive")
                            }

                            if !item.duration.isEmpty {
                                Label(item.duration, systemImage: "clock")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                qualityBadge
            }

            switch item.status {
            case .queued:
                queuedView
            case .fetchingInfo:
                fetchingInfoView
            case .downloading:
                downloadingView
            case .merging:
                mergingView
            case .completed:
                completedView
            case .failed(let message):
                failedView(message: message)
            case .cancelled:
                cancelledView
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contextMenu { contextMenuItems }
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .fetchingInfo:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 24, height: 24)
        case .downloading:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
        case .merging:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 24, height: 24)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Quality Badge

    private var qualityBadge: some View {
        Label(item.quality.rawValue, systemImage: item.quality.icon)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.fill.tertiary)
            .clipShape(Capsule())
    }

    // MARK: - Status Views

    private var queuedView: some View {
        HStack(spacing: 8) {
            Text("Waiting in queue…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            removeButton("Remove queued download")
        }
    }

    private var fetchingInfoView: some View {
        HStack(spacing: 6) {
            Text("Fetching video info…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            removeButton("Remove download")
        }
    }

    private var downloadingView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: item.progress, total: 1.0)
                .tint(.blue)

            HStack {
                if !item.downloadStage.isEmpty {
                    Text(item.downloadStage)
                        .foregroundStyle(.secondary)
                }
                Text(String(format: "%.1f%%", item.progress * 100))
                    .monospacedDigit()
                    .fontWeight(.medium)

                Spacer()

                if !item.speed.isEmpty {
                    Label(item.speed, systemImage: "speedometer")
                        .foregroundStyle(.secondary)
                }
                if !item.eta.isEmpty {
                    Label(item.eta, systemImage: "clock")
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive, action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Cancel download")

                removeButton("Remove download")
            }
            .font(.caption)
        }
    }

    private var mergingView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: 0.95, total: 1.0)
                .tint(.orange)

            HStack {
                Text("Merging video & audio…")
                    .foregroundStyle(.orange)
                Spacer()
                Button(role: .destructive, action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                removeButton("Remove download")
            }
            .font(.caption)
        }
    }

    private var completedView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Download complete")
                    .font(.caption)
                    .foregroundStyle(.green)
                if let completedAt = item.completedAt {
                    Text(completedAt, format: .dateTime.hour().minute().second())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if item.filePath != nil {
                Button(action: onOpen) {
                    Label("Open", systemImage: "play.fill")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)

                Button(action: onReveal) {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)

                Button(action: onShare) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)
            }

            Button(action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func failedView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)

            HStack(spacing: 12) {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)

                Button(action: onRemove) {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var cancelledView: some View {
        HStack(spacing: 12) {
            Text("Cancelled")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.blue)

            Button(action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Context Menu

    private func removeButton(_ helpText: String) -> some View {
        Button(role: .destructive, action: onRemove) {
            Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(helpText)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }

        if item.filePath != nil {
            Divider()
            Button("Open File", action: onOpen)
            Button("Show in Finder", action: onReveal)
            Button("Share…", action: onShare)
        }

        Divider()

        if item.status.isActive {
            Button("Cancel", role: .destructive, action: onCancel)
        }
        if case .failed = item.status {
            Button("Retry", action: onRetry)
        }
        if case .cancelled = item.status {
            Button("Retry", action: onRetry)
        }
        Button("Remove", role: .destructive, action: onRemove)
    }
}
