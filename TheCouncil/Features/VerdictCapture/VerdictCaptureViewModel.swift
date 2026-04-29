import Foundation
import Observation

// MARK: - Errors

enum VerdictCaptureError: Error, Equatable {
    case missingVerdictText
    case saveFailed(String)
    case generationFailed(String)
}

// MARK: - VerdictCaptureViewModel

@Observable
@MainActor
final class VerdictCaptureViewModel {

    // MARK: - Inputs

    let decision: Decision
    let trayItems: [TrayItem]
    let graphViewModel: GraphViewModel?

    // MARK: - Form fields

    var verdictText: String = ""
    var confidence: Int = 70
    var risk: String = ""
    var blindSpot: String = ""
    var opportunity: String = ""
    var testAction: String = ""
    var testMetric: String = ""
    var testThreshold: String = ""
    var outcomeDeadline: Date

    // Auto-populated from tray
    private(set) var keyForArguments: [TrayItem] = []
    private(set) var keyAgainstArguments: [TrayItem] = []

    // Pre-mortem (AI-generated, editable)
    var preMortem: String = ""

    // MARK: - State

    var isDrafting: Bool = false
    var isGeneratingPreMortem: Bool = false
    var showPreMortemSheet: Bool = false
    var isSaving: Bool = false
    var didSave: Bool = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let chatClient: StreamingChatClient
    private let db: DatabaseManager
    private let now: () -> Date
    private let draftModel = "claude-sonnet-4-6"
    private let preMortemModel = "claude-sonnet-4-6"

    // MARK: - Init

    init(
        decision: Decision,
        trayItems: [TrayItem],
        graphViewModel: GraphViewModel? = nil,
        chatClient: StreamingChatClient = AnthropicClient.shared,
        db: DatabaseManager = .shared,
        now: @escaping () -> Date = { Date() }
    ) {
        self.decision = decision
        self.trayItems = trayItems
        self.graphViewModel = graphViewModel
        self.chatClient = chatClient
        self.db = db
        self.now = now
        let deadlineDays = 60
        self.outcomeDeadline = Calendar.current.date(
            byAdding: .day, value: deadlineDays, to: now()
        ) ?? now().addingTimeInterval(60 * 86_400)
        self.populateFromTray()
    }

    // MARK: - Auto-populate

    func populateFromTray() {
        keyForArguments = trayItems.filter { $0.position == .for }
        keyAgainstArguments = trayItems.filter { $0.position == .against }
    }

    // MARK: - Draft verdict with Claude

    func draftVerdict() async {
        guard !isDrafting else { return }
        isDrafting = true
        errorMessage = nil
        defer { isDrafting = false }

        let prompt = Self.buildVerdictPrompt(
            brief: decision.refinedBrief ?? decision.question,
            forArgs: keyForArguments,
            againstArgs: keyAgainstArguments
        )
        do {
            let text = try await runStreamingPrompt(prompt: prompt, model: draftModel, temperature: 0.4)
            verdictText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            errorMessage = "Draft failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Generate pre-mortem (called on Save Verdict)

    func generatePreMortem() async {
        guard !isGeneratingPreMortem else { return }
        isGeneratingPreMortem = true
        errorMessage = nil
        defer { isGeneratingPreMortem = false }

        let prompt = Self.buildPreMortemPrompt(
            verdictText: verdictText,
            confidence: confidence,
            outcomeDeadline: outcomeDeadline
        )
        do {
            let text = try await runStreamingPrompt(prompt: prompt, model: preMortemModel, temperature: 0.6)
            preMortem = text.trimmingCharacters(in: .whitespacesAndNewlines)
            showPreMortemSheet = true
        } catch {
            errorMessage = "Pre-mortem generation failed: \(error.localizedDescription)"
            showPreMortemSheet = true  // still show so user can write their own
        }
    }

    // MARK: - Save

    func save() async {
        guard !isSaving else { return }
        guard !verdictText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Verdict text is required."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let verdict = Verdict(
            id: UUID().uuidString,
            decisionId: decision.id,
            createdAt: now(),
            verdictText: verdictText,
            confidence: confidence,
            keyForJson: Self.encodeArgumentTexts(keyForArguments),
            keyAgainstJson: Self.encodeArgumentTexts(keyAgainstArguments),
            risk: risk,
            blindSpot: blindSpot,
            opportunity: opportunity,
            preMortem: preMortem,
            outcomeDeadline: outcomeDeadline,
            testAction: testAction,
            testMetric: testMetric,
            testThreshold: testThreshold,
            outcomeStatus: .pending
        )
        let decisionId = decision.id
        do {
            try await db.write { db in
                try verdict.insert(db)
                try db.execute(
                    sql: "UPDATE decisions SET status = 'complete' WHERE id = ?",
                    arguments: [decisionId]
                )
            }
            graphViewModel?.saveGraphState()
            didSave = true
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Streaming helper

    private func runStreamingPrompt(
        prompt: String,
        model: String,
        temperature: Double
    ) async throws -> String {
        let messages = [ChatMessage(role: "user", content: prompt)]
        let stream = chatClient.streamChat(messages: messages, model: model, temperature: temperature)
        var buffer = ""
        for try await delta in stream { buffer += delta }
        return buffer
    }

    // MARK: - Prompt construction (static so tests can verify exact strings)

    static func buildVerdictPrompt(
        brief: String,
        forArgs: [TrayItem],
        againstArgs: [TrayItem]
    ) -> String {
        let forBlock = forArgs.isEmpty
            ? "(none pinned)"
            : forArgs.enumerated().map { "\($0 + 1). \($1.text)" }.joined(separator: "\n")
        let againstBlock = againstArgs.isEmpty
            ? "(none pinned)"
            : againstArgs.enumerated().map { "\($0 + 1). \($1.text)" }.joined(separator: "\n")

        return """
        You are helping draft a decision verdict.

        Refined brief:
        \(brief)

        Key arguments FOR:
        \(forBlock)

        Key arguments AGAINST:
        \(againstBlock)

        Write a 2–4 sentence recommendation that names the action to take and the single most important reason. Do not list the arguments back. Do not hedge with caveats unless one is decisive.
        """
    }

    static func buildPreMortemPrompt(
        verdictText: String,
        confidence: Int,
        outcomeDeadline: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        let dateString = formatter.string(from: outcomeDeadline)
        return """
        Assume it is \(dateString) and this decision proved wrong.

        Verdict: \(verdictText)
        Confidence at decision time: \(confidence)%

        Write a concise pre-mortem (3–5 bullets) explaining the most plausible failure path. Each bullet should name a specific cause and its consequence. No preamble.
        """
    }

    // MARK: - JSON helpers

    nonisolated static func encodeArgumentTexts(_ items: [TrayItem]) -> String {
        let texts = items.map(\.text)
        guard let data = try? JSONEncoder().encode(texts),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    nonisolated static func decodeArgumentTexts(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }
}
