import Foundation
import GRDB

// MARK: - ArgumentPosition (shared enum)

enum ArgumentPosition: String, Codable, DatabaseValueConvertible {
    case `for`
    case against
    case neutral
}

private struct ModelDecodingError: Error {
    let column: String
}

// MARK: - Cluster

struct Cluster: Codable, FetchableRecord, PersistableRecord, Sendable {

    static let databaseTableName = "clusters"

    var id: String
    var decisionId: String
    var position: ArgumentPosition
    var centroidText: String

    // MARK: - FetchableRecord

    init(row: Row) throws {
        id = row["id"]
        decisionId = row["decision_id"]
        guard let p = ArgumentPosition(rawValue: row["position"] as String)
        else { throw ModelDecodingError(column: "position") }
        position = p
        centroidText = row["centroid_text"]
    }

    // MARK: - PersistableRecord

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["decision_id"] = decisionId
        container["position"] = position.rawValue
        container["centroid_text"] = centroidText
    }

    enum CodingKeys: String, CodingKey {
        case id, decisionId, position, centroidText
    }
}
