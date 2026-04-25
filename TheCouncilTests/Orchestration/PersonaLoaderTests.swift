import Foundation
import XCTest
@testable import TheCouncil

final class PersonaLoaderTests: XCTestCase {

    func test_parse_validFrontMatter_extractsFields() throws {
        let src = """
        ---
        id: skeptic
        version: 1
        label: The Skeptic
        ---

        You are The Skeptic. Attack assumptions.
        """
        let p = try PersonaLoader().parse(src, expectedID: "skeptic")
        XCTAssertEqual(p.id, "skeptic")
        XCTAssertEqual(p.version, 1)
        XCTAssertEqual(p.label, "The Skeptic")
        XCTAssertTrue(p.systemPrompt.hasPrefix("You are The Skeptic"))
    }

    func test_parse_missingFrontMatter_throws() {
        let src = "no front matter here"
        XCTAssertThrowsError(try PersonaLoader().parse(src, expectedID: "skeptic"))
    }

    func test_parse_idMismatch_throws() {
        let src = """
        ---
        id: strategist
        version: 1
        label: The Strategist
        ---
        body
        """
        XCTAssertThrowsError(try PersonaLoader().parse(src, expectedID: "skeptic"))
    }

    func test_parse_invalidID_throws() {
        let src = """
        ---
        id: not-a-persona
        version: 1
        label: nope
        ---
        body
        """
        XCTAssertThrowsError(try PersonaLoader().parse(src, expectedID: "not-a-persona"))
    }
}
