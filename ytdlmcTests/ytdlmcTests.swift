//
//  ytdlmcTests.swift
//  ytdlmcTests
//
//  Created by Eason Smith on 09/03/2026.
//

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

}
