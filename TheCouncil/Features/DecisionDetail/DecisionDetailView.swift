import SwiftUI
import GRDB
import Observation

// MARK: - DecisionDetailViewModel

@Observable
@MainActor
final class DecisionDetailViewModel {

    let decision: Decision
    private(set) var verdict: Verdict?
    private(set) var outcome: Outcome?
    private(set) var modelRuns: [ModelRun] = []
    private(set) var arguments: [Argument] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    // Outcome marking input (Outcome tab)
    var notesDraft: String = ""
    var whatChangedDraft: String = ""

    private let db: DatabaseManager
    private let marker: OutcomeMarkingService

    init(
        decision: Decision,
        db: DatabaseManager = .shared,
        marker: OutcomeMarkingService = OutcomeMarkingService()
    ) {
        self.decision = decision
        self.db = db
        self.marker = marker
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let id = decision.id
        do {
            let result = try await db.read { db -> (Verdict?, Outcome?, [ModelRun], [Argument]) in
                let v = try Verdict.fetchOne(db,
                    sql: "SELECT * FROM verdicts WHERE decision_id = ? ORDER BY created_at DESC LIMIT 1",
                    arguments: [id])
                let o: Outcome?
                if let v {
                    o = try Outcome.fetchOne(db,
                        sql: "SELECT * FROM outcomes WHERE verdict_id = ? ORDER BY marked_at DESC LIMIT 1",
                        arguments: [v.id])
                } else {
                    o = nil
                }
                let runs = try ModelRun.fetchAll(db,
                    sql: "SELECT * FROM model_runs WHERE decision_id = ? ORDER BY round_number, sample_number",
                    arguments: [id])
                let args = try Argument.fetchAll(db,
                    sql: "SELECT * FROM arguments WHERE decision_id = ?",
                    arguments: [id])
                return (v, o, runs, args)
            }
            self.verdict = result.0
            self.outcome = result.1
            self.modelRuns = result.2
            self.arguments = result.3
        } catch {
            errorMessage = "Failed to load decision detail: \(error.localizedDescription)"
        }
    }

    // MARK: - Outcome marking (Outcome tab)

    func mark(result: OutcomeResult) async {
        guard let verdict else { return }
        do {
            _ = try await marker.mark(
                verdictId: verdict.id,
                result: result,
                actualNotes: notesDraft,
                whatChanged: whatChangedDraft
            )
            await load()
        } catch {
            errorMessage = "Mark failed: \(error.localizedDescription)"
        }
    }

