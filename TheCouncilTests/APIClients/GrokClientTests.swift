import Foundation
import XCTest
@testable import TheCouncil

final class GrokClientTests: XCTestCase {

    // Grok uses the OpenAI chunk shape — verify the same extractor works.

    func test_grokChunk_parsedByOpenAIExtractor() {
        let chunk = #"""
        {"id":"x1","choices":[{"index":0,"delta":{"content":"grokked"},"finish_reason":null}]}
        """#
        XCTAssertEqual(OpenAIClient.extractContentDelta(from: chunk), "grokked")
    }

    func test_airGapURLProtocol_blocksXaiHost() {
        AirGapURLProtocol.active = true
        defer { AirGapURLProtocol.active = false }

        let request = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
        XCTAssertTrue(AirGapURLProtocol.canInit(with: request))
    }

    func test_airGapURLProtocol_letsThroughWhenInactive() {
        AirGapURLProtocol.active = false
        let request = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
        XCTAssertFalse(AirGapURLProtocol.canInit(with: request))
    }

    func test_airGapURLProtocol_ignoresUnrelatedHost() {
        AirGapURLProtocol.active = true
        defer { AirGapURLProtocol.active = false }

        let request = URLRequest(url: URL(string: "https://example.com/ok")!)
        XCTAssertFalse(AirGapURLProtocol.canInit(with: request))
    }
}
