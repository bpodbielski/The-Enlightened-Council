# STYLE.md — Swift 6 and SwiftUI Conventions

Read alongside CLAUDE.md. These rules override any conflicting default conventions.

---

## Language

- Swift 6 with full strict concurrency
- No Combine in new code. Use `AsyncStream` and `AsyncSequence`
- No implicitly unwrapped optionals except for IBOutlet-equivalent bootstrap paths (which we do not have here)
- Prefer `let` over `var`
- Prefer value types (`struct`, `enum`) over classes. Classes only where reference semantics are required (actors, observable roots)

---

## Naming

- Types: `UpperCamelCase` (`CouncilOrchestrator`, `DebateEngine`)
- Methods, properties, cases: `lowerCamelCase`
- File name matches the primary type in the file
- SwiftUI views end in `View` (`SynthesisMapView`)
- View models end in `ViewModel`
- Engine and service types end in `Engine`, `Orchestrator`, `Runner`, `Client`, `Manager`, `Store`
- Acronyms: camelCase except when the full acronym is a standalone word (`APIKey`, `URL`, `UUID`, `SQL`)

---

## Concurrency

- All async work uses Swift Concurrency (`async / await`, `TaskGroup`, `AsyncStream`)
- Long-lived state owning mutable data: `actor`
- UI-bound observable state: `@MainActor` types
- Structured concurrency only. No detached tasks unless fire-and-forget is explicitly required and documented inline
- Cancellation must propagate. Every long-running async function checks `Task.isCancelled` at loop boundaries

---

## Error handling

- Custom `Error` types per subsystem. Example: `AnthropicError`, `MLXError`, `DatabaseError`
- Errors include enough context to surface a user-readable banner without losing debug detail
- `do` / `try` / `catch` with specific cases. No blanket `catch { }` in production code
- Never throw from a SwiftUI `body`
- Failed model runs are caught and stored as `error` on the `model_runs` row. Do not let one failed run crash the orchestration group

---

## SwiftUI patterns

- `@Observable` macro for view model types where Swift 6 concurrency supports it
- `@State` for view-local state. `@Bindable` for cross-view binding
- Prefer composition over monolithic views. Any view > 200 lines is a signal to split
- Use `.task { }` for lifecycle async work. Attach `id:` when the task depends on an argument
- Custom force graph rendering uses `Canvas` inside `TimelineView(.animation)` per SPEC §6.6

---

## Database access (GRDB)

- All persistence goes through `DatabaseManager`. Feature code never holds a `DatabasePool` directly
- Reads use `read` closures. Writes use `write` closures
- Never block the main thread on a database call. Always `await` from a background queue
- Migrations live under `Database/Migrations/`. One migration per version. Never mutate a shipped migration; add a new one

---

## Secrets and logging

- API keys: Keychain only. Never in the database, a file, a log, or a string interpolation
- `os.Logger` for debug logs. No `print` in release code
- Log levels: `.debug` for engineering signals, `.info` for user-facing state changes, `.error` for failures
- Never log prompt text, response text, or user decision content at info or above in release builds

---

## Networking

- One client per provider (`AnthropicClient`, `OpenAIClient`, `GeminiClient`, `GrokClient`)
- All clients share a common `StreamingChatClient` protocol
- URLSession configuration checked at app launch and before every council run for air gap enforcement
- No third-party HTTP libraries. `URLSession` only

---

## Testing

- Test file name matches source file: `DebateEngine.swift` → `DebateEngineTests.swift`
- XCTest. No alternate frameworks
- Every parser has a test with a malformed-input fixture
- Every orchestrator has a test that injects a failing client and verifies graceful degradation
- Performance-critical code has an `XCTMeasure` block guarding the SPEC §11 budget
- See TESTING.md for the full harness design

---

## Git hygiene

- Commit messages: imperative mood, capitalized, 72 char subject max, body wraps at 80
- One logical change per commit
- No `--no-verify`. No `--amend` on pushed commits
- Branches per phase: `phase-0-foundation`, `phase-1-intake`, etc.

---

## Forbidden

- Combine (use `AsyncStream`)
- UIKit or AppKit bridging (SwiftUI only, unless SwiftUI cannot express the requirement, documented inline)
- Third-party dependencies beyond SPEC §2
- Network calls outside the four named AI providers plus local MLX and optional Ollama
- Anything that writes to disk outside `~/Library/Application Support/The Council/` or user-selected export paths
- Anything that writes secrets to disk
- Telemetry libraries, analytics SDKs, crash reporting SDKs
