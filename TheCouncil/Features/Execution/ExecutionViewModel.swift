import Foundation
import Observation

enum RunStatus: Sendable, Equatable {
    case waiting
    case running
    case done
    case failed(String)

    var label: String {
        switch self {
        case .waiting: return "Waiting"
        case .running: return "Running"
        case .done:    return "Done"
        case .failed:  return "Failed"
        }
    }
}

struct RunRow: Sendable, Identifiable, Equatable {
    let id: UUID
    let round: Int
    let model: String
    let persona: String
    var status: RunStatus
}

@Observable
@MainActor
final class ExecutionViewModel {

    private(set) var rows: [RunRow] = []
    private(set) var totalCostUsd: Double = 0
    private(set) var totalTokens: Int = 0
    private(set) var completedCount: Int = 0
    private(set) var failedCount: Int = 0
    private(set) var isRunning: Bool = false
    private(set) var isCancelling: Bool = false
    private(set) var isExtracting: Bool = false

    var showSoftWarn: Bool = false
    var showHardPause: Bool = false
    var didFinish: Bool = false
    var wasCancelled: Bool = false

    // Set when extraction + clustering are complete → triggers synthesis navigation
    var synthesisReady: Bool = false
    private(set) var graphViewModel: GraphViewModel? = nil

    private let orchestrator: CouncilOrchestrator
    private var runTask: Task<Void, Never>?
    private var completedRuns: [ModelRun] = []
    private var decisionId: String = ""

    init(orchestrator: CouncilOrchestrator = CouncilOrchestrator()) {
        self.orchestrator = orchestrator
    }

    // MARK: - Start (single-round legacy path, used in tests)

