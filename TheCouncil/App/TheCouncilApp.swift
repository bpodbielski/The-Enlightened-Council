import SwiftUI
import os.log

// MARK: - TheCouncilApp

@main
struct TheCouncilApp: App {

    private static let logger = Logger(subsystem: "com.benpodbielski.thecouncil", category: "App")

    @State private var databaseReady: Bool = false
    @State private var showingDatabaseError: Bool = false

    var body: some Scene {
        WindowGroup {
            Group {
                if databaseReady {
                    ContentView()
                } else if showingDatabaseError {
                    DatabaseErrorView()
                } else {
                    // Brief moment while migrations run
                    ProgressView("Initializing…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task {
                await initializeDatabase()
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
        }
    }

    // MARK: - Private

    private func initializeDatabase() async {
        do {
            // Touch the shared singleton — its init runs migrations
            _ = DatabaseManager.shared
            await AirGapNetworkGuard.refresh(from: .shared)
            databaseReady = true
        } catch {
            Self.logger.error("Database initialization failed: \(error)")
            showingDatabaseError = true
        }
    }
}

// MARK: - DatabaseErrorView

private struct DatabaseErrorView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("The database could not be initialized. Please contact support.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
