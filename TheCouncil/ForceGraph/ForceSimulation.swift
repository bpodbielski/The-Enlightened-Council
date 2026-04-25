// ForceSimulation.swift — Verlet physics engine per SPEC §6.6.
//
// Physics model:
//   Repulsion:  F ∝ 1/d², strength 200   (Barnes-Hut at > 100 nodes, theta 0.9)
//   Spring:     ideal 80 px, strength 0.3
//   Centering:  gravity toward canvas centre, strength 0.05
//   Damping:    velocity × 0.85 per tick
//   Integration: x += vx, y += vy

import Foundation

// MARK: - Data types

struct SimNode: Sendable {
    var id: String
    var pos: SIMD2<Double>
    var vel: SIMD2<Double>
    var pinned: Bool
    var argumentId: String

    init(id: String, argumentId: String, pos: SIMD2<Double>) {
        self.id = id
        self.argumentId = argumentId
        self.pos = pos
        self.vel = .zero
        self.pinned = false
    }
}

struct SimEdge: Sendable {
    let a: Int
    let b: Int
    let kind: EdgeKind

    enum EdgeKind: Sendable {
        case agreement, rebuttal, tangent
    }
}

// MARK: - Simulation

final class ForceSimulation: @unchecked Sendable {

    // SPEC §6.6 physics parameters
    let repulsionStrength: Double = 200
    let springIdeal: Double = 80
    let springStrength: Double = 0.3
    let centeringStrength: Double = 0.05
    let damping: Double = 0.85
    let theta: Double = 0.9
    var canvasSize: SIMD2<Double> = SIMD2(800, 600)

    var nodes: [SimNode]
    var edges: [SimEdge]

    private var positionsScratch: [SIMD2<Double>]

    // Barnes-Hut engages automatically at > 100 nodes per SPEC §6.6
    private var useBarnesHut: Bool { nodes.count > 100 }

    // MARK: Init

    init(nodes: [SimNode] = [], edges: [SimEdge] = []) {
        self.nodes = nodes
        self.edges = edges
        self.positionsScratch = nodes.map(\.pos)
    }

    // MARK: - Tick

    func tick() {
        let n = nodes.count
        guard n > 0 else { return }

        if positionsScratch.count != n {
            positionsScratch = nodes.map(\.pos)
        }

        let center = canvasSize * 0.5

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

    // MARK: - Repulsion

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
        var minX = nodes[0].pos.x, maxX = nodes[0].pos.x
        var minY = nodes[0].pos.y, maxY = nodes[0].pos.y
        for n in nodes {
            minX = min(minX, n.pos.x); maxX = max(maxX, n.pos.x)
            minY = min(minY, n.pos.y); maxY = max(maxY, n.pos.y)
        }
        let pad = 10.0
        minX -= pad; minY -= pad
        let size = max(maxX - minX, maxY - minY) + pad * 2

        for i in nodes.indices { positionsScratch[i] = nodes[i].pos }

        let root = BHNode(bx: minX, by: minY, bsize: size)
        positionsScratch.withUnsafeBufferPointer { buf in
            let ptr = buf.baseAddress!
            for i in nodes.indices {
                root.insert(idx: i, px: positionsScratch[i].x, py: positionsScratch[i].y, positions: ptr)
            }
            for i in nodes.indices {
                let (dvx, dvy) = root.force(
                    for: i,
                    px: positionsScratch[i].x,
                    py: positionsScratch[i].y,
                    theta: theta,
                    strength: repulsionStrength
                )
                nodes[i].vel += SIMD2(dvx, dvy)
            }
        }
    }
}

// MARK: - Seeded RNG

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 1 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state &* 0x2545F491_4F6CDD1D
    }
}
