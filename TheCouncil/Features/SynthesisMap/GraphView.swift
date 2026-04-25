import SwiftUI

// MARK: - Edge colors per SPEC §6.6

private extension SimEdge.EdgeKind {
    var color: Color {
        switch self {
        case .agreement: return Color(red: 0.204, green: 0.780, blue: 0.349)  // #34C759
        case .rebuttal:  return Color(red: 1.000, green: 0.231, blue: 0.188)  // #FF3B30
        case .tangent:   return Color(red: 0.557, green: 0.557, blue: 0.576)  // #8E8E93
        }
    }
    var lineWidth: Double {
        switch self {
        case .agreement: return 1.5
        case .rebuttal:  return 1.5
        case .tangent:   return 1.0
        }
    }
    var isDashed: Bool { self == .tangent }
}

// MARK: - GraphView

struct GraphView: View {

    @Bindable var viewModel: GraphViewModel
    /// Optional callback when user taps "Capture Verdict →".
    /// Hidden when nil (e.g. read-only Map tab in Decision Detail).
    var onCaptureVerdict: (() -> Void)? = nil

    // Interaction state
    @State private var zoom: Double = 1.0
    @State private var pan: CGSize = .zero
    @State private var hoveredNodeId: String? = nil
    @State private var draggingNodeId: String? = nil
    @State private var lastFrameTime: Double = 0
    @State private var canvasSize: CGSize = .zero

    // Cluster sigma for outlier detection (populated after load)
    @State private var clusterSigmas: [String: Double] = [:]

