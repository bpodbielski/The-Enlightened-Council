import SwiftUI

// MARK: - LensTemplate display mapping

private let lensTemplateDisplayNames: [(id: String, label: String)] = [
    ("strategic-bet", "Strategic Bet"),
    ("make-buy-partner", "Make / Buy / Partner"),
    ("market-entry", "Market Entry"),
    ("pivot-scale-kill", "Pivot, Scale, or Kill"),
    ("innovation-portfolio", "Innovation Portfolio"),
    ("vendor-technology", "Vendor / Technology"),
    ("org-design", "Org Design"),
    ("pilot-to-scale", "Pilot to Scale")
]

// MARK: - IntakeView

struct IntakeView: View {
    @State private var viewModel = IntakeViewModel()
    var onDecisionCreated: (Decision) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Question
                questionField

                // 2. Decision type
                decisionTypePicker

                // 3. Reversibility
                reversibilityPicker

                // 4. Time horizon
                timeHorizonPicker

                // 5. Sensitivity
                sensitivityPicker

                // 6. Success criteria
                successCriteriaField

                // 7. Context attachments
                attachmentSection

                // Submit button
                submitButton
            }
            .padding(24)
        }
        .navigationTitle("New Decision")
        .alert("Submission Error", isPresented: Binding(
            get: { viewModel.submissionError != nil },
            set: { if !$0 { viewModel.submissionError = nil } }
        )) {
            Button("OK") { viewModel.submissionError = nil }
        } message: {
            Text(viewModel.submissionError ?? "")
        }
    }

    // MARK: - Field views

    private var questionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Decision Question")
                .font(.headline)
            TextEditor(text: $viewModel.question)
                .frame(minHeight: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            if let error = viewModel.questionValidationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var decisionTypePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Decision Type")
                .font(.headline)
            Picker("Decision Type", selection: $viewModel.lensTemplate) {
                ForEach(lensTemplateDisplayNames, id: \.id) { item in
                    Text(item.label).tag(item.id)
                }
            }
            .labelsHidden()
        }
    }

    private var reversibilityPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reversibility")
                .font(.headline)
            Picker("Reversibility", selection: $viewModel.reversibility) {
                Text("Reversible").tag("reversible")
                Text("Semi-reversible").tag("semi-reversible")
                Text("Irreversible").tag("irreversible")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var timeHorizonPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Time Horizon")
                .font(.headline)
            Picker("Time Horizon", selection: $viewModel.timeHorizon) {
                Text("Weeks").tag("weeks")
                Text("Months").tag("months")
                Text("Quarters").tag("quarters")
                Text("Years").tag("years")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var sensitivityPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sensitivity")
                .font(.headline)
            Picker("Sensitivity", selection: $viewModel.sensitivityClass) {
                Text("Public").tag("public")
                Text("Sensitive").tag("sensitive")
                Text("Confidential").tag("confidential")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if viewModel.sensitivityClass == "confidential" {
                Label("Air gap mode will be enforced.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var successCriteriaField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Success Criteria")
                .font(.headline)
            TextEditor(text: $viewModel.successCriteria)
                .frame(minHeight: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            if let error = viewModel.successCriteriaValidationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Context")
                .font(.headline)
            AttachmentView(
                attachmentURLs: $viewModel.attachmentURLs,
                pastedTexts: $viewModel.attachmentTexts
            )
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                do {
                    let decision = try await viewModel.submit(db: DatabaseManager.shared)
                    onDecisionCreated(decision)
                } catch {
                    viewModel.submissionError = error.localizedDescription
                }
            }
        } label: {
            HStack {
                if viewModel.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("Refine with Claude")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.isValid || viewModel.isSubmitting)
        .padding(.top, 8)
    }
}
