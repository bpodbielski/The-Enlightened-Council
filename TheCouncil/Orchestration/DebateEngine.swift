import Foundation

/// Stateless helpers for the 3-round debate protocol per SPEC §6.4.
///
/// Round 1: independent analysis (temperature variation, built by the
/// configuration VM).
/// Round 2: each participant rebuts all other round-1 outputs with
/// labels anonymized to "Perspective A / B / …". Mapping is stable per
/// decision — same (model,persona) always maps to the same letter.
/// Round 3: each participant sees its own round-1 output plus all
/// round-2 rebuttals *from other participants* and must declare
/// `POSITION: maintained|updated`.
enum DebateEngine {

    typealias Participant = (model: ModelSpec, persona: Persona)

    // MARK: - Anonymization

    static func key(model: String, persona: String) -> String {
        "\(model)|\(persona)"
    }

    /// Stable `(model,persona) → "Perspective X"` mapping. Sorted by
    /// (model.id, persona.id) so the assignment is deterministic across
    /// rounds within a single decision.
    static func anonMap(for runs: [ModelRun]) -> [String: String] {
        let unique = Set(runs.map { key(model: $0.modelName, persona: $0.persona) })
        let sorted = unique.sorted()
        let letters = (UnicodeScalar("A").value...UnicodeScalar("Z").value).map { String(UnicodeScalar($0)!) }
        var out: [String: String] = [:]
        for (i, k) in sorted.enumerated() where i < letters.count {
            out[k] = "Perspective \(letters[i])"
        }
        return out
    }

    // MARK: - Round 2 prompt assembly

    static func buildRound2Tasks(
        decisionId: String,
        participants: [Participant],
        samples: Int,
        round1Runs: [ModelRun],
        brief: String,
        lensLabel: String
    ) -> [OrchestratorTask] {
        let anon = anonMap(for: round1Runs)
        var tasks: [OrchestratorTask] = []
        for (model, persona) in participants {
            let selfKey = key(model: model.id, persona: persona.id)
            let others = round1Runs.filter { key(model: $0.modelName, persona: $0.persona) != selfKey }
            let othersBlock = others
                .compactMap { r -> String? in
                    let label = anon[key(model: r.modelName, persona: r.persona)] ?? "Perspective ?"
                    guard let resp = r.response, !resp.isEmpty else { return nil }
                    return "--- \(label) ---\n\(resp)"
                }
                .joined(separator: "\n\n")

            for sample in 1...max(1, samples) {
                tasks.append(OrchestratorTask(
                    decisionId: decisionId,
                    model: model,
                    persona: persona,
                    round: 2,
                    sample: sample,
                    temperature: CouncilConfigurationViewModel.temperature(forSample: sample),
                    systemPrompt: persona.systemPrompt,
                    userPrompt: round2Prompt(brief: brief, lensLabel: lensLabel, othersBlock: othersBlock)
                ))
            }
        }
        return tasks
    }

    static func round2Prompt(brief: String, lensLabel: String, othersBlock: String) -> String {
        """
        Decision lens: \(lensLabel)

        Refined brief:
        \(brief)

        Below are the round-1 analyses of the other perspectives, with identities
        anonymized. Rebut and steel-man each.

        \(othersBlock)

        Respond in the following exact format:

        REBUTTAL:
        - WEAKNESS: [flaw in argument X]
        - ASSUMPTION: [unstated assumption in argument Y]
        - COUNTER-EVIDENCE: [evidence that contradicts argument Z]
        STEEL-MAN: [strongest version of the opposite recommendation]
        """
    }

    // MARK: - Round 3 prompt assembly

    static func buildRound3Tasks(
        decisionId: String,
        participants: [Participant],
        samples: Int,
        round1Runs: [ModelRun],
        round2Runs: [ModelRun],
        brief: String,
        lensLabel: String
    ) -> [OrchestratorTask] {
        let anon = anonMap(for: round1Runs)
        var tasks: [OrchestratorTask] = []
        for (model, persona) in participants {
            let selfKey = key(model: model.id, persona: persona.id)
            let ownRound1 = round1Runs.first { key(model: $0.modelName, persona: $0.persona) == selfKey }
            let otherRound2 = round2Runs.filter { key(model: $0.modelName, persona: $0.persona) != selfKey }
            let othersBlock = otherRound2
                .compactMap { r -> String? in
                    let label = anon[key(model: r.modelName, persona: r.persona)] ?? "Perspective ?"
                    guard let resp = r.response, !resp.isEmpty else { return nil }
                    return "--- \(label) rebuttal ---\n\(resp)"
                }
                .joined(separator: "\n\n")

            for sample in 1...max(1, samples) {
                tasks.append(OrchestratorTask(
                    decisionId: decisionId,
                    model: model,
                    persona: persona,
                    round: 3,
                    sample: sample,
                    temperature: CouncilConfigurationViewModel.temperature(forSample: sample),
                    systemPrompt: persona.systemPrompt,
                    userPrompt: round3Prompt(
                        brief: brief,
                        lensLabel: lensLabel,
                        ownRound1: ownRound1?.response ?? "",
                        othersBlock: othersBlock
                    )
                ))
            }
        }
        return tasks
    }

    static func round3Prompt(brief: String, lensLabel: String, ownRound1: String, othersBlock: String) -> String {
        """
        Decision lens: \(lensLabel)

        Refined brief:
        \(brief)

        Your round-1 analysis:
        \(ownRound1)

        Rebuttals from other perspectives:
        \(othersBlock)

        Defend or update your position. Respond in the following exact format:

        POSITION: [maintained/updated]
        IF MAINTAINED:
          STRONGER EVIDENCE: [additional support]
          REBUTTAL RESPONSE: [why rebuttals don't change the position]
        IF UPDATED:
          CHANGE: [what changed and why]
          NEW RECOMMENDATION: [for/against/conditional]
        """
    }

    // MARK: - POSITION parsing

    /// Parse `POSITION: maintained|updated` (case-insensitive) out of a
    /// round-3 response. Returns `true` if the position changed, `false` if
    /// maintained, `nil` if no marker or an unrecognized value.
    static func parsePosition(in response: String) -> Bool? {
        let pattern = #"(?im)^\s*position\s*:\s*(maintained|updated)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(response.startIndex..<response.endIndex, in: response)
        guard let match = regex.firstMatch(in: response, range: range),
              let valRange = Range(match.range(at: 1), in: response) else { return nil }
        let value = response[valRange].lowercased()
        switch value {
        case "updated":    return true
        case "maintained": return false
        default:           return nil
        }
    }
}
