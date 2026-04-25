// RedactionEngineTests.swift
// Tests the redaction pattern detection rules from SPEC §6.7.
// RedactionEngine is not yet implemented; the engine is inline here.
// The production RedactionEngine must match this API.

import Foundation
import XCTest

// MARK: - Inline types

struct RedactionSuggestion: Sendable, Equatable {
    let originalText: String
    let reason: String
}

struct RedactionEngine: Sendable {

    // SPEC §6.7 patterns:
    //   Email  : \b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b  (case-insensitive)
    //   Dollar : \$[\d,]+
    //   Name   : two consecutive Title-Cased words (e.g. "John Smith")

    private static let emailPattern =
        #"\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#

    private static let dollarPattern =
        #"\$[\d,]+"#

    // Two consecutive title-cased words separated by a single space.
    // A title-cased word starts with an uppercase letter followed by one or
    // more lowercase letters.
    private static let capitalizedPairPattern =
        #"\b[A-Z][a-z]+\s[A-Z][a-z]+\b"#

    func findSuggestions(
        in text: String,
        customKeywords: [String] = []
    ) -> [RedactionSuggestion] {
        guard !text.isEmpty else { return [] }

        var suggestions: [RedactionSuggestion] = []

        suggestions += matches(
            for: Self.emailPattern,
            in: text,
            options: .caseInsensitive,
            reason: "email address"
        )

        suggestions += matches(
            for: Self.dollarPattern,
            in: text,
            options: [],
            reason: "dollar amount"
        )

        suggestions += matches(
            for: Self.capitalizedPairPattern,
            in: text,
            options: [],
            reason: "possible name"
        )

        for keyword in customKeywords where !keyword.isEmpty {
            // Escape the keyword so regex metacharacters are treated literally,
            // then wrap in word-boundary anchors for whole-word matching.
            let escaped = NSRegularExpression.escapedPattern(for: keyword)
            suggestions += matches(
                for: #"\b"# + escaped + #"\b"#,
                in: text,
                options: [],
                reason: "custom keyword"
            )
        }

        return suggestions
    }

    // MARK: - Private helpers

    private func matches(
        for pattern: String,
        in text: String,
        options: NSRegularExpression.Options,
        reason: String
    ) -> [RedactionSuggestion] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return RedactionSuggestion(originalText: String(text[swiftRange]), reason: reason)
        }
    }
}

// MARK: - Tests

final class RedactionEngineTests: XCTestCase {

    private let engine = RedactionEngine()

    // MARK: Email

    func test_redactionEngine_email_isDetected() {
        let text = "Contact alice@example.com for details"
        let suggestions = engine.findSuggestions(in: text)
        let matched = suggestions.map(\.originalText)
        XCTAssertTrue(
            matched.contains("alice@example.com"),
            "Expected 'alice@example.com' in suggestions, got: \(matched)"
        )
    }

    // MARK: Dollar amount

    func test_redactionEngine_dollarAmount_isDetected() {
        let text = "Budget is $1,500,000 for this"
        let suggestions = engine.findSuggestions(in: text)
        let matched = suggestions.map(\.originalText)
        XCTAssertTrue(
            matched.contains("$1,500,000"),
            "Expected '$1,500,000' in suggestions, got: \(matched)"
        )
    }

    // MARK: Capitalized pair (name)

    func test_redactionEngine_capitalizedPair_isDetected() {
        let text = "Please ask John Smith about this"
        let suggestions = engine.findSuggestions(in: text)
        let matched = suggestions.map(\.originalText)
        XCTAssertTrue(
            matched.contains("John Smith"),
            "Expected 'John Smith' in suggestions, got: \(matched)"
        )
    }

    // MARK: Multiple patterns

    func test_redactionEngine_multiplePatterns_allDetected() {
        let text = "Sarah Connor emailed sarah@example.com about the $50,000 contract."
        let suggestions = engine.findSuggestions(in: text)
        // Expect at least one hit for name, one for email, one for dollar amount.
        XCTAssertGreaterThanOrEqual(
            suggestions.count, 3,
            "Expected at least 3 suggestions, got: \(suggestions.map(\.originalText))"
        )
        let matched = suggestions.map(\.originalText)
        XCTAssertTrue(matched.contains("Sarah Connor"), "Missing name suggestion")
        XCTAssertTrue(matched.contains("sarah@example.com"), "Missing email suggestion")
        XCTAssertTrue(matched.contains("$50,000"), "Missing dollar suggestion")
    }

    // MARK: No patterns

    func test_redactionEngine_noPatterns_returnsEmpty() {
        let text = "this is plain lowercase text with no sensitive data here"
        let suggestions = engine.findSuggestions(in: text)
        XCTAssertTrue(
            suggestions.isEmpty,
            "Expected empty suggestions for plain text, got: \(suggestions.map(\.originalText))"
        )
    }

    // MARK: Custom keyword

    func test_redactionEngine_customKeyword_isDetected() {
        let text = "Acme Corp is our client and they love us."
        let suggestions = engine.findSuggestions(in: text, customKeywords: ["Acme"])
        let matched = suggestions.map(\.originalText)
        XCTAssertTrue(
            matched.contains("Acme"),
            "Expected 'Acme' in suggestions, got: \(matched)"
        )
    }

    // MARK: Malformed / edge-case input

    func test_redactionEngine_malformedInput_doesNotCrash() {
        // Empty string — must return [] without crashing.
        let emptyResult = engine.findSuggestions(in: "")
        XCTAssertEqual(emptyResult, [], "Empty string should return []")

        // Very long string (10 000 chars) — must not crash and must return [].
        let longPlain = String(repeating: "a", count: 10_000)
        let longResult = engine.findSuggestions(in: longPlain)
        // No assertion on count — just verifying no crash and a valid value is returned.
        _ = longResult

        // Unicode-heavy string — must not crash.
        let unicode = "日本語テキスト 🎉 مرحبا"
        let unicodeResult = engine.findSuggestions(in: unicode)
        _ = unicodeResult
    }
}
