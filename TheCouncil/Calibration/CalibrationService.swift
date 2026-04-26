import Foundation
import GRDB

// MARK: - Bucket types

struct CalibrationBucket: Sendable, Identifiable, Equatable {
    let label: String          // lens template name OR reversibility raw value
    let total: Int
    let rightCount: Int

    var rightRate: Double {
        total == 0 ? 0 : Double(rightCount) / Double(total)
    }

    var id: String { label }
}

enum CalibrationGate: Sendable, Equatable {
    /// Not enough marked outcomes to compute patterns. Pattern queries should not run.
    case insufficient(marked: Int, threshold: Int)
    /// Enough samples — patterns are meaningful.
    case ready(marked: Int)

    var isReady: Bool {
        if case .ready = self { return true } else { return false }
    }
}

// MARK: - CalibrationService
//
// SPEC §6.9: pattern queries run only when `COUNT(outcomes WHERE result IS NOT NULL) >= 20`.
// Below that, the calibration view shows "Patterns appear after 20 marked outcomes. You have N so far."

actor CalibrationService {

    static let patternThreshold = 20

    private let db: DatabaseManager

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    // MARK: - Gate

    /// Returns whether we have enough marked outcomes to render patterns.
    func gate() async throws -> CalibrationGate {
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outcomes") ?? 0
        }
        if count >= Self.patternThreshold {
            return .ready(marked: count)
        } else {
            return .insufficient(marked: count, threshold: Self.patternThreshold)
        }
    }

    // MARK: - Pattern queries

    /// Calibration rate by `decisions.lens_template`.
    /// Sorted descending by right_rate.
    func calibrationByLens() async throws -> [CalibrationBucket] {
        try await db.read { db in
            try Self.fetchBuckets(
                db: db,
                groupBy: "d.lens_template"
            )
        }
    }

    /// Calibration rate by `decisions.reversibility`.
    /// Sorted descending by right_rate.
    func calibrationByReversibility() async throws -> [CalibrationBucket] {
        try await db.read { db in
            try Self.fetchBuckets(
                db: db,
                groupBy: "d.reversibility"
            )
        }
    }

    // MARK: - Shared SQL

    /// Aggregates outcomes joined to verdicts → decisions, grouped by `groupColumn`.
    /// `groupColumn` MUST be a known schema column name (we never interpolate user input here).
    private static func fetchBuckets(db: Database, groupBy groupColumn: String) throws -> [CalibrationBucket] {
        let sql = """
            SELECT \(groupColumn) AS bucket,
                   COUNT(*) AS total,
                   SUM(CASE WHEN o.result = 'right' THEN 1 ELSE 0 END) AS right_count
            FROM outcomes o
            JOIN verdicts v  ON o.verdict_id  = v.id
            JOIN decisions d ON v.decision_id = d.id
            GROUP BY bucket
            ORDER BY (right_count * 1.0 / total) DESC, bucket ASC
            """
        let rows = try Row.fetchAll(db, sql: sql)
        return rows.compactMap { row in
            guard let label = row["bucket"] as String?,
                  let total = row["total"] as Int?,
                  let right = row["right_count"] as Int?
            else { return nil }
            return CalibrationBucket(label: label, total: total, rightCount: right)
        }
    }
}
