import SwiftUI

// MARK: - RefinementView

struct RefinementView: View {
    @State var viewModel: RefinementViewModel
    var onSignOff: (Decision) -> Void

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 280)
            rightPane
                .frame(minWidth: 400)
        }
        .navigationTitle("Refine Decision")
        .task {
            await viewModel.startSession(client: AnthropicClient.shared, db: DatabaseManager.shared)
        }
    }

    // MARK: - Left pane (40%)

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.decision.question)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                sensitivityBadge
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Brief draft
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.currentBriefDraft.isEmpty {
                        Text("The refined brief will appear here once Claude generates it.")
                            .foregroundStyle(.tertiary)
                            .italic()
                            .padding()
                    } else {
                        Text(viewModel.currentBriefDraft)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding()
                    }

                    // Redaction suggestions
                    if !pendingSuggestions.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Redaction Suggestions")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(pendingSuggestions) { suggestion in
                                redactionRow(suggestion)
                            }
                        }
                        .padding(.bottom)
                    }
                }
            }

            Divider()

            // Sign-off button
            VStack(spacing: 8) {
                if let error = viewModel.signOffError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        do {
                            let decision = try await viewModel.signOff(db: DatabaseManager.shared)
                            onSignOff(decision)
                        } catch {
                            // signOffError is already set by viewModel
                        }
                    }
                } label: {
                    HStack {
                        if viewModel.isSavingSignOff {
                            ProgressView().controlSize(.small)
                        }
                        Text("Approve Brief and Continue \u{2192}")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isStreaming || viewModel.isSavingSignOff)
            }
            .padding()
        }
    }

    // MARK: - Right pane (60%)

    private var rightPane: some View {
        VStack(spacing: 0) {
            // Chat scroll area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(viewModel.chatMessages.enumerated()), id: \.offset) { index, message in
                            chatBubble(message: message, index: index)
                                .id(index)
                        }

                        if viewModel.isStreaming {
                            streamingIndicator
                                .id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.chatMessages.count) { _, _ in
                    if let last = viewModel.chatMessages.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
                .onChange(of: viewModel.isStreaming) { _, newValue in
                    if newValue {
                        withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Input area
            ChatInputView(isStreaming: viewModel.isStreaming) { text in
                Task {
                    await viewModel.sendMessage(text, client: AnthropicClient.shared, db: DatabaseManager.shared)
                }
            }
            .padding()
        }
    }

    // MARK: - Subviews

    private var sensitivityBadge: some View {
        let (label, color): (String, Color) = switch viewModel.decision.sensitivityClass {
        case .public: ("Public", .green)
        case .sensitive: ("Sensitive", .orange)
        case .confidential: ("Confidential", .red)
        }
        return Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var pendingSuggestions: [RedactionSuggestion] {
        viewModel.redactionSuggestions.filter { $0.state == .pending }
    }

    private func redactionRow(_ suggestion: RedactionSuggestion) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("[REDACTED: \(suggestion.reason)]")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
                Text("\"\(suggestion.originalText)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Approve") {
                viewModel.updateSuggestion(id: suggestion.id, state: .approved)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.green)

            Button("Dismiss") {
                viewModel.updateSuggestion(id: suggestion.id, state: .dismissed)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(.horizontal)
    }

    private func chatBubble(message: ChatMessage, index: Int) -> some View {
        let isUser = message.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 60) }
            Text(message.content.isEmpty && viewModel.isStreaming && index == viewModel.chatMessages.count - 1
                 ? "…"
                 : message.content)
                .padding(10)
                .background(isUser ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 60) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var streamingIndicator: some View {
        HStack {
            StreamingDotsView()
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 60)
        }
    }
}

// MARK: - StreamingDotsView

private struct StreamingDotsView: View {
    @State private var dotOpacities: [Double] = [0.3, 0.3, 0.3]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 6, height: 6)
                    .opacity(dotOpacities[i])
            }
        }
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.4)
                .repeatForever()
                .delay(Double(i) * 0.15)
            ) {
                dotOpacities[i] = 1.0
            }
        }
    }
}

// MARK: - ChatInputView

private struct ChatInputView: View {
    let isStreaming: Bool
    let onSend: (String) -> Void

    @State private var inputText = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $inputText)
                .frame(minHeight: 36, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .onSubmit {
                    sendIfPossible()
                }

            Button("Send") {
                sendIfPossible()
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func sendIfPossible() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        inputText = ""
        onSend(trimmed)
    }
}
