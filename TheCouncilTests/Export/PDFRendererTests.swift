import XCTest
import PDFKit
@testable import TheCouncil

final class PDFRendererTests: XCTestCase {

    // MARK: - Fixtures

    private func makePayload(verdictText: String = "Ship Q2.") -> ExportPayload {
        let decision = Decision(
            id: "d1", createdAt: Date(timeIntervalSince1970: 1_777_017_600),
            status: .complete, question: "Should we ship the new pricing?",
            lensTemplate: "growth-strategy", reversibility: .reversible,
            timeHorizon: .quarters, sensitivityClass: .public,
            successCriteria: "20% lift", refinedBrief: nil, refinementChatLog: nil
        )
        let verdict = Verdict(
            id: "v1", decisionId: "d1",
            createdAt: Date(timeIntervalSince1970: 1_777_017_600),
            verdictText: verdictText, confidence: 80,
            keyForJson: "[\"Margins improve\"]",
            keyAgainstJson: "[\"Churn risk\"]",
            risk: "Risk text", blindSpot: "Blind spot",
            opportunity: "Opportunity", preMortem: "Pre-mortem bullets",
            outcomeDeadline: Date(timeIntervalSince1970: 1_777_017_600 + 60 * 86_400),
            testAction: "Pilot", testMetric: "Conversion", testThreshold: "+10%",
            outcomeStatus: .pending
        )
        let runs = [
            ModelRun(id: "r1", decisionId: "d1", modelName: "claude-opus-4-7",
                     provider: .anthropic, persona: "analyst", roundNumber: 1, sampleNumber: 1,
                     temperature: 0.3, prompt: "p", response: "r", tokensIn: 100, tokensOut: 200,
                     costUsd: 0.5, createdAt: Date(), error: nil, positionChanged: nil),
            ModelRun(id: "r2", decisionId: "d1", modelName: "gpt-5.4",
                     provider: .openai, persona: "skeptic", roundNumber: 1, sampleNumber: 1,
                     temperature: 0.3, prompt: "p", response: "r", tokensIn: 100, tokensOut: 200,
                     costUsd: 0.3, createdAt: Date(), error: nil, positionChanged: nil),
        ]
        return ExportPayload(decision: decision, verdict: verdict, outcome: nil, modelRuns: runs)
    }

    // MARK: - Smoke

    func test_render_producesNonEmptyPDFData() {
        let data = PDFRenderer.render(makePayload())
        XCTAssertGreaterThan(data.count, 1000, "Expected a multi-kilobyte PDF, got \(data.count) bytes")
    }

    func test_render_producesValidPDFParseableByPDFKit() {
        let data = PDFRenderer.render(makePayload())
        let doc = PDFDocument(data: data)
        XCTAssertNotNil(doc, "Output must be parseable by PDFKit")
        XCTAssertGreaterThanOrEqual(doc?.pageCount ?? 0, 1)
    }

    func test_render_pageMediaBoxIsUSLetter() {
        let data = PDFRenderer.render(makePayload())
        guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else {
            XCTFail("PDF unparseable")
            return
        }
        let bounds = page.bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 612, accuracy: 1.0, "US Letter is 612pt wide")
        XCTAssertEqual(bounds.height, 792, accuracy: 1.0, "US Letter is 792pt tall")
    }

    // MARK: - Long content paginates

    func test_render_longContent_producesMultiplePages() {
        // Build a verdict with very long text to force multi-page layout.
        let bigText = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 200)
        let data = PDFRenderer.render(makePayload(verdictText: bigText))
        guard let doc = PDFDocument(data: data) else {
            XCTFail("PDF unparseable")
            return
        }
        XCTAssertGreaterThan(doc.pageCount, 1, "Long verdict should span multiple pages")
    }

    // MARK: - Content presence

    func test_render_extractedTextContainsKeyHeaders() {
        let data = PDFRenderer.render(makePayload())
        guard let doc = PDFDocument(data: data),
              let text = doc.string else {
            XCTFail("PDF text extraction failed")
            return
        }
        XCTAssertTrue(text.contains("Verdict"), "Body should include 'Verdict' header")
        XCTAssertTrue(text.contains("Arguments For"))
        XCTAssertTrue(text.contains("Arguments Against"))
        XCTAssertTrue(text.contains("Risk"))
        XCTAssertTrue(text.contains("Pre-mortem"))
    }

    func test_render_extractedTextContainsHeaderQuestionAndModelPanel() {
        let data = PDFRenderer.render(makePayload())
        guard let text = PDFDocument(data: data)?.string else {
            XCTFail("PDF text extraction failed")
            return
        }
        XCTAssertTrue(text.contains("Should we ship the new pricing?"),
                      "Header should print the decision question")
        XCTAssertTrue(text.contains("claude-opus-4-7") && text.contains("gpt-5.4"),
                      "Footer / body should include both models from the panel")
        XCTAssertTrue(text.contains("$0.80") || text.contains("0.80"),
                      "Total cost should appear")
    }

    func test_render_extractedTextContainsPageMarker() {
        // Force multi-page so "Page X of Y" appears more than once.
        let bigText = String(repeating: "Lorem ipsum. ", count: 1000)
        let data = PDFRenderer.render(makePayload(verdictText: bigText))
        guard let text = PDFDocument(data: data)?.string else {
            XCTFail("PDF text extraction failed")
            return
        }
        XCTAssertTrue(text.contains("Page "), "Footer should label pages")
        XCTAssertTrue(text.contains(" of "), "Footer should use 'X of Y' format")
    }
}
