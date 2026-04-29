import SwiftUI
import AppKit
import Observation

// MARK: - ExportSheetViewModel

@Observable
@MainActor
final class ExportSheetViewModel {

    let decision: Decision
    var format: ExportFormat = .both
    var destination: URL
    var isExporting: Bool = false
    var lastResult: ExportResult?
    var errorMessage: String?

    private let engine: ExportEngine

    init(decision: Decision, destination: URL, engine: ExportEngine = ExportEngine()) {
        self.decision = decision
        self.destination = destination
        self.engine = engine
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = destination
        panel.message = "Choose a folder for the exported files"
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
        }
    }

    func runExport() async {
        guard !isExporting else { return }
        isExporting = true
        errorMessage = nil
        lastResult = nil
        defer { isExporting = false }
        do {
            let result = try await engine.export(decision: decision, format: format, to: destination)
            lastResult = result
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - ExportSheet

struct ExportSheet: View {

    @State var viewModel: ExportSheetViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            formatPicker
            Divider()
            destinationRow
            if let result = viewModel.lastResult {
                resultBlock(result)
            }
            Spacer(minLength: 4)
            footer
        }
        .padding(20)
        .frame(width: 520, height: 360)
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Label("Export Verdict", systemImage: "square.and.arrow.up")
                .font(.title2.bold())
            Spacer()
        }
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Format").font(.headline)
            Picker("", selection: $viewModel.format) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.label).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Destination").font(.headline)
            HStack {
                Text(viewModel.destination.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.windowBackgroundColor).opacity(0.6))
                    .cornerRadius(6)
                Button("Choose…") { viewModel.chooseDestination() }
            }
        }
    }

    private func resultBlock(_ result: ExportResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Exported \(result.writtenPaths.count) file\(result.writtenPaths.count == 1 ? "" : "s")",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            ForEach(result.writtenPaths, id: \.self) { url in
                HStack {
                    Image(systemName: "doc.fill").foregroundStyle(.secondary)
                    Text(url.lastPathComponent).font(.callout.monospaced())
                    Spacer()
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.08))
        .cornerRadius(8)
    }

    private var footer: some View {
        HStack {
            Button("Done", role: .cancel) { onClose() }
            Spacer()
            Button {
                Task { await viewModel.runExport() }
            } label: {
                if viewModel.isExporting {
                    ProgressView().scaleEffect(0.6).controlSize(.small)
                } else {
                    Text("Export")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isExporting)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in }
        )
    }
}
