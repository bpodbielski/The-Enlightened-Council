import SwiftUI
import os.log

// MARK: - SettingsViewModel

@Observable
@MainActor
final class SettingsViewModel {

    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "SettingsViewModel")
    private let db: DatabaseManager
    private let keychain: KeychainStore

    // MARK: General
    var defaultOutcomeDeadlineDays: Int = 60

    // MARK: Debate
    var defaultRounds: Int = 3
    var defaultSamples: Int = 3

    // MARK: Cost
    var costSoftWarnUsd: String = "2.00"
    var costHardPauseUsd: String = "5.00"

    // MARK: Air Gap
    var airGapEnabled: Bool = false

    // MARK: Export
    var exportDefaultPath: String = "~/Desktop"

    // MARK: API Keys (transient — not persisted in DB)
    var anthropicKeyInput: String = ""
    var openaiKeyInput: String = ""
    var googleKeyInput: String = ""
    var xaiKeyInput: String = ""

    var anthropicKeyExists: Bool = false
    var openaiKeyExists: Bool = false
    var googleKeyExists: Bool = false
    var xaiKeyExists: Bool = false

    // MARK: Alert
    var alertMessage: String = ""
    var showingAlert: Bool = false

    init(db: DatabaseManager = .shared, keychain: KeychainStore = KeychainStore()) {
        self.db = db
        self.keychain = keychain
    }

    // MARK: - Load

    func load() async {
        do {
            let rows = try await db.read { db in
                try AppSettings.fetchAll(db)
            }
            let map = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.value) })
            if let v = map[SettingsKey.defaultOutcomeDeadlineDays.rawValue], let i = Int(v) {
                defaultOutcomeDeadlineDays = i
            }
            if let v = map[SettingsKey.defaultRounds.rawValue], let i = Int(v) { defaultRounds = i }
            if let v = map[SettingsKey.defaultSamples.rawValue], let i = Int(v) { defaultSamples = i }
            if let v = map[SettingsKey.costSoftWarnUsd.rawValue] { costSoftWarnUsd = v }
            if let v = map[SettingsKey.costHardPauseUsd.rawValue] { costHardPauseUsd = v }
            if let v = map[SettingsKey.airGapEnabled.rawValue] { airGapEnabled = v == "true" }
            if let v = map[SettingsKey.exportDefaultPath.rawValue] { exportDefaultPath = v }
        } catch {
            Self.logger.error("Failed to load settings: \(error)")
        }
        refreshKeychainStatus()
    }

    // MARK: - Keychain status

    func refreshKeychainStatus() {
        anthropicKeyExists = keychain.hasKey(for: .anthropic)
        openaiKeyExists = keychain.hasKey(for: .openai)
        googleKeyExists = keychain.hasKey(for: .google)
        xaiKeyExists = keychain.hasKey(for: .xai)
    }

    // MARK: - Save individual settings

    func saveSetting(key: SettingsKey, value: String) async {
        do {
            try await db.write { db in
                try db.execute(
                    sql: "INSERT INTO settings(key, value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                    arguments: [key.rawValue, value]
                )
            }
        } catch {
            Self.logger.error("Failed to save setting \(key.rawValue): \(error)")
            showAlert("Failed to save setting.")
        }
    }

    func saveDeadlineDays() async {
        await saveSetting(key: .defaultOutcomeDeadlineDays, value: String(defaultOutcomeDeadlineDays))
    }

    func saveRounds() async {
        await saveSetting(key: .defaultRounds, value: String(defaultRounds))
    }

    func saveSamples() async {
        await saveSetting(key: .defaultSamples, value: String(defaultSamples))
    }

    func saveCostLimits() async {
        await saveSetting(key: .costSoftWarnUsd, value: costSoftWarnUsd)
        await saveSetting(key: .costHardPauseUsd, value: costHardPauseUsd)
    }

    func saveAirGap() async {
        await saveSetting(key: .airGapEnabled, value: airGapEnabled ? "true" : "false")
        AirGapURLProtocol.active = airGapEnabled
    }

    func saveExportPath() async {
        await saveSetting(key: .exportDefaultPath, value: exportDefaultPath)
    }

    // MARK: - Keychain operations

    func saveApiKey(for provider: KeychainStore.Provider, value: String) {
        do {
            if value.isEmpty {
                try keychain.delete(for: provider)
            } else {
                try keychain.save(key: value, for: provider)
            }
            refreshKeychainStatus()
        } catch {
            Self.logger.error("Failed to save API key for \(provider.rawValue): \(error)")
            showAlert("Failed to save API key.")
        }
    }

    // MARK: - Helpers

    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

// MARK: - SettingsView

struct SettingsView: View {

    @State private var viewModel = SettingsViewModel()