    func dismiss() async {
        guard let verdict else { return }
        do {
            try await marker.dismiss(verdictId: verdict.id)
            await load()
        } catch {
            errorMessage = "Dismiss failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - DecisionDetailView

struct DecisionDetailView: View {

    @State var viewModel: DecisionDetailViewModel
    @State private var selectedTab: Tab = .brief
    @State private var exportSheetVisible = false
    @State private var exportSheetVM: ExportSheetViewModel?

    enum Tab: String, CaseIterable, Identifiable {
        case brief, council, map, verdict, outcome
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
        .navigationTitle(viewModel.decision.question)
        .toolbar {
            if selectedTab == .verdict, viewModel.verdict != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await openExportSheet() }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $exportSheetVisible) {
            if let vm = exportSheetVM {
                ExportSheet(viewModel: vm, onClose: { exportSheetVisible = false })
            }
        }
        .task { await viewModel.load() }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func openExportSheet() async {
        let dest = await ExportEngine().defaultExportDirectory()
        exportSheetVM = ExportSheetViewModel(decision: viewModel.decision, destination: dest)
        exportSheetVisible = true
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            ForEach(Tab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .brief:   briefTab
        case .council: councilTab
        case .map:     mapTab
        case .verdict: verdictTab
        case .outcome: outcomeTab
        }
    }

    // MARK: - Brief

    private var briefTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Question", body: viewModel.decision.question)
                section("Lens template", body: viewModel.decision.lensTemplate)
                section("Reversibility", body: viewModel.decision.reversibility.rawValue)
                section("Time horizon", body: viewModel.decision.timeHorizon.rawValue)
                section("Sensitivity", body: viewModel.decision.sensitivityClass.rawValue)
                section("Success criteria", body: viewModel.decision.successCriteria)
                if let brief = viewModel.decision.refinedBrief, !brief.isEmpty {
                    section("Refined brief", body: brief)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Council (transcript)

    private var councilTab: some View {
        Group {
            if viewModel.modelRuns.isEmpty {
                Text("No model runs recorded for this decision.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.modelRuns, id: \.id) { run in
                            CouncilRunCard(run: run)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Map (placeholder — full graph rebuild deferred)

    private var mapTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.grid.hex")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Synthesis Map")
                .font(.headline)
            Text("\(viewModel.arguments.count) arguments captured for this decision.")
                .foregroundStyle(.secondary)
            Text("Open the map from the live Synthesis Map flow to interact. A read-only Map tab here is a future polish item (SPEC §7.9).")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Verdict (read-only)

    private var verdictTab: some View {
        Group {
            if let v = viewModel.verdict {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        verdictHeader(v)
                        section("Verdict", body: v.verdictText)
                        argList(title: "Key arguments FOR",
                                items: VerdictCaptureViewModel.decodeArgumentTexts(v.keyForJson),
                                color: .green)
                        argList(title: "Key arguments AGAINST",
                                items: VerdictCaptureViewModel.decodeArgumentTexts(v.keyAgainstJson),
                                color: .red)
                        if !v.risk.isEmpty       { section("Risk",        body: v.risk) }
                        if !v.blindSpot.isEmpty  { section("Blind spot",  body: v.blindSpot) }
                        if !v.opportunity.isEmpty { section("Opportunity", body: v.opportunity) }
                        if !v.preMortem.isEmpty  { section("Pre-mortem",  body: v.preMortem) }
                        section("Outcome deadline", body: dateString(v.outcomeDeadline))
                        if !v.testAction.isEmpty || !v.testMetric.isEmpty || !v.testThreshold.isEmpty {
                            section("Outcome test",
                                    body: "Action: \(v.testAction)\nMetric: \(v.testMetric)\nThreshold: \(v.testThreshold)")
                        }
                    }
                    .padding(20)
                }
            } else {
                Text("No verdict captured yet for this decision.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func verdictHeader(_ v: Verdict) -> some View {
        HStack(spacing: 12) {
            Label("\(v.confidence)% confidence", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.blue)
            statusChip(v.outcomeStatus)
            Spacer()
            Text("Captured \(dateString(v.createdAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func statusChip(_ status: OutcomeStatus) -> some View {
        let color: Color = {
            switch status {
            case .pending:   return .gray
            case .right:     return .green
            case .partial:   return .yellow
            case .wrong:     return .red
            case .dismissed: return .secondary
            }
        }()
        return Text(status.rawValue.capitalized)
            .font(.caption)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .cornerRadius(4)
    }

    // MARK: - Outcome

    private var outcomeTab: some View {
        Group {
            if let v = viewModel.verdict {
                if v.outcomeStatus == .pending {
                    outcomeMarkingForm(verdict: v)
                } else {
                    outcomeRecord(verdict: v, outcome: viewModel.outcome)
                }
            } else {
                Text("No verdict yet — outcome marking is unavailable.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func outcomeMarkingForm(verdict: Verdict) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Mark outcome")
                    .font(.title3.bold())
                Text("Verdict: \(verdict.verdictText)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                TextField("What actually happened?", text: $viewModel.notesDraft, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                TextField("What changed since the verdict? (optional)", text: $viewModel.whatChangedDraft, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Button("Right")   { Task { await viewModel.mark(result: .right) } }
                        .tint(.green)
                    Button("Partial") { Task { await viewModel.mark(result: .partial) } }
                        .tint(.yellow)
                    Button("Wrong")   { Task { await viewModel.mark(result: .wrong) } }
                        .tint(.red)
                    Spacer()
                    Button("Dismiss", role: .destructive) { Task { await viewModel.dismiss() } }
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
    }

    private func outcomeRecord(verdict: Verdict, outcome: Outcome?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Outcome").font(.title3.bold())
                    Spacer()
                    statusChip(verdict.outcomeStatus)
                }
                if let outcome {
                    section("Result",       body: outcome.result.rawValue.capitalized)
                    section("Marked",       body: dateString(outcome.markedAt))
                    if !outcome.actualNotes.isEmpty {
                        section("What happened", body: outcome.actualNotes)
                    }
                    if !outcome.whatChanged.isEmpty {
                        section("What changed",  body: outcome.whatChanged)
                    }
                } else {
                    Text("Verdict was dismissed; no outcome row recorded.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Helpers

    private func section(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Text(body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.windowBackgroundColor).opacity(0.5))
                .cornerRadius(6)
        }
    }

    private func argList(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            if items.isEmpty {
                Text("(none)").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(color).frame(width: 5, height: 5).padding(.top, 6)
                        Text(item).font(.callout)
                    }
                }
            }
        }
    }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in }
        )
    }
}

// MARK: - CouncilRunCard

struct CouncilRunCard: View {
    let run: ModelRun

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.modelName).monospaced().font(.caption)
                Text("·").foregroundStyle(.tertiary)
                Text(run.persona).font(.caption).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text("Round \(run.roundNumber) · sample \(run.sampleNumber)")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let changed = run.positionChanged, run.roundNumber == 3 {
                    Label(changed ? "Updated" : "Maintained",
                          systemImage: changed ? "arrow.triangle.2.circlepath" : "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(changed ? .orange : .secondary)
                }
            }
            if let response = run.response, !response.isEmpty {
                Text(response)
                    .font(.callout)
                    .lineLimit(8)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.windowBackgroundColor).opacity(0.4))
                    .cornerRadius(6)
            }
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))
    }
}
