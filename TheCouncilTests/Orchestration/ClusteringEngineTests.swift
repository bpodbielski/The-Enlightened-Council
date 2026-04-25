import Foundation
import XCTest
@testable import TheCouncil

private struct FixedEmbedder: Embedder {
    let vectors: [[Float]]
    func embed(_ texts: [String]) async throws -> [[Float]] { vectors }
}

final class ClusteringEngineTests: XCTestCase {

    private func arg(_ id: String, _ pos: ArgumentPosition, _ text: String) -> Argument {
        Argument(
            id: id, decisionId: "D", sourceRunId: "R",
            position: pos, text: text, clusterId: nil, prominence: 0
        )
    }

    // Three tight clusters in 2D
    private let threeClusterVectors: [[Float]] = [
        [0.0, 0.0], [0.01, 0.0], [0.0, 0.02],     // cluster at origin
        [10.0, 10.0], [10.1, 9.9], [9.9, 10.1],   // cluster at (10,10)
        [-8.0, 5.0], [-8.1, 5.1], [-7.9, 4.9]     // cluster at (-8,5)
    ]

    func test_cluster_findsElbowInReasonableRange() async throws {
        let args = (0..<9).map { arg("a\($0)", .for, "text\($0)") }
        let engine = ClusteringEngine()
        let out = try await engine.cluster(arguments: args, embedder: FixedEmbedder(vectors: threeClusterVectors))
        let kUsed = Set(out.assignments.map { $0.clusterIndex }).count
        XCTAssertGreaterThanOrEqual(kUsed, 2)
        XCTAssertLessThanOrEqual(kUsed, 8)
    }

    func test_cluster_prominenceSumsToOne() async throws {
        let args = (0..<9).map { arg("a\($0)", .for, "text\($0)") }
        let engine = ClusteringEngine()
        let out = try await engine.cluster(arguments: args, embedder: FixedEmbedder(vectors: threeClusterVectors))
        let sum = out.clusters.map { $0.prominence }.reduce(0.0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.0001)
    }

    func test_cluster_kClampedWhenFewerArgumentsThanMinK() async throws {
        // n=1 should not crash or produce invalid clusters
        let args = [arg("a1", .for, "only")]
        let engine = ClusteringEngine()
        let out = try await engine.cluster(arguments: args, embedder: FixedEmbedder(vectors: [[1.0, 1.0]]))
        XCTAssertEqual(out.assignments.count, 1)
        XCTAssertEqual(out.clusters.count, 1)
        XCTAssertEqual(out.clusters[0].prominence, 1.0, accuracy: 0.0001)
    }

    func test_cluster_representativeTextIsFromCluster() async throws {
        let args = (0..<9).map { arg("a\($0)", .for, "text\($0)") }
        let engine = ClusteringEngine()
        let out = try await engine.cluster(arguments: args, embedder: FixedEmbedder(vectors: threeClusterVectors))
        let allTexts = Set(args.map { $0.text })
        for c in out.clusters {
            XCTAssertTrue(allTexts.contains(c.representativeText))
        }
    }

    func test_kMeans_respectsMaxK8() async throws {
        // 20 random-ish vectors — k should never exceed 8
        var rng = SystemRandomNumberGenerator()
        let vectors: [[Float]] = (0..<20).map { _ in
            [Float.random(in: 0...100, using: &rng), Float.random(in: 0...100, using: &rng)]
        }
        let args = (0..<20).map { arg("a\($0)", .for, "t\($0)") }
        let engine = ClusteringEngine()
        let out = try await engine.cluster(arguments: args, embedder: FixedEmbedder(vectors: vectors))
        let kUsed = Set(out.assignments.map { $0.clusterIndex }).count
        XCTAssertLessThanOrEqual(kUsed, 8)
    }
}
