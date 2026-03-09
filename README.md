# yt-dlp-mac

A lightweight native macOS app for downloading YouTube videos, powered by [yt-dlp](https://github.com/yt-dlp/yt-dlp). No terminal needed — just paste a URL and click Download.

![Main Window](assets/screenshot-main.png)

## Features

- **One-click download** — paste a YouTube URL, pick quality, hit Download
- **Multiple simultaneous downloads** — configurable concurrency (up to 10)
- **Quality selection** — Best, 1080p, 720p, 480p, or Audio Only
- **Live progress** — real-time progress bar, speed, and ETA for each download
- **Choose download folder** — save videos wherever you want
- **Drag & drop** — drop YouTube links directly onto the window
- **Smart paste** — auto-extracts YouTube URLs from clipboard text
- **Keyboard shortcuts** — `Cmd+Return` to download, `Cmd+D` to download from clipboard
- **macOS notifications** — get notified when downloads finish
- **Open / Reveal** — open completed files or show them in Finder
- **Cookies support** — use a cookies file for age-restricted or private videos

## Requirements

- macOS 15.0 or later
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) installed on your system

## Install yt-dlp

```bash
brew install yt-dlp
```

Or see the [yt-dlp installation guide](https://github.com/yt-dlp/yt-dlp#installation) for other methods.

## Download

[**Download ytdlmc.dmg**](https://github.com/lisenhuang/yt-dlp-mac/releases/latest/download/ytdlmc.dmg) (latest build)

## Getting Started

1. **Download** [`ytdlmc.dmg`](https://github.com/lisenhuang/yt-dlp-mac/releases/latest/download/ytdlmc.dmg) or grab it from [Releases](https://github.com/lisenhuang/yt-dlp-mac/releases)
2. **Open** the DMG and drag `ytdlmc.app` to your Applications folder
3. **First launch** — right-click the app → Open (required once for unsigned builds)
4. The app auto-detects your yt-dlp installation. If not found, it will prompt you to configure the path in Settings.

## Usage

1. **Copy** a YouTube video URL from your browser
2. **Paste** it into the URL field (or click the clipboard button to auto-paste)
3. **Choose quality** from the dropdown (Best, 1080p, 720p, 480p, Audio Only)
4. **Click Download** — the video appears in the download list with live progress
5. Once complete, click **Open** to play or **Show in Finder** to locate the file

You can queue up multiple videos — they download concurrently based on your max concurrent setting.

## Settings

Open Settings via the gear icon or `Cmd+,`.

![Settings](assets/screenshot-settings.png)

| Setting | Description |
|---|---|
| **Download Folder** | Where videos are saved |
| **Default Quality** | Quality preset for new downloads |
| **Max Concurrent Downloads** | How many videos download at once (1–10) |
| **yt-dlp Path** | Path to the yt-dlp binary (auto-detected) |
| **Cookies File** | Optional `cookies.txt` for age-restricted or private videos |

### Cookies

Some videos require authentication. To use cookies:

1. Install a browser extension like [Get cookies.txt LOCALLY](https://chromewebstore.google.com/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc)
2. Export cookies from YouTube as a `.txt` file
3. Set the path in Settings → Cookies File

## Building from Source

```bash
git clone https://github.com/lisenhuang/yt-dlp-mac.git
cd yt-dlp-mac
open ytdlmc.xcodeproj
```

Then hit `Cmd+R` in Xcode to build and run.

## License

MIT
