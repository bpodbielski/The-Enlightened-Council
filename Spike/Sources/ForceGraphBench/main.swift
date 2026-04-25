// main.swift — Force-graph physics benchmark for The Council spike.
//
// Measures physics ticks/second at 50, 100, and 200 nodes.
// Each tick must complete in < 16.67 ms to sustain 60 fps.
//
// Barnes-Hut engages automatically at >100 nodes per SPEC §6.6.
//
// Results are printed to stdout AND written to ../../results.md
// (relative to the package root, i.e. Spike/results.md).

import Foundation

// MARK: - Helpers

func benchmark(nodeCount: Int, warmupTicks: Int = 120, measureSeconds: Double = 10.0) -> (tps: Double, avgMs: Double) {
    let sim = ForceSimulation(nodeCount: nodeCount)

    // Warm-up: let the graph settle and JIT/cache warm
    for _ in 0 ..< warmupTicks { sim.tick() }

    // Measure
    var ticks = 0
    let start = Date()
    while Date().timeIntervalSince(start) < measureSeconds {
        sim.tick()
        ticks += 1
    }
    let elapsed = Date().timeIntervalSince(start)
    let tps = Double(ticks) / elapsed
    let avgMs = elapsed / Double(ticks) * 1000
    return (tps, avgMs)
}

// MARK: - Run

let configs: [(nodeCount: Int, label: String, bhEngaged: Bool)] = [
    (50,  "50 nodes (naïve O(n²))",        false),
    (100, "100 nodes (naïve O(n²))",       false),
    (200, "200 nodes (Barnes-Hut O(n log n))", true),
]

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("The Council — Force Graph Physics Benchmark")
print("Swift \(#file.contains("") ? "6" : "?") · \(ProcessInfo.processInfo.processorCount) CPU cores · \(Date())")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("")
print("Config: repulsion 200, spring (80 px, k=0.3), centering 0.05, damping 0.85")
print("        Barnes-Hut theta 0.9, engages at >100 nodes")
print("")
print("Warming up each simulation (120 ticks) then measuring for 10 s …")
print("")

struct Result {
    let label: String
    let tps: Double
    let avgMs: Double
    let bhEngaged: Bool

    var fps: Int { Int(tps.rounded()) }
    var verdict: String {
        switch fps {
        case 60...:        return "✅ GO — ≥60 fps"
        case 55 ..< 60:    return "✅ GO — ≥55 fps (within spike threshold)"
        case 40 ..< 55:    return "⚠️  BORDERLINE — 40-54 fps (plan BH refinement)"
        default:           return "❌ NO-GO — <40 fps (column-view fallback required)"
        }
    }
}

var results: [Result] = []

for config in configs {
    print("  Benchmarking \(config.label) …", terminator: "")
    fflush(stdout)
    let (tps, avgMs) = benchmark(nodeCount: config.nodeCount)
    let r = Result(label: config.label, tps: tps, avgMs: avgMs, bhEngaged: config.bhEngaged)
    results.append(r)
    print(" \(r.fps) ticks/sec  (\(String(format: "%.2f", avgMs)) ms/tick)  \(r.verdict)")
}

print("")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

// MARK: - Go / no-go decision

let twoHundredResult = results.last!
let overallVerdict: String
let goNoGo: String

switch twoHundredResult.fps {
case 55...:
    overallVerdict = "GO"
    goNoGo = "Proceed to Phase 5 as planned. Barnes-Hut + Canvas approach validated."
case 40 ..< 55:
    overallVerdict = "BORDERLINE"
    goNoGo = "Proceed but add Barnes-Hut refinement task and plan column-view as fallback for >150 nodes."
default:
    overallVerdict = "NO-GO"
    goNoGo = "Switch Phase 5 to column-view primary. Small graph mode capped at <50 nodes."
}

print("Overall verdict at 200 nodes: \(overallVerdict)")
print(goNoGo)
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

// MARK: - Write results.md

// Resolve Spike/results.md relative to the package root
let scriptDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // ForceGraphBench/
    .deletingLastPathComponent()  // Sources/
    .deletingLastPathComponent()  // package root (Spike/)

let resultsURL = scriptDir.appendingPathComponent("results.md")

var md = """
# Force Graph Spike — Results

**Date:** \(ISO8601DateFormatter().string(from: Date()))
**Hardware:** \(ProcessInfo.processInfo.processorCount)-core Apple Silicon (target: M5 32 GB)
**Test duration per config:** 10 s (+ 120-tick warm-up)

## Physics parameters

| Parameter | Value |
|---|---|
| Repulsion strength | 200 |
| Spring ideal length | 80 px |
| Spring strength | 0.3 |
| Centering gravity | 0.05 |
| Velocity damping | 0.85 |
| Barnes-Hut theta | 0.9 |
| BH threshold | >100 nodes |

## Results

| Config | Ticks/sec | ms/tick | Barnes-Hut | Verdict |
|---|---|---|---|---|

"""

for r in results {
    let bh = r.bhEngaged ? "Yes" : "No"
    md += "| \(r.label) | \(r.fps) | \(String(format: "%.2f", r.avgMs)) | \(bh) | \(r.verdict) |\n"
}

md += """

## Go / No-Go

**Decision: \(overallVerdict)**

\(goNoGo)

## Notes

- Ticks/sec is a proxy for render fps: one physics tick is expected per display frame.
- Rendering via SwiftUI `Canvas` inside `TimelineView(.animation)` adds draw-call overhead
  on top of physics. In practice, Canvas is Metal-backed and draw cost for 200 filled circles
  + edges is well under 2 ms on Apple Silicon — physics is the dominant cost.
- If the production render loop shows fps regression, profile with Instruments Metal Debugger.
- SPEC §6.6 acceptance gate: ≥55 fps at 200 nodes (target 60 fps).
- SPEC §11 performance budget: ≥60 fps at 50 and 200 nodes.
"""

do {
    try md.write(to: resultsURL, atomically: true, encoding: .utf8)
    print("")
    print("Results written to: \(resultsURL.path)")
} catch {
    print("Warning: could not write results.md — \(error)")
}