    func start(tasksByRound: [Int: [OrchestratorTask]], guardrails: CostGuardrails) {
        if let firstTask = tasksByRound.values.first?.first {
            decisionId = firstTask.decisionId
        }
        populateRows(from: tasksByRound)
        isRunning = true
        runTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.orchestrator.run(tasksByRound: tasksByRound, guardrails: guardrails)
            for await event in stream { await self.handle(event) }
            self.isRunning = false
        }
    }

    // MARK: - Start debate (3-round path)

    func startDebate(
        decisionId: String,
        participants: [DebateEngine.Participant],
        samples: Int,
        round1Tasks: [OrchestratorTask],
        brief: String,
        lensLabel: String,
        guardrails: CostGuardrails
    ) {
        self.decisionId = decisionId
        populateRows(from: [1: round1Tasks])
        isRunning = true
        runTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.orchestrator.runDebate(
                decisionId: decisionId,
                participants: participants,
                samples: samples,
                round1Tasks: round1Tasks,
                brief: brief,
                lensLabel: lensLabel,
                guardrails: guardrails
            )
            for await event in stream {
                // Dynamically add rows for rounds 2+
                if case .runStarted(let taskId, let round, let model, let persona) = event, round > 1 {
                    if !self.rows.contains(where: { $0.id == taskId }) {
                        self.rows.append(RunRow(id: taskId, round: round, model: model, persona: persona, status: .running))
                    }
                }
                await self.handle(event)
            }
            self.isRunning = false
        }
    }

    func cancel() {
        guard !isCancelling else { return }
        isCancelling = true
        Task { await orchestrator.cancel() }
    }

    // MARK: - Event handling

    private func handle(_ event: OrchestratorEvent) {
        switch event {
        case .runStarted(let id, _, _, _):
            updateStatus(id: id) { $0 = .running }
        case .runCompleted(let run):
            guard let uuid = UUID(uuidString: run.id) else { break }
            updateStatus(id: uuid) { $0 = .done }
            totalCostUsd += run.costUsd ?? 0
            totalTokens += (run.tokensIn ?? 0) + (run.tokensOut ?? 0)
            completedCount += 1
            completedRuns.append(run)
        case .runFailed(let id, _, _, _, let err):
            updateStatus(id: id) { $0 = .failed(err) }
            failedCount += 1
        case .roundCompleted:
            break
        case .costSoftWarn:
            showSoftWarn = true
        case .costHardPause:
            showHardPause = true
        case .cancelled:
            wasCancelled = true
            didFinish = true
        case .finished:
            didFinish = true
            Task { await self.runPostProcessing() }
        }
    }

    private func updateStatus(id: UUID, _ mutate: (inout RunStatus) -> Void) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        mutate(&rows[idx].status)
    }

    // MARK: - Post-processing

    private func runPostProcessing() async {
        guard !decisionId.isEmpty else { synthesisReady = true; return }
        isExtracting = true
        defer { isExtracting = false }

        let round3Runs = completedRuns.filter { $0.roundNumber == 3 }
        let runsForExtraction = round3Runs.isEmpty ? completedRuns : round3Runs

        do {
            let arguments = try await ArgumentExtractor().extract(from: runsForExtraction, decisionId: decisionId)

            guard !arguments.isEmpty else {
                synthesisReady = true
                return
            }

            // Write arguments
            var savedArgs: [Argument] = []
            for arg in arguments {
                let a = arg
                try await DatabaseManager.shared.write { db in try a.save(db) }
                savedArgs.append(arg)
            }

            // Cluster with passthrough embedder (real embedders are Phase 5 polish)
            let clusteringResult = try await ClusteringEngine().cluster(
                arguments: savedArgs,
                embedder: PassthroughEmbedder()
            )

            // Write clusters (using Cluster's actual schema: position + centroidText)
            for summary in clusteringResult.clusters {
                // Derive dominant position in this cluster
                let memberIds = clusteringResult.assignments
                    .filter { $0.clusterIndex == summary.index }
                    .map(\.argumentId)
                let memberArgs = savedArgs.filter { memberIds.contains($0.id) }
                let dominant = dominantPosition(of: memberArgs)
                let cluster = Cluster(
                    id: UUID().uuidString,
                    decisionId: decisionId,
                    position: dominant,
                    centroidText: summary.representativeText
                )
                try await DatabaseManager.shared.write { db in try cluster.insert(db) }
            }

            let gvm = GraphViewModel()
            gvm.load(
                arguments: savedArgs,
                clusters: clusteringResult.clusters,
                assignments: clusteringResult.assignments,
                decisionId: decisionId
            )
            graphViewModel = gvm

        } catch {
            // Extraction failed — proceed without graph
        }

        synthesisReady = true
    }

    private func dominantPosition(of args: [Argument]) -> ArgumentPosition {
        var counts: [ArgumentPosition: Int] = [.for: 0, .against: 0, .neutral: 0]
        for a in args { counts[a.position, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? .neutral
    }

    // MARK: - Helpers

    private func populateRows(from tasksByRound: [Int: [OrchestratorTask]]) {
        rows = tasksByRound
            .sorted(by: { $0.key < $1.key })
            .flatMap { round, tasks in
                tasks.map { t in
                    RunRow(id: t.id, round: round, model: t.model.id, persona: t.persona.id, status: .waiting)
                }
            }
    }
}

// MARK: - Cluster memberwise init

extension Cluster {
    init(id: String, decisionId: String, position: ArgumentPosition, centroidText: String) {
        self.id = id
        self.decisionId = decisionId
        self.position = position
        self.centroidText = centroidText
    }
}

// MARK: - PassthroughEmbedder
// Returns deterministic pseudo-random unit vectors so ClusteringEngine can run
// without a network call. Real cloud/local embedders are Phase 5 polish.

private struct PassthroughEmbedder: Embedder {
    func embed(_ texts: [String]) async throws -> [[Float]] {
        let dim = 64
        return texts.map { text in
            var rng = SeededRNG(seed: UInt64(bitPattern: Int64(text.hashValue)))
            var v = (0 ..< dim).map { _ in Float(Double(rng.next() & 0xFFFF) / Double(0xFFFF)) - 0.5 }
            let norm = v.map { $0 * $0 }.reduce(0, +).squareRoot()
            if norm > 0 { v = v.map { $0 / norm } }
            return v
        }
    }
}
