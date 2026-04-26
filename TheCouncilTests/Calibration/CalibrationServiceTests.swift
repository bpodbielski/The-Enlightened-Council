import XCTest
import GRDB
@testable import TheCouncil

final class CalibrationServiceTests: XCTestCase {

    // MARK: - Bucket math

    func test_bucket_rightRate_dividesCorrectly() {
        let b = CalibrationBucket(label: "growth-strategy", total: 10, rightCount: 5)
        XCTAssertEqual(b.rightRate, 0.5)
    }

    func test_bucket_rightRate_zeroTotal() {
        let b = CalibrationBucket(label: "x", total: 0, rightCount: 0)
        XCTAssertEqual(b.rightRate, 0)
    }

    func test_bucket_rightRate_allWrong() {
        let b = CalibrationBucket(label: "x", total: 8, rightCount: 0)
        XCTAssertEqual(b.rightRate, 0)
    }

    func test_bucket_rightRate_allRight() {
        let b = CalibrationBucket(label: "x", total: 8, rightCount: 8)
        XCTAssertEqual(b.rightRate, 1.0)
    }

    // MARK: - Gate threshold

    func test_calibrationGate_threshold_is20() {
        XCTAssertEqual(CalibrationService.patternThreshold, 20)
    }

    func test_calibrationGate_isReady_onlyWhenReady() {
        XCTAssertFalse(CalibrationGate.insufficient(marked: 5, threshold: 20).isReady)
        XCTAssertFalse(CalibrationGate.insufficient(marked: 19, threshold: 20).isReady)
        XCTAssertTrue(CalibrationGate.ready(marked: 20).isReady)
        XCTAssertTrue(CalibrationGate.ready(marked: 100).isReady)
    }

    // MARK: - Pattern SQL contract
    //
    // We exercise the same aggregating SQL the service issues against an in-memory
    // schema, so we don't need a real DatabaseManager.

    func test_patternQuery_byLens_groupsAndSorts() throws {
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        // Lens A: 5 right of 5 (rate 1.0)
        try seedDecisions(queue, lens: "lens-A", reversibility: "reversible",   results: ["right","right","right","right","right"])
        // Lens B: 2 right of 4 (rate 0.5)
        try seedDecisions(queue, lens: "lens-B", reversibility: "irreversible", results: ["right","right","wrong","partial"])
        // Lens C: 0 right of 3 (rate 0.0)
        try seedDecisions(queue, lens: "lens-C", reversibility: "reversible",   results: ["wrong","wrong","partial"])

        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT d.lens_template AS bucket,
                       COUNT(*) AS total,
                       SUM(CASE WHEN o.result = 'right' THEN 1 ELSE 0 END) AS right_count
                FROM outcomes o
                JOIN verdicts v  ON o.verdict_id  = v.id
                JOIN decisions d ON v.decision_id = d.id
                GROUP BY bucket
                ORDER BY (right_count * 1.0 / total) DESC, bucket ASC
                """)
            XCTAssertEqual(rows.count, 3)
            XCTAssertEqual(rows[0]["bucket"] as String?, "lens-A")
            XCTAssertEqual(rows[0]["total"] as Int?, 5)
            XCTAssertEqual(rows[0]["right_count"] as Int?, 5)
            XCTAssertEqual(rows[1]["bucket"] as String?, "lens-B")
            XCTAssertEqual(rows[2]["bucket"] as String?, "lens-C")
        }
    }

    func test_patternQuery_byReversibility_aggregatesAcrossLenses() throws {
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        try seedDecisions(queue, lens: "lens-A", reversibility: "reversible",   results: ["right","right","right","wrong"])      // 3/4
        try seedDecisions(queue, lens: "lens-B", reversibility: "irreversible", results: ["wrong","wrong"])                       // 0/2
        try seedDecisions(queue, lens: "lens-C", reversibility: "reversible",   results: ["right","partial"])                     // 1/2

        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT d.reversibility AS bucket,
                       COUNT(*) AS total,
                       SUM(CASE WHEN o.result = 'right' THEN 1 ELSE 0 END) AS right_count
                FROM outcomes o
                JOIN verdicts v  ON o.verdict_id  = v.id
                JOIN decisions d ON v.decision_id = d.id
                GROUP BY bucket
                ORDER BY (right_count * 1.0 / total) DESC, bucket ASC
                """)
            XCTAssertEqual(rows.count, 2)
            // reversible: 3+1=4 right of 4+2=6 → 0.667
            // irreversible: 0/2 → 0
            XCTAssertEqual(rows[0]["bucket"] as String?, "reversible")
            XCTAssertEqual(rows[0]["total"] as Int?, 6)
            XCTAssertEqual(rows[0]["right_count"] as Int?, 4)
            XCTAssertEqual(rows[1]["bucket"] as String?, "irreversible")
        }
    }

    func test_gateQuery_threshold_firesAtExactly20() throws {
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        // 19 outcomes
        try seedDecisions(queue, lens: "x", reversibility: "reversible",
                          results: Array(repeating: "right", count: 19))
        try queue.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outcomes") ?? 0
            XCTAssertEqual(count, 19)
            XCTAssertLessThan(count, CalibrationService.patternThreshold)
        }

        // +1 = 20 — boundary
        try seedDecisions(queue, lens: "y", reversibility: "irreversible", results: ["right"])
        try queue.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outcomes") ?? 0
            XCTAssertEqual(count, 20)
            XCTAssertGreaterThanOrEqual(count, CalibrationService.patternThreshold)
        }
    }

    // MARK: - Helper

    /// Inserts one decision (with the given lens + reversibility) and one verdict + one outcome
    /// per element of `results`. Each result string must be one of "right", "partial", "wrong".
    private func seedDecisions(_ queue: DatabaseQueue, lens: String, reversibility: String, results: [String]) throws {
        try queue.write { db in
            for (i, result) in results.enumerated() {
                let decisionId = UUID().uuidString
                let verdictId = UUID().uuidString
                let outcomeId = UUID().uuidString
                let now = Int(Date().timeIntervalSince1970) + i
                let deadline = now + 60 * 86_400
                try db.execute(
                    sql: """
                        INSERT INTO decisions (id, created_at, status, question, lens_template, reversibility,
                            time_horizon, sensitivity_class, success_criteria)
                        VALUES (?, ?, 'complete', 'Q?', ?, ?, 'quarters', 'public', 'crit')
                        """,
                    arguments: [decisionId, now, lens, reversibility]
                )
                try db.execute(
                    sql: """
                        INSERT INTO verdicts (id, decision_id, created_at, verdict_text, confidence,
                            key_for_json, key_against_json, risk, blind_spot, opportunity,
                            pre_mortem, outcome_deadline, test_action, test_metric, test_threshold, outcome_status)
                        VALUES (?, ?, ?, 'V', 70, '[]', '[]', 'r', 'b', 'o', 'p', ?, 't', 'm', 'th', ?)
                        """,
                    arguments: [verdictId, decisionId, now, deadline, result]
                )
                try db.execute(
                    sql: """
                        INSERT INTO outcomes (id, verdict_id, marked_at, result, actual_notes, what_changed)
                        VALUES (?, ?, ?, ?, 'notes', 'changed')
                        """,
                    arguments: [outcomeId, verdictId, now, result]
                )
            }
        }
    }
}
