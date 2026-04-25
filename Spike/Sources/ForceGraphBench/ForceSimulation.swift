// ForceSimulation.swift — Verlet physics engine for The Council force-directed graph spike.
//
// Implements the physics model from SPEC §6.6:
//   1. Repulsion:   F ∝ 1/d², strength 200  (Barnes-Hut at >100 nodes, theta 0.9)
//   2. Spring:      ideal 80 px, strength 0.3
//   3. Centering:   gravity toward canvas center, strength 0.05
//   4. Damping:     velocity × 0.85 per tick
//   5. Integration: x += vx, y += vy
//
// This file is used only for the Week-1 spike; it will be superseded by
// ForceGraph/ForceSimulation.swift in the main app target.

import Foundation

// MARK: - Data types

struct SimNode {
    var pos: SIMD2<Double>
    var vel: SIMD2<Double>
    var pinned: Bool = false
}

struct SimEdge {
    let a: Int
    let b: Int
}

// MARK: - Simulation

final class ForceSimulation {

    // Physics parameters (SPEC §6.6)
    let repulsionStrength: Double = 200
    let springIdeal: Double = 80
    let springStrength: Double = 0.3
    let centeringStrength: Double = 0.05
    let damping: Double = 0.85
    let theta: Double = 0.9         // Barnes-Hut approximation threshold
    let canvasSize: Double = 800    // square canvas assumed

    var nodes: [SimNode]
    var edges: [SimEdge]

    private var positions: [SIMD2<Double>]  // scratch buffer for BH tree insertion

    // Barnes-Hut engages automatically at >100 nodes per SPEC §6.6
    private var useBarnesHut: Bool { nodes.count > 100 }

    // MARK: Init

    init(nodeCount: Int, seed: UInt64 = 42) {
        var rng = SeededRNG(seed: seed)

        nodes = (0 ..< nodeCount).map { _ in
            SimNode(
                pos: SIMD2(
                    Double.random(in: 100 ... 700, using: &rng),
                    Double.random(in: 100 ... 700, using: &rng)
                ),
                vel: .zero
            )
        }

        // Random edges — roughly 3 per node, no self-loops
        var edgeSet = Set<Int64>()
        let targetEdges = max(nodeCount * 3 / 2, 1)
        while edgeSet.count < targetEdges {
            let a = Int(UInt64.random(in: 0 ..< UInt64(nodeCount), using: &rng))
            let b = Int(UInt64.random(in: 0 ..< UInt64(nodeCount), using: &rng))
            guard a != b else { continue }
            let key = Int64(min(a, b)) << 32 | Int64(max(a, b))
            edgeSet.insert(key)
        }
        edges = edgeSet.map { key in
            SimEdge(a: Int(key >> 32), b: Int(key & 0xFFFF_FFFF))
        }

        positions = nodes.map(\.pos)
    }

    // MARK: Tick

    /// Advance the simulation by one step.
    /// Call once per display frame (≈16.67 ms at 60 fps).
    func tick() {
        let n = nodes.count
        let center = SIMD2<Double>(canvasSize / 2, canvasSize / 2)

        // Step 1 — Repulsion
        if useBarnesHut {
            applyRepulsionBarnesHut()
        } else {
            applyRepulsionNaive()
        }

        // Step 2 — Spring forces
        for edge in edges {
            let delta = nodes[edge.b].pos - nodes[edge.a].pos
            let d2 = (delta * delta).sum()
            guard d2 > 0.25 else { continue }
            let d = d2.squareRoot()
            let displacement = (d - springIdeal) * springStrength
            let f = delta / d * displacement
            nodes[edge.a].vel += f
            nodes[edge.b].vel -= f
        }

        // Step 3 — Centering + damping + integrate
        for i in 0 ..< n {
            guard !nodes[i].pinned else { continue }
            nodes[i].vel += (center - nodes[i].pos) * centeringStrength
            nodes[i].vel *= damping
            nodes[i].pos += nodes[i].vel
        }
    }

    // MARK: - Repulsion implementations

    private func applyRepulsionNaive() {
        let n = nodes.count
        for i in 0 ..< n {
            for j in (i + 1) ..< n {
                let delta = nodes[j].pos - nodes[i].pos
                let d2 = (delta * delta).sum()
                guard d2 > 0.25 else { continue }
                let d = d2.squareRoot()
                let f = repulsionStrength / d2
                let fv = delta / d * f
                nodes[i].vel -= fv
                nodes[j].vel += fv
            }
        }
    }

    private func applyRepulsionBarnesHut() {
        // Compute bounding box
        var minX = nodes[0].pos.x, maxX = nodes[0].pos.x
        var minY = nodes[0].pos.y, maxY = nodes[0].pos.y
        for n in nodes {
            minX = min(minX, n.pos.x); maxX = max(maxX, n.pos.x)
            minY = min(minY, n.pos.y); maxY = max(maxY, n.pos.y)
        }
        let pad = 10.0
        minX -= pad; minY -= pad
        let size = max(maxX - minX, maxY - minY) + pad * 2

        // Sync scratch buffer
        for i in nodes.indices { positions[i] = nodes[i].pos }

        // Build tree
        let root = BHNode(bx: minX, by: minY, bsize: size)
        positions.withUnsafeBufferPointer { buf in
            let ptr = buf.baseAddress!
            for i in nodes.indices {
                root.insert(idx: i, px: positions[i].x, py: positions[i].y, positions: ptr)
            }

            // Apply forces
            for i in nodes.indices {
                let (dvx, dvy) = root.force(
                    for: i,
                    px: positions[i].x,
                    py: positions[i].y,
                    theta: theta,
                    strength: repulsionStrength
                )
                nodes[i].vel += SIMD2(dvx, dvy)
            }
        }
    }
}

// MARK: - Seeded RNG (for reproducible benchmarks)

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 1 : seed }

    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state &* 0x2545F491_4F6CDD1D
    }
}
