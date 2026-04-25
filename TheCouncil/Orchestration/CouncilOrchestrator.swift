import Foundation
import os.log

// MARK: - Public types

struct OrchestratorTask: Sendable, Identifiable, Hashable {
    let id: UUID
    let decisionId: String
    let model: ModelSpec
    let persona: Persona
    let round: Int
    let sample: Int
    let temperature: Double
    let systemPrompt: String
    let userPrompt: String

    init(
        id: UUID = UUID(),
        decisionId: String,
        model: ModelSpec,
        persona: Persona,
        round: Int,
        sample: Int,
        temperature: Double,
        systemPrompt: String,
        userPrompt: String
    ) {
        self.id = id
        self.decisionId = decisionId
        self.model = model
        self.persona = persona
        self.round = round
        self.sample = sample
        self.temperature = temperature
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
    }

    static func == (lhs: OrchestratorTask, rhs: OrchestratorTask) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum OrchestratorEvent: Sendable {
    case runStarted(taskId: UUID, round: Int, model: String, persona: String)
    case runCompleted(run: ModelRun)
    case runFailed(taskId: UUID, round: Int, model: String, persona: String, error: String)
    case roundCompleted(round: Int, completed: Int, failed: Int)
    case costSoftWarn(total: Double)
    case costHardPause(total: Double)
    case cancelled(completedRuns: Int, failedRuns: Int)
    case finished(completedRuns: Int, failedRuns: Int, totalCost: Double)
}

// MARK: - Errors

enum OrchestratorError: Error {
    case noClientForProvider(ModelProvider)
    case cancelled
}

// MARK: - CouncilOrchestrator

actor CouncilOrchestrator {

    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "Orchestrator")

    private let db: DatabaseManager
    private let clientForProvider: @Sendable (ModelProvider) -> StreamingChatClient?

    private var cancelled = false
    private var totalCostUsd: Double = 0
    private var totalTokensIn = 0
    private var totalTokensOut = 0
    private var completedRuns = 0
    private var failedRuns = 0

    init(
        db: DatabaseManager = .shared,
        clientForProvider: @escaping @Sendable (ModelProvider) -> StreamingChatClient? = CloudClientFactory.client(for:)
    ) {
        self.db = db
        self.clientForProvider = clientForProvider
    }

    // MARK: - Public API

    func cancel() { cancelled = true }

    /// Execute a batch of tasks grouped by round. Rounds are executed
    /// sequentially; within a round all tasks run in parallel via
    /// `withThrowingTaskGroup`. Cost guardrails are checked between rounds.
    func run(
        tasksByRound: [Int: [OrchestratorTask]],
        guardrails: CostGuardrails
    ) -> AsyncStream<OrchestratorEvent> {

        AsyncStream { continuation in
            Task { [tasksByRound, guardrails] in
                let orderedRounds = tasksByRound.keys.sorted()
                for round in orderedRounds {
                    if await self.cancelled {
                        await self.emitCancel(continuation: continuation)
                        continuation.finish()
                        return
                    }
                    let tasks = tasksByRound[round] ?? []
                    let (completed, failed) = await self.runRound(
                        round: round,
                        tasks: tasks,
                        continuation: continuation
                    )
                    continuation.yield(.roundCompleted(round: round, completed: completed, failed: failed))

                    // Cost guardrail check after round completes.
                    let cost = await self.totalCostUsd
                    let previousCost = cost - (await self.lastRoundCost)
                    switch guardrails.evaluate(previousTotal: previousCost, newTotal: cost) {
                    case .softWarnCrossed:
                        continuation.yield(.costSoftWarn(total: cost))
                    case .hardPauseCrossed:
                        continuation.yield(.costHardPause(total: cost))
                    case .ok:
                        break
                    }
                }
                if await self.cancelled {
                    await self.emitCancel(continuation: continuation)
                } else {
                    let (c, f, total) = await self.summary()
                    continuation.yield(.finished(completedRuns: c, failedRuns: f, totalCost: total))
                }
                continuation.finish()
            }
        }
    }

