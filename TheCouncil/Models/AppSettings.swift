import Foundation
import GRDB

// MARK: - SettingsKey

enum SettingsKey: String, CaseIterable {
    case defaultRounds = "default_rounds"
    case defaultSamples = "default_samples"
    case defaultOutcomeDeadlineDays = "default_outcome_deadline_days"
    case costSoftWarnUsd = "cost_soft_warn_usd"
    case costHardPauseUsd = "cost_hard_pause_usd"
    case airGapEnabled = "air_gap_enabled"
    case frontierSetModels = "frontier_set_models"
    case balancedSetModels = "balanced_set_models"
    case exportDefaultPath = "export_default_path"
    case exportFormatOrder = "export_format_order"
    case localModelDirectory = "local_model_directory"
    case ollamaEnabled = "ollama_enabled"
    case ollamaBaseUrl = "ollama_base_url"
}

// MARK: - AppSettings

struct AppSettings: Codable, FetchableRecord, PersistableRecord, Sendable {

    static let databaseTableName = "settings"

    var key: String
    var value: String

    // MARK: - FetchableRecord

    init(from row: Row) throws {
        key = row["key"]
        value = row["value"]
    }

    // MARK: - PersistableRecord

    func encode(to container: inout PersistenceContainer) throws {
        container["key"] = key
        container["value"] = value
    }
}
