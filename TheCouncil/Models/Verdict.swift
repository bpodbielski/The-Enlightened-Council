import Foundation
import GRDB

// MARK: - OutcomeStatus

enum OutcomeStatus: String, Codable, DatabaseValueConvertible {
    case pending
    case right
    case partial
    case wrong
    case dismissed

    var isTerminal: Bool { self != .pending }
}

private struct ModelDecodingError: Error {
    let column: String
}

// MARK: - Verdict

struct Verdict: Codable, FetchableRecord, PersistableRecord, Sendable {

    static let databaseTableName = "verdicts"

    var id: String
    var decisionId: String
    var createdAt: Date
    var verdictText: String
    var confidence: Int
    var keyForJson: String
    var keyAgainstJson: String
    var risk: String
    var blindSpot: String
    var opportunity: String
    var preMortem: String
    var outcomeDeadline: Date
    var testAction: String
    var testMetric: String
    var testThreshold: String
    var outcomeStatus: OutcomeStatus

    // MARK: - Memberwise init

    init(
        id: String,
        decisionId: String,
        createdAt: Date,
        verdictText: String,
        confidence: Int,
        keyForJson: String,
        keyAgainstJson: String,
        risk: String,
        blindSpot: String,
        opportunity: String,
        preMortem: String,
        outcomeDeadline: Date,
        testAction: String,
        testMetric: String,
        testThreshold: String,
        outcomeStatus: OutcomeStatus
    ) {
        self.id = id
        self.decisionId = decisionId
        self.createdAt = createdAt
        self.verdictText = verdictText
        self.confidence = confidence
        self.keyForJson = keyForJson
        self.keyAgainstJson = keyAgainstJson
        self.risk = risk
        self.blindSpot = blindSpot
        self.opportunity = opportunity
        self.preMortem = preMortem
        self.outcomeDeadline = outcomeDeadline
        self.testAction = testAction
        self.testMetric = testMetric
        self.testThreshold = testThreshold
        self.outcomeStatus = outcomeStatus
    }

    // MARK: - FetchableRecord

    init(row: Row) throws {
        id = row["id"]
        decisionId = row["decision_id"]
        let createdTimestamp: Int64 = row["created_at"]
        createdAt = Date(timeIntervalSince1970: Double(createdTimestamp))
        verdictText = row["verdict_text"]
        confidence = row["confidence"]
        keyForJson = row["key_for_json"]
        keyAgainstJson = row["key_against_json"]
        risk = row["risk"]
        blindSpot = row["blind_spot"]
        opportunity = row["opportunity"]
        preMortem = row["pre_mortem"]
        let deadlineTimestamp: Int64 = row["outcome_deadline"]
        outcomeDeadline = Date(timeIntervalSince1970: Double(deadlineTimestamp))
        testAction = row["test_action"]
        testMetric = row["test_metric"]
        testThreshold = row["test_threshold"]
        guard let os = OutcomeStatus(rawValue: row["outcome_status"] as String)
        else { throw ModelDecodingError(column: "outcome_status") }
        outcomeStatus = os
    }

    // MARK: - PersistableRecord

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["decision_id"] = decisionId
        container["created_at"] = Int64(createdAt.timeIntervalSince1970)
        container["verdict_text"] = verdictText
        container["confidence"] = confidence
        container["key_for_json"] = keyForJson
        container["key_against_json"] = keyAgainstJson
        container["risk"] = risk
        container["blind_spot"] = blindSpot
        container["opportunity"] = opportunity
        container["pre_mortem"] = preMortem
        container["outcome_deadline"] = Int64(outcomeDeadline.timeIntervalSince1970)
        container["test_action"] = testAction
        container["test_metric"] = testMetric
        container["test_threshold"] = testThreshold
        container["outcome_status"] = outcomeStatus.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case id, decisionId, createdAt, verdictText, confidence
        case keyForJson, keyAgainstJson, risk, blindSpot, opportunity
        case preMortem, outcomeDeadline, testAction, testMetric, testThreshold, outcomeStatus
    }
}
