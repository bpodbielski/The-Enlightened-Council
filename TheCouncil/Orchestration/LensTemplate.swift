import Foundation

/// A curated decision lens. Defines default persona set, rounds, and samples.
/// Loaded from `Resources/LensTemplates/<id>.json` per SPEC §6.2.
struct LensTemplate: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let label: String
    let defaultPersonas: [String]
    let defaultRounds: Int
    let defaultSamples: Int

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case defaultPersonas = "default_personas"
        case defaultRounds = "default_rounds"
        case defaultSamples = "default_samples"
    }

    static let validIDs: Set<String> = [
        "strategic-bet",
        "make-buy-partner",
        "market-entry",
        "pivot-scale-kill",
        "innovation-portfolio",
        "vendor-technology",
        "org-design",
        "pilot-to-scale"
    ]
}
