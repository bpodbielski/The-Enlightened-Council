import Foundation
import GRDB

// MARK: - Supporting enums

enum ModelProvider: String, Codable, DatabaseValueConvertible {
    case anthropic
    case openai
    case google
    case xai
    case localMLX = "local-mlx"
    case localOllama = "local-ollama"
}

private struct ModelDecodingError: Error {
    let column: String
}

// MARK: - ModelRun

struct ModelRun: Codable, FetchableRecord, PersistableRecord, Sendable {

    static let databaseTableName = "model_runs"

    var id: String
    var decisionId: String
    var modelName: String
    var provider: ModelProvider
    var persona: String
    var roundNumber: Int
    var sampleNumber: Int
    var temperature: Double
    var prompt: String
    var response: String?
    var tokensIn: Int?
    var tokensOut: Int?
    var costUsd: Double?
    var createdAt: Date
    var error: String?
    var positionChanged: Bool?

    // MARK: - Memberwise init

    init(
        id: String,
        decisionId: String,
        modelName: String,
        provider: ModelProvider,
        persona: String,
        roundNumber: Int,
        sampleNumber: Int,
        temperature: Double,
        prompt: String,
        response: String? = nil,
        tokensIn: Int? = nil,
        tokensOut: Int? = nil,
        costUsd: Double? = nil,
        createdAt: Date,
        error: String? = nil,
        positionChanged: Bool? = nil
    ) {
        self.id = id
        self.decisionId = decisionId
        self.modelName = modelName
        self.provider = provider
        self.persona = persona
        self.roundNumber = roundNumber
        self.sampleNumber = sampleNumber
        self.temperature = temperature
        self.prompt = prompt
        self.response = response
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.costUsd = costUsd
        self.createdAt = createdAt
        self.error = error
        self.positionChanged = positionChanged
    }

    // MARK: - FetchableRecord

    init(row: Row) throws {
        id = row["id"]
        decisionId = row["decision_id"]
        modelName = row["model_name"]
        guard let p = ModelProvider(rawValue: row["provider"] as String)
        else { throw ModelDecodingError(column: "provider") }
        provider = p
        persona = row["persona"]
        roundNumber = row["round_number"]
        sampleNumber = row["sample_number"]
        temperature = row["temperature"]
        prompt = row["prompt"]
        response = row["response"]
        tokensIn = row["tokens_in"]
        tokensOut = row["tokens_out"]
        costUsd = row["cost_usd"]
        let timestamp: Int64 = row["created_at"]
        createdAt = Date(timeIntervalSince1970: Double(timestamp))
        error = row["error"]
        let pc: Int? = row["position_changed"]
        positionChanged = pc.map { $0 != 0 }
    }

    // MARK: - PersistableRecord

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["decision_id"] = decisionId
        container["model_name"] = modelName
        container["provider"] = provider.rawValue
        container["persona"] = persona
        container["round_number"] = roundNumber
        container["sample_number"] = sampleNumber
        container["temperature"] = temperature
        container["prompt"] = prompt
        container["response"] = response
        container["tokens_in"] = tokensIn
        container["tokens_out"] = tokensOut
        container["cost_usd"] = costUsd
        container["created_at"] = Int64(createdAt.timeIntervalSince1970)
        container["error"] = error
        container["position_changed"] = positionChanged.map { $0 ? 1 : 0 }
    }

    enum CodingKeys: String, CodingKey {
        case id, decisionId, modelName, provider, persona, roundNumber, sampleNumber
        case temperature, prompt, response, tokensIn, tokensOut, costUsd, createdAt, error, positionChanged
    }
}