    /// Run the full 3-round debate for a decision. Round 1 is the provided
    /// `round1Tasks`. Rounds 2 and 3 are constructed dynamically via
    /// `DebateEngine` using the prior round's completed `ModelRun`s.
    func runDebate(
        decisionId: String,
        participants: [DebateEngine.Participant],
        samples: Int,
        round1Tasks: [OrchestratorTask],
        brief: String,
        lensLabel: String,
        guardrails: CostGuardrails
    ) -> AsyncStream<OrchestratorEvent> {

        AsyncStream { continuation in
            Task { [participants, round1Tasks] in

                var lastRoundCompletedRuns: [ModelRun] = []
                var round1Runs: [ModelRun] = []
                var round2Runs: [ModelRun] = []

                // Drive each round in turn. Between rounds, build the next
                // round's tasks from the just-completed ModelRuns.
                for round in 1...3 {
                    if await self.cancelled {
                        await self.emitCancel(continuation: continuation)
                        continuation.finish()
                        return
                    }
                    let tasks: [OrchestratorTask]
                    switch round {
                    case 1: tasks = round1Tasks
                    case 2:
                        round1Runs = lastRoundCompletedRuns
                        tasks = DebateEngine.buildRound2Tasks(
                            decisionId: decisionId,
                            participants: participants,
                            samples: samples,
                            round1Runs: round1Runs,
                            brief: brief,
                            lensLabel: lensLabel
                        )
                    default:
                        round2Runs = lastRoundCompletedRuns
                        tasks = DebateEngine.buildRound3Tasks(
                            decisionId: decisionId,
                            participants: participants,
                            samples: samples,
                            round1Runs: round1Runs,
                            round2Runs: round2Runs,
                            brief: brief,
                            lensLabel: lensLabel
                        )
                    }

                    let captured = CaptureBox()
                    let (completed, failed) = await self.runRound(
                        round: round,
                        tasks: tasks,
                        continuation: continuation,
                        capture: captured
                    )
                    lastRoundCompletedRuns = await captured.runs
                    continuation.yield(.roundCompleted(round: round, completed: completed, failed: failed))

                    let cost = await self.totalCostUsd
                    let previousCost = cost - (await self.lastRoundCost)
                    switch guardrails.evaluate(previousTotal: previousCost, newTotal: cost) {
                    case .softWarnCrossed:  continuation.yield(.costSoftWarn(total: cost))
                    case .hardPauseCrossed: continuation.yield(.costHardPause(total: cost))
                    case .ok:               break
                    }
                }

                if await self.cancelled {
                    await self.emitCancel(continuation: continuation)
                } else {
                    let (c, f, total) = await self.summary()
                    continuation.yield(.finished(completedRuns: c, failedRuns: f, totalCost: total))
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Internal

    private var lastRoundCost: Double = 0

    private func emitCancel(continuation: AsyncStream<OrchestratorEvent>.Continuation) {
        continuation.yield(.cancelled(completedRuns: completedRuns, failedRuns: failedRuns))
    }

    private func summary() -> (Int, Int, Double) {
        (completedRuns, failedRuns, totalCostUsd)
    }

    private func recordRun(_ run: ModelRun, costDelta: Double) {
        totalCostUsd += costDelta
        totalTokensIn += run.tokensIn ?? 0
        totalTokensOut += run.tokensOut ?? 0
        completedRuns += 1
        lastRoundCost += costDelta
    }

    private func recordFailure() {
        failedRuns += 1
    }

    private func resetRoundCost() { lastRoundCost = 0 }

    private func runRound(
        round: Int,
        tasks: [OrchestratorTask],
        continuation: AsyncStream<OrchestratorEvent>.Continuation,
        capture: CaptureBox? = nil
    ) async -> (Int, Int) {
        resetRoundCost()
        var completed = 0
        var failed = 0

        await withTaskGroup(of: Result<ModelRun, TaskFailure>.self) { group in
            for task in tasks {
                if cancelled { break }
                let db = self.db
                let clientProvider = self.clientForProvider
                group.addTask { [task] in
                    continuation.yield(.runStarted(
                        taskId: task.id,
                        round: task.round,
                        model: task.model.id,
                        persona: task.persona.id
                    ))
                    do {
                        let run = try await Self.execute(task: task, db: db, clientProvider: clientProvider)
                        return .success(run)
                    } catch {
                        return .failure(TaskFailure(task: task, error: error))
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let run):
                    let delta = run.costUsd ?? 0
                    recordRun(run, costDelta: delta)
                    if let capture { await capture.add(run) }
                    continuation.yield(.runCompleted(run: run))
                    completed += 1
                case .failure(let fail):
                    recordFailure()
                    continuation.yield(.runFailed(
                        taskId: fail.task.id,
                        round: fail.task.round,
                        model: fail.task.model.id,
                        persona: fail.task.persona.id,
                        error: Self.describe(fail.error)
                    ))
                    failed += 1
                }
            }
        }
        return (completed, failed)
    }

    // MARK: - Per-task execution

    private struct TaskFailure: Error {
        let task: OrchestratorTask
        let error: Error
    }

    /// Minimal actor used by `runDebate` to collect each round's completed
    /// `ModelRun`s so the next round can be constructed.
    actor CaptureBox {
        private(set) var runs: [ModelRun] = []
        func add(_ run: ModelRun) { runs.append(run) }
    }

    private static func execute(
        task: OrchestratorTask,
        db: DatabaseManager,
        clientProvider: @Sendable (ModelProvider) -> StreamingChatClient?
    ) async throws -> ModelRun {
        guard let client = clientProvider(task.model.provider) else {
            throw OrchestratorError.noClientForProvider(task.model.provider)
        }
        let messages: [ChatMessage] = [
            ChatMessage(role: "system", content: task.systemPrompt),
            ChatMessage(role: "user",   content: task.userPrompt)
        ]

        var assembled = ""
        let stream = client.streamChat(
            messages: messages,
            model: task.model.id,
            temperature: task.temperature
        )
        for try await token in stream {
            assembled += token
        }
        if assembled.isEmpty {
            throw OrchestratorError.noClientForProvider(task.model.provider)
        }

        // Token count approximation: ~4 chars per token.
        let tokensIn  = (task.systemPrompt.count + task.userPrompt.count) / 4
        let tokensOut = assembled.count / 4
        let cost = task.model.estimatedCost(tokensIn: tokensIn, tokensOut: tokensOut)

        // Round 3 declares POSITION: maintained|updated per SPEC §6.4.
        let positionChanged: Bool? = (task.round == 3)
            ? DebateEngine.parsePosition(in: assembled)
            : nil

        let run = ModelRun(
            id: task.id.uuidString,
            decisionId: task.decisionId,
            modelName: task.model.id,
            provider: task.model.provider,
            persona: task.persona.id,
            roundNumber: task.round,
            sampleNumber: task.sample,
            temperature: task.temperature,
            prompt: task.userPrompt,
            response: assembled,
            tokensIn: tokensIn,
            tokensOut: tokensOut,
            costUsd: cost,
            createdAt: Date(),
            error: nil,
            positionChanged: positionChanged
        )
        try await db.write { db in try run.insert(db) }
        return run
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? OrchestratorError {
            return String(describing: e)
        }
        return String(describing: error)
    }
}
