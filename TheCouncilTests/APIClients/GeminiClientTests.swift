import Foundation
import XCTest
@testable import TheCouncil

final class GeminiClientTests: XCTestCase {

    func test_extractText_joinsAllPartsInCandidate() {
        let chunk = #"""
        {"candidates":[{"content":{"parts":[{"text":"Hello "},{"text":"world"}],"role":"model"},"finishReason":null}]}
        """#
        XCTAssertEqual(GeminiClient.extractText(from: chunk), "Hello world")
    }

    func test_extractText_nilForEmptyParts() {
        let chunk = #"{"candidates":[{"content":{"parts":[]}}]}"#
        XCTAssertNil(GeminiClient.extractText(from: chunk))
    }

    func test_extractText_nilForMissingCandidates() {
        XCTAssertNil(GeminiClient.extractText(from: "{}"))
        XCTAssertNil(GeminiClient.extractText(from: "not json"))
    }
}
