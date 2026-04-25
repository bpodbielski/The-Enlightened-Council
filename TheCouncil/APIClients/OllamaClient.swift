import Foundation
import os.log

// MARK: - Error

enum OllamaError: Error, Sendable {
    case invalidBaseURL
    case serverError(Int)
    case invalidResponse
    case cancelled
    case transport(String)
}

// MARK: - OllamaClient
//
// Optional local bridge to a user-run Ollama server (default http://localhost:11434).
// NDJSON streaming — one JSON object per line, final frame has `"done": true`.
// Air-gap-safe by default: localhost traffic is never blocked by AirGapURLProtocol
// (only known cloud hostnames are on the blocklist), so this is the recommended
// fallback for confidential decisions when MLX isn't available.
actor OllamaClient: StreamingChatClient {

    static let shared = OllamaClient()

    private let db: DatabaseManager
    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "OllamaClient")
    private let timeoutInterval: TimeInterval = 300

    init(db: DatabaseManager = .shared) {
        self.db = db
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
                    try await self.performStream(
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

    // MARK: - Core stream

    private func performStream(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let base = try await resolveBaseURL()
        guard let url = URL(string: "/api/chat", relativeTo: base)?.absoluteURL else {
            throw OllamaError.invalidBaseURL
        }

        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.buildRequestBody(
            model: model,
            messages: messages,
            temperature: temperature
        )

        let config = URLSessionConfiguration.ephemeral
        AirGapNetworkGuard.install(into: config)
        let session = URLSession(configuration: config)

        let (bytes, response) = try await session.bytes(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OllamaError.serverError(http.statusCode)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            if let fragment = Self.parseResponseField(from: line), !fragment.isEmpty {
                continuation.yield(fragment)
            }
        }
    }

    // MARK: - Base URL resolution

    private func resolveBaseURL() async throws -> URL {
        var raw = "http://localhost:11434"
        if let fetched = try? await db.read({ db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'ollama_base_url'")
        }), !fetched.isEmpty {
            raw = fetched
        }
        guard let url = URL(string: raw) else { throw OllamaError.invalidBaseURL }
        return url
    }

    // MARK: - Static helpers (testable)

    static func buildRequestBody(
        model: String,
        messages: [ChatMessage],
        temperature: Double
    ) throws -> Data {
        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "options": ["temperature": temperature]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    static func parseResponseField(from line: String) -> String? {
        guard let data = line.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Chat API frames use `{ "message": { "role": "assistant", "content": "..." } }`.
        // Generate API frames use `{ "response": "..." }`. Accept either.
        if let message = obj["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        if let response = obj["response"] as? String {
            return response
        }
        return nil
    }
}
