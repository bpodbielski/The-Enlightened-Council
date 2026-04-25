import XCTest
import GRDB
@testable import TheCouncil

final class DatabaseMigrationTests: XCTestCase {

    // MARK: - test_migration_appliesAllTablesOnFreshDatabase

    func test_migration_appliesAllTablesOnFreshDatabase() throws {
        let queue = try DatabaseQueue()
        let migrator = Migration001_InitialSchema.makeMigrator()
        try migrator.migrate(queue)

        // Assert all 7 tables exist (read-only query via sqlite_master)
        try queue.read { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
            let expectedTables = [
                "arguments",
                "clusters",
                "decisions",
                "model_runs",
                "outcomes",
                "settings",
                "verdicts"
            ]
            for table in expectedTables {
                XCTAssertTrue(tables.contains(table), "Missing table: \(table)")
            }
        }

        // Assert write to each table succeeds
        try queue.write { db in
            let uuid = UUID().uuidString
            let now = Int(Date().timeIntervalSince1970)

            try db.execute(
                sql: """
                INSERT INTO decisions (id, created_at, status, question, lens_template, reversibility,
                    time_horizon, sensitivity_class, success_criteria)
                VALUES (?, ?, 'draft', 'Test question?', 'test', 'reversible', 'weeks', 'public', 'test criteria')
                """,
                arguments: [uuid, now]
            )

            let runId = UUID().uuidString
            try db.execute(
                sql: """
                INSERT INTO model_runs (id, decision_id, model_name, provider, persona,
                    round_number, sample_number, temperature, prompt, created_at)
                VALUES (?, ?, 'test-model', 'anthropic', 'analyst', 1, 1, 0.7, 'test prompt', ?)
                """,
                arguments: [runId, uuid, now]
            )

            let clusterId = UUID().uuidString
            try db.execute(
                sql: """
                INSERT INTO clusters (id, decision_id, position, centroid_text)
                VALUES (?, ?, 'for', 'test centroid')
                """,
                arguments: [clusterId, uuid]
            )

            let argId = UUID().uuidString
            try db.execute(
                sql: """
                INSERT INTO arguments (id, decision_id, source_run_id, position, text, cluster_id, prominence)
                VALUES (?, ?, ?, 'for', 'test argument', ?, 1.0)
                """,
                arguments: [argId, uuid, runId, clusterId]
            )

            let verdictId = UUID().uuidString
            try db.execute(
                sql: """
                INSERT INTO verdicts (id, decision_id, created_at, verdict_text, confidence,
                    key_for_json, key_against_json, risk, blind_spot, opportunity,
                    pre_mortem, outcome_deadline, test_action, test_metric, test_threshold)
                VALUES (?, ?, ?, 'test verdict', 75, '[]', '[]', 'test risk', 'test blind spot',
                    'test opportunity', 'test pre_mortem', ?, 'test action', 'test metric', 'threshold')
                """,
                arguments: [verdictId, uuid, now, now + 86400 * 60]
            )

            let outcomeId = UUID().uuidString
            try db.execute(
                sql: """
                INSERT INTO outcomes (id, verdict_id, marked_at, result, actual_notes, what_changed)
                VALUES (?, ?, ?, 'right', 'test notes', 'test changed')
                """,
                arguments: [outcomeId, verdictId, now]
            )

            try db.execute(
                sql: "INSERT INTO settings (key, value) VALUES ('test_key', 'test_value')"
            )
        }
    }

    // MARK: - test_migration_isIdempotent

    func test_migration_isIdempotent() throws {
        let queue = try DatabaseQueue()
        let migrator = Migration001_InitialSchema.makeMigrator()

        // First run
        try migrator.migrate(queue)
        // Second run — must not throw
        try migrator.migrate(queue)
    }
}
