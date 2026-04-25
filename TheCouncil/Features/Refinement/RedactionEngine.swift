import Foundation

// MARK: - SuggestionState

enum SuggestionState: Sendable {
    case pending
    case approved
    case dismissed
}

// MARK: - RedactionSuggestion

struct RedactionSuggestion: Identifiable, Sendable {
    let id: UUID
    let range: Range<String.Index>
    let originalText: String
    let reason: String
    var state: SuggestionState
}

// MARK: - RedactionEngine

struct RedactionEngine: Sendable {

    // Known-places list per SPEC §6.7 — Title-Case words that are common place names,
    // suppressed to avoid flagging "New York", "San Francisco", "North America", etc. as person names.
    // Also includes generic Title-Case words that are not names.
    private static let knownPlaces: Set<String> = [
        // Directions / geographic descriptors
        "North", "South", "East", "West", "Central", "Upper", "Lower", "Greater",
        // Countries / continents
        "America", "Europe", "Asia", "Africa", "Australia", "Canada", "Mexico",
        "France", "Germany", "Japan", "China", "India", "Brazil", "Russia",
        "United", "Kingdom", "States",
        // US States (common abbreviated forms used as Title-Case words)
        "California", "Texas", "Florida", "York", "Jersey", "Hampshire",
        "Mexico", "Orleans", "Francisco", "Angeles", "Diego", "Vegas",
        // Generic non-name Title-Case words (determiners, pronouns, connectives)
        "The", "This", "That", "These", "Those",
        "When", "Where", "What", "How", "Why", "Which",
        "Each", "Every", "Some", "Many", "Most",
        "Other", "Another",
        "First", "Last", "Next",
        "New", "Old", "Good", "Best",
        "High", "Low", "San", "Los", "Las", "El", "La"
    ]

    // MARK: - Public API

    func findSuggestions(in text: String, customKeywords: [String] = []) -> [RedactionSuggestion] {
        var suggestions: [RedactionSuggestion] = []

        // Collect all matches across pattern types
        suggestions += findEmailMatches(in: text)
        suggestions += findDollarAmountMatches(in: text)
        suggestions += findPersonNameMatches(in: text)
        suggestions += findCustomKeywordMatches(in: text, keywords: customKeywords)

        // Sort by range start position
        suggestions.sort { $0.range.lowerBound < $1.range.lowerBound }

        // Remove overlapping: keep first, skip any that overlap with an already-accepted range
        var result: [RedactionSuggestion] = []
        var lastUpperBound: String.Index? = nil

        for suggestion in suggestions {
            if let lastUpper = lastUpperBound, suggestion.range.lowerBound < lastUpper {
                // Overlaps — skip
                continue
            }
            result.append(suggestion)
            lastUpperBound = suggestion.range.upperBound
        }

        return result
    }

    func applyApproved(_ suggestions: [RedactionSuggestion], to text: String) -> String {
        // Only process approved suggestions; sort descending so we can mutate without invalidating indices
        let approved = suggestions
            .filter { $0.state == .approved }
            .sorted { $0.range.lowerBound > $1.range.lowerBound }

        var result = text
        for suggestion in approved {
            let replacement = "[REDACTED: \(suggestion.reason)]"
            result.replaceSubrange(suggestion.range, with: replacement)
        }
        return result
    }

    // MARK: - Pattern finders

    private func findEmailMatches(in text: String) -> [RedactionSuggestion] {
        // SPEC §6.7 exact pattern — \b anchors prevent matching inside larger tokens
        guard let regex = try? NSRegularExpression(
            pattern: #"\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#,
            options: [.caseInsensitive]
        ) else { return [] }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return RedactionSuggestion(
                id: UUID(),
                range: swiftRange,
                originalText: String(text[swiftRange]),
                reason: "Email address",
                state: .pending
            )
        }
    }

    private func findDollarAmountMatches(in text: String) -> [RedactionSuggestion] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\$[\d,]+"#,
            options: []
        ) else { return [] }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return RedactionSuggestion(
                id: UUID(),
                range: swiftRange,
                originalText: String(text[swiftRange]),
                reason: "Financial figure",
                state: .pending
            )
        }
    }

    private func findPersonNameMatches(in text: String) -> [RedactionSuggestion] {
        // Match two consecutive Title-Case words (each starting with uppercase, containing at least one lowercase)
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([A-Z][a-z]+)\s+([A-Z][a-z]+)\b"#,
            options: []
        ) else { return [] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var results: [RedactionSuggestion] = []

        regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match,
                  let swiftRange = Range(match.range, in: text),
                  let firstRange = Range(match.range(at: 1), in: text),
                  let secondRange = Range(match.range(at: 2), in: text) else { return }

            let firstWord = String(text[firstRange])
            let secondWord = String(text[secondRange])

            // Skip if either word is in the stop list
            guard !Self.knownPlaces.contains(firstWord),
                  !Self.knownPlaces.contains(secondWord) else { return }

            results.append(RedactionSuggestion(
                id: UUID(),
                range: swiftRange,
                originalText: String(text[swiftRange]),
                reason: "Person name",
                state: .pending
            ))
        }

        return results
    }

    private func findCustomKeywordMatches(in text: String, keywords: [String]) -> [RedactionSuggestion] {
        var results: [RedactionSuggestion] = []
        let lowercasedText = text.lowercased()

        for keyword in keywords where !keyword.isEmpty {
            let lowercasedKeyword = keyword.lowercased()
            var searchStart = lowercasedText.startIndex

            while searchStart < lowercasedText.endIndex {
                guard let found = lowercasedText.range(of: lowercasedKeyword, range: searchStart..<lowercasedText.endIndex) else {
                    break
                }

                // Map the found range back to the original text
                let swiftRange = found.lowerBound..<found.upperBound
                results.append(RedactionSuggestion(
                    id: UUID(),
                    range: swiftRange,
                    originalText: String(text[swiftRange]),
                    reason: "Custom keyword: \(keyword)",
                    state: .pending
                ))
                searchStart = found.upperBound
            }
        }

        return results
    }
}
