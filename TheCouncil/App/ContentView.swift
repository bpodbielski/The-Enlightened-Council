import SwiftUI

// MARK: - Sidebar Item

enum SidebarItem: String, CaseIterable, Identifiable {
    case newDecision = "New Decision"
    case thisWeek = "This Week"
    case allDecisions = "All Decisions"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .newDecision: return "plus.circle"
        case .thisWeek: return "calendar"
        case .allDecisions: return "list.bullet"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - NavigationDestination

enum NavigationDestination {
    case sidebarItem(SidebarItem)
    case refinement(Decision)
    case configuration(Decision)
    case execution(Decision, tasksByRound: [Int: [OrchestratorTask]], guardrails: CostGuardrails)
    case synthesisMap(Decision, GraphViewModel)
    case verdictCapture(Decision, GraphViewModel)

    var navigationKey: String {
        switch self {
        case .sidebarItem(let item): return "sidebar:\(item.rawValue)"
        case .refinement(let d):     return "refinement:\(d.id)"
        case .configuration(let d):  return "configuration:\(d.id)"
        case .execution(let d, _, _): return "execution:\(d.id)"
        case .synthesisMap(let d, _): return "synthesisMap:\(d.id)"
        case .verdictCapture(let d, _): return "verdictCapture:\(d.id)"
        }
    }
}

// MARK: - ContentViewModel

@Observable
@MainActor
final class ContentViewModel {
    var selectedItem: SidebarItem? = .allDecisions
    var destination: NavigationDestination = .sidebarItem(.allDecisions)
    var airGapActive: Bool = false

    func refreshAirGapIndicator() {
        airGapActive = AirGapURLProtocol.active
    }

    func navigate(to item: SidebarItem) {
        selectedItem = item
        destination = .sidebarItem(item)
    }

    func navigateToRefinement(decision: Decision) {
        destination = .refinement(decision)
    }

    func navigateToConfiguration(decision: Decision) {
        destination = .configuration(decision)
    }

    func navigateToExecution(
        decision: Decision,
        tasksByRound: [Int: [OrchestratorTask]],
        guardrails: CostGuardrails
    ) {
        destination = .execution(decision, tasksByRound: tasksByRound, guardrails: guardrails)
    }

    func navigateToSynthesisMap(decision: Decision, graphViewModel: GraphViewModel) {
        destination = .synthesisMap(decision, graphViewModel)
    }

    func navigateToVerdictCapture(decision: Decision, graphViewModel: GraphViewModel) {
        destination = .verdictCapture(decision, graphViewModel)
    }
}

// MARK: - ContentView

struct ContentView: View {

    @State private var viewModel = ContentViewModel()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $viewModel.selectedItem) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.systemImage)
                }
            }
            .navigationTitle("The Council")
            .onChange(of: viewModel.selectedItem) { _, newValue in
                if let item = newValue {
                    viewModel.navigate(to: item)
                }
            }
        } detail: {
            detailView(for: viewModel.destination)
                .toolbar {
                    if viewModel.airGapActive {
                        ToolbarItem(placement: .principal) {
                            Label("Air Gap Active", systemImage: "wifi.slash")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.25))
                                .cornerRadius(4)
                                .help("Cloud AI provider hosts are blocked. Local models only.")
                        }
                    }
                }
        }
        .task {
            viewModel.refreshAirGapIndicator()
        }
        .onChange(of: viewModel.destination.navigationKey) { _, _ in
            viewModel.refreshAirGapIndicator()
        }
    }

    @ViewBuilder
    private func detailView(for destination: NavigationDestination) -> some View {
        switch destination {
        case .sidebarItem(let item):
            sidebarDetailView(for: item)
        case .refinement(let decision):
            RefinementView(
                viewModel: RefinementViewModel(decision: decision),
                onSignOff: { decision in
                    viewModel.navigateToConfiguration(decision: decision)
                }
            )
        case .configuration(let decision):
            CouncilConfigurationView(
                viewModel: CouncilConfigurationViewModel(decision: decision),
                onRun: { tasks in
                    Task {
                        if decision.sensitivityClass == .confidential {
                            _ = try? await DatabaseManager.shared.write { db in
                                try db.execute(
                                    sql: "INSERT INTO settings(key, value) VALUES('air_gap_enabled','true') ON CONFLICT(key) DO UPDATE SET value='true'"
                                )
                            }
                            await AirGapNetworkGuard.refresh(from: .shared)
                        }
                        let guardrails = (try? await CostGuardrails.load(from: .shared)) ?? .defaults
                        await MainActor.run {
                            viewModel.refreshAirGapIndicator()
                            viewModel.navigateToExecution(
                                decision: decision,
                                tasksByRound: tasks,
                                guardrails: guardrails
                            )
                        }
                    }
                }
            )
        case .execution(let decision, let tasks, let guardrails):
            ExecutionView(
                viewModel: ExecutionViewModel(),
                tasksByRound: tasks,
                guardrails: guardrails,
                onComplete: {
                    viewModel.navigate(to: .allDecisions)
                },
                onSynthesisReady: { graphVM in
                    viewModel.navigateToSynthesisMap(decision: decision, graphViewModel: graphVM)
                }
            )
        case .synthesisMap(let decision, let graphVM):
            if graphVM.useColumnView {
                ColumnFallbackView(arguments: [])
            } else {
                GraphView(viewModel: graphVM, onCaptureVerdict: {
                    viewModel.navigateToVerdictCapture(decision: decision, graphViewModel: graphVM)
                })
            }
        case .verdictCapture(let decision, let graphVM):
            VerdictCaptureView(
                viewModel: VerdictCaptureViewModel(
                    decision: decision,
                    trayItems: graphVM.trayItems,
                    graphViewModel: graphVM
                ),
                onSave: { viewModel.navigate(to: .allDecisions) },
                onCancel: { viewModel.navigateToSynthesisMap(decision: decision, graphViewModel: graphVM) }
            )
        }
    }

    @ViewBuilder
    private func sidebarDetailView(for item: SidebarItem) -> some View {
        switch item {
        case .newDecision:
            IntakeView(onDecisionCreated: { decision in
                viewModel.navigateToRefinement(decision: decision)
            })
        case .thisWeek:
            ThisWeekView()
        case .allDecisions:
            AllDecisionsView()
        case .settings:
            SettingsView()
        }
    }
}
