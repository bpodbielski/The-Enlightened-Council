import SwiftUI

// MARK: - VerdictTray
// Right-side drop zone. Drag-to-tray pins an argument as key evidence.
// SPEC §6.6 "drag-to-tray" interaction.

struct VerdictTray: View {

    @Bindable var viewModel: GraphViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if viewModel.trayItems.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .topLeading) {
            // Drop target indicator
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "tray.full")
                .foregroundStyle(.secondary)
            Text("Verdict Tray")
                .font(.headline)
            Spacer()
            Text("\(viewModel.trayItems.count)")
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .cornerRadius(4)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left.to.line")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Drag arguments here to pin them as key evidence")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.trayItems) { item in
                    TrayItemRow(item: item) {
                        viewModel.removeFromTray(itemId: item.id)
                    }
                }
            }
            .padding(10)
        }
    }
}

// MARK: - TrayItemRow

struct TrayItemRow: View {
    let item: TrayItem
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                positionBadge
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from tray")
            }
            Text(item.text)
                .font(.caption)
                .lineLimit(4)
                .foregroundStyle(.primary)
        }
        .padding(8)
        .background(Color(.windowBackgroundColor).opacity(0.6))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(positionColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var positionBadge: some View {
        Label(item.position.rawValue.capitalized, systemImage: positionIcon)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(positionColor.opacity(0.15))
            .foregroundStyle(positionColor)
            .cornerRadius(3)
    }

    private var positionIcon: String {
        switch item.position {
        case .for: return "hand.thumbsup.fill"
        case .against: return "hand.thumbsdown.fill"
        case .neutral: return "minus.circle.fill"
        }
    }

    private var positionColor: Color {
        switch item.position {
        case .for: return .green
        case .against: return .red
        case .neutral: return .secondary
        }
    }
}

// MARK: - Column fallback view

struct ColumnFallbackView: View {
    let arguments: [Argument]

    var body: some View {
        HStack(spacing: 0) {
            column(position: .for)
            Divider()
            column(position: .neutral)
            Divider()
            column(position: .against)
        }
    }

    private func column(position: ArgumentPosition) -> some View {
        let filtered = arguments.filter { $0.position == position }
        return VStack(alignment: .leading, spacing: 0) {
            Text(position.rawValue.capitalized)
                .font(.headline)
                .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filtered, id: \.id) { arg in
                        Text(arg.text)
                            .font(.caption)
                            .padding(8)
                            .background(.quaternary)
                            .cornerRadius(6)
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
