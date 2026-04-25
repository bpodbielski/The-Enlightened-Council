import XCTest

// MARK: - Minimal inline ForceSimulation for spec-compliance test
// This is a self-contained copy of the physics model from SPEC §6.6.
// It does NOT import or reference the Spike target.

private struct TestSimNode {
    var pos: SIMD2<Double>
    var vel: SIMD2<Double>
    var pinned: Bool = false
}

private struct TestSimEdge {
    let a: Int
    let b: Int
}

private struct TestSeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 1 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state &* 0x2545F491_4F6CDD1D
    }
}

// Barnes-Hut quad-tree node
private final class TestBHNode {
    let bx: Double
    let by: Double
    let bsize: Double

    var cmX: Double = 0
    var cmY: Double = 0
    var mass: Int = 0
    var bodyIndex: Int = -1

    var nw: TestBHNode?
    var ne: TestBHNode?
    var sw: TestBHNode?
    var se: TestBHNode?

    init(bx: Double, by: Double, bsize: Double) {
        self.bx = bx
        self.by = by
        self.bsize = bsize
    }

    func insert(idx: Int, px: Double, py: Double, positions: UnsafePointer<SIMD2<Double>>) {
        guard mass > 0 else {
            bodyIndex = idx; cmX = px; cmY = py; mass = 1; return
        }
        let newMass = mass + 1
        cmX = (cmX * Double(mass) + px) / Double(newMass)
        cmY = (cmY * Double(mass) + py) / Double(newMass)
        mass = newMass
        if bodyIndex >= 0 {
            let ei = bodyIndex
            let ep = positions[ei]
            bodyIndex = -1
            child(for: ep.x, ep.y).insert(idx: ei, px: ep.x, py: ep.y, positions: positions)
        }
        child(for: px, py).insert(idx: idx, px: px, py: py, positions: positions)
    }

    func force(for idx: Int, px: Double, py: Double, theta: Double, strength: Double) -> (Double, Double) {
        guard mass > 0 else { return (0, 0) }
        if bodyIndex == idx { return (0, 0) }
        let dx = cmX - px, dy = cmY - py
        let d2 = dx * dx + dy * dy
        guard d2 > 0.25 else { return (0, 0) }
        let d = d2.squareRoot()
        if bodyIndex >= 0 {
            let f = strength / d2
            return (-f * dx / d, -f * dy / d)
        }
        if bsize / d < theta {
            let f = strength * Double(mass) / d2
            return (-f * dx / d, -f * dy / d)
        }
        var dvx = 0.0, dvy = 0.0
        for child in [nw, ne, sw, se] {
            guard let child else { continue }
            let (fx, fy) = child.force(for: idx, px: px, py: py, theta: theta, strength: strength)
            dvx += fx; dvy += fy
        }
        return (dvx, dvy)
    }

    private func child(for px: Double, _ py: Double) -> TestBHNode {
        let half = bsize / 2, midX = bx + half, midY = by + half
        if px < midX {
            if py < midY { if nw == nil { nw = TestBHNode(bx: bx, by: by, bsize: half) }; return nw! }
            else { if sw == nil { sw = TestBHNode(bx: bx, by: midY, bsize: half) }; return sw! }
        } else {
            if py < midY { if ne == nil { ne = TestBHNode(bx: midX, by: by, bsize: half) }; return ne! }
            else { if se == nil { se = TestBHNode(bx: midX, by: midY, bsize: half) }; return se! }
        }
    }
}

private final class TestForceSimulation {
    let repulsionStrength: Double = 200
    let springIdeal: Double = 80
    let springStrength: Double = 0.3
    let centeringStrength: Double = 0.05
    let damping: Double = 0.85
    let theta: Double = 0.9
    let canvasSize: Double = 800

    var nodes: [TestSimNode]
    var edges: [TestSimEdge]
    private var positions: [SIMD2<Double>]

    private var useBarnesHut: Bool { nodes.count > 100 }

    init(nodeCount: Int, seed: UInt64 = 42) {
        var rng = TestSeededRNG(seed: seed)
        nodes = (0 ..< nodeCount).map { _ in
            TestSimNode(
                pos: SIMD2(
                    Double.random(in: 100 ... 700, using: &rng),
                    Double.random(in: 100 ... 700, using: &rng)
                ),
                vel: .zero
            )
        }
        var edgeSet = Set<Int64>()
        let targetEdges = max(nodeCount * 3 / 2, 1)
        while edgeSet.count < targetEdges {
            let a = Int(UInt64.random(in: 0 ..< UInt64(nodeCount), using: &rng))
            let b = Int(UInt64.random(in: 0 ..< UInt64(nodeCount), using: &rng))
            guard a != b else { continue }
            let key = Int64(min(a, b)) << 32 | Int64(max(a, b))
            edgeSet.insert(key)
        }
        edges = edgeSet.map { key in TestSimEdge(a: Int(key >> 32), b: Int(key & 0xFFFF_FFFF)) }
        positions = nodes.map(\.pos)
    }

    func tick() {
        let n = nodes.count
        let center = SIMD2<Double>(canvasSize / 2, canvasSize / 2)

        if useBarnesHut {
            applyRepulsionBarnesHut()
        } else {
            applyRepulsionNaive()
        }

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

        for i in 0 ..< n {
            guard !nodes[i].pinned else { continue }
            nodes[i].vel += (center - nodes[i].pos) * centeringStrength
            nodes[i].vel *= damping
            nodes[i].pos += nodes[i].vel
        }
    }

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
        for i in nodes.indices { positions[i] = nodes[i].pos }
        let root = TestBHNode(bx: minX, by: minY, bsize: size)
        positions.withUnsafeBufferPointer { buf in
            let ptr = buf.baseAddress!
            for i in nodes.indices {
                root.insert(idx: i, px: positions[i].x, py: positions[i].y, positions: ptr)
            }
            for i in nodes.indices {
                let (dvx, dvy) = root.force(
                    for: i, px: positions[i].x, py: positions[i].y,
                    theta: theta, strength: repulsionStrength
                )
                nodes[i].vel += SIMD2(dvx, dvy)
            }
        }
    }
}

// MARK: - Tests

final class ForceSimulationTests: XCTestCase {

    // MARK: - test_forceSimulation_200nodes_meetsFrameRateBudget

    func test_forceSimulation_200nodes_meetsFrameRateBudget() {
        // SPEC §11 performance budget: 600 ticks (10 s at 60 fps) must complete in < 10 seconds
        let sim = TestForceSimulation(nodeCount: 200)
        let start = Date()
        for _ in 0 ..< 600 {
            sim.tick()
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 10.0,
            "600 ticks with 200 nodes took \(elapsed)s — exceeds 10s frame-rate budget from SPEC §11")
    }
}
