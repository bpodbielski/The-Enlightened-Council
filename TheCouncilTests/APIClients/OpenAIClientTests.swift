import Foundation
import XCTest
@testable import TheCouncil

final class OpenAIClientTests: XCTestCase {

    // MARK: Parses a canned streaming delta

    func test_extractContentDelta_parsesStandardChunk() {
        let chunk = #"""
        {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}
        """#
        let text = OpenAIClient.extractContentDelta(from: chunk)
        XCTAssertEqual(text, "Hello")
    }

    // MARK: Ignores role-only chunks

    func test_extractContentDelta_returnsNilForRoleChunk() {
        let chunk = #"""
        {"choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}
        """#
        XCTAssertNil(OpenAIClient.extractContentDelta(from: chunk))
    }

    // MARK: Ignores malformed JSON

    func test_extractContentDelta_returnsNilForMalformed() {
        XCTAssertNil(OpenAIClient.extractContentDelta(from: "not json"))
        XCTAssertNil(OpenAIClient.extractContentDelta(from: "{}"))
    }

    // MARK: GPT-5 / o-series: max_completion_tokens, no temperature

    func test_buildBody_gpt5_usesMaxCompletionTokens_omitsTemperature() throws {
        let messages = [TheCouncil.ChatMessage(role: "user", content: "hi")]
        let data = try OpenAIClient.buildBody(messages: messages, model: "gpt-5.4", temperature: 0.7)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-5.4")
        XCTAssertEqual(json["max_completion_tokens"] as? Int, OpenAIClient.defaultMaxTokens)
        XCTAssertNil(json["max_tokens"])
        XCTAssertNil(json["temperature"], "GPT-5 only accepts default temperature; omit to avoid 400.")
        XCTAssertEqual(json["stream"] as? Bool, true)
    }

    func test_buildBody_oSeriesAlsoUsesMaxCompletionTokens() throws {
        for model in ["o1-preview", "o3", "o4-mini"] {
            let data = try OpenAIClient.buildBody(messages: [], model: model, temperature: 0.7)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNotNil(json["max_completion_tokens"], "Model \(model) should use max_completion_tokens")
            XCTAssertNil(json["max_tokens"], "Model \(model) must not send max_tokens")
        }
    }

    // MARK: Older models: max_tokens, temperature passed through

    func test_buildBody_gpt4o_usesMaxTokens_includesTemperature() throws {
        let messages = [TheCouncil.ChatMessage(role: "user", content: "hi")]
        let data = try OpenAIClient.buildBody(messages: messages, model: "gpt-4o-mini", temperature: 0.3)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["max_tokens"] as? Int, OpenAIClient.defaultMaxTokens)
        XCTAssertNil(json["max_completion_tokens"])
        XCTAssertEqual(json["temperature"] as? Double, 0.3)
    }
}
