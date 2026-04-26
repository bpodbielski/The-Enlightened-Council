import Foundation
import GRDB

// MARK: - OutcomeResult

enum OutcomeResult: String, Codable, DatabaseValueConvertible {
    case right
    case partial
    case wrong
}

private struct ModelDecodingError: Error {
    let column: String
}

// MARK: - Outcome

struct Outcome: Codable, FetchableRecord, PersistableRecord, Sendable {

    static let databaseTableName = "outcomes"

    var id: String
    var verdictId: String
    var markedAt: Date
    var result: OutcomeResult
    var actualNotes: String
    var whatChanged: String

    // MARK: - Memberwise init

    init(
        id: String,
        verdictId: String,
        markedAt: Date,
        result: OutcomeResult,
        actualNotes: String,
        whatChanged: String
    ) {
        self.id = id
        self.verdictId = verdictId
        self.markedAt = markedAt
        self.result = result
        self.actualNotes = actualNotes
        self.whatChanged = whatChanged
    }

    // MARK: - FetchableRecord

    init(row: Row) throws {
        id = row["id"]
        verdictId = row["verdict_id"]
        let timestamp: Int64 = row["marked_at"]
        markedAt = Date(timeIntervalSince1970: Double(timestamp))
        guard let r = OutcomeResult(rawValue: row["result"] as String)
        else { throw ModelDecodingError(column: "result") }
        result = r
        actualNotes = row["actual_notes"]
        whatChanged = row["what_changed"]
    }

    // MARK: - PersistableRecord

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["verdict_id"] = verdictId
        container["marked_at"] = Int64(markedAt.timeIntervalSince1970)
        container["result"] = result.rawValue
        container["actual_notes"] = actualNotes
        container["what_changed"] = whatChanged
    }

    enum CodingKeys: String, CodingKey {
        case id, verdictId, markedAt, result, actualNotes, whatChanged
    }
}
