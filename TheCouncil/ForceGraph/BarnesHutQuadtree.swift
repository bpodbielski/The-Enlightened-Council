// BarnesHutQuadtree.swift — Barnes-Hut quad-tree for O(n log n) repulsion.
//
// Coordinate system: origin at top-left, x increases right, y increases down.
// Quadrant layout:
//   NW = top-left    NE = top-right
//   SW = bottom-left SE = bottom-right

import Foundation

// MARK: - Tree node

final class BHNode {
    let bx: Double
    let by: Double
    let bsize: Double

    var cmX: Double = 0
    var cmY: Double = 0
    var mass: Int = 0

    // >= 0 → leaf containing that body index; -1 → internal / empty
    var bodyIndex: Int = -1

    var nw: BHNode?
    var ne: BHNode?
    var sw: BHNode?
    var se: BHNode?

    init(bx: Double, by: Double, bsize: Double) {
        self.bx = bx
        self.by = by
        self.bsize = bsize
    }

    // MARK: Insert

    func insert(idx: Int, px: Double, py: Double, positions: UnsafePointer<SIMD2<Double>>) {
        guard mass > 0 else {
            bodyIndex = idx
            cmX = px
            cmY = py
            mass = 1
            return
        }

        let newMass = mass + 1
        cmX = (cmX * Double(mass) + px) / Double(newMass)
        cmY = (cmY * Double(mass) + py) / Double(newMass)
        mass = newMass

        if bodyIndex >= 0 {
            let existingIdx = bodyIndex
            let ep = positions[existingIdx]
            bodyIndex = -1
            child(for: ep.x, ep.y).insert(idx: existingIdx, px: ep.x, py: ep.y, positions: positions)
        }

        child(for: px, py).insert(idx: idx, px: px, py: py, positions: positions)
    }

    // MARK: Force query

    func force(
        for idx: Int,
        px: Double,
        py: Double,
        theta: Double,
        strength: Double
    ) -> (dvx: Double, dvy: Double) {
        guard mass > 0 else { return (0, 0) }
        if bodyIndex == idx { return (0, 0) }

        let dx = cmX - px
        let dy = cmY - py
        let d2 = dx * dx + dy * dy
        guard d2 > 0.25 else { return (0, 0) }

        let d = d2.squareRoot()

        if bodyIndex >= 0 {
            let f = strength / d2
            return (-f * dx / d, -f * dy / d)
        }

        // Barnes-Hut criterion: treat as single mass when size/d < theta
        if bsize / d < theta {
            let f = strength * Double(mass) / d2
            return (-f * dx / d, -f * dy / d)
        }

        var dvx = 0.0, dvy = 0.0
        for child in [nw, ne, sw, se] {
            guard let child else { continue }
            let (fx, fy) = child.force(for: idx, px: px, py: py, theta: theta, strength: strength)
            dvx += fx
            dvy += fy
        }
        return (dvx, dvy)
    }

    // MARK: Private

    private func child(for px: Double, _ py: Double) -> BHNode {
        let half = bsize / 2
        let midX = bx + half
        let midY = by + half
        if px < midX {
            if py < midY {
                if nw == nil { nw = BHNode(bx: bx, by: by, bsize: half) }
                return nw!
            } else {
                if sw == nil { sw = BHNode(bx: bx, by: midY, bsize: half) }
                return sw!
            }
        } else {
            if py < midY {
                if ne == nil { ne = BHNode(bx: midX, by: by, bsize: half) }
                return ne!
            } else {
                if se == nil { se = BHNode(bx: midX, by: midY, bsize: half) }
                return se!
            }
        }
    }
}
