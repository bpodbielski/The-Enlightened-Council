import XCTest
@testable import TheCouncil

final class MarkdownRendererTests: XCTestCase {

    // MARK: - Helpers

    private func makeDecision(question: String = "Should we ship the new pricing?") -> Decision {
        Decision(
            id: "d1",
            createdAt: Date(timeIntervalSince1970: 1_777_017_600),
            status: .complete,
            question: question,
            lensTemplate: "growth-strategy",
            reversibility: .reversible,
            timeHorizon: .quarters,
            sensitivityClass: .public,
            successCriteria: "20% lift",
            refinedBrief: nil,
            refinementChatLog: nil
        )
    }

    private func makeVerdict(status: OutcomeStatus = .pending, decisionId: String = "d1") -> Verdict {
        Verdict(
            id: "v1",
            decisionId: decisionId,
            createdAt: Date(timeIntervalSince1970: 1_777_017_600),
            verdictText: "Ship the new pricing in Q2.",
            confidence: 75,
            keyForJson: VerdictCaptureViewModel.encodeArgumentTexts([
                TrayItem(id: "a", nodeId: "n1", text: "Margins improve", position: .for, modelId: "m"),
                TrayItem(id: "b", nodeId: "n2", text: "Competitor priced up", position: .for, modelId: "m")
            ]),
            keyAgainstJson: VerdictCaptureViewModel.encodeArgumentTexts([
                TrayItem(id: "c", nodeId: "n3", text: "Existing customers may churn", position: .against, modelId: "m")
            ]),
            risk: "Churn at top of funnel.",
            blindSpot: "Enterprise contracts auto-renew.",
            opportunity: "Capture mid-market.",
            preMortem: "- Sales pipeline stalls\n- PR backlash",
            outcomeDeadline: Date(timeIntervalSince1970: 1_777_017_600 + 60 * 86_400),
            testAction: "Run pilot at 3 accounts",
            testMetric: "Conversion %",
            testThreshold: "+10%",
            outcomeStatus: status
        )
    }

    private func makeRuns() -> [ModelRun] {
        let now = Date()
        return [
            ModelRun(id: UUID().uuidString, decisionId: "d1", modelName: "claude-opus-4-7",
                     provider: .anthropic, persona: "analyst", roundNumber: 1, sampleNumber: 1,
                     temperature: 0.3, prompt: "p", response: "r", tokensIn: 100, tokensOut: 200,
                     costUsd: 0.50, createdAt: now, error: nil, positionChanged: nil),
            ModelRun(id: UUID().uuidString, decisionId: "d1", modelName: "gpt-5.4",
                     provider: .openai, persona: "skeptic", roundNumber: 1, sampleNumber: 1,
                     temperature: 0.3, prompt: "p", response: "r", tokensIn: 100, tokensOut: 200,
                     costUsd: 0.30, createdAt: now, error: nil, positionChanged: nil),
        ]
    }

    private func makePayload(status: OutcomeStatus = .pending, outcome: Outcome? = nil) -> ExportPayload {
        ExportPayload(decision: makeDecision(),
                      verdict: makeVerdict(status: status),
                      outcome: outcome,
                      modelRuns: makeRuns())
    }

    // MARK: - Section coverage

    func test_render_includesAllRequiredHeaders() {
        let md = MarkdownRenderer.render(makePayload())
        let required = [
            "# Should we ship the new pricing?",
            "## Verdict",
            "## Arguments For",
            "## Arguments Against",
            "## Risk",
            "## Blind Spot",
            "## Opportunity",
            "## Pre-mortem",
            "## Test"
        ]
        for header in required {
            XCTAssertTrue(md.contains(header), "Markdown missing required section: \(header)")
        }
    }

    func test_render_includesMetadata() {
        let md = MarkdownRenderer.render(makePayload())
        XCTAssertTrue(md.contains("**Lens:** growth-strategy"))
        XCTAssertTrue(md.contains("**Confidence:** 75%"))
        XCTAssertTrue(md.contains("**Date:**"))
        XCTAssertTrue(md.contains("**Outcome deadline:**"))
    }

