import Foundation
import KeychainAccess

// MARK: - Error type

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
}

// MARK: - KeychainStore

struct KeychainStore {

    // MARK: - Provider

    enum Provider: String, CaseIterable {
        case anthropic
        case openai
        case google
        case xai

        var serviceName: String {
            "com.benpodbielski.thecouncil.apikey.\(rawValue)"
        }
    }

    // MARK: - Private helpers

    private func keychain(for provider: Provider) -> Keychain {
        Keychain(service: provider.serviceName)
            .accessibility(.whenUnlockedThisDeviceOnly)
    }

    // MARK: - API

    func save(key: String, for provider: Provider) throws {
        // Strip whitespace/newlines that creep in from clipboard pastes.
        // A trailing \n in an Authorization header causes silent 401s.
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try keychain(for: provider).set(cleaned, key: provider.serviceName)
        } catch {
            let status = (error as NSError).code
            throw KeychainError.saveFailed(OSStatus(status))
        }
    }

    func load(for provider: Provider) throws -> String? {
        do {
            // Trim defensively on read too, in case a key was saved before the
            // save-side trim was added.
            return try keychain(for: provider)
                .get(provider.serviceName)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            let status = (error as NSError).code
            throw KeychainError.loadFailed(OSStatus(status))
        }
    }

    func delete(for provider: Provider) throws {
        do {
            try keychain(for: provider).remove(provider.serviceName)
        } catch {
            let status = (error as NSError).code
            throw KeychainError.deleteFailed(OSStatus(status))
        }
    }

    func hasKey(for provider: Provider) -> Bool {
        (try? load(for: provider)) != nil
    }
}
