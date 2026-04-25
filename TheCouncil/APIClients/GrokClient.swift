import Foundation
import os.log

enum GrokError: Error, Equatable {
    case missingAPIKey
    case airGapActive
    case unauthorized
    case rateLimited
    case serverError(Int)
    case timeout
    case invalidResponse
    case emptyResponse
}

/// Streaming client for xAI Grok. The xAI API is OpenAI-compatible — the
/// request/response shape matches `OpenAIClient`, only the base URL and auth
/// scope differ.
actor GrokClient: StreamingChatClient {

    static let shared = GrokClient()

    private let db: DatabaseManager
    private let keychain: KeychainStore
    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "GrokClient")

    private let endpointURL = URL(string: "https://api.x.ai/v1/chat/completions")!
    private let maxTokens = 8192
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

    private func performStream(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let airGapValue = try await db.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'air_gap_enabled'")
        }
        if airGapValue == "true" { throw GrokError.airGapActive }
        guard let apiKey = try keychain.load(for: .xai), !apiKey.isEmpty else {
            throw GrokError.missingAPIKey
        }
        let body = try buildBody(messages: messages, model: model, temperature: temperature)
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
                } catch GrokError.unauthorized {
                    throw GrokError.unauthorized
                } catch GrokError.rateLimited {
                    break
                } catch GrokError.serverError(let code) {
                    serverErrorAttempt += 1
                    if serverErrorAttempt >= serverErrorMaxRetries {
                        throw GrokError.serverError(code)
                    }
                    try await Task.sleep(nanoseconds: UInt64(serverErrorDelay * 1_000_000_000))
                    continue
                } catch {
                    throw error
                }
            }
            rateLimitAttempt += 1
            if rateLimitAttempt >= rateLimitMaxRetries { throw GrokError.rateLimited }
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
        guard let http = response as? HTTPURLResponse else { throw GrokError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 401: throw GrokError.unauthorized
        case 429: throw GrokError.rateLimited
        case 500...599: throw GrokError.serverError(http.statusCode)
        default: throw GrokError.serverError(http.statusCode)
        }

        var any = false
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard json != "[DONE]" else { break }
            if let delta = OpenAIClient.extractContentDelta(from: json) {
                any = true
                continuation.yield(delta)
            }
        }
        if !any { throw GrokError.emptyResponse }
    }

    private func buildBody(messages: [ChatMessage], model: String, temperature: Double) throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": true,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
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
}
