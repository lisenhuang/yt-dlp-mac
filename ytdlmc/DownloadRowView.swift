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

                    Text(item.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
        Text("Waiting in queue…")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var fetchingInfoView: some View {
        HStack(spacing: 6) {
            Text("Fetching video info…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            }
            .font(.caption)
        }
    }

    private var completedView: some View {
        HStack(spacing: 12) {
            Text("Download complete")
                .font(.caption)
                .foregroundStyle(.green)

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
