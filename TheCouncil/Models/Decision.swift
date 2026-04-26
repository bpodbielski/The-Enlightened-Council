import Foundation
import GRDB

// MARK: - Supporting enums

enum DecisionStatus: String, Codable, DatabaseValueConvertible {
    case draft
    case refining
    case ready
    case running
    case complete
    case archived
}

enum Reversibility: String, Codable, DatabaseValueConvertible {
    case reversible
    case semiReversible = "semi-reversible"
    case irreversible
}

enum TimeHorizon: String, Codable, DatabaseValueConvertible {
    case weeks
    case months
    case quarters
    case years
}

enum SensitivityClass: String, Codable, DatabaseValueConvertible {
    case `public`
    case sensitive
    case confidential
}

// MARK: - Model decoding error

private struct ModelDecodingError: Error {
    let column: String
}

// MARK: - Decision

struct Decision: Codable, FetchableRecord, PersistableRecord, Sendable {

    static let databaseTableName = "decisions"

    var id: String
    var createdAt: Date
    var status: DecisionStatus
    var question: String
    var lensTemplate: String
    var reversibility: Reversibility
    var timeHorizon: TimeHorizon
    var sensitivityClass: SensitivityClass
    var successCriteria: String
    var refinedBrief: String?
    var refinementChatLog: String?

    // MARK: - Memberwise init

    init(
        id: String,
        createdAt: Date,
        status: DecisionStatus,
        question: String,
        lensTemplate: String,
        reversibility: Reversibility,
        timeHorizon: TimeHorizon,
        sensitivityClass: SensitivityClass,
        successCriteria: String,
        refinedBrief: String? = nil,
        refinementChatLog: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.status = status
        self.question = question
        self.lensTemplate = lensTemplate
        self.reversibility = reversibility
        self.timeHorizon = timeHorizon
        self.sensitivityClass = sensitivityClass
        self.successCriteria = successCriteria
        self.refinedBrief = refinedBrief
        self.refinementChatLog = refinementChatLog
    }

    // MARK: - FetchableRecord (row-based init)

    init(row: Row) throws {
        id = row["id"]
        let timestamp: Int64 = row["created_at"]
        createdAt = Date(timeIntervalSince1970: Double(timestamp))
        guard let s = DecisionStatus(rawValue: row["status"] as String)
        else { throw ModelDecodingError(column: "status") }
        status = s
        question = row["question"]
        lensTemplate = row["lens_template"]
        guard let r = Reversibility(rawValue: row["reversibility"] as String)
        else { throw ModelDecodingError(column: "reversibility") }
        reversibility = r
        guard let t = TimeHorizon(rawValue: row["time_horizon"] as String)
        else { throw ModelDecodingError(column: "time_horizon") }
        timeHorizon = t
        guard let sc = SensitivityClass(rawValue: row["sensitivity_class"] as String)
        else { throw ModelDecodingError(column: "sensitivity_class") }
        sensitivityClass = sc
        successCriteria = row["success_criteria"]
        refinedBrief = row["refined_brief"]
        refinementChatLog = row["refinement_chat_log"]
    }

    // MARK: - PersistableRecord

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["created_at"] = Int64(createdAt.timeIntervalSince1970)
        container["status"] = status.rawValue
        container["question"] = question
        container["lens_template"] = lensTemplate
        container["reversibility"] = reversibility.rawValue
        container["time_horizon"] = timeHorizon.rawValue
        container["sensitivity_class"] = sensitivityClass.rawValue
        container["success_criteria"] = successCriteria
        container["refined_brief"] = refinedBrief
        container["refinement_chat_log"] = refinementChatLog
    }

    // Codable conformance (for JSON, distinct from GRDB row-based init)
    enum CodingKeys: String, CodingKey {
        case id, status, question, successCriteria, refinedBrief, refinementChatLog
        case createdAt, lensTemplate, reversibility, timeHorizon, sensitivityClass
    }
}
