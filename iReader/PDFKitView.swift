import SwiftUI
import PDFKit

/// SwiftUI wrapper around `PDFView`.
struct PDFKitView: NSViewRepresentable {
    let document: PDFFileDocument
    let viewer: ViewerState
    let tool: AnnotationTool
    let color: AnnotationColor
    /// Passed in so that SwiftUI calls `updateNSView` after document changes.
    let revision: Int
    let undoManager: UndoManager?

    final class Coordinator {
        var revision: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ReaderPDFView {
        let view = ReaderPDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.autoScales = true
        view.document = document.pdf
        viewer.pdfView = view
        return view
    }

    func updateNSView(_ view: ReaderPDFView, context: Context) {
        if view.document !== document.pdf {
            view.document = document.pdf
        }
        viewer.pdfView = view
        view.tool = tool
        view.annotationColor = color.nsColor

        let document = self.document
        let undoManager = self.undoManager
        view.onAddAnnotations = { items, actionName in
            document.addAnnotations(items, actionName: actionName, undoManager: undoManager)
        }
        view.onRemoveAnnotations = { items, actionName in
            document.removeAnnotations(items, actionName: actionName, undoManager: undoManager)
        }

        if context.coordinator.revision != revision {
            if context.coordinator.revision != nil {
                view.layoutDocumentView()
            }
            context.coordinator.revision = revision
        }
    }
}

/// `PDFView` subclass implementing the markup tools.
///
/// * highlight / underline: the user selects text as usual; on mouse-up the
///   selection is turned into one markup annotation per line.
/// * pen: mouse drags are recorded as an ink annotation.
/// * eraser: clicking a markup or ink annotation removes it.
///
/// Annotations are handed to the document through the callbacks so that they
/// are undoable and mark the document as edited.
final class ReaderPDFView: PDFView {
    var tool: AnnotationTool = .select {
        didSet {
            guard oldValue != tool else { return }
            if tool != .select { clearSelection() }
            window?.invalidateCursorRects(for: self)
        }
    }
    var annotationColor: NSColor = .systemYellow
    var inkLineWidth: CGFloat = 2.5

    var onAddAnnotations: (([PlacedAnnotation], String) -> Void)?
    var onRemoveAnnotations: (([PlacedAnnotation], String) -> Void)?

    // In-progress ink stroke.
    private var inkPage: PDFPage?
    private var inkPath: NSBezierPath?
    private var inkPreview: PDFAnnotation?

    private static let erasableSubtypes: Set<String> = ["highlight", "underline", "strikeout", "squiggly", "ink"]

    // MARK: Mouse handling

    override func mouseDown(with event: NSEvent) {
        switch tool {
        case .pen:
            beginInk(with: event)
        case .eraser:
            erase(at: event)
        case .highlight, .underline:
            super.mouseDown(with: event)
            // PDFView may run its own tracking loop and swallow mouse-up.
            if NSEvent.pressedMouseButtons & 1 == 0 {
                markUpSelection()
            }
        case .select:
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        switch tool {
        case .pen: continueInk(with: event)
        case .eraser: break
        default: super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch tool {
        case .pen:
            endInk(with: event)
        case .eraser:
            break
        case .highlight, .underline:
            super.mouseUp(with: event)
            markUpSelection()
        case .select:
            super.mouseUp(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        switch tool {
        case .pen, .eraser:
            NSCursor.crosshair.set()
        case .highlight, .underline:
            super.mouseMoved(with: event)
            NSCursor.iBeam.set()
        case .select:
            super.mouseMoved(with: event)
        }
    }

    // MARK: Highlight / underline

    private func markUpSelection() {
        guard tool == .highlight || tool == .underline,
              let selection = currentSelection else { return }
        let subtype: PDFAnnotationSubtype = tool == .highlight ? .highlight : .underline
        let color = tool == .highlight ? annotationColor.withAlphaComponent(0.5) : annotationColor

        var items: [PlacedAnnotation] = []
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard bounds.width > 0.5, bounds.height > 0.5 else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
                annotation.color = color
                // Quad points are relative to the annotation's bounds origin:
                // top-left, top-right, bottom-left, bottom-right.
                annotation.quadrilateralPoints = [
                    NSValue(point: NSPoint(x: 0, y: bounds.height)),
                    NSValue(point: NSPoint(x: bounds.width, y: bounds.height)),
                    NSValue(point: NSPoint(x: 0, y: 0)),
                    NSValue(point: NSPoint(x: bounds.width, y: 0)),
                ]
                items.append(PlacedAnnotation(annotation: annotation, page: page))
            }
        }
        clearSelection()
        guard !items.isEmpty else { return }
        onAddAnnotations?(items, tool == .highlight ? "高亮" : "下划线")
    }

    // MARK: Ink

    private func beginInk(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = self.page(for: viewPoint, nearest: true) else { return }
        let point = convert(viewPoint, to: page)
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: point)
        inkPage = page
        inkPath = path
        updateInkPreview()
    }

    private func continueInk(with event: NSEvent) {
        guard let page = inkPage, let path = inkPath else { return }
        let point = convert(convert(event.locationInWindow, from: nil), to: page)
        path.line(to: point)
        updateInkPreview()
    }

    private func endInk(with event: NSEvent) {
        guard let page = inkPage, let path = inkPath else { return }
        if let preview = inkPreview {
            page.removeAnnotation(preview)
        }
        inkPreview = nil
        inkPage = nil
        inkPath = nil

        if path.elementCount < 2 {
            // A simple click: draw a dot.
            let p = path.currentPoint
            path.line(to: NSPoint(x: p.x + 0.1, y: p.y + 0.1))
        }
        let annotation = makeInkAnnotation(path: path, page: page, tightBounds: true)
        onAddAnnotations?([PlacedAnnotation(annotation: annotation, page: page)], "画笔")
    }

    /// Shows the stroke while drawing by replacing a temporary annotation.
    private func updateInkPreview() {
        guard let page = inkPage, let path = inkPath else { return }
        if let preview = inkPreview {
            page.removeAnnotation(preview)
        }
        let preview = makeInkAnnotation(path: path, page: page, tightBounds: false)
        page.addAnnotation(preview)
        inkPreview = preview
    }

    private func makeInkAnnotation(path: NSBezierPath, page: PDFPage, tightBounds: Bool) -> PDFAnnotation {
        let bounds: NSRect
        if tightBounds {
            bounds = path.bounds.insetBy(dx: -inkLineWidth * 2, dy: -inkLineWidth * 2)
        } else {
            bounds = page.bounds(for: .mediaBox)
        }
        // Ink paths are expressed relative to the annotation's bounds origin.
        let relativePath = path.copy() as! NSBezierPath
        relativePath.transform(using: AffineTransform(translationByX: -bounds.origin.x, byY: -bounds.origin.y))

        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = annotationColor
        let border = PDFBorder()
        border.lineWidth = inkLineWidth
        annotation.border = border
        annotation.add(relativePath)
        return annotation
    }

    // MARK: Eraser

    private func erase(at event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = self.page(for: viewPoint, nearest: false) else { return }
        let point = convert(viewPoint, to: page)
        let hit = page.annotations.reversed().first { annotation in
            let subtype = (annotation.type ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
            return Self.erasableSubtypes.contains(subtype)
                && annotation.bounds.insetBy(dx: -3, dy: -3).contains(point)
        }
        guard let hit else {
            NSSound.beep()
            return
        }
        onRemoveAnnotations?([PlacedAnnotation(annotation: hit, page: page)], "删除标注")
    }
}
