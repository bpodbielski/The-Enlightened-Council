import Foundation
import GRDB

/// Blocks outbound requests to known AI-provider hostnames when air gap mode is
/// enabled. Per SPEC §6.1 the blocked hosts are:
///
///   - api.anthropic.com
///   - api.openai.com
///   - generativelanguage.googleapis.com
///   - api.x.ai
///
/// All cloud clients must install this protocol on their `URLSessionConfiguration`
/// via `AirGapNetworkGuard.install(into:)`. Each client additionally performs an
/// eager settings check and throws before constructing a request — the protocol
/// is defence-in-depth for race conditions or bugs.
final class AirGapURLProtocol: URLProtocol, @unchecked Sendable {

    static let blockedHosts: Set<String> = [
        "api.anthropic.com",
        "api.openai.com",
        "generativelanguage.googleapis.com",
        "api.x.ai"
    ]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _active: Bool = false

    static var active: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _active }
        set { lock.lock(); _active = newValue; lock.unlock() }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard active else { return false }
        guard let host = request.url?.host?.lowercased() else { return false }
        return blockedHosts.contains(host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let error = NSError(
            domain: "TheCouncil.AirGap",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Air gap mode is active. Requests to AI provider hosts are blocked."
            ]
        )
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() { /* no-op */ }
}

enum AirGapNetworkGuard {

    /// Insert the blocking URLProtocol at the head of the given session
    /// configuration. Call on every `URLSessionConfiguration` used by cloud
    /// clients.
    static func install(into configuration: URLSessionConfiguration) {
        var classes = configuration.protocolClasses ?? []
        if !classes.contains(where: { $0 == AirGapURLProtocol.self }) {
            classes.insert(AirGapURLProtocol.self, at: 0)
        }
        configuration.protocolClasses = classes
    }

    /// Refresh the global blocklist flag from the `settings` table. Call at app
    /// launch and before every council run (per SPEC §6.1 / Phase 3 tasks).
    static func refresh(from db: DatabaseManager) async {
        let value = try? await db.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'air_gap_enabled'")
        }
        AirGapURLProtocol.active = (value == "true")
    }
}
