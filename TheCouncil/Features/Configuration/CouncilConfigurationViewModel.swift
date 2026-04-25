import Foundation
import Observation

@Observable
@MainActor
final class CouncilConfigurationViewModel {

    let decision: Decision

    var availableModels: [ModelSpec]
    var availablePersonas: [Persona] = []
    var lensTemplate: LensTemplate?

    var enabledModelIDs: Set<String>
    var enabledPersonaIDs: Set<String> = []

    var rounds: Int = 3
    var samples: Int = 3

    var isLoading: Bool = false
    var loadError: String?

    private let lensLoader: LensTemplateLoader
    private let personaLoader: PersonaLoader

    init(
        decision: Decision,
        models: [ModelSpec] = ModelSpec.frontierSet,
        lensLoader: LensTemplateLoader = LensTemplateLoader(),
        personaLoader: PersonaLoader = PersonaLoader()
    ) {
        self.decision = decision
        self.availableModels = models
        self.enabledModelIDs = Set(models.map { $0.id })
        self.lensLoader = lensLoader
        self.personaLoader = personaLoader
    }

    // MARK: - Loading

    func loadResources() {
        isLoading = true
        loadError = nil
        do {
            let template = try lensLoader.load(id: decision.lensTemplate)
            self.lensTemplate = template
            self.rounds = template.defaultRounds
            self.samples = template.defaultSamples
            let all = try personaLoader.loadAll()
            self.availablePersonas = all
            self.enabledPersonaIDs = Set(template.defaultPersonas)
        } catch {
            loadError = "Failed to load lens/personas: \(error)"
        }
        isLoading = false
    }

    // MARK: - Actions

    func toggleModel(_ id: String) {
        if enabledModelIDs.contains(id) { enabledModelIDs.remove(id) }
        else { enabledModelIDs.insert(id) }
    }

    func togglePersona(_ id: String) {
        if enabledPersonaIDs.contains(id) { enabledPersonaIDs.remove(id) }
        else { enabledPersonaIDs.insert(id) }
    }

    var canRun: Bool {
        !enabledModelIDs.isEmpty
        && !enabledPersonaIDs.isEmpty
        && rounds >= 1 && rounds <= 5
        && samples >= 1 && samples <= 5
    }

    var estimatedCostUsd: Double {
        // Rough estimate: 2k input + 1k output tokens per run.
        let inTokens = 2_000
        let outTokens = 1_000
        let perRun = availableModels
            .filter { enabledModelIDs.contains($0.id) }
            .map { $0.estimatedCost(tokensIn: inTokens, tokensOut: outTokens) }
            .reduce(0, +)
        let runsPerModel = enabledPersonaIDs.count * rounds * samples
        return perRun * Double(runsPerModel)
    }

    /// Build an OrchestratorTask matrix: one task per (model × persona × sample)
    /// for round 1. Rounds 2+ are Phase 4 (DebateEngine).
    func buildTasks() -> [Int: [OrchestratorTask]] {
        let enabledModels = availableModels.filter { enabledModelIDs.contains($0.id) }
        let enabledPersonas = availablePersonas.filter { enabledPersonaIDs.contains($0.id) }
        let brief = decision.refinedBrief ?? decision.question
        let lensLabel = lensTemplate?.label ?? decision.lensTemplate

        var tasks: [OrchestratorTask] = []
        for model in enabledModels {
            for persona in enabledPersonas {
                for sample in 1...samples {
                    tasks.append(OrchestratorTask(
                        decisionId: decision.id,
                        model: model,
                        persona: persona,
                        round: 1,
                        sample: sample,
                        temperature: Self.temperature(forSample: sample),
                        systemPrompt: persona.systemPrompt,
                        userPrompt: Self.buildRound1UserPrompt(brief: brief, lensLabel: lensLabel)
                    ))
                }
            }
        }
        return [1: tasks]
    }

    /// Replace Qwen 32B with Qwen 14B in the enabled model set.
    /// Called from the configuration view when LocalResourceGate returns .insufficientMemory.
    func substituteQwen14B() {
        enabledModelIDs.remove("qwen-2.5-32b-instruct")
        enabledModelIDs.insert("qwen-2.5-14b-instruct")
    }

    nonisolated static func temperature(forSample sample: Int) -> Double {
        switch sample {
        case 1: return 0.3
        case 2: return 0.7
        default: return 1.0
        }
    }

    static func buildRound1UserPrompt(brief: String, lensLabel: String) -> String {
        """
        Decision lens: \(lensLabel)

        Refined brief:
        \(brief)

        Provide your independent analysis in the following exact format:

        RECOMMENDATION: [for/against/conditional]
        EVIDENCE:
        - [evidence point 1]
        - [evidence point 2]
        KEY ASSUMPTION: [single most critical assumption]
        FLAGGED LIMITATION: [what this analysis does not cover]
        """
    }
}
