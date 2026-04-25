import Foundation
import os.log

enum OpenAIError: Error, Equatable {
    case missingAPIKey
    case airGapActive
    case unauthorized
    case rateLimited
    case serverError(Int)
    case timeout
    case invalidResponse
    case emptyResponse
}

/// Streaming client for OpenAI Chat Completions (SSE). Shape mirrors
/// AnthropicClient so the orchestrator can treat providers uniformly.
actor OpenAIClient: StreamingChatClient {

    static let shared = OpenAIClient()

    private let db: DatabaseManager
    private let keychain: KeychainStore
    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "OpenAIClient")

    private let endpointURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    static let defaultMaxTokens = 8192
    private let timeoutInterval: TimeInterval = 120

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

    // MARK: - Core

    private func performStream(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let airGapValue = try await db.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'air_gap_enabled'")
        }
        if airGapValue == "true" {
            throw OpenAIError.airGapActive
        }
        guard let apiKey = try keychain.load(for: .openai), !apiKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }
        let body = try Self.buildBody(messages: messages, model: model, temperature: temperature)
        try await streamWithRetries(body: body, apiKey: apiKey, continuation: continuation)
    }

    private func streamWithRetries(
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
                    let request = buildRequest(body: body, apiKey: apiKey)
                    try await executeStream(request: request, continuation: continuation)
                    return
                } catch OpenAIError.unauthorized {
                    throw OpenAIError.unauthorized
                } catch OpenAIError.rateLimited {
                    break
                } catch OpenAIError.serverError(let code) {
                    serverErrorAttempt += 1
                    if serverErrorAttempt >= serverErrorMaxRetries {
                        throw OpenAIError.serverError(code)
                    }
                    Self.logger.debug("OpenAI 5xx \(code) retry \(serverErrorAttempt)")
                    try await Task.sleep(nanoseconds: UInt64(serverErrorDelay * 1_000_000_000))
                    continue
                } catch {
                    throw error
                }
            }
            rateLimitAttempt += 1
            if rateLimitAttempt >= rateLimitMaxRetries { throw OpenAIError.rateLimited }
            Self.logger.debug("OpenAI 429 retry \(rateLimitAttempt) after \(rateLimitDelay)s")
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
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }

        switch http.statusCode {
        case 200: break
        case 401: throw OpenAIError.unauthorized
        case 429: throw OpenAIError.rateLimited
        case 500...599: throw OpenAIError.serverError(http.statusCode)
        default: throw OpenAIError.serverError(http.statusCode)
        }

        var any = false
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard json != "[DONE]" else { break }
            if let delta = Self.extractContentDelta(from: json) {
                any = true
                continuation.yield(delta)
            }
        }
        if !any { throw OpenAIError.emptyResponse }
    }

    // MARK: - Helpers

    /// GPT-5 family rejects `max_tokens` and only accepts default temperature.
    /// See OpenAI API: 400 "Unsupported parameter: 'max_tokens'... Use 'max_completion_tokens' instead."
    static func usesCompletionTokensParam(model: String) -> Bool {
        let id = model.lowercased()
        return id.hasPrefix("gpt-5") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4")
    }

    static func buildBody(messages: [ChatMessage], model: String, temperature: Double) throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        if usesCompletionTokensParam(model: model) {
            body["max_completion_tokens"] = defaultMaxTokens
            // GPT-5 / o-series only accept default temperature; omit to avoid 400.
        } else {
            body["max_tokens"] = defaultMaxTokens
            body["temperature"] = temperature
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func buildRequest(body: Data, apiKey: String) -> URLRequest {
        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeoutInterval
        return req
    }

    static func extractContentDelta(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return nil }
        return content
    }
}
