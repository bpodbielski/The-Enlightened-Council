import Foundation
import CoreText
import CoreGraphics
import AppKit

// MARK: - PDFRenderer
//
// Renders the SPEC §6.10 PDF: US Letter, system serif body, system monospace
// for model names, header (question + date + lens) + footer (model panel,
// cost, page X of Y) on every page.
//
// Implementation strategy: build a single NSAttributedString for the body,
// then walk the CTFramesetter, drawing successive frames into successive
// PDF pages. Each page also gets header + footer drawn outside the body
// rect.

enum PDFRenderer {

    // US Letter @ 72 dpi
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 54     // ~0.75"
    static let headerHeight: CGFloat = 60
    static let footerHeight: CGFloat = 48

    static func render(_ payload: ExportPayload) -> Data {
        let body = buildBody(payload)
        let bodyRect = CGRect(
            x: margin,
            y: margin + footerHeight,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2 - headerHeight - footerHeight
        )

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData),
              let cgctx = makePDFContext(consumer: consumer) else {
            return Data()
        }

        // First pass — count pages so the footer can read "Page X of Y".
        let pages = paginate(body: body, bodyRect: bodyRect)

        for (idx, range) in pages.enumerated() {
            cgctx.beginPDFPage(nil)

            // Header + footer in user-space (origin top-left flip).
            drawHeader(cgctx: cgctx, payload: payload)
            drawFooter(cgctx: cgctx, payload: payload, pageIndex: idx, pageCount: pages.count)

            // Body via CT.
            let framesetter = CTFramesetterCreateWithAttributedString(body as CFAttributedString)
            let path = CGPath(rect: bodyRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
            CTFrameDraw(frame, cgctx)

            cgctx.endPDFPage()
        }

        cgctx.closePDF()
        return pdfData as Data
    }

    // MARK: - Pagination

    /// Returns the CFRanges that exactly fill each page. Walks the framesetter
    /// in body-rect-sized chunks until the entire string has been laid out.
    private static func paginate(body: NSAttributedString, bodyRect: CGRect) -> [CFRange] {
        let framesetter = CTFramesetterCreateWithAttributedString(body as CFAttributedString)
        let total = CFAttributedStringGetLength(body)
        var ranges: [CFRange] = []
        var location = 0
        let path = CGPath(rect: bodyRect, transform: nil)

        // Safety cap so a pathological (zero-advance) string can't loop forever.
        let maxPages = 200
        var iteration = 0
        while location < total && iteration < maxPages {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            let consumed = max(visible.length, 1)
            ranges.append(CFRange(location: location, length: consumed))
            location += consumed
            iteration += 1
        }
        if ranges.isEmpty { ranges.append(CFRange(location: 0, length: 0)) }
        return ranges
    }

    // MARK: - Body content

