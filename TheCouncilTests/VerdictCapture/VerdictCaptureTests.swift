import XCTest
import GRDB
@testable import TheCouncil

// MARK: - StubStreamingChatClient

private final class StubStreamingChatClient: StreamingChatClient, @unchecked Sendable {
    let chunks: [String]

    init(chunks: [String]) { self.chunks = chunks }

    nonisolated func streamChat(
        messages: [TheCouncil.ChatMessage],
        model: String,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { cont in
            for c in chunks { cont.yield(c) }
            cont.finish()
        }
    }
}

private final class FailingStreamingChatClient: StreamingChatClient, @unchecked Sendable {
    nonisolated func streamChat(
        messages: [TheCouncil.ChatMessage],
        model: String,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            cont.finish(throwing: NSError(domain: "TestError", code: 1))
        }
    }
}

@MainActor
final class VerdictCaptureTests: XCTestCase {

    // MARK: - Helpers

    private func makeDecision(id: String = "decision-1", brief: String? = nil) -> Decision {
        Decision(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .ready,
            question: "Should we ship the new pricing?",
            lensTemplate: "growth-strategy",
            reversibility: .reversible,
            timeHorizon: .quarters,
            sensitivityClass: .public,
            successCriteria: "20% lift",
            refinedBrief: brief,
            refinementChatLog: nil
        )
    }

    private func makeTrayItems() -> [TrayItem] {
        [
            TrayItem(id: "t1", nodeId: "n1", text: "Margins improve under new tier.", position: .for, modelId: "claude-opus-4-7"),
            TrayItem(id: "t2", nodeId: "n2", text: "Existing customers may churn at new prices.", position: .against, modelId: "claude-opus-4-7"),
            TrayItem(id: "t3", nodeId: "n3", text: "Pilot test would de-risk this.", position: .neutral, modelId: "gpt-5.4"),
            TrayItem(id: "t4", nodeId: "n4", text: "Competitor X raised prices last quarter.", position: .for, modelId: "gemini-3.1-pro-preview"),
        ]
    }

    // MARK: - Auto-populate from tray

    func test_populateFromTray_partitionsForAndAgainst() {
        let vm = VerdictCaptureViewModel(
            decision: makeDecision(),
            trayItems: makeTrayItems(),
            chatClient: StubStreamingChatClient(chunks: [])
        )
        XCTAssertEqual(vm.keyForArguments.count, 2)
        XCTAssertEqual(vm.keyAgainstArguments.count, 1)
        XCTAssertTrue(vm.keyForArguments.allSatisfy { $0.position == .for })
        XCTAssertTrue(vm.keyAgainstArguments.allSatisfy { $0.position == .against })
    }

    func test_populateFromTray_excludesNeutral() {
        let vm = VerdictCaptureViewModel(
            decision: makeDecision(),
            trayItems: makeTrayItems(),
            chatClient: StubStreamingChatClient(chunks: [])
        )
        let allTexts = vm.keyForArguments.map(\.text) + vm.keyAgainstArguments.map(\.text)
        XCTAssertFalse(allTexts.contains("Pilot test would de-risk this."))
    }

    // MARK: - Default deadline (today + 60 days)

