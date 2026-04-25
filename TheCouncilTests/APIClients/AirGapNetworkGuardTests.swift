import Foundation
import XCTest
@testable import TheCouncil

final class AirGapNetworkGuardTests: XCTestCase {

    override func tearDown() {
        AirGapURLProtocol.active = false
        super.tearDown()
    }

    func test_blocksAllFourCloudHosts_whenActive() {
        AirGapURLProtocol.active = true
        for host in ["api.anthropic.com", "api.openai.com", "generativelanguage.googleapis.com", "api.x.ai"] {
            let req = URLRequest(url: URL(string: "https://\(host)/v1/chat")!)
            XCTAssertTrue(AirGapURLProtocol.canInit(with: req), "Should block \(host)")
        }
    }

    func test_doesNotBlock_unrelatedHost() {
        AirGapURLProtocol.active = true
        let req = URLRequest(url: URL(string: "https://example.com/anything")!)
        XCTAssertFalse(AirGapURLProtocol.canInit(with: req))
    }

    func test_doesNotBlock_localOllama() {
        AirGapURLProtocol.active = true
        let req = URLRequest(url: URL(string: "http://localhost:11434/api/chat")!)
        XCTAssertFalse(AirGapURLProtocol.canInit(with: req))
    }

    func test_inactive_doesNotBlockAnything() {
        AirGapURLProtocol.active = false
        let req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        XCTAssertFalse(AirGapURLProtocol.canInit(with: req))
    }

    func test_install_prependsProtocolOnce() {
        let config = URLSessionConfiguration.ephemeral
        AirGapNetworkGuard.install(into: config)
        AirGapNetworkGuard.install(into: config)
        let count = (config.protocolClasses ?? []).filter { $0 == AirGapURLProtocol.self }.count
        XCTAssertEqual(count, 1)
    }
}
