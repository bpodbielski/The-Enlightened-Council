import Foundation

/// Reads and evaluates cost thresholds per SPEC §6.5. Soft warn triggers a
/// non-blocking dialog at $2; hard pause triggers a blocking dialog at $5.
/// Thresholds live in `settings` (`cost_soft_warn_usd`, `cost_hard_pause_usd`).
struct CostGuardrails: Sendable, Equatable {

    let softWarnUsd: Double
    let hardPauseUsd: Double

    static let defaults = CostGuardrails(softWarnUsd: 2.00, hardPauseUsd: 5.00)

    enum Evaluation: Sendable, Equatable {
        case ok
        case softWarnCrossed
        case hardPauseCrossed
    }

    /// Classify a total. `previousTotal` is the last-observed total; only the
    /// crossing edge returns a warn/pause so repeated ticks don't spam.
    func evaluate(previousTotal: Double, newTotal: Double) -> Evaluation {
        if previousTotal < hardPauseUsd && newTotal >= hardPauseUsd {
            return .hardPauseCrossed
        }
        if previousTotal < softWarnUsd && newTotal >= softWarnUsd {
            return .softWarnCrossed
        }
        return .ok
    }

    static func load(from db: DatabaseManager) async throws -> CostGuardrails {
        let rows = try await db.read { db -> [String: String] in
            let keys = ["cost_soft_warn_usd", "cost_hard_pause_usd"]
            var out: [String: String] = [:]
            for key in keys {
                if let v = try String.fetchOne(
                    db,
                    sql: "SELECT value FROM settings WHERE key = ?",
                    arguments: [key]
                ) {
                    out[key] = v
                }
            }
            return out
        }
        let soft = Double(rows["cost_soft_warn_usd"] ?? "") ?? CostGuardrails.defaults.softWarnUsd
        let hard = Double(rows["cost_hard_pause_usd"] ?? "") ?? CostGuardrails.defaults.hardPauseUsd
        return CostGuardrails(softWarnUsd: soft, hardPauseUsd: hard)
    }
}