    private static func buildBody(_ payload: ExportPayload) -> NSAttributedString {
        let body = NSMutableAttributedString()
        let v = payload.verdict
        let d = payload.decision

        let bodyFont = NSFont(name: "Times New Roman", size: 11) ?? .systemFont(ofSize: 11)
        let h2Font = NSFont.boldSystemFont(ofSize: 14)
        let labelFont = NSFont.boldSystemFont(ofSize: 11)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont]
        let h2Attrs: [NSAttributedString.Key: Any] = [.font: h2Font]
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont]
        let monoAttrs: [NSAttributedString.Key: Any] = [.font: monoFont, .foregroundColor: NSColor.secondaryLabelColor]

        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .none
        dateFmt.locale = Locale(identifier: "en_US_POSIX")

        // Top metadata
        body.append(NSAttributedString(string: "Date: ", attributes: labelAttrs))
        body.append(NSAttributedString(string: "\(dateFmt.string(from: v.createdAt))\n", attributes: bodyAttrs))
        body.append(NSAttributedString(string: "Lens: ", attributes: labelAttrs))
        body.append(NSAttributedString(string: "\(d.lensTemplate)\n", attributes: bodyAttrs))
        body.append(NSAttributedString(string: "Confidence: ", attributes: labelAttrs))
        body.append(NSAttributedString(string: "\(v.confidence)%\n", attributes: bodyAttrs))
        body.append(NSAttributedString(string: "Outcome deadline: ", attributes: labelAttrs))
        body.append(NSAttributedString(string: "\(dateFmt.string(from: v.outcomeDeadline))\n\n", attributes: bodyAttrs))

        appendSection(body, title: "Verdict", text: v.verdictText, h2: h2Attrs, body: bodyAttrs)
        appendBulletSection(body, title: "Arguments For",
                            items: VerdictCaptureViewModel.decodeArgumentTexts(v.keyForJson),
                            h2: h2Attrs, body: bodyAttrs)
        appendBulletSection(body, title: "Arguments Against",
                            items: VerdictCaptureViewModel.decodeArgumentTexts(v.keyAgainstJson),
                            h2: h2Attrs, body: bodyAttrs)
        appendSection(body, title: "Risk", text: v.risk, h2: h2Attrs, body: bodyAttrs)
        appendSection(body, title: "Blind Spot", text: v.blindSpot, h2: h2Attrs, body: bodyAttrs)
        appendSection(body, title: "Opportunity", text: v.opportunity, h2: h2Attrs, body: bodyAttrs)
        appendSection(body, title: "Pre-mortem", text: v.preMortem, h2: h2Attrs, body: bodyAttrs)

        body.append(NSAttributedString(string: "Test\n", attributes: h2Attrs))
        body.append(NSAttributedString(string: "Action: ", attributes: labelAttrs))
        body.append(NSAttributedString(string: "\(v.testAction)\n", attributes: bodyAttrs))
        body.append(NSAttributedString(string: "Metric: ", attributes: labelAttrs))
        body.append(NSAttributedString(string: "\(v.testMetric)\n", attributes: bodyAttrs))
        body.append(NSAttributedString(string: "Threshold: ", attributes: labelAttrs))
        body.append(NSAttributedString(string: "\(v.testThreshold)\n\n", attributes: bodyAttrs))

        if let outcome = payload.outcome,
           v.outcomeStatus.isTerminal,
           v.outcomeStatus != .dismissed {
            body.append(NSAttributedString(string: "Outcome\n", attributes: h2Attrs))
            body.append(NSAttributedString(string: "Result: ", attributes: labelAttrs))
            body.append(NSAttributedString(string: "\(outcome.result.rawValue.capitalized)\n", attributes: bodyAttrs))
            body.append(NSAttributedString(string: "Marked: ", attributes: labelAttrs))
            body.append(NSAttributedString(string: "\(dateFmt.string(from: outcome.markedAt))\n", attributes: bodyAttrs))
            if !outcome.actualNotes.isEmpty {
                body.append(NSAttributedString(string: "What happened: ", attributes: labelAttrs))
                body.append(NSAttributedString(string: "\(outcome.actualNotes)\n", attributes: bodyAttrs))
            }
            if !outcome.whatChanged.isEmpty {
                body.append(NSAttributedString(string: "What changed: ", attributes: labelAttrs))
                body.append(NSAttributedString(string: "\(outcome.whatChanged)\n", attributes: bodyAttrs))
            }
            body.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        }

        // Trailing run/cost summary in monospace
        body.append(NSAttributedString(
            string: "Model panel: \(payload.modelPanel.joined(separator: ", "))\n",
            attributes: monoAttrs))
        body.append(NSAttributedString(
            string: "Total cost: $\(String(format: "%.2f", payload.totalCostUsd))\n",
            attributes: monoAttrs))

        return body
    }

    private static func appendSection(
        _ acc: NSMutableAttributedString,
        title: String,
        text: String,
        h2: [NSAttributedString.Key: Any],
        body: [NSAttributedString.Key: Any]
    ) {
        acc.append(NSAttributedString(string: "\(title)\n", attributes: h2))
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        acc.append(NSAttributedString(string: "\(trimmed.isEmpty ? "(none)" : trimmed)\n\n", attributes: body))
    }

    private static func appendBulletSection(
        _ acc: NSMutableAttributedString,
        title: String,
        items: [String],
        h2: [NSAttributedString.Key: Any],
        body: [NSAttributedString.Key: Any]
    ) {
        acc.append(NSAttributedString(string: "\(title)\n", attributes: h2))
        if items.isEmpty {
            acc.append(NSAttributedString(string: "(none)\n\n", attributes: body))
        } else {
            for item in items {
                acc.append(NSAttributedString(string: "• \(item)\n", attributes: body))
            }
            acc.append(NSAttributedString(string: "\n", attributes: body))
        }
    }

    // MARK: - Header / Footer

    private static func drawHeader(cgctx: CGContext, payload: ExportPayload) {
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .none
        let header = "\(payload.decision.question)  ·  \(dateFmt.string(from: payload.verdict.createdAt))  ·  \(payload.decision.lensTemplate)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray
        ]
        let line = NSAttributedString(string: header, attributes: attrs)
        let rect = CGRect(
            x: margin,
            y: pageSize.height - headerHeight,
            width: pageSize.width - margin * 2,
            height: headerHeight
        )
        drawAttributedString(line, in: rect, cgctx: cgctx)
        // Thin rule under the header
        cgctx.setStrokeColor(NSColor.separatorColor.cgColor)
        cgctx.setLineWidth(0.5)
        cgctx.move(to: CGPoint(x: margin, y: pageSize.height - headerHeight))
        cgctx.addLine(to: CGPoint(x: pageSize.width - margin, y: pageSize.height - headerHeight))
        cgctx.strokePath()
    }

    private static func drawFooter(cgctx: CGContext, payload: ExportPayload, pageIndex: Int, pageCount: Int) {
        let panel = payload.modelPanel.joined(separator: ", ")
        let costStr = String(format: "$%.2f", payload.totalCostUsd)
        let footerLeft = "\(panel)  ·  \(costStr)"
        let footerRight = "Page \(pageIndex + 1) of \(pageCount)"
        let monoAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.darkGray
        ]
        let leftLine = NSAttributedString(string: footerLeft, attributes: monoAttrs)
        let rightLine = NSAttributedString(string: footerRight, attributes: monoAttrs)
        let leftRect = CGRect(x: margin, y: 12, width: pageSize.width - margin * 2 - 100, height: footerHeight - 16)
        let rightRect = CGRect(x: pageSize.width - margin - 100, y: 12, width: 100, height: footerHeight - 16)
        drawAttributedString(leftLine, in: leftRect, cgctx: cgctx, alignRight: false)
        drawAttributedString(rightLine, in: rightRect, cgctx: cgctx, alignRight: true)
        // Thin rule above the footer
        cgctx.setStrokeColor(NSColor.separatorColor.cgColor)
        cgctx.setLineWidth(0.5)
        cgctx.move(to: CGPoint(x: margin, y: footerHeight))
        cgctx.addLine(to: CGPoint(x: pageSize.width - margin, y: footerHeight))
        cgctx.strokePath()
    }

    private static func drawAttributedString(_ s: NSAttributedString, in rect: CGRect, cgctx: CGContext, alignRight: Bool = false) {
        let framesetter = CTFramesetterCreateWithAttributedString(s as CFAttributedString)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        if alignRight {
            // Trivial right-alignment: shift origin so the text hugs the right edge.
            // This is fine for short single-line strings (page numbers).
            let lineWidth: CGFloat = (s.string as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 9)]).width
            cgctx.saveGState()
            cgctx.translateBy(x: rect.width - lineWidth, y: 0)
            CTFrameDraw(frame, cgctx)
            cgctx.restoreGState()
        } else {
            CTFrameDraw(frame, cgctx)
        }
    }

    // MARK: - PDF context creation

    private static func makePDFContext(consumer: CGDataConsumer) -> CGContext? {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        return CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    }
}
