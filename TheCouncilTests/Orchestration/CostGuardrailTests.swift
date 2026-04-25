import Foundation
import XCTest
@testable import TheCouncil

final class CostGuardrailTests: XCTestCase {

    func test_softWarnCrossed_onlyOnceAtBoundary() {
        let g = CostGuardrails(softWarnUsd: 2, hardPauseUsd: 5)
        XCTAssertEqual(g.evaluate(previousTotal: 1.99, newTotal: 2.01), .softWarnCrossed)
        XCTAssertEqual(g.evaluate(previousTotal: 2.01, newTotal: 2.50), .ok)
    }

    func test_hardPauseCrossed_trumpsSoft() {
        let g = CostGuardrails(softWarnUsd: 2, hardPauseUsd: 5)
        XCTAssertEqual(g.evaluate(previousTotal: 0, newTotal: 5.01), .hardPauseCrossed)
    }

    func test_hardPause_aloneWhenAlreadyPastSoft() {
        let g = CostGuardrails(softWarnUsd: 2, hardPauseUsd: 5)
        XCTAssertEqual(g.evaluate(previousTotal: 4.99, newTotal: 5.00), .hardPauseCrossed)
    }

    func test_ok_whenBelowAllThresholds() {
        let g = CostGuardrails(softWarnUsd: 2, hardPauseUsd: 5)
        XCTAssertEqual(g.evaluate(previousTotal: 0, newTotal: 0.50), .ok)
    }

    func test_defaults_matchSpec() {
        XCTAssertEqual(CostGuardrails.defaults.softWarnUsd, 2.00)
        XCTAssertEqual(CostGuardrails.defaults.hardPauseUsd, 5.00)
    }
}
