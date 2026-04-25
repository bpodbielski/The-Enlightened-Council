import Foundation
import SwiftUI
import Observation

// MARK: - Graph node (view model layer)

struct GraphNode: Sendable, Identifiable {
    let id: String           // == Argument.id
    let argumentId: String
    let text: String
    let position: ArgumentPosition
    let modelId: String
    let personaId: String
    let round: Int
    let prominence: Double
    let clusterId: String?

    // Computed display properties
    var radius: Double { max(6, min(20, prominence * 30)) }

    // 4-color palette consistent per model id, SPEC §6.6
    static let modelColors: [Color] = [
        Color(red: 0.31, green: 0.55, blue: 0.87),  // blue
        Color(red: 0.87, green: 0.55, blue: 0.31),  // orange
        Color(red: 0.40, green: 0.78, blue: 0.50),  // green
        Color(red: 0.78, green: 0.40, blue: 0.78),  // purple
    ]
}

// MARK: - Tray item

struct TrayItem: Sendable, Identifiable {
    let id: String
    let nodeId: String
    let text: String
    let position: ArgumentPosition
    let modelId: String
}

// MARK: - Graph state for persistence

struct GraphNodeState: Codable, Sendable {
    let id: String
    let x: Double
    let y: Double
    let pinned: Bool
}

// MARK: - Filter state

struct GraphFilter: Equatable, Sendable {
    var models: Set<String> = []      // empty = show all
    var personas: Set<String> = []
    var rounds: Set<Int> = []
    var positions: Set<String> = []

