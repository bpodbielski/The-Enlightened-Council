import Foundation
import os.log

// MARK: - Download status

enum ModelDownloadStatus: Sendable, Equatable {
    case notStarted
    case inProgress(bytesDownloaded: Int64, bytesTotal: Int64)
    case completed
    case failed(String)
}

// MARK: - ModelDownloadManager
//
// Manages on-disk local model weights under the app's Application Support
// folder (SPEC §11 data paths). The manager does not perform inference — that
// belongs to MLXRunner / Ollama. It only handles placement and presence checks.
actor ModelDownloadManager {

    static let shared = ModelDownloadManager()

    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "ModelDownloadManager")
    private let destinationDirectory: URL
    private var statuses: [String: ModelDownloadStatus] = [:]

    init(destinationDirectory: URL = ModelDownloadManager.defaultDestination()) {
        self.destinationDirectory = destinationDirectory
    }

    // MARK: - Defaults

    static func defaultDestination() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("The Council/models", isDirectory: true)
    }

    // MARK: - Presence

    func isDownloaded(modelID: String) -> Bool {
        let dir = destinationDirectory.appendingPathComponent(modelID, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return !contents.isEmpty
    }

    func status(for modelID: String) -> ModelDownloadStatus {
        if isDownloaded(modelID: modelID) { return .completed }
        return statuses[modelID] ?? .notStarted
    }

    // MARK: - Filesystem

    func modelDirectory(for modelID: String) -> URL {
        destinationDirectory.appendingPathComponent(modelID, isDirectory: true)
    }

    func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
    }

    func removeModel(modelID: String) throws {
        let dir = modelDirectory(for: modelID)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        statuses.removeValue(forKey: modelID)
    }

    // MARK: - Download (scaffold)
    //
    // Phase 3 ships the directory/presence plumbing. Actual download transports
    // (HuggingFace Hub, user-provided URL, drag-drop import) slot in as a later
    // step — the UI in Settings → Air Gap calls `beginDownload(modelID:from:)`
    // once that lands.
    func beginDownload(modelID: String, from remoteURL: URL) async throws {
        try ensureDirectoryExists()
        statuses[modelID] = .inProgress(bytesDownloaded: 0, bytesTotal: 0)
        Self.logger.info("Queued download request for \(modelID) from \(remoteURL.absoluteString)")
        throw NSError(
            domain: "TheCouncil.ModelDownload",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Download transport not yet implemented. Place weights manually in \(modelDirectory(for: modelID).path)"]
        )
    }
}
