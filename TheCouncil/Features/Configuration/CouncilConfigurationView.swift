import SwiftUI

struct CouncilConfigurationView: View {

    @State var viewModel: CouncilConfigurationViewModel
    let onRun: (_ tasksByRound: [Int: [OrchestratorTask]]) -> Void

    @State private var showQwen32BAlert: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let error = viewModel.loadError {
                    Text(error).foregroundStyle(.red)
                }

                modelPanel
                personasPanel
                roundsAndSamples
                costPanel

                Divider()

                HStack {
                    Spacer()
                    Button("Run Council") {
                        checkLocalMemoryThenRun()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canRun || viewModel.isLoading)
                }
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .navigationTitle("Council Configuration")
        .onAppear { viewModel.loadResources() }
        .alert("Insufficient Memory for Qwen 32B", isPresented: $showQwen32BAlert) {
            Button("Use Qwen 14B instead") {
                viewModel.substituteQwen14B()
                onRun(viewModel.buildTasks())
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Qwen 32B requires approximately 20 GB of free memory. Your system doesn't have enough free RAM. Would you like to use the Qwen 14B fallback instead?")
        }
    }

    // MARK: - Memory gate for local runs

    private func checkLocalMemoryThenRun() {
        let hasLocalQwen32B = viewModel.enabledModelIDs.contains("qwen-2.5-32b-instruct")
        if hasLocalQwen32B {
            let gate = LocalResourceGate().check(minFreeBytes: 20 * 1024 * 1024 * 1024)
            if case .insufficientMemory = gate {
                showQwen32BAlert = true
                return
            }
        }
        onRun(viewModel.buildTasks())
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.decision.question).font(.title2).bold()
            if let label = viewModel.lensTemplate?.label {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var modelPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Panel").font(.headline)
            WrapChips(items: viewModel.availableModels.map { $0.id }) { id in
                ChipToggle(
                    label: id,
                    isOn: viewModel.enabledModelIDs.contains(id)
                ) { viewModel.toggleModel(id) }
            }
        }
    }

    private var personasPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personas").font(.headline)
            if viewModel.availablePersonas.isEmpty {
                Text("Loading personas…").foregroundStyle(.secondary)
            } else {
                WrapChips(items: viewModel.availablePersonas.map { $0.id }) { id in
                    ChipToggle(
                        label: id,
                        isOn: viewModel.enabledPersonaIDs.contains(id)
                    ) { viewModel.togglePersona(id) }
                }
            }
        }
    }

    private var roundsAndSamples: some View {
        HStack(spacing: 40) {
            Stepper("Rounds: \(viewModel.rounds)", value: $viewModel.rounds, in: 1...5)
            Stepper("Samples: \(viewModel.samples)", value: $viewModel.samples, in: 1...5)
            Spacer()
        }
    }

    private var costPanel: some View {
        HStack {
            Text("Estimated cost:").foregroundStyle(.secondary)
            Text(String(format: "$%.2f", viewModel.estimatedCostUsd)).monospaced()
            Spacer()
        }
    }
}

// MARK: - Chip components

private struct ChipToggle: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

private struct WrapChips<Item: Hashable, ChipView: View>: View {
    let items: [Item]
    @ViewBuilder let chip: (Item) -> ChipView

    var body: some View {
        // macOS LazyVGrid with flexible columns approximates a wrap.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items, id: \.self) { chip($0) }
        }
    }
}
