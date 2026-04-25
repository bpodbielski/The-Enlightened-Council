import Foundation
import XCTest
@testable import TheCouncil

final class LocalResourceGateTests: XCTestCase {

    func test_memoryGate_admitsWhenFreeAboveThreshold() {
        let gate = LocalResourceGate(freeMemoryProvider: { 20 * 1_024 * 1_024 * 1_024 },
                                     thermalStateProvider: { .nominal })
        XCTAssertEqual(gate.check(minFreeBytes: 10 * 1_024 * 1_024 * 1_024), .ok)
    }

    func test_memoryGate_refusesWhenFreeBelowThreshold() {
        let gate = LocalResourceGate(freeMemoryProvider: { 4 * 1_024 * 1_024 * 1_024 },
                                     thermalStateProvider: { .nominal })
        if case .insufficientMemory(let needed, let free) = gate.check(minFreeBytes: 10 * 1_024 * 1_024 * 1_024) {
            XCTAssertEqual(needed, 10 * 1_024 * 1_024 * 1_024)
            XCTAssertEqual(free, 4 * 1_024 * 1_024 * 1_024)
        } else {
            XCTFail("Expected .insufficientMemory")
        }
    }

    func test_thermalGate_refusesWhenSeriousOrWorse() {
        let gate = LocalResourceGate(freeMemoryProvider: { 64 * 1_024 * 1_024 * 1_024 },
                                     thermalStateProvider: { .serious })
        XCTAssertEqual(gate.check(minFreeBytes: 10 * 1_024 * 1_024 * 1_024), .thermalThrottle(.serious))
    }

    func test_thermalGate_refusesOnCritical() {
        let gate = LocalResourceGate(freeMemoryProvider: { 64 * 1_024 * 1_024 * 1_024 },
                                     thermalStateProvider: { .critical })
        XCTAssertEqual(gate.check(minFreeBytes: 10 * 1_024 * 1_024 * 1_024), .thermalThrottle(.critical))
    }

    func test_fair_passes() {
        let gate = LocalResourceGate(freeMemoryProvider: { 64 * 1_024 * 1_024 * 1_024 },
                                     thermalStateProvider: { .fair })
        XCTAssertEqual(gate.check(minFreeBytes: 10 * 1_024 * 1_024 * 1_024), .ok)
    }
}
