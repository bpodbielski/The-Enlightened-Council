import SwiftUI

// MARK: - VerdictCaptureView
// Single-column form per SPEC §6.8 / §7.8.

struct VerdictCaptureView: View {

    @Bindable var viewModel: VerdictCaptureViewModel
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                questionSection
                Divider()
                keyArgumentsSection
                Divider()
                analysisSection
                Divider()
                verdictSection
                Divider()
                confidenceSection
                Divider()
                deadlineSection
                Divider()
                testSection
                Divider()
                footer
            }
            .padding(20)
            .frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .navigationTitle("Capture Verdict")
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $viewModel.showPreMortemSheet) {
            preMortemSheet
        }
        .onChange(of: viewModel.didSave) { _, saved in
            if saved { onSave() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Capture Verdict")
                    .font(.title)
                    .bold()
                Text(viewModel.decision.lensTemplate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Question (read-only)

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Question").font(.headline)
            Text(viewModel.decision.question)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.windowBackgroundColor).opacity(0.5))
                .cornerRadius(6)
        }
    }

    // MARK: - Key arguments (auto-populated)

    private var keyArgumentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("From council", systemImage: "tray.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            argumentList(title: "Key arguments FOR",
                         items: viewModel.keyForArguments,
                         positionColor: .green)

            argumentList(title: "Key arguments AGAINST",
                         items: viewModel.keyAgainstArguments,
                         positionColor: .red)
        }
    }

    private func argumentList(title: String, items: [TrayItem], positionColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text("None pinned in tray.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(positionColor)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(item.text)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - Analysis fields

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelledField(title: "Risk", text: $viewModel.risk, prompt: "Single biggest thing that goes wrong if we're right and act on this.")
            labelledField(title: "Blind Spot", text: $viewModel.blindSpot, prompt: "What might the council have missed?")
            labelledField(title: "Opportunity", text: $viewModel.opportunity, prompt: "Upside if this goes well.")
        }
    }

    // MARK: - Verdict

    private var verdictSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Verdict")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.draftVerdict() }
                } label: {
                    if viewModel.isDrafting {
                        ProgressView().scaleEffect(0.6).controlSize(.small)
                    } else {
                        Label("Draft with Claude", systemImage: "sparkles")
                    }
                }
                .disabled(viewModel.isDrafting || viewModel.isSaving)
                .help("Draft a 2–4 sentence recommendation using the brief and tray arguments.")
            }
            TextEditor(text: $viewModel.verdictText)
                .font(.body)
                .frame(minHeight: 120)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    // MARK: - Confidence

    private var confidenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Confidence").font(.headline)
                Spacer()
                Text("\(viewModel.confidence)%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: confidenceBinding, in: 0...100, step: 1)
        }
    }

    private var confidenceBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.confidence) },
            set: { viewModel.confidence = Int($0.rounded()) }
        )
    }

    // MARK: - Deadline

    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Outcome Deadline").font(.headline)
            DatePicker(
                "",
                selection: $viewModel.outcomeDeadline,
                displayedComponents: [.date]
            )
            .labelsHidden()
        }
    }

    // MARK: - Test

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Outcome Test").font(.headline)
            labelledField(title: "Test action", text: $viewModel.testAction,
                          prompt: "What will you do to check if this verdict was right?")
            labelledField(title: "Test metric", text: $viewModel.testMetric,
                          prompt: "What you'll measure.")
            labelledField(title: "Test threshold", text: $viewModel.testThreshold,
                          prompt: "Numeric threshold for success.")
        }
    }

    // MARK: - Footer (Save/Cancel)

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) { onCancel() }
                .disabled(viewModel.isSaving || viewModel.isGeneratingPreMortem)
            Spacer()
            Button {
                Task { await viewModel.generatePreMortem() }
            } label: {
                if viewModel.isGeneratingPreMortem {
                    ProgressView().scaleEffect(0.6).controlSize(.small)
                } else {
                    Text("Save Verdict")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(saveDisabled)
        }
    }

    private var saveDisabled: Bool {
        viewModel.isSaving ||
        viewModel.isGeneratingPreMortem ||
        viewModel.verdictText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Pre-mortem sheet

    private var preMortemSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pre-mortem", systemImage: "exclamationmark.triangle")
                    .font(.title3.bold())
                Spacer()
            }
            Text("Imagine this verdict proved wrong. Edit the failure modes Claude generated, or add your own.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $viewModel.preMortem)
                .font(.body)
                .frame(minHeight: 220)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Button("Back") { viewModel.showPreMortemSheet = false }
                Spacer()
                Button {
                    Task {
                        viewModel.showPreMortemSheet = false
                        await viewModel.save()
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView().scaleEffect(0.6).controlSize(.small)
                    } else {
                        Text("Confirm Save")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSaving)
            }
        }
        .padding(20)
        .frame(width: 540, height: 460)
    }

    // MARK: - Helpers

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func labelledField(title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).bold()
            TextField(prompt, text: text, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
    }
}
