import Foundation

// MARK: - ExportPayload
//
// All data the renderers need, bundled so callers gather it once.

struct ExportPayload: Sendable {
    let decision: Decision
    let verdict: Verdict
    let outcome: Outcome?       // nil if pending or dismissed-without-row
    let modelRuns: [ModelRun]   // for the model panel + cost summary

    var modelPanel: [String] {
        // Distinct model_name values in insertion order.
        var seen = Set<String>()
        var ordered: [String] = []
        for run in modelRuns where seen.insert(run.modelName).inserted {
            ordered.append(run.modelName)
        }
        return ordered
    }

    var totalCostUsd: Double {
        modelRuns.compactMap(\.costUsd).reduce(0, +)
    }
}

// MARK: - MarkdownRenderer
//
// Renders the SPEC §6.10 Markdown template. Pure function, easy to test.

enum MarkdownRenderer {

    static func render(_ payload: ExportPayload) -> String {
        let d = payload.decision
        let v = payload.verdict
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .none
        dateFmt.locale = Locale(identifier: "en_US_POSIX")

        let createdDate = dateFmt.string(from: v.createdAt)
        let deadlineDate = dateFmt.string(from: v.outcomeDeadline)

        let forItems = VerdictCaptureViewModel.decodeArgumentTexts(v.keyForJson)
        let againstItems = VerdictCaptureViewModel.decodeArgumentTexts(v.keyAgainstJson)

        var out = ""
        out += "# \(d.question)\n\n"
        out += "**Date:** \(createdDate)\n"
        out += "**Lens:** \(d.lensTemplate)\n"
        out += "**Confidence:** \(v.confidence)%\n"
        out += "**Outcome deadline:** \(deadlineDate)\n\n"

        out += "## Verdict\n\n"
        out += "\(v.verdictText.trimmedOrFallback("(empty)"))\n\n"

        out += "## Arguments For\n\n"
        out += renderBullets(forItems)

        out += "\n## Arguments Against\n\n"
        out += renderBullets(againstItems)

        out += "\n## Risk\n\n"
        out += "\(v.risk.trimmedOrFallback("(none)"))\n\n"

        out += "## Blind Spot\n\n"
        out += "\(v.blindSpot.trimmedOrFallback("(none)"))\n\n"

        out += "## Opportunity\n\n"
        out += "\(v.opportunity.trimmedOrFallback("(none)"))\n\n"

        out += "## Pre-mortem\n\n"
        out += "\(v.preMortem.trimmedOrFallback("(none)"))\n\n"

        out += "## Test\n\n"
        out += "**Action:** \(v.testAction.trimmedOrFallback("(none)"))\n"
        out += "**Metric:** \(v.testMetric.trimmedOrFallback("(none)"))\n"
        out += "**Threshold:** \(v.testThreshold.trimmedOrFallback("(none)"))\n\n"

        // Optional outcome record (only if marked)
        if let outcome = payload.outcome, v.outcomeStatus.isTerminal, v.outcomeStatus != .dismissed {
            out += "## Outcome\n\n"
            out += "**Result:** \(outcome.result.rawValue.capitalized)\n"
            out += "**Marked:** \(dateFmt.string(from: outcome.markedAt))\n"
            if !outcome.actualNotes.isEmpty {
                out += "\n**What happened:**\n\(outcome.actualNotes)\n"
            }
            if !outcome.whatChanged.isEmpty {
                out += "\n**What changed:**\n\(outcome.whatChanged)\n"
            }
            out += "\n"
        }

        out += "---\n"
        out += "*Model panel: \(payload.modelPanel.joined(separator: ", "))*\n"
        out += "*Total cost: $\(String(format: "%.2f", payload.totalCostUsd))*\n"
        return out
    }

    private static func renderBullets(_ items: [String]) -> String {
        if items.isEmpty { return "_(none)_\n" }
        return items.map { "- \($0)" }.joined(separator: "\n") + "\n"
    }
}

// MARK: - String helper

private extension String {
    func trimmedOrFallback(_ fallback: String) -> String {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }
}
