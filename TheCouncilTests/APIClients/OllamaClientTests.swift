import Foundation
import XCTest
@testable import TheCouncil

final class OllamaClientTests: XCTestCase {

    func test_parseNDJSONChunk_extractsResponseField() {
        let line = #"{"model":"qwen2.5:32b","response":"Hello","done":false}"#
        XCTAssertEqual(OllamaClient.parseResponseField(from: line), "Hello")
    }

    func test_parseNDJSONChunk_returnsNilForDoneFrame() {
        let line = #"{"model":"qwen2.5:32b","response":"","done":true}"#
        XCTAssertEqual(OllamaClient.parseResponseField(from: line), "")
    }

    func test_parseNDJSONChunk_returnsNilForMalformed() {
        XCTAssertNil(OllamaClient.parseResponseField(from: "not-json"))
    }

    func test_buildRequestBody_includesMessagesAndTemperature() throws {
        let body = try OllamaClient.buildRequestBody(
            model: "mistral-small:22b",
            messages: [
                TheCouncil.ChatMessage(role: "system", content: "sys"),
                TheCouncil.ChatMessage(role: "user", content: "hi")
            ],
            temperature: 0.3
        )
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "mistral-small:22b")
        XCTAssertEqual(json?["stream"] as? Bool, true)
        let msgs = json?["messages"] as? [[String: Any]]
        XCTAssertEqual(msgs?.count, 2)
        XCTAssertEqual(msgs?[0]["role"] as? String, "system")
        let options = json?["options"] as? [String: Any]
        XCTAssertEqual(options?["temperature"] as? Double, 0.3)
    }
}
