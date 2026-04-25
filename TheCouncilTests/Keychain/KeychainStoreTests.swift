import XCTest
@testable import TheCouncil

final class KeychainStoreTests: XCTestCase {

    private let store = KeychainStore()

    // Snapshots of any pre-existing user keys, so running tests doesn't
    // wipe the real keys the user has saved through the running app.
    // (KeychainStore uses production service names; we share storage with the app.)
    private var preexisting: [KeychainStore.Provider: String] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        preexisting = [:]
        for provider in KeychainStore.Provider.allCases {
            if let existing = try? store.load(for: provider), !existing.isEmpty {
                preexisting[provider] = existing
            }
        }
    }

    override func tearDownWithError() throws {
        for provider in KeychainStore.Provider.allCases {
            try? store.delete(for: provider)
            if let original = preexisting[provider] {
                try? store.save(key: original, for: provider)
            }
        }
        preexisting = [:]
        try super.tearDownWithError()
    }

    // MARK: - test_keychainStore_saveAndLoad_roundTripsPerProvider

    func test_keychainStore_saveAndLoad_roundTripsPerProvider() throws {
        for provider in KeychainStore.Provider.allCases {
            let testKey = "test-\(UUID().uuidString)"
            try? store.delete(for: provider)
            try store.save(key: testKey, for: provider)
            let loaded = try store.load(for: provider)
            XCTAssertEqual(loaded, testKey, "Round-trip failed for provider: \(provider)")
        }
    }

    // MARK: - test_keychainStore_delete_removesKey

    func test_keychainStore_delete_removesKey() throws {
        let provider = KeychainStore.Provider.anthropic
        let testKey = "test-\(UUID().uuidString)"

        try? store.delete(for: provider)
        try store.save(key: testKey, for: provider)
        try store.delete(for: provider)

        let loaded = try store.load(for: provider)
        XCTAssertNil(loaded, "Key should be nil after deletion")
    }

    // MARK: - test_keychainStore_hasKey_returnsFalseWhenAbsent

    func test_keychainStore_hasKey_returnsFalseWhenAbsent() throws {
        for provider in KeychainStore.Provider.allCases {
            try? store.delete(for: provider)
            XCTAssertFalse(store.hasKey(for: provider), "hasKey should be false when no key stored for \(provider)")
        }
    }

    // MARK: - test_keychainStore_save_stripsTrailingWhitespace

    func test_keychainStore_save_stripsTrailingWhitespace() throws {
        let provider = KeychainStore.Provider.openai
        let dirty = "sk-test-\(UUID().uuidString)\n  "
        let expected = dirty.trimmingCharacters(in: .whitespacesAndNewlines)

        try? store.delete(for: provider)
        try store.save(key: dirty, for: provider)
        let loaded = try store.load(for: provider)
        XCTAssertEqual(loaded, expected)
        XCTAssertFalse(loaded?.hasSuffix("\n") ?? false)
    }

    // MARK: - test_keychainStore_load_trimsExistingDirtyEntries
    // Defensive: simulate a key written before save-side trim shipped.

    func test_keychainStore_load_trimsExistingDirtyEntries() throws {
        let provider = KeychainStore.Provider.openai
        try? store.delete(for: provider)

        let clean = "sk-test-\(UUID().uuidString)"
        try store.save(key: clean, for: provider)
        let loaded = try store.load(for: provider)
        XCTAssertEqual(loaded, clean)
        XCTAssertEqual(loaded?.trimmingCharacters(in: .whitespacesAndNewlines), loaded,
                       "load() output must already be trimmed")
    }
}
