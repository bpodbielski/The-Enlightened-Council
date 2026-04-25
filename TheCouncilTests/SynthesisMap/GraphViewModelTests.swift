import XCTest
@testable import TheCouncil

@MainActor
final class GraphViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeArguments(count: Int) -> [Argument] {
        (0 ..< count).map { i in
            Argument(
                id: "arg-\(i)",
                decisionId: "decision-1",
                sourceRunId: "run-1",
                position: [ArgumentPosition.for, .against, .neutral][i % 3],
                text: "Argument text \(i)",
                clusterId: nil,
                prominence: Double(i + 1) / Double(count)
            )
        }
    }

    private func makeClusters(count: Int) -> ([ClusterSummary], [ClusterAssignment]) {
        let summaries = (0 ..< count).map { i in
            ClusterSummary(index: i, centroid: [], representativeText: "Cluster \(i)", count: 1, prominence: 1.0 / Double(count))
        }
        return (summaries, [])
    }

    // MARK: - Tests

    func test_addToTray_appendsItem() {
        let vm = GraphViewModel()
        let args = makeArguments(count: 3)
        let (clusters, assignments) = makeClusters(count: 1)
        vm.load(arguments: args, clusters: clusters, assignments: assignments, decisionId: "d1")

        vm.addToTray(nodeId: "arg-0")

        XCTAssertEqual(vm.trayItems.count, 1)
        XCTAssertEqual(vm.trayItems.first?.nodeId, "arg-0")
    }

    func test_addToTray_doesNotDuplicate() {
        let vm = GraphViewModel()
        let args = makeArguments(count: 2)
        let (clusters, assignments) = makeClusters(count: 1)
        vm.load(arguments: args, clusters: clusters, assignments: assignments, decisionId: "d1")

        vm.addToTray(nodeId: "arg-0")
        vm.addToTray(nodeId: "arg-0")

        XCTAssertEqual(vm.trayItems.count, 1)
    }

    func test_removeFromTray_removesItem() {
        let vm = GraphViewModel()
        let args = makeArguments(count: 3)
        let (clusters, assignments) = makeClusters(count: 1)
        vm.load(arguments: args, clusters: clusters, assignments: assignments, decisionId: "d1")

        vm.addToTray(nodeId: "arg-0")
        vm.addToTray(nodeId: "arg-1")
        guard let item = vm.trayItems.first else { XCTFail("No tray item"); return }
        vm.removeFromTray(itemId: item.id)

        XCTAssertEqual(vm.trayItems.count, 1)
        XCTAssertFalse(vm.trayItems.contains { $0.nodeId == item.nodeId })
    }

    func test_addToTray_pinsNodeInSimulation() {
        let vm = GraphViewModel()
        let args = makeArguments(count: 2)
        let (clusters, assignments) = makeClusters(count: 1)
        vm.load(arguments: args, clusters: clusters, assignments: assignments, decisionId: "d1")

        vm.addToTray(nodeId: "arg-0")

        let pinnedNode = vm.simulation.nodes.first { $0.id == "arg-0" }
        XCTAssertEqual(pinnedNode?.pinned, true)
    }

    func test_removeFromTray_unpinsNode() {
        let vm = GraphViewModel()
        let args = makeArguments(count: 2)
        let (clusters, assignments) = makeClusters(count: 1)
        vm.load(arguments: args, clusters: clusters, assignments: assignments, decisionId: "d1")

        vm.addToTray(nodeId: "arg-0")
        guard let item = vm.trayItems.first else { XCTFail(); return }
        vm.removeFromTray(itemId: item.id)

        let node = vm.simulation.nodes.first { $0.id == "arg-0" }
        XCTAssertEqual(node?.pinned, false)
    }

    func test_graphStateJSON_roundTrip() throws {
        let states: [GraphNodeState] = [
            GraphNodeState(id: "n1", x: 100, y: 200, pinned: true),
            GraphNodeState(id: "n2", x: 300, y: 400, pinned: false),
        ]
        let data = try JSONEncoder().encode(states)
        let decoded = try JSONDecoder().decode([GraphNodeState].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].id, "n1")
        XCTAssertEqual(decoded[0].x, 100)
        XCTAssertEqual(decoded[0].pinned, true)
        XCTAssertEqual(decoded[1].pinned, false)
    }

    func test_filter_hiddenNodesExcluded() {
        let vm = GraphViewModel()
        let args = makeArguments(count: 6)
        let (clusters, assignments) = makeClusters(count: 1)
        vm.load(arguments: args, clusters: clusters, assignments: assignments, decisionId: "d1")

        vm.filter.positions = ["for"]

        let visible = vm.graphNodes.filter { vm.isVisible($0) }
        XCTAssertTrue(visible.allSatisfy { $0.position == .for })
    }

    func test_filterClear_showsAll() {
        let vm = GraphViewModel()
        let args = makeArguments(count: 6)
        let (clusters, assignments) = makeClusters(count: 1)
        vm.load(arguments: args, clusters: clusters, assignments: assignments, decisionId: "d1")

        vm.filter.positions = ["for"]
        vm.filter.positions = []

        let visible = vm.graphNodes.filter { vm.isVisible($0) }
        XCTAssertEqual(visible.count, 6)
    }
}