    var body: some View {
        HStack(spacing: 0) {
            graphCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) { filterBar }
                .overlay(alignment: .topTrailing) { captureVerdictButton }
                .overlay(alignment: .bottom) { fpsWarning }
                .overlay(alignment: .trailing) {
                    if viewModel.selectedNode != nil { detailPanel }
                }

            VerdictTray(viewModel: viewModel)
                .frame(width: 240)
        }
    }

    @ViewBuilder
    private var captureVerdictButton: some View {
        if let onCaptureVerdict {
            Button {
                onCaptureVerdict()
            } label: {
                Label("Capture Verdict", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(8)
        }
    }

    // MARK: - Canvas

    private var graphCanvas: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let dt = lastFrameTime == 0 ? 0 : t - lastFrameTime

                // Tick physics (skipping first frame)
                if dt > 0 && dt < 0.1 {
                    viewModel.tick(frameTimestamp: t)
                }

                // FPS reporting
                if dt > 0 {
                    let currentFPS = 1.0 / dt
                    viewModel.recordFPS(currentFPS)
                }

                drawGraph(ctx: ctx, size: size)
            }
            .onChange(of: timeline.date) { _, _ in
                lastFrameTime = timeline.date.timeIntervalSinceReferenceDate
            }
        }
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
            canvasSize = size
            viewModel.updateCanvasSize(size)
        }
        .gesture(
            MagnificationGesture()
                .onChanged { zoom = max(0.25, min(4.0, $0)) }
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    if draggingNodeId == nil {
                        pan = CGSize(
                            width: pan.width + value.translation.width,
                            height: pan.height + value.translation.height
                        )
                    }
                }
        )
        .onTapGesture { location in
            let worldPt = screenToWorld(location)
            if let nodeId = hitTest(at: worldPt) {
                viewModel.select(nodeId: nodeId == viewModel.selectedNodeId ? nil : nodeId)
            } else {
                viewModel.select(nodeId: nil)
            }
        }
    }

    private func drawGraph(ctx: GraphicsContext, size: CGSize) {
        var ctx = ctx
        ctx.translateBy(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
        ctx.scaleBy(x: zoom, y: zoom)
        let offsetX = -size.width / 2
        let offsetY = -size.height / 2

        let simNodes = viewModel.simNodes
        let graphNodes = viewModel.graphNodes
        let nodeMap = Dictionary(uniqueKeysWithValues: simNodes.enumerated().map { ($1.id, $0) })

        // Pass 1: Edges
        let dashPattern: [CGFloat] = [4, 3]
        for edge in viewModel.edges {
            guard edge.a < simNodes.count, edge.b < simNodes.count else { continue }
            let na = simNodes[edge.a]
            let nb = simNodes[edge.b]
            let aNode = graphNodes.first { $0.id == na.id }
            let bNode = graphNodes.first { $0.id == nb.id }
            guard let aNode, let bNode else { continue }
            if !viewModel.isVisible(aNode) || !viewModel.isVisible(bNode) { continue }

            let ap = CGPoint(x: na.pos.x + offsetX, y: na.pos.y + offsetY)
            let bp = CGPoint(x: nb.pos.x + offsetX, y: nb.pos.y + offsetY)

            var path = Path()
            path.move(to: ap)
            path.addLine(to: bp)

            let stroke = GraphicsContext.Shading.color(edge.kind.color)
            if edge.kind.isDashed {
                ctx.stroke(path, with: stroke,
                           style: StrokeStyle(lineWidth: edge.kind.lineWidth, dash: dashPattern))
            } else {
                ctx.stroke(path, with: stroke,
                           style: StrokeStyle(lineWidth: edge.kind.lineWidth))
            }
        }

        // Pass 2: Node fills
        for (i, simNode) in simNodes.enumerated() {
            guard let graphNode = graphNodes.first(where: { $0.id == simNode.id }) else { continue }
            guard viewModel.isVisible(graphNode) else { continue }

            let cx = simNode.pos.x + offsetX
            let cy = simNode.pos.y + offsetY
            let r = graphNode.radius

            let colorIdx = abs(graphNode.modelId.hashValue) % GraphNode.modelColors.count
            let color = GraphNode.modelColors[colorIdx]

            let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            let circlePath = Path(ellipseIn: rect)

            ctx.fill(circlePath, with: .color(color))

            // Dashed border for outliers (placeholder: use prominence < 0.05 as heuristic)
            let isOutlier = graphNode.prominence < 0.05
            if isOutlier {
                ctx.stroke(circlePath, with: .color(.secondary),
                           style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            }

            // Selected node ring
            if viewModel.selectedNodeId == graphNode.id {
                ctx.stroke(circlePath, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2))
            }

            _ = i
        }

        // Pass 3: Labels (skip when radius < 8px at current zoom)
        let labelThreshold: Double = 8 / zoom
        for simNode in simNodes {
            guard let graphNode = graphNodes.first(where: { $0.id == simNode.id }) else { continue }
            guard viewModel.isVisible(graphNode) else { continue }
            guard graphNode.radius >= labelThreshold else { continue }

            let cx = simNode.pos.x + offsetX
            let cy = simNode.pos.y + offsetY

            let truncated = String(graphNode.text.prefix(30))
            let text = Text(truncated).font(.system(size: 9)).foregroundColor(.primary)
            ctx.draw(text, at: CGPoint(x: cx, y: cy + graphNode.radius + 5), anchor: .top)
        }
    }

    // MARK: - Hover tooltip (approximated via overlaid view)

    private func hitTest(at worldPoint: CGPoint) -> String? {
        for (i, simNode) in viewModel.simNodes.enumerated() {
            guard let graphNode = viewModel.graphNodes.first(where: { $0.id == simNode.id }),
                  viewModel.isVisible(graphNode) else { continue }
            let dx = worldPoint.x - simNode.pos.x
            let dy = worldPoint.y - simNode.pos.y
            if dx * dx + dy * dy <= graphNode.radius * graphNode.radius { return simNode.id }
            _ = i
        }
        return nil
    }

    private func screenToWorld(_ point: CGPoint) -> CGPoint {
        let cx = canvasSize.width / 2 + pan.width
        let cy = canvasSize.height / 2 + pan.height
        return CGPoint(
            x: (point.x - cx) / zoom + canvasSize.width / 2,
            y: (point.y - cy) / zoom + canvasSize.height / 2
        )
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            Menu("Rounds") {
                Button("All") { viewModel.filter.rounds = [] }
                ForEach([1, 2, 3], id: \.self) { r in
                    Button("Round \(r)") {
                        if viewModel.filter.rounds.contains(r) {
                            viewModel.filter.rounds.remove(r)
                        } else {
                            viewModel.filter.rounds.insert(r)
                        }
                    }
                }
            }
            Menu("Position") {
                Button("All") { viewModel.filter.positions = [] }
                ForEach(["for", "against", "neutral"], id: \.self) { p in
                    Button(p.capitalized) {
                        if viewModel.filter.positions.contains(p) {
                            viewModel.filter.positions.remove(p)
                        } else {
                            viewModel.filter.positions.insert(p)
                        }
                    }
                }
            }
            Spacer()
            Text(String(format: "%.0f fps", viewModel.fps))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial)
    }

    // MARK: - FPS warning

    @ViewBuilder
    private var fpsWarning: some View {
        if viewModel.showColumnFallback && !viewModel.useColumnView {
            HStack {
                Text("Performance low. Switch to column view?")
                    .font(.caption)
                Button("Switch") { viewModel.useColumnView = true }
                Button("Dismiss") { viewModel.showColumnFallback = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.thinMaterial)
            .cornerRadius(8)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Detail panel

    private var detailPanel: some View {
        Group {
            if let node = viewModel.selectedNode {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Argument")
                            .font(.headline)
                        Spacer()
                        Button { viewModel.select(nodeId: nil) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(node.text)
                        .font(.caption)
                        .lineLimit(8)
                    Divider()
                    Label(node.position.rawValue.capitalized, systemImage: positionIcon(node.position))
                        .font(.caption)
                        .foregroundStyle(positionColor(node.position))
                    Label("Round \(node.round)", systemImage: "arrow.circlepath")
                        .font(.caption)
                    Spacer()
                    Button("Add to Tray") { viewModel.addToTray(nodeId: node.id) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(viewModel.trayItems.contains { $0.nodeId == node.id })
                }
                .padding(12)
                .frame(width: 220)
                .background(.regularMaterial)
                .cornerRadius(10)
                .padding(12)
            }
        }
    }

    private func positionIcon(_ pos: ArgumentPosition) -> String {
        switch pos {
        case .for: return "hand.thumbsup"
        case .against: return "hand.thumbsdown"
        case .neutral: return "minus.circle"
        }
    }

    private func positionColor(_ pos: ArgumentPosition) -> Color {
        switch pos {
        case .for: return .green
        case .against: return .red
        case .neutral: return .secondary
        }
    }
}

// MARK: - VoiceOver accessibility list

struct GraphAccessibilityList: View {
    let viewModel: GraphViewModel

    var body: some View {
        List(viewModel.graphNodes.filter(viewModel.isVisible)) { node in
            VStack(alignment: .leading) {
                Text(node.text)
                Text("Position: \(node.position.rawValue) · Round \(node.round)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(node.position.rawValue) argument: \(node.text). Round \(node.round).")
        }
    }
}
