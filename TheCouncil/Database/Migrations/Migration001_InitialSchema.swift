import GRDB

enum Migration001_InitialSchema {

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // Enable foreign key enforcement
            try db.execute(sql: "PRAGMA foreign_keys = ON")

            // decisions
            try db.create(table: "decisions") { t in
                t.column("id", .text).primaryKey()
                t.column("created_at", .integer).notNull()
                t.column("status", .text).notNull()
                t.column("question", .text).notNull()
                t.column("lens_template", .text).notNull()
                t.column("reversibility", .text).notNull()
                t.column("time_horizon", .text).notNull()
                t.column("sensitivity_class", .text).notNull()
                t.column("success_criteria", .text).notNull()
                t.column("refined_brief", .text)
                t.column("refinement_chat_log", .text)
            }

            // model_runs
            try db.create(table: "model_runs") { t in
                t.column("id", .text).primaryKey()
                t.column("decision_id", .text).notNull().references("decisions", onDelete: .cascade)
                t.column("model_name", .text).notNull()
                t.column("provider", .text).notNull()
                t.column("persona", .text).notNull()
                t.column("round_number", .integer).notNull()
                t.column("sample_number", .integer).notNull()
                t.column("temperature", .double).notNull()
                t.column("prompt", .text).notNull()
                t.column("response", .text)
                t.column("tokens_in", .integer)
                t.column("tokens_out", .integer)
                t.column("cost_usd", .double)
                t.column("created_at", .integer).notNull()
                t.column("error", .text)
                t.column("position_changed", .integer)
            }

            // clusters (created before arguments so arguments can reference it)
            try db.create(table: "clusters") { t in
                t.column("id", .text).primaryKey()
                t.column("decision_id", .text).notNull().references("decisions", onDelete: .cascade)
                t.column("position", .text).notNull()
                t.column("centroid_text", .text).notNull()
            }

            // arguments
            try db.create(table: "arguments") { t in
                t.column("id", .text).primaryKey()
                t.column("decision_id", .text).notNull().references("decisions", onDelete: .cascade)
                t.column("source_run_id", .text).notNull().references("model_runs", onDelete: .cascade)
                t.column("position", .text).notNull()
                t.column("text", .text).notNull()
                t.column("cluster_id", .text).references("clusters", onDelete: .setNull)
                t.column("prominence", .double).notNull().defaults(to: 1.0)
            }

            // verdicts
            try db.create(table: "verdicts") { t in
                t.column("id", .text).primaryKey()
                t.column("decision_id", .text).notNull().references("decisions", onDelete: .cascade)
                t.column("created_at", .integer).notNull()
                t.column("verdict_text", .text).notNull()
                t.column("confidence", .integer).notNull()
                t.column("key_for_json", .text).notNull()
                t.column("key_against_json", .text).notNull()
                t.column("risk", .text).notNull()
                t.column("blind_spot", .text).notNull()
                t.column("opportunity", .text).notNull()
                t.column("pre_mortem", .text).notNull()
                t.column("outcome_deadline", .integer).notNull()
                t.column("test_action", .text).notNull()
                t.column("test_metric", .text).notNull()
                t.column("test_threshold", .text).notNull()
                t.column("outcome_status", .text).notNull().defaults(to: "pending")
            }

            // outcomes
            try db.create(table: "outcomes") { t in
                t.column("id", .text).primaryKey()
                t.column("verdict_id", .text).notNull().references("verdicts", onDelete: .cascade)
                t.column("marked_at", .integer).notNull()
                t.column("result", .text).notNull()
                t.column("actual_notes", .text).notNull()
                t.column("what_changed", .text).notNull()
            }

            // settings
            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }
        return migrator
    }
}