    func test_defaultDeadline_is60DaysFromNow() {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let vm = VerdictCaptureViewModel(
            decision: makeDecision(),
            trayItems: [],
            chatClient: StubStreamingChatClient(chunks: []),
            now: { fixedNow }
        )
        let expected = Calendar.current.date(byAdding: .day, value: 60, to: fixedNow)!
        XCTAssertEqual(vm.outcomeDeadline.timeIntervalSince1970,
                       expected.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    // MARK: - Default confidence

    func test_defaultConfidence_is70() {
        let vm = VerdictCaptureViewModel(
            decision: makeDecision(),
            trayItems: [],
            chatClient: StubStreamingChatClient(chunks: [])
        )
        XCTAssertEqual(vm.confidence, 70)
    }

    // MARK: - Verdict prompt construction

    func test_buildVerdictPrompt_includesBriefAndArguments() {
        let prompt = VerdictCaptureViewModel.buildVerdictPrompt(
            brief: "Pricing change brief.",
            forArgs: [TrayItem(id: "1", nodeId: "n1", text: "alpha", position: .for, modelId: "m1")],
            againstArgs: [TrayItem(id: "2", nodeId: "n2", text: "beta", position: .against, modelId: "m2")]
        )
        XCTAssertTrue(prompt.contains("Pricing change brief."))
        XCTAssertTrue(prompt.contains("alpha"))
        XCTAssertTrue(prompt.contains("beta"))
        XCTAssertTrue(prompt.contains("FOR"))
        XCTAssertTrue(prompt.contains("AGAINST"))
        XCTAssertTrue(prompt.contains("2–4 sentence"))
    }

    func test_buildVerdictPrompt_handlesEmptyArguments() {
        let prompt = VerdictCaptureViewModel.buildVerdictPrompt(
            brief: "Brief.",
            forArgs: [],
            againstArgs: []
        )
        XCTAssertTrue(prompt.contains("(none pinned)"))
    }

    // MARK: - Pre-mortem prompt construction

    func test_buildPreMortemPrompt_includesVerdictConfidenceDeadline() {
        let deadline = Date(timeIntervalSince1970: 1_768_300_000) // 2026-01-13
        let prompt = VerdictCaptureViewModel.buildPreMortemPrompt(
            verdictText: "Ship pricing change in Q2.",
            confidence: 65,
            outcomeDeadline: deadline
        )
        XCTAssertTrue(prompt.contains("Ship pricing change in Q2."))
        XCTAssertTrue(prompt.contains("65%"))
        XCTAssertTrue(prompt.contains("pre-mortem"))
        XCTAssertTrue(prompt.contains("3–5 bullets"))
        // The full date string contains "2026"
        XCTAssertTrue(prompt.contains("2026"))
    }

    // MARK: - JSON encoding for key_for/key_against

    func test_encodeArgumentTexts_roundTrip() {
        let items = [
            TrayItem(id: "a", nodeId: "n1", text: "first", position: .for, modelId: "m1"),
            TrayItem(id: "b", nodeId: "n2", text: "second", position: .for, modelId: "m1")
        ]
        let json = VerdictCaptureViewModel.encodeArgumentTexts(items)
        let decoded = VerdictCaptureViewModel.decodeArgumentTexts(json)
        XCTAssertEqual(decoded, ["first", "second"])
    }

    func test_encodeArgumentTexts_emptyArrayProducesEmptyJSON() {
        XCTAssertEqual(VerdictCaptureViewModel.encodeArgumentTexts([]), "[]")
    }

    func test_encodeArgumentTexts_handlesUnicode() {
        let items = [TrayItem(id: "a", nodeId: "n1", text: "naïve résumé 🌟", position: .for, modelId: "m1")]
        let json = VerdictCaptureViewModel.encodeArgumentTexts(items)
        let decoded = VerdictCaptureViewModel.decodeArgumentTexts(json)
        XCTAssertEqual(decoded, ["naïve résumé 🌟"])
    }

    // MARK: - Drafting via stub client

    func test_draftVerdict_setsVerdictTextFromStream() async {
        let stub = StubStreamingChatClient(chunks: ["Ship ", "the change ", "in Q2."])
        let vm = VerdictCaptureViewModel(
            decision: makeDecision(brief: "Some brief"),
            trayItems: makeTrayItems(),
            chatClient: stub
        )
        await vm.draftVerdict()
        XCTAssertEqual(vm.verdictText, "Ship the change in Q2.")
        XCTAssertFalse(vm.isDrafting)
        XCTAssertNil(vm.errorMessage)
    }

    func test_draftVerdict_failureSetsErrorMessage() async {
        let vm = VerdictCaptureViewModel(
            decision: makeDecision(),
            trayItems: [],
            chatClient: FailingStreamingChatClient()
        )
        await vm.draftVerdict()
        XCTAssertTrue(vm.verdictText.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Pre-mortem generation via stub client

    func test_generatePreMortem_populatesAndShowsSheet() async {
        let stub = StubStreamingChatClient(chunks: ["- Cause A\n", "- Cause B"])
        let vm = VerdictCaptureViewModel(
            decision: makeDecision(),
            trayItems: makeTrayItems(),
            chatClient: stub
        )
        vm.verdictText = "Test verdict."
        await vm.generatePreMortem()
        XCTAssertEqual(vm.preMortem, "- Cause A\n- Cause B")
        XCTAssertTrue(vm.showPreMortemSheet)
    }

    // MARK: - Verdict schema integration

    func test_verdictRow_writesAllFieldsAndDecisionStatusCompletes() throws {
        let queue = try DatabaseQueue()
        let migrator = Migration001_InitialSchema.makeMigrator()
        try migrator.migrate(queue)

        let decisionId = UUID().uuidString
        let now = Int(Date().timeIntervalSince1970)
        let deadline = Int(Date().addingTimeInterval(60 * 86_400).timeIntervalSince1970)

        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO decisions (id, created_at, status, question, lens_template, reversibility,
                    time_horizon, sensitivity_class, success_criteria)
                VALUES (?, ?, 'ready', 'Q?', 'growth-strategy', 'reversible', 'quarters', 'public', 'criteria')
                """,
                arguments: [decisionId, now]
            )
        }

        // Mimic VerdictCaptureViewModel.save() — insert + update status
        let verdict = Verdict(
            id: UUID().uuidString,
            decisionId: decisionId,
            createdAt: Date(timeIntervalSince1970: TimeInterval(now)),
            verdictText: "Ship.",
            confidence: 75,
            keyForJson: VerdictCaptureViewModel.encodeArgumentTexts([
                TrayItem(id: "a", nodeId: "n1", text: "alpha", position: .for, modelId: "m1")
            ]),
            keyAgainstJson: VerdictCaptureViewModel.encodeArgumentTexts([
                TrayItem(id: "b", nodeId: "n2", text: "beta", position: .against, modelId: "m1")
            ]),
            risk: "Risk text.",
            blindSpot: "Blind spot.",
            opportunity: "Opportunity.",
            preMortem: "- A\n- B",
            outcomeDeadline: Date(timeIntervalSince1970: TimeInterval(deadline)),
            testAction: "Run pilot.",
            testMetric: "Conversion %",
            testThreshold: "+10%",
            outcomeStatus: .pending
        )

        try queue.write { db in
            try verdict.insert(db)
            try db.execute(
                sql: "UPDATE decisions SET status = 'complete' WHERE id = ?",
                arguments: [decisionId]
            )
        }

        // Re-read and verify roundtrip
        try queue.read { db in
            let row = try Row.fetchOne(db,
                sql: "SELECT * FROM verdicts WHERE decision_id = ?",
                arguments: [decisionId])
            XCTAssertNotNil(row)
            XCTAssertEqual(row?["verdict_text"] as String?, "Ship.")
            XCTAssertEqual(row?["confidence"] as Int?, 75)
            XCTAssertEqual(row?["outcome_status"] as String?, "pending")
            XCTAssertEqual(row?["pre_mortem"] as String?, "- A\n- B")

            let status = try String.fetchOne(db,
                sql: "SELECT status FROM decisions WHERE id = ?",
                arguments: [decisionId])
            XCTAssertEqual(status, "complete")

            // Verify key_for_json contains "alpha"
            let keyFor = (row?["key_for_json"] as String?) ?? ""
            let decoded = VerdictCaptureViewModel.decodeArgumentTexts(keyFor)
            XCTAssertEqual(decoded, ["alpha"])
        }
    }

    func test_verdictRow_queryableByDeadline() throws {
        let queue = try DatabaseQueue()
        let migrator = Migration001_InitialSchema.makeMigrator()
        try migrator.migrate(queue)

        let decisionId = UUID().uuidString
        let now = Int(Date().timeIntervalSince1970)

        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO decisions (id, created_at, status, question, lens_template, reversibility,
                    time_horizon, sensitivity_class, success_criteria)
                VALUES (?, ?, 'complete', 'Q?', 'growth-strategy', 'reversible', 'quarters', 'public', 'crit')
                """,
                arguments: [decisionId, now]
            )

            // Insert two verdicts with different deadlines
            let early = Int(Date().addingTimeInterval(7 * 86_400).timeIntervalSince1970)
            let late  = Int(Date().addingTimeInterval(120 * 86_400).timeIntervalSince1970)

            for (suffix, deadline) in [("a", early), ("b", late)] {
                try db.execute(
                    sql: """
                    INSERT INTO verdicts (id, decision_id, created_at, verdict_text, confidence,
                        key_for_json, key_against_json, risk, blind_spot, opportunity,
                        pre_mortem, outcome_deadline, test_action, test_metric, test_threshold)
                    VALUES (?, ?, ?, 'V', 70, '[]', '[]', 'r', 'b', 'o', 'p', ?, 't', 'm', 'th')
                    """,
                    arguments: [UUID().uuidString + suffix, decisionId, now, deadline]
                )
            }
        }

        try queue.read { db in
            let cutoff = Int(Date().addingTimeInterval(30 * 86_400).timeIntervalSince1970)
            let count = try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM verdicts WHERE outcome_deadline <= ? AND outcome_status = 'pending'",
                arguments: [cutoff]) ?? 0
            XCTAssertEqual(count, 1)
        }
    }
}

// MARK: - AllDecisions query tests

@MainActor
final class AllDecisionsViewTests: XCTestCase {

    func test_decisionsQuery_sortsByCreatedAtDescending() throws {
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        let baseTime = Int(Date().timeIntervalSince1970)
        try queue.write { db in
            for (idx, offset) in [(0, 0), (1, 100), (2, 200)].enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO decisions (id, created_at, status, question, lens_template, reversibility,
                        time_horizon, sensitivity_class, success_criteria)
                    VALUES (?, ?, 'draft', 'Q\(idx)', 'growth-strategy', 'reversible', 'weeks', 'public', 'c')
                    """,
                    arguments: ["d-\(idx)", baseTime + offset.1]
                )
            }
        }

        let questions: [String] = try queue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT question FROM decisions ORDER BY created_at DESC")
            return rows.compactMap { $0["question"] as String? }
        }
        XCTAssertEqual(questions, ["Q2", "Q1", "Q0"])
    }
}
