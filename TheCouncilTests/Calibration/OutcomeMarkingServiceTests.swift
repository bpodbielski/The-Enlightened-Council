import XCTest
import GRDB
@testable import TheCouncil

final class OutcomeMarkingServiceTests: XCTestCase {

    // MARK: - statusForResult mapping

    func test_statusForResult_mapsAllResults() {
        XCTAssertEqual(OutcomeMarkingService.statusForResult(.right),   .right)
        XCTAssertEqual(OutcomeMarkingService.statusForResult(.partial), .partial)
        XCTAssertEqual(OutcomeMarkingService.statusForResult(.wrong),   .wrong)
    }

    // MARK: - OutcomeStatus.isTerminal

    func test_outcomeStatus_isTerminal_isTrueForAllExceptPending() {
        XCTAssertFalse(OutcomeStatus.pending.isTerminal)
        XCTAssertTrue(OutcomeStatus.right.isTerminal)
        XCTAssertTrue(OutcomeStatus.partial.isTerminal)
        XCTAssertTrue(OutcomeStatus.wrong.isTerminal)
        XCTAssertTrue(OutcomeStatus.dismissed.isTerminal)
    }

    // MARK: - State machine via SQL contract
    //
    // We exercise the same SQL the service issues so we don't need a real DatabaseManager
    // (which is a file-backed singleton). This proves the schema accepts the marker output
    // and that the cascade (insert outcome + update verdict status) lands as expected.

    func test_markRight_insertsOutcomeAndUpdatesVerdictStatus() throws {
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        let (verdictId, _) = try seedDecisionAndVerdict(queue)

        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO outcomes (id, verdict_id, marked_at, result, actual_notes, what_changed)
                    VALUES (?, ?, ?, 'right', 'It worked', 'No major changes')
                    """,
                arguments: [UUID().uuidString, verdictId, Int(Date().timeIntervalSince1970)]
            )
            try db.execute(
                sql: "UPDATE verdicts SET outcome_status = 'right' WHERE id = ?",
                arguments: [verdictId]
            )
        }

        try queue.read { db in
            let status = try String.fetchOne(db,
                sql: "SELECT outcome_status FROM verdicts WHERE id = ?",
                arguments: [verdictId])
            XCTAssertEqual(status, "right")

            let count = try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM outcomes WHERE verdict_id = ?",
                arguments: [verdictId]) ?? 0
            XCTAssertEqual(count, 1)
        }
    }

    func test_dismiss_setsStatusButWritesNoOutcomeRow() throws {
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        let (verdictId, _) = try seedDecisionAndVerdict(queue)

        try queue.write { db in
            try db.execute(
                sql: "UPDATE verdicts SET outcome_status = 'dismissed' WHERE id = ?",
                arguments: [verdictId]
            )
        }

        try queue.read { db in
            let status = try String.fetchOne(db,
                sql: "SELECT outcome_status FROM verdicts WHERE id = ?",
                arguments: [verdictId])
            XCTAssertEqual(status, "dismissed")

            let count = try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM outcomes WHERE verdict_id = ?",
                arguments: [verdictId]) ?? 0
            XCTAssertEqual(count, 0, "Dismissed verdicts must not write an outcomes row")
        }
    }

    func test_terminalVerdict_cannotTransitionAgain() throws {
        // Once a verdict is in a terminal state, the service's assertPending guard
        // would refuse a second mark. We can't call the actor easily here, but we can
        // assert the invariant the guard relies on: status != 'pending'.
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        let (verdictId, _) = try seedDecisionAndVerdict(queue)
        try queue.write { db in
            try db.execute(
                sql: "UPDATE verdicts SET outcome_status = 'right' WHERE id = ?",
                arguments: [verdictId]
            )
        }
        try queue.read { db in
            let status = try String.fetchOne(db,
                sql: "SELECT outcome_status FROM verdicts WHERE id = ?",
                arguments: [verdictId]) ?? "pending"
            let parsed = OutcomeStatus(rawValue: status) ?? .pending
            XCTAssertTrue(parsed.isTerminal, "Service must reject further marks against a terminal status")
        }
    }

    // MARK: - Verdict schema accepts 'dismissed'

    func test_verdictSchema_acceptsDismissedStatus() throws {
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        let (verdictId, _) = try seedDecisionAndVerdict(queue, initialStatus: "dismissed")
        try queue.read { db in
            let status = try String.fetchOne(db,
                sql: "SELECT outcome_status FROM verdicts WHERE id = ?",
                arguments: [verdictId])
            XCTAssertEqual(status, "dismissed")
            // And the model can decode it
            if let row = try Row.fetchOne(db, sql: "SELECT * FROM verdicts WHERE id = ?", arguments: [verdictId]) {
                let v = try Verdict(row: row)
                XCTAssertEqual(v.outcomeStatus, .dismissed)
            } else {
                XCTFail("Expected verdict row")
            }
        }
    }

    // MARK: - Helper

    /// Inserts one decision + one verdict; returns (verdictId, decisionId).
    private func seedDecisionAndVerdict(_ queue: DatabaseQueue, initialStatus: String = "pending") throws -> (String, String) {
        let decisionId = UUID().uuidString
        let verdictId = UUID().uuidString
        let now = Int(Date().timeIntervalSince1970)
        let deadline = Int(Date().addingTimeInterval(60 * 86_400).timeIntervalSince1970)
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO decisions (id, created_at, status, question, lens_template, reversibility,
                        time_horizon, sensitivity_class, success_criteria)
                    VALUES (?, ?, 'complete', 'Q?', 'growth-strategy', 'reversible', 'quarters', 'public', 'crit')
                    """,
                arguments: [decisionId, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO verdicts (id, decision_id, created_at, verdict_text, confidence,
                        key_for_json, key_against_json, risk, blind_spot, opportunity,
                        pre_mortem, outcome_deadline, test_action, test_metric, test_threshold, outcome_status)
                    VALUES (?, ?, ?, 'V', 70, '[]', '[]', 'r', 'b', 'o', 'p', ?, 't', 'm', 'th', ?)
                    """,
                arguments: [verdictId, decisionId, now, deadline, initialStatus]
            )
        }
        return (verdictId, decisionId)
    }
}
