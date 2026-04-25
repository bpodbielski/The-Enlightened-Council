import Foundation

/// A council member persona. System prompt content lives in the body of a
/// Markdown file with YAML-style front matter per SPEC §6.3:
///
///     ---
///     id: skeptic
///     version: 1
///     label: The Skeptic
///     ---
///     [System prompt content]
struct Persona: Sendable, Hashable, Identifiable {
    let id: String
    let version: Int
    let label: String
    let systemPrompt: String

    static let validIDs: Set<String> = [
        "skeptic",
        "first-principles",
        "operator",
        "strategist",
        "outsider",
        "customer-voice",
        "finance-lens",
        "risk-officer",
        "founder-mindset",
        "regulator"
    ]
}
