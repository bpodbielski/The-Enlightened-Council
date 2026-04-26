import Foundation
import GRDB
import Observation

// MARK: - DueVerdict
//
// Verdict + the decision question, ready to render in This Week.

struct DueVerdict: Identifiable, Sendable {
    let verdict: Verdict
    let question: String          // decisions.question
    let lensTemplate: String

    var id: String { verdict.id }

    var isOverdue: Bool { verdict.outcomeDeadline < Date() }
    var daysUntilDeadline: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: verdict.outcomeDeadline).day ?? 0
    }
}

// MARK: - ThisWeekViewModel

@Observable
@MainActor
final class ThisWeekViewModel {

    private(set) var verdicts: [DueVerdict] = []
    private(set) var dueCount: Int = 0          // verdicts visible right now (due ≤ 7d OR overdue)
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    // Per-row inline notes / what-changed input. Keyed by verdict id.
    var notesDraft: [String: String] = [:]
    var whatChangedDraft: [String: String] = [:]

    private let db: DatabaseManager
    private let marker: OutcomeMarkingService
    private let now: () -> Date

    init(
        db: DatabaseManager = .shared,
        marker: OutcomeMarkingService = OutcomeMarkingService(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.db = db
        self.marker = marker
        self.now = now
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let nowDate = now()
            let cutoff = Calendar.current.date(byAdding: .day, value: 7, to: nowDate) ?? nowDate
            verdicts = try await Self.fetchDue(db: db, now: nowDate, weekCutoff: cutoff)
            dueCount = verdicts.count
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    // MARK: - Mark / dismiss actions

    func mark(verdictId: String, result: OutcomeResult) async {
        do {
            _ = try await marker.mark(
                verdictId: verdictId,
                result: result,
                actualNotes: notesDraft[verdictId] ?? "",
                whatChanged: whatChangedDraft[verdictId] ?? ""
            )
            notesDraft.removeValue(forKey: verdictId)
            whatChangedDraft.removeValue(forKey: verdictId)
            await load()
        } catch {
            errorMessage = "Mark failed: \(error.localizedDescription)"
        }
    }

    func dismiss(verdictId: String) async {
        do {
            try await marker.dismiss(verdictId: verdictId)
            notesDraft.removeValue(forKey: verdictId)
            whatChangedDraft.removeValue(forKey: verdictId)
            await load()
        } catch {
            errorMessage = "Dismiss failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Query helper (also used by sidebar badge)

    /// Fetches verdicts where `outcome_status = 'pending'` AND
    /// (`outcome_deadline <= weekCutoff` OR `outcome_deadline < now`).
    /// Sort: overdue first, then by ascending deadline.
    static func fetchDue(db: DatabaseManager, now: Date, weekCutoff: Date) async throws -> [DueVerdict] {
        try await db.read { db in
            let nowTs = Int64(now.timeIntervalSince1970)
            let cutoffTs = Int64(weekCutoff.timeIntervalSince1970)
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT v.*, d.question AS decision_question, d.lens_template AS decision_lens
                    FROM verdicts v
                    JOIN decisions d ON v.decision_id = d.id
                    WHERE v.outcome_status = 'pending'
                      AND (v.outcome_deadline <= ? OR v.outcome_deadline < ?)
                    ORDER BY v.outcome_deadline ASC
                    """,
                arguments: [cutoffTs, nowTs]
            )
            return try rows.map { row in
                let verdict = try Verdict(row: row)
                let question = (row["decision_question"] as String?) ?? ""
                let lens = (row["decision_lens"] as String?) ?? ""
                return DueVerdict(verdict: verdict, question: question, lensTemplate: lens)
            }
        }
    }

    /// Lightweight count for the sidebar badge — same predicate as `fetchDue` but COUNT only.
    static func fetchDueCount(db: DatabaseManager, now: Date) async throws -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return try await db.read { db in
            let nowTs = Int64(now.timeIntervalSince1970)
            let cutoffTs = Int64(cutoff.timeIntervalSince1970)
            return try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM verdicts
                    WHERE outcome_status = 'pending'
                      AND (outcome_deadline <= ? OR outcome_deadline < ?)
                    """,
                arguments: [cutoffTs, nowTs]
            ) ?? 0
        }
    }
}
