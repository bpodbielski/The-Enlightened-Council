import SwiftUI
import GRDB
import Observation

// MARK: - Card row model

struct DecisionCard: Identifiable, Sendable {
    let decision: Decision
    let confidence: Int?

    var id: String { decision.id }
}

// MARK: - ViewModel

@Observable
@MainActor
final class AllDecisionsViewModel {

    private(set) var cards: [DecisionCard] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    private let db: DatabaseManager

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            cards = try await Self.fetchCards(db: db)
        } catch {
            errorMessage = "Failed to load decisions: \(error.localizedDescription)"
        }
    }

    /// Fetches decisions joined with their latest verdict (if any), sorted by created_at desc.
    static func fetchCards(db: DatabaseManager) async throws -> [DecisionCard] {
        try await db.read { db in
            let decisions = try Decision.fetchAll(
                db,
                sql: "SELECT * FROM decisions ORDER BY created_at DESC"
            )
            var result: [DecisionCard] = []
            for decision in decisions {
                let confidence = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT confidence FROM verdicts
                        WHERE decision_id = ?
                        ORDER BY created_at DESC LIMIT 1
                        """,
                    arguments: [decision.id]
                )
                result.append(DecisionCard(decision: decision, confidence: confidence))
            }
            return result
        }
    }
}

// MARK: - View

struct AllDecisionsView: View {

    @State private var viewModel = AllDecisionsViewModel()
    var onSelectDecision: ((Decision) -> Void)? = nil

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading decisions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.cards.isEmpty {
                emptyState
            } else {
                cardList
            }
        }
        .navigationTitle("All Decisions")
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No decisions yet. Start one with New Decision.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.cards) { card in
                    Button {
                        onSelectDecision?(card.decision)
                    } label: {
                        DecisionCardRow(card: card)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { } }
        )
    }
}

// MARK: - Card row

struct DecisionCardRow: View {
    let card: DecisionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(card.decision.question)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                statusChip
            }
            HStack(spacing: 12) {
                Label(formattedDate, systemImage: "calendar")
                Label(card.decision.lensTemplate, systemImage: "rectangle.3.group")
                if let confidence = card.confidence {
                    Label("\(confidence)% confidence", systemImage: "checkmark.seal")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))
    }

    private var statusChip: some View {
        Text(card.decision.status.rawValue.capitalized)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(statusColor.opacity(0.2))
            .foregroundStyle(statusColor)
            .cornerRadius(4)
    }

    private var statusColor: Color {
        switch card.decision.status {
        case .draft: return .gray
        case .refining: return .blue
        case .ready: return .indigo
        case .running: return .orange
        case .complete: return .green
        case .archived: return .secondary
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: card.decision.createdAt)
    }
}
