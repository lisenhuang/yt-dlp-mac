import SwiftUI

@main
struct ytdlmcApp: App {
    @State private var manager = DownloadManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(manager)
        }
        .defaultSize(width: 680, height: 520)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Download from Clipboard") {
                    if let content = NSPasteboard.general.string(forType: .string),
                       let url = DownloadManager.extractYouTubeURL(from: content)
                    {
                        manager.addDownload(url: url)
                    }
                }
                .keyboardShortcut("d", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(manager)
        }
    }
}
