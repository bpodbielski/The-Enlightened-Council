import SwiftUI
import Charts
import Observation

// MARK: - ViewModel

@Observable
@MainActor
final class CalibrationViewModel {

    private(set) var gate: CalibrationGate = .insufficient(marked: 0, threshold: CalibrationService.patternThreshold)
    private(set) var byLens: [CalibrationBucket] = []
    private(set) var byReversibility: [CalibrationBucket] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    private let service: CalibrationService

    init(service: CalibrationService = CalibrationService()) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            gate = try await service.gate()
            if gate.isReady {
                byLens = try await service.calibrationByLens()
                byReversibility = try await service.calibrationByReversibility()
            } else {
                byLens = []
                byReversibility = []
            }
        } catch {
            errorMessage = "Failed to load calibration patterns: \(error.localizedDescription)"
        }
    }
}

// MARK: - View

struct CalibrationPatternsView: View {

    @State private var viewModel = CalibrationViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            content
        }
        .padding(20)
        .task { await viewModel.load() }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Calibration Patterns", systemImage: "chart.bar.xaxis")
                .font(.title2.bold())
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewModel.gate {
            case .insufficient(let marked, let threshold):
                insufficientState(marked: marked, threshold: threshold)
            case .ready:
                readyState
            }
        }
    }

    private func insufficientState(marked: Int, threshold: Int) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Patterns appear after \(threshold) marked outcomes.")
                .font(.headline)
            Text("You have \(marked) so far.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                bucketSection(title: "By lens template", buckets: viewModel.byLens)
                bucketSection(title: "By reversibility", buckets: viewModel.byReversibility)
            }
        }
    }

    // MARK: - Bucket section

    @ViewBuilder
    private func bucketSection(title: String, buckets: [CalibrationBucket]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if buckets.isEmpty {
                Text("No data yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Right rate", bucket.rightRate),
                        y: .value("Bucket", bucket.label)
                    )
                    .foregroundStyle(.green)
                    .annotation(position: .trailing) {
                        Text("n=\(bucket.total)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXScale(domain: 0...1)
                .chartXAxis {
                    AxisMarks(format: Decimal.FormatStyle.Percent.percent)
                }
                .frame(height: max(80, CGFloat(buckets.count) * 32))
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in }
        )
    }
}
