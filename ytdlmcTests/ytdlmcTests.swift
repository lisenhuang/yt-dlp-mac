//
//  ytdlmcTests.swift
//  ytdlmcTests
//
//  Created by Eason Smith on 09/03/2026.
//

import Foundation
import Testing
@testable import yt_dlp_mac

struct ytdlmcTests {

    @Test func parseMetadataOutputUsesDurationAndExactFileSize() async throws {
        let metadata = DownloadManager.parseMetadataOutput(
            """
            Sample Video
            12:34
            10485760
            12582912
            """
        )

        #expect(metadata.title == "Sample Video")
        #expect(metadata.duration == "12:34")
        #expect(metadata.fileSize == "10.5 MB")
    }

    @Test func parseMetadataOutputFallsBackToApproximateFileSize() async throws {
        let metadata = DownloadManager.parseMetadataOutput(
            """
            Sample Video
            03:21
            NA
            5242880
            """
        )

        #expect(metadata.title == "Sample Video")
        #expect(metadata.duration == "03:21")
        #expect(metadata.fileSize == "5.2 MB")
    }

    @Test func diagnosticsEntryIncludesCookieSpecificHint() async throws {
        let entry = DownloadManager.makeDiagnosticsEntry(
            title: "Blocked Video",
            url: "https://www.youtube.com/watch?v=blocked",
            message: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
            rawError: "Trace line",
            cookieSource: .file,
            cookieBrowser: .chrome,
            cookieFile: "/tmp/cookies.txt",
            timestamp: Date(timeIntervalSince1970: 0)
        )

        #expect(entry.contains("Error: ERROR: unable to download video data: HTTP Error 403: Forbidden"))
        #expect(entry.contains("Cookies: From File (cookies.txt)"))
        #expect(entry.contains("Hint: This often means the exported cookies file is stale."))
        #expect(entry.contains("Raw yt-dlp output:\nTrace line"))
    }

}
