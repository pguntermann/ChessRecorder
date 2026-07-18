import XCTest
@testable import Chess_Recorder

final class PreparedLanguageModelDiskCacheTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "PreparedLanguageModelDiskCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    private func validPreparedModelData() -> Data {
        let minimum = Int(PreparedLanguageModelDiskCache.minimumPreparedModelByteCount)
        let endOfCentralDirectory = Data([
            0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ])
        var data = Data([0x50, 0x4B, 0x03, 0x04])
        data.append(Data(repeating: 0, count: minimum - data.count - endOfCentralDirectory.count))
        data.append(endOfCentralDirectory)
        return data
    }

    private func truncatedZipPreparedModelData() -> Data {
        var data = Data([0x50, 0x4B, 0x03, 0x04])
        let minimum = Int(PreparedLanguageModelDiskCache.minimumPreparedModelByteCount)
        data.append(Data(repeating: 0, count: minimum - data.count))
        return data
    }

    private func saveManifestMatchingArtifactBundle(
        for language: RecognitionLanguage,
        preparedURL: URL,
        revision: Int = 2
    ) throws {
        guard let bundleFingerprint = PreparedLanguageModelDiskCache.artifactBundleFingerprint(
            for: language,
            in: temporaryDirectory
        ) else {
            XCTFail("Expected artifact bundle fingerprint")
            return
        }

        try PreparedLanguageModelDiskCache.saveManifest(
            PreparedLanguageModelDiskCache.Manifest(
                baseModelVersion: "4.0",
                vocabRevision: revision,
                languageCode: language.rawValue,
                artifactBundleByteCount: bundleFingerprint.byteCount,
                artifactBundleSHA256: bundleFingerprint.sha256,
                preparedModelRelativePath: preparedURL.lastPathComponent,
                preparedModelByteCount: nil,
                preparedModelSHA256: nil
            ),
            for: language,
            in: temporaryDirectory
        )
    }

    func testCanRestoreWhenManifestAndPreparedArtifactsMatch() throws {
        let preparedURL = PreparedLanguageModelDiskCache.preparedModelURL(for: .german, in: temporaryDirectory)
        try validPreparedModelData().write(to: preparedURL)
        try Data("export".utf8).write(to: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory))
        try saveManifestMatchingArtifactBundle(for: .german, preparedURL: preparedURL)

        XCTAssertTrue(
            PreparedLanguageModelDiskCache.canRestore(
                for: .german,
                baseModelVersion: "4.0",
                vocabRevision: 2,
                preparedURL: preparedURL,
                exportURL: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory),
                in: temporaryDirectory
            )
        )
    }

    func testCanRestoreDetectsExportBinModification() throws {
        let preparedURL = PreparedLanguageModelDiskCache.preparedModelURL(for: .german, in: temporaryDirectory)
        let exportURL = PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory)
        try validPreparedModelData().write(to: preparedURL)
        try Data("<lexicon version=\"1.0\">".utf8).write(to: exportURL)
        try saveManifestMatchingArtifactBundle(for: .german, preparedURL: preparedURL)

        try Data("<lexicon verwefsion=\"1.0\">".utf8).write(to: exportURL)

        let reason = PreparedLanguageModelDiskCache.restoreSkipReason(
            for: .german,
            baseModelVersion: "4.0",
            vocabRevision: 2,
            preparedURL: preparedURL,
            exportURL: exportURL,
            in: temporaryDirectory
        )

        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("artifact bundle appears corrupt") == true)
    }

    func testCanRestoreAcceptsPreparedModelFileOrDirectory() throws {
        let preparedFile = PreparedLanguageModelDiskCache.preparedModelURL(for: .german, in: temporaryDirectory)
        try validPreparedModelData().write(to: preparedFile)
        try Data("export".utf8).write(to: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory))
        try saveManifestMatchingArtifactBundle(for: .german, preparedURL: preparedFile)

        XCTAssertTrue(PreparedLanguageModelDiskCache.preparedArtifactsExist(at: preparedFile))
        XCTAssertEqual(
            PreparedLanguageModelDiskCache.resolvedPreparedModelURL(for: .german, in: temporaryDirectory),
            preparedFile
        )
    }

    func testCanRestoreAcceptsPreparedModelSiblingFile() throws {
        let preparedBase = PreparedLanguageModelDiskCache.preparedModelURL(for: .german, in: temporaryDirectory)
        let preparedFile = preparedBase.appendingPathExtension("bin")
        try validPreparedModelData().write(to: preparedFile)
        try Data("export".utf8).write(to: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory))
        try saveManifestMatchingArtifactBundle(for: .german, preparedURL: preparedFile)

        XCTAssertTrue(PreparedLanguageModelDiskCache.preparedArtifactsExist(for: .german, in: temporaryDirectory))
        XCTAssertEqual(
            PreparedLanguageModelDiskCache.resolvedPreparedModelURL(for: .german, in: temporaryDirectory),
            preparedFile
        )
    }

    func testCanRestoreRejectsManifestWithoutFingerprint() throws {
        let preparedURL = PreparedLanguageModelDiskCache.preparedModelURL(for: .german, in: temporaryDirectory)
        try validPreparedModelData().write(to: preparedURL)
        try Data("export".utf8).write(to: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory))
        try PreparedLanguageModelDiskCache.saveManifest(
            PreparedLanguageModelDiskCache.Manifest(
                baseModelVersion: "4.0",
                vocabRevision: 2,
                languageCode: RecognitionLanguage.german.rawValue,
                artifactBundleByteCount: nil,
                artifactBundleSHA256: nil,
                preparedModelRelativePath: preparedURL.lastPathComponent,
                preparedModelByteCount: 4096,
                preparedModelSHA256: "legacy"
            ),
            for: .german,
            in: temporaryDirectory
        )

        let reason = PreparedLanguageModelDiskCache.restoreSkipReason(
            for: .german,
            baseModelVersion: "4.0",
            vocabRevision: 2,
            preparedURL: preparedURL,
            exportURL: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory),
            in: temporaryDirectory
        )

        XCTAssertEqual(reason, "manifest missing artifact bundle fingerprint (recompile required)")
    }

    func testCanRestoreRejectsDigestMismatch() throws {
        let preparedURL = PreparedLanguageModelDiskCache.preparedModelURL(for: .german, in: temporaryDirectory)
        try validPreparedModelData().write(to: preparedURL)
        try Data("export".utf8).write(to: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory))
        try saveManifestMatchingArtifactBundle(for: .german, preparedURL: preparedURL)

        var corrupted = try Data(contentsOf: preparedURL)
        corrupted[corrupted.count / 2] ^= 0xFF
        try corrupted.write(to: preparedURL)

        let reason = PreparedLanguageModelDiskCache.restoreSkipReason(
            for: .german,
            baseModelVersion: "4.0",
            vocabRevision: 2,
            preparedURL: preparedURL,
            exportURL: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory),
            in: temporaryDirectory
        )

        XCTAssertEqual(reason, "artifact bundle appears corrupt (digest mismatch)")
    }

    func testCanRestoreRejectsTruncatedPreparedModel() throws {
        let preparedURL = PreparedLanguageModelDiskCache.preparedModelURL(for: .german, in: temporaryDirectory)
        try Data("bad".utf8).write(to: preparedURL)
        try Data("export".utf8).write(to: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory))
        try saveManifestMatchingArtifactBundle(for: .german, preparedURL: preparedURL)

        let reason = PreparedLanguageModelDiskCache.restoreSkipReason(
            for: .german,
            baseModelVersion: "4.0",
            vocabRevision: 2,
            preparedURL: preparedURL,
            exportURL: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory),
            in: temporaryDirectory
        )

        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("corrupt") == true)
        XCTAssertTrue(PreparedLanguageModelDiskCache.shouldPurgeArtifactsAfterRestoreSkip(reason!))
    }

    func testCanRestoreRejectsTruncatedZipPreparedModel() throws {
        let preparedURL = PreparedLanguageModelDiskCache.preparedModelURL(for: .german, in: temporaryDirectory)
        try truncatedZipPreparedModelData().write(to: preparedURL)
        try Data("export".utf8).write(to: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory))
        try saveManifestMatchingArtifactBundle(for: .german, preparedURL: preparedURL)

        let reason = PreparedLanguageModelDiskCache.restoreSkipReason(
            for: .german,
            baseModelVersion: "4.0",
            vocabRevision: 2,
            preparedURL: preparedURL,
            exportURL: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory),
            in: temporaryDirectory
        )

        XCTAssertEqual(reason, "compiled model appears corrupt (truncated ZIP archive at de-DE-prepared)")
    }

    func testCanRestoreIsFalseForRevisionMismatch() throws {
        let preparedURL = PreparedLanguageModelDiskCache.preparedModelURL(for: .german, in: temporaryDirectory)
        try validPreparedModelData().write(to: preparedURL)
        try Data("export".utf8).write(to: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory))
        try saveManifestMatchingArtifactBundle(for: .german, preparedURL: preparedURL, revision: 1)

        let reason = PreparedLanguageModelDiskCache.restoreSkipReason(
            for: .german,
            baseModelVersion: "4.0",
            vocabRevision: 2,
            preparedURL: preparedURL,
            exportURL: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory),
            in: temporaryDirectory
        )

        XCTAssertEqual(reason, "vocab revision mismatch (manifest 1, expected 2)")
        XCTAssertTrue(PreparedLanguageModelDiskCache.shouldPurgeArtifactsAfterRestoreSkip(reason!))
        XCTAssertFalse(
            PreparedLanguageModelDiskCache.canRestore(
                for: .german,
                baseModelVersion: "4.0",
                vocabRevision: 2,
                preparedURL: preparedURL,
                exportURL: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory),
                in: temporaryDirectory
            )
        )
    }

    func testCanRestoreIsFalseWhenPreparedDirectoryMissing() throws {
        let preparedURL = PreparedLanguageModelDiskCache.preparedModelURL(for: .german, in: temporaryDirectory)
        try Data("export".utf8).write(to: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory))
        try PreparedLanguageModelDiskCache.saveManifest(
            PreparedLanguageModelDiskCache.Manifest(
                baseModelVersion: "4.0",
                vocabRevision: 2,
                languageCode: RecognitionLanguage.german.rawValue,
                artifactBundleByteCount: 4096,
                artifactBundleSHA256: "abc",
                preparedModelRelativePath: preparedURL.lastPathComponent,
                preparedModelByteCount: nil,
                preparedModelSHA256: nil
            ),
            for: .german,
            in: temporaryDirectory
        )

        XCTAssertFalse(
            PreparedLanguageModelDiskCache.canRestore(
                for: .german,
                baseModelVersion: "4.0",
                vocabRevision: 2,
                preparedURL: preparedURL,
                exportURL: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory),
                in: temporaryDirectory
            )
        )
    }

    func testRemoveArtifactsDeletesManifestExportAndPreparedModel() throws {
        let preparedURL = PreparedLanguageModelDiskCache.preparedModelURL(for: .german, in: temporaryDirectory)
        let preparedSibling = preparedURL.appendingPathExtension("bin")
        try validPreparedModelData().write(to: preparedSibling)
        try Data("export".utf8).write(to: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory))
        try saveManifestMatchingArtifactBundle(for: .german, preparedURL: preparedSibling)

        PreparedLanguageModelDiskCache.removeArtifacts(for: .german, in: temporaryDirectory)

        XCTAssertNil(PreparedLanguageModelDiskCache.loadManifest(for: .german, in: temporaryDirectory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedSibling.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: PreparedLanguageModelDiskCache.exportURL(for: .german, in: temporaryDirectory).path
            )
        )
    }
}