    func test_render_bulletsArguments() {
        let md = MarkdownRenderer.render(makePayload())
        XCTAssertTrue(md.contains("- Margins improve"))
        XCTAssertTrue(md.contains("- Competitor priced up"))
        XCTAssertTrue(md.contains("- Existing customers may churn"))
    }

    func test_render_includesModelPanelAndCost() {
        let md = MarkdownRenderer.render(makePayload())
        XCTAssertTrue(md.contains("Model panel: claude-opus-4-7, gpt-5.4"))
        XCTAssertTrue(md.contains("Total cost: $0.80"))
    }

    func test_render_emptyArgsRendersFallback() {
        let v = Verdict(
            id: "v2", decisionId: "d1", createdAt: Date(),
            verdictText: "", confidence: 50,
            keyForJson: "[]", keyAgainstJson: "[]",
            risk: "", blindSpot: "", opportunity: "",
            preMortem: "", outcomeDeadline: Date().addingTimeInterval(60 * 86_400),
            testAction: "", testMetric: "", testThreshold: "",
            outcomeStatus: .pending
        )
        let payload = ExportPayload(decision: makeDecision(), verdict: v, outcome: nil, modelRuns: [])
        let md = MarkdownRenderer.render(payload)
        XCTAssertTrue(md.contains("_(none)_"), "Empty arg lists should render the italic '(none)' fallback")
        XCTAssertTrue(md.contains("(empty)") || md.contains("(none)"))
    }

    // MARK: - Outcome inclusion

    func test_render_includesOutcomeWhenMarkedRight() {
        let outcome = Outcome(
            id: "o1", verdictId: "v1",
            markedAt: Date(timeIntervalSince1970: 1_777_017_600),
            result: .right,
            actualNotes: "Conversion lifted 12%.",
            whatChanged: "Pricing rolled out cleanly."
        )
        let md = MarkdownRenderer.render(makePayload(status: .right, outcome: outcome))
        XCTAssertTrue(md.contains("## Outcome"))
        XCTAssertTrue(md.contains("**Result:** Right"))
        XCTAssertTrue(md.contains("Conversion lifted 12%."))
    }

    func test_render_omitsOutcomeWhenDismissed() {
        let md = MarkdownRenderer.render(makePayload(status: .dismissed, outcome: nil))
        XCTAssertFalse(md.contains("## Outcome"),
                       "Dismissed verdicts have no outcome section (no row was written)")
    }

    func test_render_omitsOutcomeWhenStillPending() {
        let md = MarkdownRenderer.render(makePayload(status: .pending, outcome: nil))
        XCTAssertFalse(md.contains("## Outcome"))
    }

    // MARK: - Model panel uniqueness + ordering

    func test_modelPanel_dedupesAndPreservesInsertionOrder() {
        let runs = [
            ModelRun(id: "r1", decisionId: "d1", modelName: "B", provider: .openai, persona: "p",
                     roundNumber: 1, sampleNumber: 1, temperature: 0.3, prompt: "p", response: nil,
                     tokensIn: nil, tokensOut: nil, costUsd: 0.1, createdAt: Date(), error: nil, positionChanged: nil),
            ModelRun(id: "r2", decisionId: "d1", modelName: "A", provider: .anthropic, persona: "p",
                     roundNumber: 1, sampleNumber: 1, temperature: 0.3, prompt: "p", response: nil,
                     tokensIn: nil, tokensOut: nil, costUsd: 0.1, createdAt: Date(), error: nil, positionChanged: nil),
            ModelRun(id: "r3", decisionId: "d1", modelName: "B", provider: .openai, persona: "p",
                     roundNumber: 2, sampleNumber: 1, temperature: 0.3, prompt: "p", response: nil,
                     tokensIn: nil, tokensOut: nil, costUsd: 0.2, createdAt: Date(), error: nil, positionChanged: nil),
        ]
        let payload = ExportPayload(decision: makeDecision(), verdict: makeVerdict(),
                                    outcome: nil, modelRuns: runs)
        XCTAssertEqual(payload.modelPanel, ["B", "A"])  // first-seen ordering
        XCTAssertEqual(payload.totalCostUsd, 0.4, accuracy: 0.0001)
    }
}
