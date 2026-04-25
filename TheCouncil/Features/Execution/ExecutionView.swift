import SwiftUI

struct ExecutionView: View {

    @State var viewModel: ExecutionViewModel
    let tasksByRound: [Int: [OrchestratorTask]]
    let guardrails: CostGuardrails
    /// Called when execution completes without synthesis data (cancelled or extraction failed)
    let onComplete: () -> Void
    /// Called when extraction + clustering succeed; provides GraphViewModel for synthesis map
    let onSynthesisReady: (GraphViewModel) -> Void

    @State private var started = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ThermalBanner()
            header
            Divider()
            timelineList
            Divider()
            footer
        }
        .padding(16)
        .onAppear {
            guard !started else { return }
            started = true
            viewModel.start(tasksByRound: tasksByRound, guardrails: guardrails)
        }
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            if viewModel.wasCancelled {
                onComplete()
            }
            // If debate path: wait for synthesisReady
        }
        .onChange(of: viewModel.synthesisReady) { _, ready in
            guard ready else { return }
            if let gvm = viewModel.graphViewModel {
                onSynthesisReady(gvm)
            } else {
                onComplete()
            }
        }
        .overlay {
            if viewModel.isExtracting {
                extractingOverlay
            }
        }
        .alert("Cost soft warning",
               isPresented: $viewModel.showSoftWarn) {
            Button("Continue", role: .cancel) { viewModel.showSoftWarn = false }
            Button("Cancel", role: .destructive) { viewModel.cancel() }
        } message: {
            Text(String(format: "Total cost has crossed $%.2f.", guardrails.softWarnUsd))
        }
        .alert("Cost hard pause",
               isPresented: $viewModel.showHardPause) {
            Button("Override and continue") { viewModel.showHardPause = false }
            Button("Stop and save partial results", role: .destructive) { viewModel.cancel() }
        } message: {
            Text(String(format: "Total cost has crossed $%.2f. Execution has paused between rounds.", guardrails.hardPauseUsd))
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Council Execution").font(.title2).bold()
                Text("\(viewModel.completedCount) completed · \(viewModel.failedCount) failed")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(viewModel.isCancelling ? "Cancelling…" : "Cancel") {
                viewModel.cancel()
            }
            .disabled(!viewModel.isRunning || viewModel.isCancelling)
        }
    }

    private var timelineList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(rowsGrouped, id: \.round) { group in
                    Text("Round \(group.round)").font(.headline).padding(.top, 8)
                    ForEach(group.rows) { row in
                        HStack {
                            Text(row.model).monospaced().frame(minWidth: 240, alignment: .leading)
                            Text(row.persona).foregroundStyle(.secondary).frame(minWidth: 160, alignment: .leading)
                            statusChip(row.status)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(String(format: "$%.2f spent · %@ tokens",
                        viewModel.totalCostUsd,
                        ExecutionView.formatTokens(viewModel.totalTokens)))
                .monospaced()
            Spacer()
            if viewModel.didFinish && viewModel.wasCancelled {
                Text("Cancelled — partial results saved").foregroundStyle(.orange)
            } else if viewModel.isExtracting {
                ProgressView().scaleEffect(0.7)
                Text("Extracting arguments…").foregroundStyle(.secondary)
            } else if viewModel.didFinish {
                Text("Complete").foregroundStyle(.green)
            }
        }
    }

    private var extractingOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
            VStack(spacing: 12) {
                ProgressView()
                Text("Extracting and clustering arguments…")
                    .font(.callout)
            }
            .padding(20)
            .background(.regularMaterial)
            .cornerRadius(12)
        }
        .ignoresSafeArea()
    }

    private func statusChip(_ status: RunStatus) -> some View {
        let (bg, fg): (Color, Color) = {
            switch status {
            case .waiting: return (.gray.opacity(0.2), .secondary)
            case .running: return (.blue.opacity(0.2), .blue)
            case .done:    return (.green.opacity(0.2), .green)
            case .failed:  return (.red.opacity(0.2), .red)
            }
        }()
        return Text(status.label)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(bg).foregroundStyle(fg)
            .cornerRadius(4)
    }

    private struct RowGroup { let round: Int; let rows: [RunRow] }

    private var rowsGrouped: [RowGroup] {
        let grouped = Dictionary(grouping: viewModel.rows, by: { $0.round })
        return grouped.keys.sorted().map { RowGroup(round: $0, rows: grouped[$0] ?? []) }
    }

    private static func formatTokens(_ n: Int) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - ThermalBanner

struct ThermalBanner: View {
    @State private var thermalState: ProcessInfo.ThermalState = .nominal
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if thermalState == .serious || thermalState == .critical {
                HStack(spacing: 8) {
                    Image(systemName: "thermometer.high")
                        .foregroundStyle(thermalState == .critical ? .red : .orange)
                    Text(thermalState == .critical
                         ? "Device critically hot — local inference paused."
                         : "Device running hot — local inference may slow.")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((thermalState == .critical ? Color.red : Color.orange).opacity(0.15))
                .cornerRadius(6)
            }
        }
        .onReceive(timer) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
        .onAppear {
            thermalState = ProcessInfo.processInfo.thermalState
        }
    }
}
