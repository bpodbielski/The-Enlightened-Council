// AnthropicClientTests.swift
// Tests the streaming chat contract that AnthropicClient will satisfy.
// No real network calls are made. All types are inline so the tests compile
// before production code exists. The production client must conform to
// StreamingChatClientProtocol with the same API surface.

import Foundation
import XCTest

// MARK: - Inline protocol and types

struct ChatMessage: Sendable {
    let role: String
    let content: String
}

protocol StreamingChatClientProtocol: Sendable {
    /// Returns an async throwing stream of string tokens.
    func streamChat(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error>
}

// MARK: - Mock client — happy path

/// Returns a pre-baked sequence of tokens in order.
struct MockStreamingChatClient: StreamingChatClientProtocol {
    let tokens: [String]

    func streamChat(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        let localTokens = tokens
        return AsyncThrowingStream { continuation in
            for token in localTokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }
}

// MARK: - Mock client — mid-stream error

struct MockErrorDescription: LocalizedError {
    let detail: String
    var errorDescription: String? { detail }
}

struct MockErrorStreamingChatClient: StreamingChatClientProtocol {
    let tokensBeforeError: [String]
    let error: Error

    func streamChat(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        let localTokens = tokensBeforeError
        let localError = error
        return AsyncThrowingStream { continuation in
            for token in localTokens {
                continuation.yield(token)
            }
            continuation.finish(throwing: localError)
        }
    }
}

// MARK: - Tests

final class AnthropicClientTests: XCTestCase {

    // MARK: Tokens arrive in order

    func test_streamingClient_tokensAppend_inOrder() async throws {
        let client = MockStreamingChatClient(tokens: ["Hello", " world", "!"])
        let messages = [ChatMessage(role: "user", content: "Hi")]

        var collected: [String] = []
        for try await token in client.streamChat(
            messages: messages,
            model: "claude-sonnet-4-5",
            temperature: 1.0
        ) {
            collected.append(token)
        }

        XCTAssertEqual(
            collected.joined(),
            "Hello world!",
            "Collected tokens joined should equal 'Hello world!'"
        )
        XCTAssertEqual(collected.count, 3, "Expected exactly 3 tokens")
    }

    // MARK: Mid-stream error propagates

    func test_streamingClient_errorPropagates() async {
        let expectedError = MockErrorDescription(detail: "mid-stream failure")
        let client = MockErrorStreamingChatClient(
            tokensBeforeError: ["Partial"],
            error: expectedError
        )
        let messages = [ChatMessage(role: "user", content: "Hello")]

        var collectedTokens: [String] = []
        var caughtError: Error?

        do {
            for try await token in client.streamChat(
                messages: messages,
                model: "claude-sonnet-4-5",
                temperature: 1.0
            ) {
                collectedTokens.append(token)
            }
        } catch {
            caughtError = error
        }

        XCTAssertNotNil(caughtError, "Expected an error to be thrown mid-stream")
        XCTAssertTrue(
            caughtError is MockErrorDescription,
            "Expected MockErrorDescription, got \(String(describing: caughtError))"
        )
        // Tokens before the error are still collected.
        XCTAssertEqual(collectedTokens, ["Partial"])
    }

    // MARK: Empty stream completes cleanly

    func test_streamingClient_emptyStream_completesCleanly() async throws {
        let client = MockStreamingChatClient(tokens: [])
        let messages = [ChatMessage(role: "user", content: "Hello")]

        var collected: [String] = []
        for try await token in client.streamChat(
            messages: messages,
            model: "claude-sonnet-4-5",
            temperature: 1.0
        ) {
            collected.append(token)
        }

        XCTAssertTrue(collected.isEmpty, "Empty stream should yield no tokens")
        XCTAssertEqual(collected.joined(), "", "Joined result of empty stream should be empty string")
    }
}
