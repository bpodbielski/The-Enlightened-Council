import Foundation

/// Post-round-3 argument extraction per SPEC §6.4. Sends the aggregated
/// round-3 responses to a `StreamingChatClient` (Claude by default) and
/// parses a JSON array of `{position, text}` into typed `Argument` rows.
actor ArgumentExtractor {

    struct Extracted: Sendable, Equatable {
        let position: ArgumentPosition
        let text: String
    }

    enum ExtractorError: Error {
        case noJSONFound
        case malformedJSON(String)
    }

    private let client: StreamingChatClient
    private let model: String

    init(
        client: StreamingChatClient = AnthropicClient.shared,
        model: String = "claude-opus-4-7"
    ) {
        self.client = client
        self.model = model
    }

    /// Stream the extraction prompt and parse the resulting JSON into
    /// `Argument` rows ready to insert into `arguments`.
    func extract(from round3Runs: [ModelRun], decisionId: String) async throws -> [Argument] {
        let combined = round3Runs
            .compactMap { r -> String? in
                guard let resp = r.response, !resp.isEmpty else { return nil }
                return "=== \(r.modelName) / \(r.persona) (sample \(r.sampleNumber)) ===\n\(resp)"
            }
            .joined(separator: "\n\n")

        let prompt = Self.extractionPrompt(round3Block: combined)
        let messages: [ChatMessage] = [
            ChatMessage(role: "system", content: Self.systemPrompt),
            ChatMessage(role: "user",   content: prompt)
        ]

        var assembled = ""
        let stream = client.streamChat(messages: messages, model: model, temperature: 0.2)
        for try await chunk in stream { assembled += chunk }

        let parsed = try Self.parseArgumentsJSON(assembled)
        let sourceRunId = round3Runs.first?.id ?? decisionId
        return parsed.map { e in
            Argument(
                id: UUID().uuidString,
                decisionId: decisionId,
                sourceRunId: sourceRunId,
                position: e.position,
                text: e.text,
                clusterId: nil,
                prominence: 0
            )
        }
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You are a research assistant distilling arguments from a structured debate.
    Return ONLY a JSON array. No prose before or after.
    """

    static func extractionPrompt(round3Block: String) -> String {
        """
        The following block contains round-3 "defend or update" responses from
        multiple perspectives in a decision debate. Extract every distinct
        argument as a JSON array element.

        Schema: [{"position": "for" | "against" | "neutral", "text": "<one sentence>"}]

        Rules:
        - Deduplicate near-identical arguments.
        - "position" must be one of: for, against, neutral.
        - Keep each "text" under 240 characters.
        - Output ONLY the JSON array, nothing else.

        Round-3 responses:

        \(round3Block)
        """
    }

    // MARK: - Parsing

    /// Parse a JSON array of `{position, text}`. Tolerates leading/trailing
    /// prose and fenced-code blocks by scanning for the first `[ … ]` balanced
    /// bracket pair.
    static func parseArgumentsJSON(_ raw: String) throws -> [Extracted] {
        guard let slice = firstJSONArraySlice(in: raw) else {
            throw ExtractorError.noJSONFound
        }
        guard let data = slice.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let array = any as? [[String: Any]] else {
            throw ExtractorError.malformedJSON(String(slice.prefix(200)))
        }
        return array.compactMap { obj in
            guard let text = obj["text"] as? String, !text.isEmpty else { return nil }
            let posRaw = (obj["position"] as? String)?.lowercased() ?? ""
            let position = ArgumentPosition(rawValue: posRaw) ?? .neutral
            return Extracted(position: position, text: text)
        }
    }

    private static func firstJSONArraySlice(in raw: String) -> String? {
        guard let start = raw.firstIndex(of: "[") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        var i = start
        while i < raw.endIndex {
            let c = raw[i]
            if escape { escape = false }
            else if c == "\\" && inString { escape = true }
            else if c == "\"" { inString.toggle() }
            else if !inString {
                if c == "[" { depth += 1 }
                else if c == "]" {
                    depth -= 1
                    if depth == 0 {
                        return String(raw[start...i])
                    }
                }
            }
            i = raw.index(after: i)
        }
        return nil
    }
}
