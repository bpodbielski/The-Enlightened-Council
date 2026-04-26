import SwiftUI

// MARK: - ThisWeekView
//
// Shows verdicts whose deadline is within 7 days, or already overdue.
// Per-row controls: Right / Partial / Wrong / Dismiss + optional notes + what-changed text fields.

struct ThisWeekView: View {

    @State private var viewModel = ThisWeekViewModel()
    @State private var calibrationVisible = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.verdicts.isEmpty {
                emptyState
            } else {
                rowList
            }
        }
        .navigationTitle("This Week")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    calibrationVisible = true
                } label: {
                    Label("Calibration", systemImage: "chart.bar.xaxis")
                }
                .help("Show calibration patterns across past outcomes")
            }
        }
        .sheet(isPresented: $calibrationVisible) {
            CalibrationPatternsView()
                .frame(minWidth: 560, minHeight: 480)
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Nothing due this week.")
                .foregroundStyle(.secondary)
            Text("Verdicts whose outcome deadline lands inside the next 7 days, or has already passed, show up here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Row list

    private var rowList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(viewModel.verdicts) { due in
                    DueVerdictRow(
                        due: due,
                        notes: bindingFor(\.notesDraft, due.id),
                        whatChanged: bindingFor(\.whatChangedDraft, due.id),
                        onMark: { result in
                            Task { await viewModel.mark(verdictId: due.id, result: result) }
                        },
                        onDismiss: {
                            Task { await viewModel.dismiss(verdictId: due.id) }
                        }
                    )
                }
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    private func bindingFor(_ keyPath: ReferenceWritableKeyPath<ThisWeekViewModel, [String: String]>, _ id: String) -> Binding<String> {
        Binding(
            get: { viewModel[keyPath: keyPath][id] ?? "" },
            set: { viewModel[keyPath: keyPath][id] = $0 }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in }
        )
    }
}

// MARK: - DueVerdictRow

struct DueVerdictRow: View {
    let due: DueVerdict
    @Binding var notes: String
    @Binding var whatChanged: String
    let onMark: (OutcomeResult) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(due.verdict.verdictText)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Label("\(due.verdict.confidence)%", systemImage: "checkmark.seal")
                Label(due.lensTemplate, systemImage: "rectangle.3.group")
                Spacer()
                deadlineLabel
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                TextField("What actually happened?", text: $notes, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                TextField("What changed since the verdict? (optional)", text: $whatChanged, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                resultButton(.right,   label: "Right",   color: .green)
                resultButton(.partial, label: "Partial", color: .yellow)
                resultButton(.wrong,   label: "Wrong",   color: .red)
                Spacer()
                Button("Dismiss", role: .destructive, action: onDismiss)
                    .buttonStyle(.bordered)
                    .help("Mark this verdict as no longer worth tracking")
            }
        }
        .padding(14)
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text(due.question)
                .font(.headline)
                .lineLimit(2)
            Spacer()
            if due.isOverdue {
                Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .cornerRadius(4)
            }
        }
    }

    private var deadlineLabel: some View {
        let days = due.daysUntilDeadline
        let text: String
        if due.isOverdue {
            let overdueBy = abs(days)
            text = overdueBy == 0 ? "Overdue today" : "Overdue \(overdueBy)d"
        } else if days == 0 {
            text = "Due today"
        } else {
            text = "Due in \(days)d"
        }
        return Text(text)
            .monospacedDigit()
    }

    private var borderColor: Color {
        due.isOverdue ? Color.red.opacity(0.3) : Color.secondary.opacity(0.15)
    }

    private func resultButton(_ result: OutcomeResult, label: String, color: Color) -> some View {
        Button {
            onMark(result)
        } label: {
            Text(label)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }
}
