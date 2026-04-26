import Foundation
import GRDB

// MARK: - Errors

enum OutcomeMarkingError: Error, Equatable {
    /// Verdict has already been marked or dismissed; no transitions out of terminal states in v1.
    case alreadyTerminal(currentStatus: OutcomeStatus)
    case verdictNotFound(id: String)
}

// MARK: - OutcomeMarkingService
//
// State machine per SPEC §6.9:
//
//   pending → right
//   pending → partial
//   pending → wrong
//   pending → dismissed
//
// Terminal states (right/partial/wrong/dismissed) cannot transition further in v1.
//
// `right`/`partial`/`wrong` writes:
//   1. INSERT row into `outcomes` with the result + notes + what_changed
//   2. UPDATE `verdicts.outcome_status` to match
//
// `dismissed` writes:
//   1. UPDATE `verdicts.outcome_status = 'dismissed'`  (no `outcomes` row — there's no result to record)
//
// Both branches are wrapped in a single GRDB transaction so the verdict status and
// the outcomes row stay in lockstep.

actor OutcomeMarkingService {

    private let db: DatabaseManager
    private let now: @Sendable () -> Date

    init(db: DatabaseManager = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.db = db
        self.now = now
    }

    // MARK: - Mark a result

    /// Marks a verdict with `right`, `partial`, or `wrong`. Inserts an outcomes row + updates verdict status.
    func mark(
        verdictId: String,
        result: OutcomeResult,
        actualNotes: String,
        whatChanged: String
    ) async throws -> Outcome {
        let outcomeId = UUID().uuidString
        let markedAt = now()

        let outcome = Outcome(
            id: outcomeId,
            verdictId: verdictId,
            markedAt: markedAt,
            result: result,
            actualNotes: actualNotes,
            whatChanged: whatChanged
        )

        try await db.write { db in
            try Self.assertPending(db: db, verdictId: verdictId)
            try outcome.insert(db)
            try db.execute(
                sql: "UPDATE verdicts SET outcome_status = ? WHERE id = ?",
                arguments: [Self.statusForResult(result).rawValue, verdictId]
            )
        }
        return outcome
    }

    /// Dismisses a verdict (e.g., the question is no longer relevant). No outcomes row written.
    func dismiss(verdictId: String) async throws {
        try await db.write { db in
            try Self.assertPending(db: db, verdictId: verdictId)
            try db.execute(
                sql: "UPDATE verdicts SET outcome_status = 'dismissed' WHERE id = ?",
                arguments: [verdictId]
            )
        }
    }

    // MARK: - State machine helpers

    private static func assertPending(db: Database, verdictId: String) throws {
        guard let raw = try String.fetchOne(
            db,
            sql: "SELECT outcome_status FROM verdicts WHERE id = ?",
            arguments: [verdictId]
        ) else {
            throw OutcomeMarkingError.verdictNotFound(id: verdictId)
        }
        let status = OutcomeStatus(rawValue: raw) ?? .pending
        guard status == .pending else {
            throw OutcomeMarkingError.alreadyTerminal(currentStatus: status)
        }
    }

    /// Maps a result onto the corresponding terminal verdict status.
    static func statusForResult(_ result: OutcomeResult) -> OutcomeStatus {
        switch result {
        case .right:   return .right
        case .partial: return .partial
        case .wrong:   return .wrong
        }
    }
}
