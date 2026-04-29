import Foundation
import GRDB

// MARK: - Errors

enum ExportError: Error, Equatable {
    case verdictNotFound(decisionId: String)
    case writeFailed(path: String, underlying: String)
}

// MARK: - ExportFormat

enum ExportFormat: String, CaseIterable, Sendable {
    case markdown
    case pdf
    case both

    var label: String {
        switch self {
        case .markdown: return "Markdown"
        case .pdf:      return "PDF"
        case .both:     return "Both"
        }
    }
}

// MARK: - ExportResult

struct ExportResult: Sendable, Equatable {
    let writtenPaths: [URL]
}

// MARK: - ExportEngine
//
// 1. Pulls the verdict + outcome + model runs for a decision.
// 2. Renders Markdown / PDF (or both).
// 3. Writes to disk under the chosen destination directory.
//
// File names follow SPEC §6.10: [slugified-question]-[YYYY-MM-DD].md / .pdf

actor ExportEngine {

    private let db: DatabaseManager

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    // MARK: - Public API

    func export(decision: Decision, format: ExportFormat, to directory: URL) async throws -> ExportResult {
        let payload = try await loadPayload(for: decision)
        let baseName = Slug.filename(question: decision.question, date: payload.verdict.createdAt)
        var written: [URL] = []

        try Self.ensureDirectoryExists(directory)

        if format == .markdown || format == .both {
            let markdown = MarkdownRenderer.render(payload)
            let url = directory.appendingPathComponent("\(baseName).md")
            try Self.writeUTF8(markdown, to: url)
            written.append(url)
        }

        if format == .pdf || format == .both {
            let pdf = PDFRenderer.render(payload)
            let url = directory.appendingPathComponent("\(baseName).pdf")
            try Self.writeData(pdf, to: url)
            written.append(url)
        }

        return ExportResult(writtenPaths: written)
    }

    // MARK: - Default destination from settings

    /// Reads `export_default_path` from the settings table, expanding `~`.
    /// Falls back to `~/Desktop` if missing.
    func defaultExportDirectory() async -> URL {
        let raw = (try? await db.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'export_default_path'")
        }) ?? nil
        let path = raw ?? "~/Desktop"
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    // MARK: - Payload assembly

    private func loadPayload(for decision: Decision) async throws -> ExportPayload {
        let id = decision.id
        let result = try await db.read { db -> (Verdict?, Outcome?, [ModelRun]) in
            let v = try Verdict.fetchOne(db,
                sql: "SELECT * FROM verdicts WHERE decision_id = ? ORDER BY created_at DESC LIMIT 1",
                arguments: [id])
            let o: Outcome?
            if let v {
                o = try Outcome.fetchOne(db,
                    sql: "SELECT * FROM outcomes WHERE verdict_id = ? ORDER BY marked_at DESC LIMIT 1",
                    arguments: [v.id])
            } else {
                o = nil
            }
            let runs = try ModelRun.fetchAll(db,
                sql: "SELECT * FROM model_runs WHERE decision_id = ? ORDER BY round_number, sample_number",
                arguments: [id])
            return (v, o, runs)
        }
        guard let verdict = result.0 else {
            throw ExportError.verdictNotFound(decisionId: id)
        }
        return ExportPayload(decision: decision, verdict: verdict, outcome: result.1, modelRuns: result.2)
    }

    // MARK: - Filesystem helpers

    private static func ensureDirectoryExists(_ url: URL) throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ExportError.writeFailed(path: url.path, underlying: error.localizedDescription)
        }
    }

    private static func writeUTF8(_ s: String, to url: URL) throws {
        do {
            try s.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(path: url.path, underlying: error.localizedDescription)
        }
    }

    private static func writeData(_ d: Data, to url: URL) throws {
        do {
            try d.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(path: url.path, underlying: error.localizedDescription)
        }
    }
}
