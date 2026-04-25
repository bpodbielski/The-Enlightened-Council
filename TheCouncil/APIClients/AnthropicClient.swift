import Foundation
import os.log

// MARK: - AnthropicError

enum AnthropicError: Error {
    case missingAPIKey
    case airGapActive
    case unauthorized           // 401
    case rateLimited            // 429 (after max retries)
    case serverError(Int)       // 5xx (after max retries)
    case timeout                // > 120s
    case invalidResponse        // unexpected format
    case emptyResponse          // no text tokens received
}

// MARK: - AnthropicClient

actor AnthropicClient: StreamingChatClient {

    static let shared = AnthropicClient()

    private let db: DatabaseManager
    private let keychain: KeychainStore
    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "AnthropicClient")

    private let endpointURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"
    private let maxTokens = 8192
    private let timeoutInterval: TimeInterval = 120

    // Retry configuration
    private let rateLimitMaxRetries = 5
    private let rateLimitInitialDelay: TimeInterval = 2
    private let rateLimitMaxDelay: TimeInterval = 64
    private let serverErrorMaxRetries = 3
    private let serverErrorDelay: TimeInterval = 2

    init(db: DatabaseManager = .shared, keychain: KeychainStore = KeychainStore()) {
        self.db = db
        self.keychain = keychain
    }

    // MARK: - StreamingChatClient

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
                        systemPrompt: nil,
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

    // MARK: - Refinement stream (includes system prompt)

    nonisolated func streamRefinement(
        systemPrompt: String,
        messages: [ChatMessage],
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.performStream(
                        messages: messages,
                        systemPrompt: systemPrompt,
                        model: model,
                        temperature: 0.7,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Core streaming implementation

    private func performStream(
        messages: [ChatMessage],
        systemPrompt: String?,
        model: String,
        temperature: Double,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        // Air gap check — read at call time
        let airGapValue = try await db.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'air_gap_enabled'")
        }
        if airGapValue == "true" {
            throw AnthropicError.airGapActive
        }

        // Load API key
        guard let apiKey = try keychain.load(for: .anthropic), !apiKey.isEmpty else {
            throw AnthropicError.missingAPIKey
        }

        // Build request body
        let requestBody = try buildRequestBody(
            messages: messages,
            systemPrompt: systemPrompt,
            model: model,
            temperature: temperature
        )

        // Attempt with retries
        try await streamWithRetries(
            requestBody: requestBody,
            apiKey: apiKey,
            continuation: continuation
        )
    }

    private func streamWithRetries(
        requestBody: Data,
        apiKey: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        // Rate limit retries (outer loop)
        var rateLimitAttempt = 0
        var rateLimitDelay = rateLimitInitialDelay

        while true {
            // Server error retries (inner loop)
            var serverErrorAttempt = 0

            while true {
                do {
                    let request = buildURLRequest(body: requestBody, apiKey: apiKey)
                    try await executeStream(request: request, continuation: continuation)
                    return // Success
                } catch AnthropicError.unauthorized {
                    throw AnthropicError.unauthorized
                } catch AnthropicError.rateLimited {
                    // Break inner loop to handle rate limit retry
                    break
                } catch AnthropicError.serverError(let code) {
                    serverErrorAttempt += 1
                    if serverErrorAttempt >= serverErrorMaxRetries {
                        throw AnthropicError.serverError(code)
                    }
                    Self.logger.debug("Server error \(code), retry \(serverErrorAttempt)/\(self.serverErrorMaxRetries)")
                    try await Task.sleep(nanoseconds: UInt64(serverErrorDelay * 1_000_000_000))
                    continue
                } catch {
                    throw error
                }
            }

            // Handle rate limit
            rateLimitAttempt += 1
            if rateLimitAttempt >= rateLimitMaxRetries {
                throw AnthropicError.rateLimited
            }
            Self.logger.debug("Rate limited, retry \(rateLimitAttempt)/\(self.rateLimitMaxRetries) after \(rateLimitDelay)s")
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

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw AnthropicError.unauthorized
        case 429:
            throw AnthropicError.rateLimited
        case 500...599:
            throw AnthropicError.serverError(httpResponse.statusCode)
        default:
            throw AnthropicError.serverError(httpResponse.statusCode)
        }

        var receivedAnyText = false

        for try await line in bytes.lines {
            // SSE format: "data: <json>" or "event: ..." or blank lines
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard jsonString != "[DONE]" else { break }

            if let text = extractTextDelta(from: jsonString) {
                receivedAnyText = true
                continuation.yield(text)
            }
        }

        if !receivedAnyText {
            throw AnthropicError.emptyResponse
        }
    }

    // MARK: - Helpers

    private func buildRequestBody(
        messages: [ChatMessage],
        systemPrompt: String?,
        model: String,
        temperature: Double
    ) throws -> Data {
        // Filter out system messages from the messages array
        let userAssistantMessages = messages.filter { $0.role != "system" }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": true,
            "messages": userAssistantMessages.map { ["role": $0.role, "content": $0.content] }
        ]

        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

        return try JSONSerialization.data(withJSONObject: body)
    }

    private func buildURLRequest(body: Data, apiKey: String) -> URLRequest {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = timeoutInterval
        return request
    }

    private func extractTextDelta(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "content_block_delta",
              let delta = json["delta"] as? [String: Any],
              let deltaType = delta["type"] as? String,
              deltaType == "text_delta",
              let text = delta["text"] as? String
        else { return nil }
        return text
    }
}
