import Foundation
import GRDB

private struct ModelDecodingError: Error {
    let column: String
}

// MARK: - Argument

struct Argument: Codable, FetchableRecord, PersistableRecord, Sendable {

    static let databaseTableName = "arguments"

    var id: String
    var decisionId: String
    var sourceRunId: String
    var position: ArgumentPosition
    var text: String
    var clusterId: String?
    var prominence: Double

    // MARK: - Memberwise init

    init(
        id: String,
        decisionId: String,
        sourceRunId: String,
        position: ArgumentPosition,
        text: String,
        clusterId: String? = nil,
        prominence: Double = 0
    ) {
        self.id = id
        self.decisionId = decisionId
        self.sourceRunId = sourceRunId
        self.position = position
        self.text = text
        self.clusterId = clusterId
        self.prominence = prominence
    }

    // MARK: - FetchableRecord

    init(row: Row) throws {
        id = row["id"]
        decisionId = row["decision_id"]
        sourceRunId = row["source_run_id"]
        guard let p = ArgumentPosition(rawValue: row["position"] as String)
        else { throw ModelDecodingError(column: "position") }
        position = p
        text = row["text"]
        clusterId = row["cluster_id"]
        prominence = row["prominence"]
    }

    // MARK: - PersistableRecord

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["decision_id"] = decisionId
        container["source_run_id"] = sourceRunId
        container["position"] = position.rawValue
        container["text"] = text
        container["cluster_id"] = clusterId
        container["prominence"] = prominence
    }

    enum CodingKeys: String, CodingKey {
        case id, decisionId, sourceRunId, position, text, clusterId, prominence
    }
}
