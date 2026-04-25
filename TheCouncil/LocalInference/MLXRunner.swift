import Foundation
import os.log

// MARK: - Error

enum MLXRunnerError: Error, Sendable {
    case resourceUnavailable(String)
    case modelNotDownloaded(id: String)
    case loadFailed(String)
    case cancelled
}

// MARK: - Model catalog

struct LocalModelCatalogEntry: Sendable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let approximateSizeBytes: UInt64
    let minFreeMemoryBytes: UInt64
    let fallbackID: String?
}

// MARK: - MLXRunner
//
// Sequential load/run/unload runner for Apple MLX. The actor owns the in-flight
// model so two loads cannot overlap — Qwen 32B must unload before Mistral 22B
// can load on a 32 GB Mac (SPEC §6.1 local tier, §8.2 memory gate).
//
// Real MLX inference binding (MLXLLM loader + generate loop) is wired in a
// Phase 3/4 polish pass; this runner presently emits a deterministic placeholder
// stream so the orchestrator can dispatch local tasks through the same
// `StreamingChatClient` pipe as cloud tasks. All lifecycle ceremony (gate check,
// catalog lookup, load/unload hooks, thermal throttle) is already in place and
// is exercised by tests.
actor MLXRunner: StreamingChatClient {

    static let shared = MLXRunner()

    static let knownModels: [LocalModelCatalogEntry] = [
        .init(id: "qwen-2.5-32b-instruct", displayName: "Qwen 2.5 32B Instruct",
              approximateSizeBytes: 20 * 1_024 * 1_024 * 1_024,
              minFreeMemoryBytes: 20 * 1_024 * 1_024 * 1_024,
              fallbackID: "qwen-2.5-14b-instruct"),
        .init(id: "qwen-2.5-14b-instruct", displayName: "Qwen 2.5 14B Instruct",
              approximateSizeBytes: 9 * 1_024 * 1_024 * 1_024,
              minFreeMemoryBytes: 10 * 1_024 * 1_024 * 1_024,
              fallbackID: nil),
        .init(id: "mistral-small-22b", displayName: "Mistral Small 22B",
              approximateSizeBytes: 14 * 1_024 * 1_024 * 1_024,
              minFreeMemoryBytes: 14 * 1_024 * 1_024 * 1_024,
              fallbackID: nil)
    ]

    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "MLXRunner")
    private let gate: LocalResourceGate
    private var loadedModelID: String?

    init(gate: LocalResourceGate = LocalResourceGate()) {
        self.gate = gate
    }

    // MARK: - StreamingChatClient

    nonisolated func streamChat(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runStream(
                        messages: messages,
                        model: model,
                        temperature: temperature,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Core loop

    private func runStream(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let entry = Self.knownModels.first(where: { $0.id == model }) else {
            throw MLXRunnerError.loadFailed("Unknown local model id '\(model)'")
        }

        switch gate.check(minFreeBytes: entry.minFreeMemoryBytes) {
        case .ok:
            break
        case .insufficientMemory(let needed, let free):
            throw MLXRunnerError.resourceUnavailable(
                "Memory gate: need \(needed / 1_073_741_824) GB, only \(free / 1_073_741_824) GB free"
            )
        case .thermalThrottle(let state):
            throw MLXRunnerError.resourceUnavailable("Thermal state \(state.displayLabel) blocks local load")
        }

        try await load(entry: entry)
        defer { Task { await self.unload() } }

        // Placeholder stream. Real MLXLLM generate loop slots in here — it emits
        // chunks on the same continuation. Keeping it deterministic lets the
        // orchestrator and tests exercise the full dispatch path today.
        let preview = messages.last?.content.prefix(80) ?? ""
        let tokens = [
            "[MLX \(entry.displayName) @ T=\(String(format: "%.1f", temperature))] ",
            "response stub for: \"\(preview)\""
        ]
        for tok in tokens {
            try Task.checkCancellation()
            continuation.yield(tok)
        }
    }

    // MARK: - Load / unload

    private func load(entry: LocalModelCatalogEntry) async throws {
        if let current = loadedModelID, current != entry.id {
            await unload()
        }
        if loadedModelID == entry.id { return }
        Self.logger.info("Loading local model \(entry.id)")
        // Real implementation: fetch weights path from ModelDownloadManager,
        // initialize MLXLLM loader on a background context. Failure → .loadFailed.
        loadedModelID = entry.id
    }

    private func unload() async {
        guard let id = loadedModelID else { return }
        Self.logger.info("Unloading local model \(id)")
        loadedModelID = nil
    }

    // MARK: - Test hooks

    func currentLoadedID() -> String? { loadedModelID }
}
