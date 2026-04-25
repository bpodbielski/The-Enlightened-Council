import Foundation
import XCTest
@testable import TheCouncil

final class LensTemplateLoaderTests: XCTestCase {

    func test_decode_validPayload_succeeds() throws {
        let json = #"""
        {
          "id": "strategic-bet",
          "label": "Strategic bet and capital allocation",
          "default_personas": ["strategist","finance-lens","risk-officer","operator","skeptic"],
          "default_rounds": 3,
          "default_samples": 3
        }
        """#
        let data = json.data(using: .utf8)!
        let loader = LensTemplateLoader()
        let t = try loader.decode(data, expectedID: "strategic-bet")

        XCTAssertEqual(t.id, "strategic-bet")
        XCTAssertEqual(t.defaultRounds, 3)
        XCTAssertEqual(t.defaultSamples, 3)
        XCTAssertEqual(t.defaultPersonas.first, "strategist")
    }

    func test_decode_rejectsIDMismatch() {
        let json = #"""
        {"id":"strategic-bet","label":"x","default_personas":[],"default_rounds":1,"default_samples":1}
        """#.data(using: .utf8)!
        let loader = LensTemplateLoader()
        XCTAssertThrowsError(try loader.decode(json, expectedID: "market-entry"))
    }

    func test_decode_rejectsUnknownID() {
        let json = #"""
        {"id":"not-a-real-lens","label":"x","default_personas":[],"default_rounds":1,"default_samples":1}
        """#.data(using: .utf8)!
        let loader = LensTemplateLoader()
        XCTAssertThrowsError(try loader.decode(json, expectedID: "not-a-real-lens"))
    }

    func test_validIDs_hasAllEight() {
        XCTAssertEqual(LensTemplate.validIDs.count, 8)
    }
}
