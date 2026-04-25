import Foundation

/// Identifies a cloud model and its cost rates. Rates are USD per 1M tokens.
/// Defaults come from SPEC §6.1 (frontier / balanced / flash sets). These are
/// approximate list prices at time of writing and should be surfaced as
/// editable fields under Settings → Models in a later polish pass.
struct ModelSpec: Sendable, Hashable, Identifiable {
    let id: String
    let provider: ModelProvider
    let inputCostPer1MUsd: Double
    let outputCostPer1MUsd: Double

    func estimatedCost(tokensIn: Int, tokensOut: Int) -> Double {
        let inUsd  = (Double(tokensIn)  / 1_000_000) * inputCostPer1MUsd
        let outUsd = (Double(tokensOut) / 1_000_000) * outputCostPer1MUsd
        return inUsd + outUsd
    }
}

extension ModelSpec {
    static let frontierSet: [ModelSpec] = [
        .init(id: "claude-opus-4-7",                provider: .anthropic, inputCostPer1MUsd: 15.00, outputCostPer1MUsd: 75.00),
        .init(id: "gpt-5.4",                        provider: .openai,    inputCostPer1MUsd:  2.50, outputCostPer1MUsd: 10.00),
        .init(id: "gemini-3.1-pro-preview",         provider: .google,    inputCostPer1MUsd:  3.50, outputCostPer1MUsd: 10.50),
        .init(id: "grok-4.20-0309-non-reasoning",   provider: .xai,       inputCostPer1MUsd:  3.00, outputCostPer1MUsd: 15.00)
    ]
    static let balancedSet: [ModelSpec] = [
        .init(id: "claude-sonnet-4-6",       provider: .anthropic, inputCostPer1MUsd: 3.00, outputCostPer1MUsd: 15.00),
        .init(id: "gpt-5.4-mini",            provider: .openai,    inputCostPer1MUsd: 0.50, outputCostPer1MUsd:  2.00),
        .init(id: "gemini-3-flash-preview",  provider: .google,    inputCostPer1MUsd: 0.30, outputCostPer1MUsd:  1.20),
        .init(id: "grok-4.1",                provider: .xai,       inputCostPer1MUsd: 1.00, outputCostPer1MUsd:  5.00)
    ]
}

enum CloudClientFactory {
    static func client(for provider: ModelProvider) -> StreamingChatClient? {
        switch provider {
        case .anthropic:   return AnthropicClient.shared
        case .openai:      return OpenAIClient.shared
        case .google:      return GeminiClient.shared
        case .xai:         return GrokClient.shared
        case .localMLX:    return MLXRunner.shared
        case .localOllama: return OllamaClient.shared
        }
    }
}
