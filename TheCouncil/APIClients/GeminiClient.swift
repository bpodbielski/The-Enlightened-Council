import Foundation
import os.log

enum GeminiError: Error, Equatable {
    case missingAPIKey
    case airGapActive
    case unauthorized
    case rateLimited
    case serverError(Int)
    case timeout
    case invalidResponse
    case emptyResponse
}

/// Streaming client for Google Gemini (`streamGenerateContent?alt=sse`).
/// Response format differs from OpenAI/Anthropic: each SSE chunk contains a
/// full JSON object whose `candidates[0].content.parts[].text` is appended.
actor GeminiClient: StreamingChatClient {

    static let shared = GeminiClient()

    private let db: DatabaseManager
    private let keychain: KeychainStore
    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "GeminiClient")

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let timeoutInterval: TimeInterval = 120
    private let maxOutputTokens = 8192

    private let rateLimitMaxRetries = 5
    private let rateLimitInitialDelay: TimeInterval = 2
    private let rateLimitMaxDelay: TimeInterval = 64
    private let serverErrorMaxRetries = 3
    private let serverErrorDelay: TimeInterval = 2

    init(db: DatabaseManager = .shared, keychain: KeychainStore = KeychainStore()) {
        self.db = db
        self.keychain = keychain
    }

    nonisolated func streamChat(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
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
        }
    }

    private func performStream(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let airGapValue = try await db.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'air_gap_enabled'")
        }
        if airGapValue == "true" { throw GeminiError.airGapActive }
        guard let apiKey = try keychain.load(for: .google), !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }
        let body = try buildBody(messages: messages, temperature: temperature)
        try await streamWithRetries(model: model, body: body, apiKey: apiKey, continuation: continuation)
    }

    private func streamWithRetries(
        model: String,
        body: Data,
        apiKey: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var rateLimitAttempt = 0
        var rateLimitDelay = rateLimitInitialDelay
        while true {
            var serverErrorAttempt = 0
            while true {
                do {
                    let request = buildRequest(model: model, body: body, apiKey: apiKey)
                    try await executeStream(request: request, continuation: continuation)
                    return
                } catch GeminiError.unauthorized {
                    throw GeminiError.unauthorized
                } catch GeminiError.rateLimited {
                    break
                } catch GeminiError.serverError(let code) {
                    serverErrorAttempt += 1
                    if serverErrorAttempt >= serverErrorMaxRetries {
                        throw GeminiError.serverError(code)
                    }
                    try await Task.sleep(nanoseconds: UInt64(serverErrorDelay * 1_000_000_000))
                    continue
                } catch {
                    throw error
                }
            }
            rateLimitAttempt += 1
            if rateLimitAttempt >= rateLimitMaxRetries { throw GeminiError.rateLimited }
            try await Task.sleep(nanoseconds: UInt64(rateLimitDelay * 1_000_000_000))
            rateLimitDelay = min(rateLimitDelay * 2, rateLimitMaxDelay)
        }
    }

    private func executeStream(
        request: URLRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval
        AirGapNetworkGuard.install(into: config)
        let session = URLSession(configuration: config)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw GeminiError.unauthorized
        case 429: throw GeminiError.rateLimited
        case 500...599: throw GeminiError.serverError(http.statusCode)
        default: throw GeminiError.serverError(http.statusCode)
        }

        var any = false
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            if let text = Self.extractText(from: json) {
                any = true
                continuation.yield(text)
            }
        }
        if !any { throw GeminiError.emptyResponse }
    }

    private func buildBody(messages: [ChatMessage], temperature: Double) throws -> Data {
        // Gemini expects `contents: [{role, parts: [{text}]}]` with roles
        // "user" and "model" (not "assistant"). System messages go to a
        // top-level `systemInstruction`.
        var systemText: String?
        var contents: [[String: Any]] = []
        for msg in messages {
            if msg.role == "system" {
                systemText = (systemText.map { $0 + "\n\n" } ?? "") + msg.content
                continue
            }
            let role = (msg.role == "assistant") ? "model" : "user"
            contents.append([
                "role": role,
                "parts": [["text": msg.content]]
            ])
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": temperature,
                "maxOutputTokens": maxOutputTokens
            ]
        ]
        if let sys = systemText {
            body["systemInstruction"] = ["parts": [["text": sys]]]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func buildRequest(model: String, body: Data, apiKey: String) -> URLRequest {
        let url = URL(string: "\(baseURL)/\(model):streamGenerateContent?alt=sse&key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeoutInterval
        return req
    }

    static func extractText(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { return nil }
        let texts = parts.compactMap { $0["text"] as? String }
        return texts.isEmpty ? nil : texts.joined()
    }
}
