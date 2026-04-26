import XCTest
import GRDB
@testable import TheCouncil

final class ThisWeekQueryTests: XCTestCase {

    // MARK: - Window predicate
    //
    // Mirrors `ThisWeekViewModel.fetchDue`:
    //   WHERE outcome_status = 'pending'
    //     AND (outcome_deadline <= ? OR outcome_deadline < ?)

    func test_thisWeekQuery_includesUpcomingWithinSevenDays() throws {
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cutoff = Calendar.current.date(byAdding: .day, value: 7, to: now)!

        try insertVerdict(queue, deadlineOffsetDays: 3,  status: "pending")  // due in 3d → in
        try insertVerdict(queue, deadlineOffsetDays: 7,  status: "pending")  // boundary
        try insertVerdict(queue, deadlineOffsetDays: 30, status: "pending")  // future → out

        try queue.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM verdicts
                WHERE outcome_status = 'pending'
                  AND (outcome_deadline <= ? OR outcome_deadline < ?)
                """,
                arguments: [Int64(cutoff.timeIntervalSince1970), Int64(now.timeIntervalSince1970)]) ?? 0
            XCTAssertEqual(count, 2, "Boundary at +7d should be included; +30d excluded")
        }
    }

    func test_thisWeekQuery_includesOverdue() throws {
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cutoff = Calendar.current.date(byAdding: .day, value: 7, to: now)!

        try insertVerdict(queue, deadlineOffsetDays: -10, status: "pending")  // 10d overdue → in
        try insertVerdict(queue, deadlineOffsetDays: -1,  status: "pending")  // 1d overdue → in
        try insertVerdict(queue, deadlineOffsetDays: 100, status: "pending")  // far future → out

        try queue.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM verdicts
                WHERE outcome_status = 'pending'
                  AND (outcome_deadline <= ? OR outcome_deadline < ?)
                """,
                arguments: [Int64(cutoff.timeIntervalSince1970), Int64(now.timeIntervalSince1970)]) ?? 0
            XCTAssertEqual(count, 2)
        }
    }

    func test_thisWeekQuery_excludesAllTerminalStates() throws {
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cutoff = Calendar.current.date(byAdding: .day, value: 7, to: now)!

        // All within window, but only 'pending' should surface
        for status in ["pending", "right", "partial", "wrong", "dismissed"] {
            try insertVerdict(queue, deadlineOffsetDays: 2, status: status, base: now)
        }

        try queue.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM verdicts
                WHERE outcome_status = 'pending'
                  AND (outcome_deadline <= ? OR outcome_deadline < ?)
                """,
                arguments: [Int64(cutoff.timeIntervalSince1970), Int64(now.timeIntervalSince1970)]) ?? 0
            XCTAssertEqual(count, 1, "Only the 'pending' verdict should be in the result set")
        }
    }

    func test_dismissedVerdicts_disappearFromThisWeek() throws {
        let queue = try DatabaseQueue()
        try Migration001_InitialSchema.makeMigrator().migrate(queue)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cutoff = Calendar.current.date(byAdding: .day, value: 7, to: now)!

        let verdictId = try insertVerdict(queue, deadlineOffsetDays: 1, status: "pending", base: now)

        // Before dismiss: visible
        try queue.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM verdicts
                WHERE outcome_status = 'pending'
                  AND (outcome_deadline <= ? OR outcome_deadline < ?)
                """,
                arguments: [Int64(cutoff.timeIntervalSince1970), Int64(now.timeIntervalSince1970)]) ?? 0
            XCTAssertEqual(count, 1)
        }

        // Dismiss
        try queue.write { db in
            try db.execute(sql: "UPDATE verdicts SET outcome_status = 'dismissed' WHERE id = ?", arguments: [verdictId])
        }

        // After dismiss: gone
        try queue.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM verdicts
                WHERE outcome_status = 'pending'
                  AND (outcome_deadline <= ? OR outcome_deadline < ?)
                """,
                arguments: [Int64(cutoff.timeIntervalSince1970), Int64(now.timeIntervalSince1970)]) ?? 0
            XCTAssertEqual(count, 0)
        }
    }

    // MARK: - Helper

    @discardableResult
    private func insertVerdict(
        _ queue: DatabaseQueue,
        deadlineOffsetDays: Int,
        status: String,
        base: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) throws -> String {
        let decisionId = UUID().uuidString
        let verdictId  = UUID().uuidString
        let createdAt  = Int(base.timeIntervalSince1970)
        let deadline   = createdAt + deadlineOffsetDays * 86_400
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO decisions (id, created_at, status, question, lens_template, reversibility,
                        time_horizon, sensitivity_class, success_criteria)
                    VALUES (?, ?, 'complete', 'Q?', 'growth-strategy', 'reversible', 'quarters', 'public', 'crit')
                    """,
                arguments: [decisionId, createdAt]
            )
            try db.execute(
                sql: """
                    INSERT INTO verdicts (id, decision_id, created_at, verdict_text, confidence,
                        key_for_json, key_against_json, risk, blind_spot, opportunity,
                        pre_mortem, outcome_deadline, test_action, test_metric, test_threshold, outcome_status)
                    VALUES (?, ?, ?, 'V', 70, '[]', '[]', 'r', 'b', 'o', 'p', ?, 't', 'm', 'th', ?)
                    """,
                arguments: [verdictId, decisionId, createdAt, deadline, status]
            )
        }
        return verdictId
    }
}
