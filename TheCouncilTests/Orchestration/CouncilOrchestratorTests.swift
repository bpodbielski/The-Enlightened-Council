import Foundation
import XCTest
@testable import TheCouncil

final class CouncilOrchestratorTests: XCTestCase {

    func test_run_withEmptyTaskSet_emitsFinishedImmediately() async {
        let orch = CouncilOrchestrator(
            db: DatabaseManager.shared,
            clientForProvider: { _ in nil }
        )
        let stream = await orch.run(tasksByRound: [:], guardrails: .defaults)

        var events: [OrchestratorEvent] = []
        for await evt in stream { events.append(evt) }

        XCTAssertEqual(events.count, 1)
        if case .finished(let c, let f, let cost) = events.last! {
            XCTAssertEqual(c, 0)
            XCTAssertEqual(f, 0)
            XCTAssertEqual(cost, 0)
        } else {
            XCTFail("Expected .finished, got \(events)")
        }
    }

    func test_temperatureForSample_matchesSpec() {
        XCTAssertEqual(CouncilConfigurationViewModel.temperature(forSample: 1), 0.3)
        XCTAssertEqual(CouncilConfigurationViewModel.temperature(forSample: 2), 0.7)
        XCTAssertEqual(CouncilConfigurationViewModel.temperature(forSample: 3), 1.0)
    }

    func test_modelSpec_estimatedCost_matchesArithmetic() {
        let spec = ModelSpec(id: "test", provider: .openai, inputCostPer1MUsd: 2.00, outputCostPer1MUsd: 4.00)
        // 500k input → $1; 250k output → $1  → total $2
        XCTAssertEqual(spec.estimatedCost(tokensIn: 500_000, tokensOut: 250_000), 2.00, accuracy: 0.0001)
    }

    func test_frontierSet_hasFourProvidersPerSpec() {
        let providers = Set(ModelSpec.frontierSet.map { $0.provider })
        XCTAssertTrue(providers.contains(.anthropic))
        XCTAssertTrue(providers.contains(.openai))
        XCTAssertTrue(providers.contains(.google))
        XCTAssertTrue(providers.contains(.xai))
        XCTAssertEqual(ModelSpec.frontierSet.count, 4)
    }
}
