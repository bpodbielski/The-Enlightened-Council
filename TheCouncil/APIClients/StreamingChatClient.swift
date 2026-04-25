import Foundation

// MARK: - ChatMessage

/// One message in a conversation.
/// Stored in `decisions.refinement_chat_log` as `{role, content, timestamp}` per SPEC §3.1 and §6.7.
struct ChatMessage: Codable, Sendable {
    let role: String        // "system" | "user" | "assistant"
    let content: String
    let timestamp: Int      // Unix timestamp (seconds since epoch)

    init(role: String, content: String, timestamp: Int = Int(Date().timeIntervalSince1970)) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - StreamingChatClient

protocol StreamingChatClient: Sendable {
    func streamChat(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error>
}
