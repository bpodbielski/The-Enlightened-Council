import Foundation
import XCTest
@testable import TheCouncil

final class ArgumentExtractorTests: XCTestCase {

    func test_parseArgumentsJSON_acceptsValidArray() throws {
        let raw = #"""
        [
          {"position": "for",     "text": "A1"},
          {"position": "against", "text": "A2"},
          {"position": "neutral", "text": "A3"}
        ]
        """#
        let parsed = try ArgumentExtractor.parseArgumentsJSON(raw)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].position, .for)
        XCTAssertEqual(parsed[1].position, .against)
        XCTAssertEqual(parsed[2].position, .neutral)
        XCTAssertEqual(parsed[2].text, "A3")
    }

    func test_parseArgumentsJSON_extractsArrayFromFencedCodeBlock() throws {
        let raw = """
        Here is the extraction:

        ```json
        [{"position": "for", "text": "wrapped"}]
        ```
        """
        let parsed = try ArgumentExtractor.parseArgumentsJSON(raw)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].text, "wrapped")
    }

    func test_parseArgumentsJSON_unknownPositionFallsBackToNeutral() throws {
        let raw = #"[{"position": "sideways", "text": "odd"}]"#
        let parsed = try ArgumentExtractor.parseArgumentsJSON(raw)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].position, .neutral)
    }

    func test_parseArgumentsJSON_malformedThrows() {
        XCTAssertThrowsError(try ArgumentExtractor.parseArgumentsJSON("not json"))
    }

    func test_parseArgumentsJSON_emptyArrayReturnsEmpty() throws {
        let parsed = try ArgumentExtractor.parseArgumentsJSON("[]")
        XCTAssertEqual(parsed.count, 0)
    }
}