    func isVisible(_ node: GraphNode) -> Bool {
        if !models.isEmpty, !models.contains(node.modelId) { return false }
        if !personas.isEmpty, !personas.contains(node.personaId) { return false }
        if !rounds.isEmpty, !rounds.contains(node.round) { return false }
        if !positions.isEmpty, !positions.contains(node.position.rawValue) { return false }
        return true
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class GraphViewModel {

    // MARK: - Sim state (read by GraphView)
    private(set) var simNodes: [SimNode] = []
    private(set) var graphNodes: [GraphNode] = []
    private(set) var edges: [SimEdge] = []

    // MARK: - Filter
    var filter: GraphFilter = GraphFilter()

    // MARK: - Tray
    private(set) var trayItems: [TrayItem] = []

    // MARK: - FPS monitor for fallback
    private(set) var fps: Double = 60
    var showColumnFallback: Bool = false
    var useColumnView: Bool = false
    private var lowFpsCount: Int = 0

    // MARK: - Detail panel
    var selectedNodeId: String? = nil

    var selectedNode: GraphNode? {
        guard let id = selectedNodeId else { return nil }
        return graphNodes.first { $0.id == id }
    }

    // MARK: - Physics sim
    let simulation: ForceSimulation = ForceSimulation()

    // MARK: - Decision folder for persistence
    private var decisionId: String = ""

    // MARK: - Load

    func load(arguments: [Argument], clusters: [ClusterSummary], assignments: [ClusterAssignment], decisionId: String) {
        self.decisionId = decisionId
        buildGraph(arguments: arguments, clusters: clusters, assignments: assignments)
        loadPersistedState()
    }

    private func buildGraph(arguments: [Argument], clusters: [ClusterSummary], assignments: [ClusterAssignment]) {
        // Build node list
        var rng = SeededRNG(seed: 42)
        let canvasW = simulation.canvasSize.x
        let canvasH = simulation.canvasSize.y

        let clusterMap = Dictionary(uniqueKeysWithValues: assignments.map { ($0.argumentId, $0.clusterIndex) })

        graphNodes = arguments.map { arg in
            let clusterIdx = clusterMap[arg.id]
            let cluster = clusterIdx.flatMap { idx in clusters.first { $0.index == idx } }
            return GraphNode(
                id: arg.id,
                argumentId: arg.id,
                text: arg.text,
                position: arg.position,
                modelId: "",          // populated when run data is available
                personaId: "",
                round: 1,
                prominence: cluster?.prominence ?? arg.prominence,
                clusterId: clusterIdx.map { String($0) }
            )
        }

        simNodes = arguments.map { arg in
            let x = Double.random(in: canvasW * 0.2 ... canvasW * 0.8, using: &rng)
            let y = Double.random(in: canvasH * 0.2 ... canvasH * 0.8, using: &rng)
            return SimNode(id: arg.id, argumentId: arg.id, pos: SIMD2(x, y))
        }
        simulation.nodes = simNodes
        simulation.edges = buildEdges(from: arguments, clusters: clusters, assignments: assignments)
        self.edges = simulation.edges
    }

    private func buildEdges(from arguments: [Argument], clusters: [ClusterSummary], assignments: [ClusterAssignment]) -> [SimEdge] {
        let clusterMap = Dictionary(uniqueKeysWithValues: assignments.map { ($0.argumentId, $0.clusterIndex) })
        var result: [SimEdge] = []

        // Same cluster → agreement edge
        for i in 0 ..< arguments.count {
            for j in (i + 1) ..< arguments.count {
                let ai = arguments[i]
                let aj = arguments[j]
                guard let ci = clusterMap[ai.id], let cj = clusterMap[aj.id] else { continue }
                if ci == cj {
                    result.append(SimEdge(a: i, b: j, kind: .agreement))
                } else if ai.position != aj.position {
                    result.append(SimEdge(a: i, b: j, kind: .rebuttal))
                }
            }
        }
        return result
    }

    // MARK: - Tick (called each frame by GraphView)

    func tick(frameTimestamp: Double) {
        // Snapshot pinned state from graph nodes into sim
        for i in simulation.nodes.indices {
            let id = simulation.nodes[i].id
            if let trayItem = trayItems.first(where: { $0.nodeId == id }) {
                _ = trayItem // node pinned via tray
                simulation.nodes[i].pinned = true
            }
        }
        simulation.tick()
        simNodes = simulation.nodes
    }

    func recordFPS(_ fps: Double) {
        self.fps = fps
        if fps < 30 {
            lowFpsCount += 1
            if lowFpsCount > 180 { // 3 seconds at 60fps
                showColumnFallback = true
            }
        } else {
            lowFpsCount = 0
        }
    }

    // MARK: - Canvas size

    func updateCanvasSize(_ size: CGSize) {
        simulation.canvasSize = SIMD2(Double(size.width), Double(size.height))
    }

    // MARK: - Node interactions

    func drag(nodeId: String, to point: CGPoint) {
        guard let idx = simulation.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        simulation.nodes[idx].pos = SIMD2(Double(point.x), Double(point.y))
        simulation.nodes[idx].vel = .zero
        simulation.nodes[idx].pinned = true
    }

    func select(nodeId: String?) {
        selectedNodeId = nodeId
    }

    // MARK: - Tray management

    func addToTray(nodeId: String) {
        guard !trayItems.contains(where: { $0.nodeId == nodeId }),
              let node = graphNodes.first(where: { $0.id == nodeId }) else { return }
        trayItems.append(TrayItem(
            id: UUID().uuidString,
            nodeId: nodeId,
            text: node.text,
            position: node.position,
            modelId: node.modelId
        ))
        // Pin the node in the simulation
        if let idx = simulation.nodes.firstIndex(where: { $0.id == nodeId }) {
            simulation.nodes[idx].pinned = true
        }
    }

    func removeFromTray(itemId: String) {
        guard let item = trayItems.first(where: { $0.id == itemId }) else { return }
        trayItems.removeAll { $0.id == itemId }
        // Unpin if no other tray reference
        if !trayItems.contains(where: { $0.nodeId == item.nodeId }),
           let idx = simulation.nodes.firstIndex(where: { $0.id == item.nodeId }) {
            simulation.nodes[idx].pinned = false
        }
    }

    // MARK: - Filter helpers

    var allModelIds: [String] { Array(Set(graphNodes.map(\.modelId))).sorted() }
    var allPersonaIds: [String] { Array(Set(graphNodes.map(\.personaId))).sorted() }
    var allRounds: [Int] { Array(Set(graphNodes.map(\.round))).sorted() }

    func isVisible(_ node: GraphNode) -> Bool { filter.isVisible(node) }

    // MARK: - Persistence

    func saveGraphState() {
        let states = simulation.nodes.map { n in
            GraphNodeState(id: n.id, x: n.pos.x, y: n.pos.y, pinned: n.pinned)
        }
        guard let data = try? JSONEncoder().encode(states) else { return }
        let url = graphStateURL()
        try? data.write(to: url)
    }

    private func loadPersistedState() {
        let url = graphStateURL()
        guard let data = try? Data(contentsOf: url),
              let states = try? JSONDecoder().decode([GraphNodeState].self, from: data) else { return }
        let stateMap = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0) })
        for i in simulation.nodes.indices {
            let id = simulation.nodes[i].id
            if let s = stateMap[id] {
                simulation.nodes[i].pos = SIMD2(s.x, s.y)
                simulation.nodes[i].pinned = s.pinned
            }
        }
        simNodes = simulation.nodes
    }

    private func graphStateURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = appSupport
            .appendingPathComponent("The Council")
            .appendingPathComponent("decisions")
            .appendingPathComponent(decisionId)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("graph-state.json")
    }
}
