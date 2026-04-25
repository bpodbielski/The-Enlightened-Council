import Foundation
import XCTest
@testable import TheCouncil

final class ModelDownloadManagerTests: XCTestCase {

    func test_defaultDestination_isApplicationSupportModelsFolder() {
        let url = ModelDownloadManager.defaultDestination()
        XCTAssertTrue(url.path.contains("Application Support"))
        XCTAssertTrue(url.path.hasSuffix("/models") || url.path.hasSuffix("/models/"))
    }

    func test_isDownloaded_falseForMissingFile() async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let mgr = ModelDownloadManager(destinationDirectory: tmp)
        let downloaded = await mgr.isDownloaded(modelID: "qwen-2.5-32b-instruct")
        XCTAssertFalse(downloaded)
    }

    func test_isDownloaded_trueAfterPlacementOnDisk() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let mgr = ModelDownloadManager(destinationDirectory: tmp)
        let modelDir = tmp.appendingPathComponent("qwen-2.5-32b-instruct")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try "x".data(using: .utf8)!.write(to: modelDir.appendingPathComponent("weights.bin"))
        let downloaded = await mgr.isDownloaded(modelID: "qwen-2.5-32b-instruct")
        XCTAssertTrue(downloaded)
    }
}
