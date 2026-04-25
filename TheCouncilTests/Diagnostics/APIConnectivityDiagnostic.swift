import Foundation
import XCTest
@testable import TheCouncil

// MARK: - APIConnectivityDiagnostic
//
// Opt-in diagnostic. Does NOT run with the default test suite.
// Invoke with:
//
//   RUN_DIAGNOSTICS=1 xcodebuild -project TheCouncil.xcodeproj -scheme TheCouncil \
//     -destination "platform=macOS" \
//     -only-testing:TheCouncilTests/APIConnectivityDiagnostic test
//
// Reads OpenAI + Anthropic keys from Keychain (the same place SettingsView writes them)
// and probes each provider with both the SPEC-defined model IDs and a known-current
// model ID, so we can tell apart: missing key, bad key (401), bad model (404),
// air-gap blocking, or sandbox/network issue.

final class APIConnectivityDiagnostic: XCTestCase {

    // MARK: - Entry

    func test_runDiagnostic() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_DIAGNOSTICS"] == nil,
            "Set RUN_DIAGNOSTICS=1 to enable. This test makes real network calls."
        )

        var report = Report()
        report.line("=== The Council — API Connectivity Diagnostic ===")
        report.line("Time: \(Date())")
        report.line("")

        // 1. Air-gap state
        await reportAirGap(into: &report)

        // 2. Keychain read for each provider
        let keychain = KeychainStore()
        let anthropicKey = try? keychain.load(for: .anthropic)
        let openaiKey    = try? keychain.load(for: .openai)
        report.line("Anthropic key in Keychain: \(maskedStatus(anthropicKey))")
        report.line("OpenAI    key in Keychain: \(maskedStatus(openaiKey))")
        report.line("")

        // 3. Anthropic probes
        if let key = anthropicKey, !key.isEmpty {
            await probeAnthropic(key: key, model: "claude-opus-4-7",          label: "SPEC",  into: &report)
            await probeAnthropic(key: key, model: "claude-sonnet-4-6",        label: "SPEC",  into: &report)
            await probeAnthropic(key: key, model: "claude-3-5-sonnet-latest", label: "known", into: &report)
        } else {
            report.line("[Anthropic] SKIPPED — no key in Keychain.")
            report.line("")
        }

        // 4. OpenAI probes
        if let key = openaiKey, !key.isEmpty {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            report.line("OpenAI key sanity:")
            report.line("  raw     length=\(key.count)     bytes=\(Array(key.utf8).suffix(4))")
            report.line("  trimmed length=\(trimmed.count) bytes=\(Array(trimmed.utf8).suffix(4))")
            if key != trimmed {
                report.line("  ⚠️  Whitespace/newline detected in stored key. SettingsView should trim before saving.")
            }
            report.line("")

            await probeOpenAI(key: key,     model: "gpt-4o-mini", label: "raw key + known model",     into: &report)
            await probeOpenAI(key: trimmed, model: "gpt-4o-mini", label: "trimmed key + known model", into: &report)
            await probeOpenAI(key: trimmed, model: "gpt-5.4",      label: "trimmed key + SPEC model",  into: &report)
            await probeOpenAI(key: trimmed, model: "gpt-5.4-mini", label: "trimmed key + SPEC model",  into: &report)
        } else {
            report.line("[OpenAI] SKIPPED — no key in Keychain.")
            report.line("")
        }

        // 5. Print and surface
        let output = report.text
        // Print to stderr so it shows up in xcodebuild output
        FileHandle.standardError.write(Data(output.utf8))
        FileHandle.standardError.write(Data("\n".utf8))

        // Always pass — value is the report. Failures inside probes are recorded as report lines.
    }

    // MARK: - Air gap

    private func reportAirGap(into report: inout Report) async {
        do {
            let value = try await DatabaseManager.shared.read { db -> String? in
                try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'air_gap_enabled'")
            }
            let active = (value == "true")
            report.line("Air-gap setting (DB): \(value ?? "<unset>") → URLProtocol active = \(active)")
            if active {
                report.line("⚠️  Air gap is ACTIVE. Cloud probes below will throw before the network call.")
            }
            report.line("")
        } catch {
            report.line("Air-gap read failed: \(error)")
            report.line("")
        }
    }

    // MARK: - Anthropic probe

    private func probeAnthropic(key: String, model: String, label: String, into report: inout Report) async {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 10,
            "messages": [["role": "user", "content": "Say ok."]]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        report.line("[Anthropic][\(label)] model=\(model)")
        await runProbe(request: req, into: &report)
    }

    // MARK: - OpenAI probe

    private func probeOpenAI(key: String, model: String, label: String, into report: inout Report) async {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        // Use the production OpenAIClient.buildBody so this exercises the real request
        // shape (gpt-5*/o-series → max_completion_tokens, older → max_tokens + temperature).
        let messages = [TheCouncil.ChatMessage(role: "user", content: "Say ok.")]
        do {
            req.httpBody = try OpenAIClient.buildBody(messages: messages, model: model, temperature: 0.7)
        } catch {
            report.line("[OpenAI][\(label)] model=\(model) — body build failed: \(error)")
            report.line("")
            return
        }
        // Override stream=true for a non-streaming probe; easier to capture full response body.
        if var json = try? JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any] {
            json["stream"] = false
            req.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }

        report.line("[OpenAI][\(label)] model=\(model) param=\(OpenAIClient.usesCompletionTokensParam(model: model) ? "max_completion_tokens" : "max_tokens")")
        await runProbe(request: req, into: &report)
    }

    // MARK: - Common probe runner

    private func runProbe(request: URLRequest, into report: inout Report) async {
        let config = URLSessionConfiguration.default
        // Install the same air-gap guard the production clients use, so we see if it's
        // intercepting requests we don't expect.
        AirGapNetworkGuard.install(into: config)
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                let bodyStr = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
                let truncated = bodyStr.count > 500 ? String(bodyStr.prefix(500)) + "…(truncated)" : bodyStr
                report.line("  HTTP \(http.statusCode)")
                report.line("  Body: \(truncated)")
                report.line("  → \(diagnose(status: http.statusCode, body: bodyStr))")
            } else {
                report.line("  Non-HTTP response: \(response)")
            }
        } catch {
            report.line("  Transport error: \(describe(error))")
        }
        report.line("")
    }

    // MARK: - Diagnose

    private func diagnose(status: Int, body: String) -> String {
        switch status {
        case 200...299:
            return "OK — provider returned a successful completion."
        case 401:
            return "401 UNAUTHORIZED — key is missing, malformed, revoked, or for a different env (e.g., personal vs org)."
        case 403:
            return "403 FORBIDDEN — key valid but lacks access to this model/feature/region."
        case 404:
            if body.lowercased().contains("model") {
                return "404 — model ID does not exist on this provider. Verify the SPEC model ID against the provider's current catalog."
            }
            return "404 — endpoint or resource not found."
        case 429:
            return "429 RATE LIMITED — too many requests or out of quota."
        case 400:
            if body.lowercased().contains("model") {
                return "400 — request rejected, likely a bad/unknown model ID."
            }
            return "400 BAD REQUEST — the body shape is wrong for this provider/version."
        case 500...599:
            return "5xx — provider-side error. Retry later."
        default:
            return "Unexpected status \(status)."
        }
    }

    private func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return "URLError code=\(urlError.code.rawValue) domain=\(urlError.errorCode) — \(urlError.localizedDescription)"
        }
        return "\(error)"
    }

    // MARK: - Helpers

    private func maskedStatus(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "MISSING" }
        let prefix = String(key.prefix(7))
        return "present (\(key.count) chars, prefix \(prefix)…)"
    }

    // MARK: - Report buffer

    private struct Report {
        var lines: [String] = []
        mutating func line(_ s: String) { lines.append(s) }
        var text: String { lines.joined(separator: "\n") }
    }
}
