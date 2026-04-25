import Foundation
import XCTest
@testable import TheCouncil

final class MLXRunnerTests: XCTestCase {

    func test_streamChat_emitsAtLeastOneToken() async throws {
        let gate = LocalResourceGate(freeMemoryProvider: { 64 * 1_024 * 1_024 * 1_024 },
                                     thermalStateProvider: { .nominal })
        let runner = MLXRunner(gate: gate)
        let stream = runner.streamChat(
            messages: [TheCouncil.ChatMessage(role: "user", content: "Hello")],
            model: "qwen-2.5-32b-instruct",
            temperature: 0.7
        )
        var joined = ""
        for try await chunk in stream {
            joined += chunk
        }
        XCTAssertFalse(joined.isEmpty)
    }

    func test_streamChat_failsFastUnderMemoryGate() async {
        let gate = LocalResourceGate(freeMemoryProvider: { 4 * 1_024 * 1_024 * 1_024 },
                                     thermalStateProvider: { .nominal })
        let runner = MLXRunner(gate: gate)
        let stream = runner.streamChat(
            messages: [TheCouncil.ChatMessage(role: "user", content: "Hello")],
            model: "qwen-2.5-32b-instruct",
            temperature: 0.7
        )
        do {
            for try await _ in stream { }
            XCTFail("Expected gate to reject")
        } catch let MLXRunnerError.resourceUnavailable(reason) {
            XCTAssertTrue(reason.contains("memory") || reason.contains("Memory"))
        } catch {
            XCTFail("Expected MLXRunnerError.resourceUnavailable, got \(error)")
        }
    }

    func test_modelCatalog_includesQwenAndMistral() {
        let ids = MLXRunner.knownModels.map { $0.id }
        XCTAssertTrue(ids.contains("qwen-2.5-32b-instruct"))
        XCTAssertTrue(ids.contains("mistral-small-22b"))
    }

    func test_modelCatalog_qwenFallbackIsQwen14B() {
        guard let qwen = MLXRunner.knownModels.first(where: { $0.id == "qwen-2.5-32b-instruct" }) else {
            XCTFail("Qwen 32B missing from catalog"); return
        }
        XCTAssertEqual(qwen.fallbackID, "qwen-2.5-14b-instruct")
    }
}
