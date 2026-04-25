import Foundation
import os.log

// MARK: - RefinementError

enum RefinementError: Error {
    case signOffFailed(underlying: Error)
    case chatPersistenceFailed(underlying: Error)
}

// MARK: - RefinementViewModel

@Observable
@MainActor
final class RefinementViewModel {

    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "RefinementViewModel")

    // MARK: - State

    let decision: Decision
    private(set) var chatMessages: [ChatMessage] = []
    private(set) var currentBriefDraft: String = ""
    private(set) var redactionSuggestions: [RedactionSuggestion] = []
    private(set) var isStreaming: Bool = false
    private(set) var streamingError: String? = nil
    private(set) var isSavingSignOff: Bool = false
    private(set) var signOffError: String? = nil

    private let engine = RedactionEngine()

    // MARK: - Init

    init(decision: Decision) {
        self.decision = decision
    }

    // MARK: - Session

    func startSession(client: AnthropicClient, db: DatabaseManager) async {
        // Pre-populate redaction suggestions from the question and success criteria
        let combinedText = "\(decision.question)\n\(decision.successCriteria)"
        redactionSuggestions = engine.findSuggestions(in: combinedText)

        // Build first user message
        let userMessageContent = buildInitialUserMessage()
        let userMessage = ChatMessage(role: "user", content: userMessageContent)
        chatMessages.append(userMessage)

        await streamClaudeResponse(
            client: client,
            db: db,
            systemPrompt: Self.refinementSystemPrompt
        )
    }

    func sendMessage(_ text: String, client: AnthropicClient, db: DatabaseManager) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userMessage = ChatMessage(role: "user", content: text)
        chatMessages.append(userMessage)

        await streamClaudeResponse(
            client: client,
            db: db,
            systemPrompt: Self.refinementSystemPrompt
        )
    }

    func updateSuggestion(id: UUID, state: SuggestionState) {
        guard let index = redactionSuggestions.firstIndex(where: { $0.id == id }) else { return }
        redactionSuggestions[index].state = state
    }

    func signOff(db: DatabaseManager) async throws -> Decision {
        isSavingSignOff = true
        signOffError = nil
        defer { isSavingSignOff = false }

        // Apply approved redactions to the current brief draft
        let redactedBrief = engine.applyApproved(redactionSuggestions, to: currentBriefDraft)

        // Build updated decision
        var updated = decision
        updated.refinedBrief = redactedBrief
        updated.status = .ready

        let snapshot = updated
        do {
            try await db.write { db in
                try snapshot.update(db)
            }
        } catch {
            signOffError = error.localizedDescription
            throw RefinementError.signOffFailed(underlying: error)
        }

        return updated
    }

    // MARK: - Private helpers

    private func streamClaudeResponse(
        client: AnthropicClient,
        db: DatabaseManager,
        systemPrompt: String
    ) async {
        isStreaming = true
        streamingError = nil

        // Add a placeholder assistant message
        let assistantMessage = ChatMessage(role: "assistant", content: "")
        chatMessages.append(assistantMessage)
        let assistantIndex = chatMessages.count - 1

        // The messages sent to the API (excluding the current empty assistant message)
        let messagesToSend = Array(chatMessages.dropLast())

        // SPEC §6.7: refinement facilitator uses claude-opus-4-7
        let model = "claude-opus-4-7"

        let stream = client.streamRefinement(
            systemPrompt: systemPrompt,
            messages: messagesToSend,
            model: model
        )

        var accumulated = ""

        do {
            for try await token in stream {
                accumulated += token
                chatMessages[assistantIndex] = ChatMessage(role: "assistant", content: accumulated)

                // If the response looks like a refined brief, update the draft
                if accumulated.hasPrefix("DECISION:") {
                    currentBriefDraft = accumulated
                }
            }
        } catch {
            streamingError = error.localizedDescription
            Self.logger.error("Streaming error: \(error)")
        }

        isStreaming = false

        // Persist chat log
        await persistChatLog(db: db)
    }

    private func persistChatLog(db: DatabaseManager) async {
        let messages = chatMessages
        let decisionId = decision.id

        do {
            let encoded = try JSONEncoder().encode(messages)
            let jsonString = String(data: encoded, encoding: .utf8)

            try await db.write { db in
                try db.execute(
                    sql: "UPDATE decisions SET refinement_chat_log = ? WHERE id = ?",
                    arguments: [jsonString, decisionId]
                )
            }
        } catch {
            Self.logger.error("Failed to persist chat log: \(error)")
        }
    }

    private func buildInitialUserMessage() -> String {
        """
        Decision question: \(decision.question)
        Decision type: \(decision.lensTemplate)
        Reversibility: \(decision.reversibility.rawValue)
        Time horizon: \(decision.timeHorizon.rawValue)
        Sensitivity: \(decision.sensitivityClass.rawValue)
        Success criteria: \(decision.successCriteria)
        """
    }

    // MARK: - System prompt (SPEC §6.7)

    private static let refinementSystemPrompt = """
    You are a decision-refinement facilitator for a structured AI debate process.

    Your job is to help the user sharpen their decision brief before it goes to the council of AI advisors.

    In your FIRST response:
    1. Review the brief for ambiguity, missing context, and unstated assumptions.
    2. Ask exactly 2 to 4 clarifying questions in a SINGLE response (never one at a time).
    3. If sensitivity class is not "confidential", suggest redactions for any PII, financial figures, personal names, or identifying detail you notice.
    4. Do NOT produce the refined brief yet.

    In SUBSEQUENT responses:
    - Answer any follow-up questions from the user.
    - When the user signals they are ready (says "done", "good enough", "approve", or clicks the sign-off button), produce the structured refined brief in this format:

    DECISION: [one-sentence statement of the decision]
    CONTEXT: [2-3 sentences of relevant context]
    SUCCESS CRITERIA: [the user's criteria, clarified]
    CONSTRAINTS: [key constraints identified from the conversation]
    KEY ASSUMPTIONS: [assumptions the council should be aware of]
    SENSITIVITY: [sensitivity class and any relevant notes]
    """
}
