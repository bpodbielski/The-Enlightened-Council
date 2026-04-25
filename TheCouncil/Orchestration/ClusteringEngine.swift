import Foundation

// MARK: - Embedder protocol

/// Vector embedder for argument clustering. SPEC §6.4: OpenAI
/// `text-embedding-3-small` in cloud mode, MLX sentence-transformers in
/// air gap mode. The protocol lets us inject a deterministic embedder in
/// tests without stubbing the network.
protocol Embedder: Sendable {
    func embed(_ texts: [String]) async throws -> [[Float]]
}

// MARK: - Clustering output

struct ClusterAssignment: Sendable, Equatable {
    let argumentId: String
    let clusterIndex: Int
}

struct ClusterSummary: Sendable, Equatable {
    let index: Int
    let centroid: [Float]
    let representativeText: String
    let count: Int
    let prominence: Double
}

struct ClusteringResult: Sendable {
    let clusters: [ClusterSummary]
    let assignments: [ClusterAssignment]
}

// MARK: - Engine

/// k-means clustering over argument embeddings. Picks `k` via the elbow
/// heuristic within `[2, 8]`. For very small inputs (`n < 2`) collapses
/// to a single-cluster result.
actor ClusteringEngine {

    func cluster(arguments: [Argument], embedder: Embedder) async throws -> ClusteringResult {
        guard !arguments.isEmpty else {
            return ClusteringResult(clusters: [], assignments: [])
        }
        let texts = arguments.map { $0.text }
        let vectors = try await embedder.embed(texts)
        precondition(vectors.count == arguments.count, "Embedder returned wrong vector count")

        let minK = 2
        let maxK = min(8, arguments.count)

        // Degenerate case: fewer than `minK` arguments → one cluster.
        if arguments.count < minK {
            let centroid = Self.mean(of: vectors)
            let rep = arguments.first!.text
            return ClusteringResult(
                clusters: [ClusterSummary(
                    index: 0,
                    centroid: centroid,
                    representativeText: rep,
                    count: arguments.count,
                    prominence: 1.0
                )],
                assignments: arguments.map { ClusterAssignment(argumentId: $0.id, clusterIndex: 0) }
            )
        }

        // Sweep k in [minK, maxK], record inertia, pick elbow.
        var runs: [(k: Int, inertia: Double, centroids: [[Float]], labels: [Int])] = []
        for k in minK...maxK {
            let res = Self.kMeans(vectors: vectors, k: k, iterations: 40, seed: 42)
            runs.append((k, res.inertia, res.centroids, res.labels))
        }
        let chosen = Self.elbow(runs: runs.map { ($0.k, $0.inertia) })
        let best = runs.first { $0.k == chosen } ?? runs[0]

        let assignments = zip(arguments, best.labels).map { ClusterAssignment(argumentId: $0.0.id, clusterIndex: $0.1) }

        var summaries: [ClusterSummary] = []
        for idx in 0..<best.k {
            let memberIdxs = best.labels.enumerated().compactMap { $0.element == idx ? $0.offset : nil }
            guard !memberIdxs.isEmpty else { continue }
            let centroid = best.centroids[idx]
            var repIdx = memberIdxs[0]
            var bestDist = Double.infinity
            for mi in memberIdxs {
                let d = Self.sqDistance(vectors[mi], centroid)
                if d < bestDist { bestDist = d; repIdx = mi }
            }
            summaries.append(ClusterSummary(
                index: idx,
                centroid: centroid,
                representativeText: arguments[repIdx].text,
                count: memberIdxs.count,
                prominence: Double(memberIdxs.count) / Double(arguments.count)
            ))
        }
        return ClusteringResult(clusters: summaries, assignments: assignments)
    }

    // MARK: - k-means

    struct KMeansResult {
        let centroids: [[Float]]
        let labels: [Int]
        let inertia: Double
    }

    static func kMeans(vectors: [[Float]], k: Int, iterations: Int, seed: UInt64) -> KMeansResult {
        let n = vectors.count
        precondition(k > 0 && k <= n)
        var rng = SplitMix64(seed: seed)

        // k-means++ seeding
        var centroids: [[Float]] = []
        let firstIdx = Int(rng.next() % UInt64(n))
        centroids.append(vectors[firstIdx])
        while centroids.count < k {
            let dists = vectors.map { v -> Double in
                centroids.map { sqDistance(v, $0) }.min() ?? 0
            }
            let total = dists.reduce(0.0, +)
            if total == 0 { centroids.append(vectors[Int(rng.next() % UInt64(n))]); continue }
            let r = Double(rng.next()) / Double(UInt64.max) * total
            var acc = 0.0
            var pick = 0
            for (i, d) in dists.enumerated() {
                acc += d
                if acc >= r { pick = i; break }
            }
            centroids.append(vectors[pick])
        }

        var labels = [Int](repeating: 0, count: n)
        for _ in 0..<iterations {
            var changed = false
            for (i, v) in vectors.enumerated() {
                var bestK = 0
                var bestD = Double.infinity
                for (ki, c) in centroids.enumerated() {
                    let d = sqDistance(v, c)
                    if d < bestD { bestD = d; bestK = ki }
                }
                if labels[i] != bestK { changed = true; labels[i] = bestK }
            }
            // Recompute centroids
            for ki in 0..<k {
                let members = vectors.enumerated().compactMap { labels[$0.offset] == ki ? $0.element : nil }
                if !members.isEmpty { centroids[ki] = mean(of: members) }
            }
            if !changed { break }
        }
        let inertia = zip(vectors, labels).reduce(0.0) { $0 + sqDistance($1.0, centroids[$1.1]) }
        return KMeansResult(centroids: centroids, labels: labels, inertia: inertia)
    }

    /// Pick k at the "elbow": largest drop in inertia relative to the next
    /// step. For a smoothly-decreasing curve, returns the k where marginal
    /// improvement collapses.
    static func elbow(runs: [(k: Int, inertia: Double)]) -> Int {
        guard runs.count >= 2 else { return runs.first?.k ?? 2 }
        var bestK = runs[0].k
        var bestDelta = -Double.infinity
        // Drop from k to k+1
        for i in 0..<(runs.count - 1) {
            let drop = runs[i].inertia - runs[i + 1].inertia
            if drop > bestDelta { bestDelta = drop; bestK = runs[i + 1].k }
        }
        return bestK
    }

    // MARK: - Math

    static func sqDistance(_ a: [Float], _ b: [Float]) -> Double {
        var s = 0.0
        for i in 0..<min(a.count, b.count) {
            let d = Double(a[i] - b[i])
            s += d * d
        }
        return s
    }

    static func mean(of vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var acc = [Double](repeating: 0, count: first.count)
        for v in vectors {
            for i in 0..<min(acc.count, v.count) { acc[i] += Double(v[i]) }
        }
        let n = Double(vectors.count)
        return acc.map { Float($0 / n) }
    }
}

// MARK: - Deterministic RNG

/// SplitMix64 — stable across runs given the same seed, so k-means test
/// outcomes do not flake. Not cryptographically random.
private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
