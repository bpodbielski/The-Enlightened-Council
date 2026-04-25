import Foundation
import XCTest
@testable import TheCouncil

final class DebateEngineTests: XCTestCase {

    private func persona(_ id: String) -> Persona {
        Persona(id: id, version: 1, label: id.capitalized, systemPrompt: "sys-\(id)")
    }

    private func model(_ id: String, _ provider: ModelProvider) -> ModelSpec {
        ModelSpec(id: id, provider: provider, inputCostPer1MUsd: 1, outputCostPer1MUsd: 1)
    }

    private func run(id: String, model: String, persona: String, round: Int, sample: Int = 1, response: String) -> ModelRun {
        ModelRun(
            id: id, decisionId: "D", modelName: model, provider: .anthropic,
            persona: persona, roundNumber: round, sampleNumber: sample,
            temperature: 0.7, prompt: "p", response: response,
            tokensIn: 0, tokensOut: 0, costUsd: 0,
            createdAt: Date(timeIntervalSince1970: 0), error: nil, positionChanged: nil
        )
    }

    // MARK: - Anonymization mapping

    func test_anonMap_assignsStableLettersSortedByModelThenPersona() {
        let runs = [
            run(id: "1", model: "gpt-5.4",          persona: "operator",  round: 1, response: "r1"),
            run(id: "2", model: "claude-opus-4-7",  persona: "skeptic",   round: 1, response: "r2"),
            run(id: "3", model: "claude-opus-4-7",  persona: "operator",  round: 1, response: "r3"),
        ]
        let map = DebateEngine.anonMap(for: runs)
        // Sorted by (model, persona): claude+operator, claude+skeptic, gpt+operator
        XCTAssertEqual(map[DebateEngine.key(model: "claude-opus-4-7", persona: "operator")], "Perspective A")
        XCTAssertEqual(map[DebateEngine.key(model: "claude-opus-4-7", persona: "skeptic")],  "Perspective B")
        XCTAssertEqual(map[DebateEngine.key(model: "gpt-5.4",         persona: "operator")], "Perspective C")
    }

    func test_anonMap_isStableAcrossCallOrder() {
        let runsA = [
            run(id: "1", model: "b", persona: "y", round: 1, response: "."),
            run(id: "2", model: "a", persona: "x", round: 1, response: ".")
        ]
        let runsB = Array(runsA.reversed())
        XCTAssertEqual(DebateEngine.anonMap(for: runsA), DebateEngine.anonMap(for: runsB))
    }

    // MARK: - Round 2 tasks

    func test_buildRound2Tasks_excludesOwnRound1OutputAndUsesAnonLabels() {
        let m1 = model("claude-opus-4-7", .anthropic)
        let m2 = model("gpt-5.4",         .openai)
        let pSkeptic  = persona("skeptic")
        let pOperator = persona("operator")
        let round1 = [
            run(id: "r-claude-skeptic",  model: m1.id, persona: pSkeptic.id,  round: 1, response: "claude says X"),
            run(id: "r-gpt-operator",    model: m2.id, persona: pOperator.id, round: 1, response: "gpt says Y")
        ]
        let tasks = DebateEngine.buildRound2Tasks(
            decisionId: "D",
            participants: [(m1, pSkeptic), (m2, pOperator)],
            samples: 1,
            round1Runs: round1,
            brief: "brief",
            lensLabel: "Lens"
        )
        XCTAssertEqual(tasks.count, 2)
        let claudeTask = tasks.first { $0.model.id == m1.id && $0.persona.id == pSkeptic.id }!
        XCTAssertEqual(claudeTask.round, 2)
        XCTAssertTrue(claudeTask.userPrompt.contains("gpt says Y"))
        XCTAssertFalse(claudeTask.userPrompt.contains("claude says X"))
        XCTAssertTrue(claudeTask.userPrompt.contains("Perspective"))
        XCTAssertTrue(claudeTask.userPrompt.contains("REBUTTAL"))
    }

    // MARK: - Round 3 tasks

    func test_buildRound3Tasks_includesOwnRound1AndOtherRound2Rebuttals() {
        let m1 = model("claude-opus-4-7", .anthropic)
        let m2 = model("gpt-5.4",         .openai)
        let pSkeptic  = persona("skeptic")
        let pOperator = persona("operator")
        let round1 = [
            run(id: "r1-cs", model: m1.id, persona: pSkeptic.id,  round: 1, response: "own-round1"),
            run(id: "r1-go", model: m2.id, persona: pOperator.id, round: 1, response: "other-round1")
        ]
        let round2 = [
            run(id: "r2-cs", model: m1.id, persona: pSkeptic.id,  round: 2, response: "own-rebuttal"),
            run(id: "r2-go", model: m2.id, persona: pOperator.id, round: 2, response: "other-rebuttal")
        ]
        let tasks = DebateEngine.buildRound3Tasks(
            decisionId: "D",
            participants: [(m1, pSkeptic), (m2, pOperator)],
            samples: 1,
            round1Runs: round1,
            round2Runs: round2,
            brief: "brief",
            lensLabel: "Lens"
        )
        let claudeTask = tasks.first { $0.model.id == m1.id && $0.persona.id == pSkeptic.id }!
        XCTAssertEqual(claudeTask.round, 3)
        XCTAssertTrue(claudeTask.userPrompt.contains("own-round1"))
        XCTAssertTrue(claudeTask.userPrompt.contains("other-rebuttal"))
        XCTAssertFalse(claudeTask.userPrompt.contains("own-rebuttal"))
        XCTAssertTrue(claudeTask.userPrompt.contains("POSITION"))
    }

    // MARK: - POSITION parsing

    func test_parsePosition_updated() {
        XCTAssertEqual(DebateEngine.parsePosition(in: "something\nPOSITION: updated\n..."), true)
    }

    func test_parsePosition_maintained() {
        XCTAssertEqual(DebateEngine.parsePosition(in: "POSITION: maintained"), false)
    }

    func test_parsePosition_caseInsensitive() {
        XCTAssertEqual(DebateEngine.parsePosition(in: "position: UPDATED"), true)
        XCTAssertEqual(DebateEngine.parsePosition(in: "Position: Maintained"), false)
    }

    func test_parsePosition_missingReturnsNil() {
        XCTAssertNil(DebateEngine.parsePosition(in: "no marker here"))
    }

    func test_parsePosition_unknownValueReturnsNil() {
        XCTAssertNil(DebateEngine.parsePosition(in: "POSITION: confused"))
    }
}