    var body: some View {
        TabView {
            GeneralTabView(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }

            ModelsTabView(viewModel: viewModel)
                .tabItem { Label("Models", systemImage: "cpu") }

            DebateTabView(viewModel: viewModel)
                .tabItem { Label("Debate", systemImage: "bubble.left.and.bubble.right") }

            CostTabView(viewModel: viewModel)
                .tabItem { Label("Cost", systemImage: "dollarsign.circle") }

            AirGapTabView(viewModel: viewModel)
                .tabItem { Label("Air Gap", systemImage: "wifi.slash") }

            ExportTabView(viewModel: viewModel)
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }

            AboutTabView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .tabViewStyle(.automatic)
        .frame(minWidth: 480, minHeight: 320)
        .alert("Settings Error", isPresented: $viewModel.showingAlert) {
            Button("OK") {}
        } message: {
            Text(viewModel.alertMessage)
        }
        .task {
            await viewModel.load()
        }
    }
}

// MARK: - General Tab

private struct GeneralTabView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Stepper(
                "Default outcome deadline: \(viewModel.defaultOutcomeDeadlineDays) days",
                value: $viewModel.defaultOutcomeDeadlineDays,
                in: 1 ... 365
            )
            .onChange(of: viewModel.defaultOutcomeDeadlineDays) { _, _ in
                Task { await viewModel.saveDeadlineDays() }
            }
        }
        .padding()
        .navigationTitle("General")
    }
}

// MARK: - Models Tab

private struct ModelsTabView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            apiKeySection(
                provider: .anthropic,
                label: "Anthropic",
                binding: $viewModel.anthropicKeyInput,
                exists: viewModel.anthropicKeyExists
            )
            Divider()
            apiKeySection(
                provider: .openai,
                label: "OpenAI",
                binding: $viewModel.openaiKeyInput,
                exists: viewModel.openaiKeyExists
            )
            Divider()
            apiKeySection(
                provider: .google,
                label: "Google",
                binding: $viewModel.googleKeyInput,
                exists: viewModel.googleKeyExists
            )
            Divider()
            apiKeySection(
                provider: .xai,
                label: "xAI",
                binding: $viewModel.xaiKeyInput,
                exists: viewModel.xaiKeyExists
            )
        }
        .padding()
        .navigationTitle("Models")
    }

    @ViewBuilder
    private func apiKeySection(
        provider: KeychainStore.Provider,
        label: String,
        binding: Binding<String>,
        exists: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
            HStack {
                SecureField(
                    exists ? "Key stored — enter new to replace" : "Enter API key",
                    text: binding
                )
                .textFieldStyle(.roundedBorder)
                Button("Save") {
                    viewModel.saveApiKey(for: provider, value: binding.wrappedValue)
                    binding.wrappedValue = ""
                }
                .disabled(binding.wrappedValue.isEmpty)
            }
            if exists {
                Text("Key is stored in Keychain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Debate Tab

private struct DebateTabView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Stepper(
                "Default rounds: \(viewModel.defaultRounds)",
                value: $viewModel.defaultRounds,
                in: 1 ... 5
            )
            .onChange(of: viewModel.defaultRounds) { _, _ in
                Task { await viewModel.saveRounds() }
            }

            Stepper(
                "Default samples: \(viewModel.defaultSamples)",
                value: $viewModel.defaultSamples,
                in: 1 ... 5
            )
            .onChange(of: viewModel.defaultSamples) { _, _ in
                Task { await viewModel.saveSamples() }
            }
        }
        .padding()
        .navigationTitle("Debate")
    }
}

// MARK: - Cost Tab

private struct CostTabView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            LabeledContent("Soft warning threshold (USD)") {
                TextField("e.g. 2.00", text: $viewModel.costSoftWarnUsd)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            LabeledContent("Hard pause threshold (USD)") {
                TextField("e.g. 5.00", text: $viewModel.costHardPauseUsd)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            Button("Save Cost Limits") {
                Task { await viewModel.saveCostLimits() }
            }
        }
        .padding()
        .navigationTitle("Cost")
    }
}

// MARK: - Air Gap Tab

private struct AirGapTabView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Toggle("Enable Air Gap", isOn: $viewModel.airGapEnabled)
                .onChange(of: viewModel.airGapEnabled) { _, _ in
                    Task { await viewModel.saveAirGap() }
                }
            Text("When enabled, all cloud AI API calls are blocked. Only local models may be used.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Air Gap")
    }
}

// MARK: - Export Tab

private struct ExportTabView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            LabeledContent("Default export path") {
                TextField("~/Desktop", text: $viewModel.exportDefaultPath)
                    .textFieldStyle(.roundedBorder)
            }
            Button("Save Export Path") {
                Task { await viewModel.saveExportPath() }
            }
        }
        .padding()
        .navigationTitle("Export")
    }
}

// MARK: - About Tab

private struct AboutTabView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "scale.3d")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("The Council")
                .font(.title)
                .bold()
            Text("Version \(appVersion) (\(buildNumber))")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("About")
    }
}
