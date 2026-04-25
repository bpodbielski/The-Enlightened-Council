import Foundation
import GRDB
import os.log

// MARK: - Error type

enum DatabaseError: Error {
    case migrationFailed(underlying: Error)
    case readFailed(underlying: Error)
    case writeFailed(underlying: Error)
    case directoryCreationFailed(underlying: Error)
}

// MARK: - DatabaseManager

actor DatabaseManager {

    private let pool: DatabasePool
    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "DatabaseManager")

    // MARK: Shared singleton

    static let shared: DatabaseManager = {
        // Force-try at module load is acceptable for a single-user app —
        // failures are surfaced by TheCouncilApp's launch guard.
        // swiftlint:disable:next force_try
        try! DatabaseManager()
    }()

    // MARK: Init

    init() throws {
        let appSupport = try DatabaseManager.resolveApplicationSupportDirectory()
        let dbURL = appSupport.appendingPathComponent("council.db")

        do {
            pool = try DatabasePool(path: dbURL.path)
        } catch {
            throw DatabaseError.migrationFailed(underlying: error)
        }

        // Run migrations
        do {
            let migrator = Migration001_InitialSchema.makeMigrator()
            try migrator.migrate(pool)
        } catch {
            throw DatabaseError.migrationFailed(underlying: error)
        }

        // Seed default settings if the table is empty
        try pool.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM settings") ?? 0
            guard count == 0 else { return }
            try DatabaseManager.seedDefaultSettings(db: db, appSupport: appSupport)
        }
    }

    // MARK: Public API

    func read<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        do {
            return try await pool.read(body)
        } catch let error as DatabaseError {
            throw error
        } catch {
            throw DatabaseError.readFailed(underlying: error)
        }
    }

    func write<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        do {
            return try await pool.write(body)
        } catch let error as DatabaseError {
            throw error
        } catch {
            throw DatabaseError.writeFailed(underlying: error)
        }
    }

    // MARK: - Private helpers

    private static func resolveApplicationSupportDirectory() throws -> URL {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            struct NoAppSupportURL: Error {}
            throw DatabaseError.directoryCreationFailed(underlying: NoAppSupportURL())
        }
        let dir = base.appendingPathComponent("The Council", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw DatabaseError.directoryCreationFailed(underlying: error)
        }
        return dir
    }

    private static func seedDefaultSettings(db: Database, appSupport: URL) throws {
        let modelsPath = appSupport.appendingPathComponent("models").path

        let defaults: [(String, String)] = [
            ("default_rounds", "3"),
            ("default_samples", "3"),
            ("default_outcome_deadline_days", "60"),
            ("cost_soft_warn_usd", "2.00"),
            ("cost_hard_pause_usd", "5.00"),
            ("air_gap_enabled", "false"),
            ("frontier_set_models", #"["claude-opus-4-7","gpt-5.4","gemini-3.1-pro-preview","grok-4.20-0309-non-reasoning"]"#),
            ("balanced_set_models", #"["claude-sonnet-4-6","gpt-5.4-mini","gemini-3-flash-preview","grok-4.1"]"#),
            ("export_default_path", "~/Desktop"),
            ("export_format_order", #"["markdown","pdf"]"#),
            ("local_model_directory", modelsPath),
            ("ollama_enabled", "false"),
            ("ollama_base_url", "http://localhost:11434")
        ]

        for (key, value) in defaults {
            try db.execute(
                sql: "INSERT INTO settings (key, value) VALUES (?, ?)",
                arguments: [key, value]
            )
        }
    }
}
