import AppKit
import PDFKit

/// `PDFView` subclass implementing the markup tools.
///
/// * highlight / underline / strikethrough: the user selects text as usual;
///   on mouse-up the selection becomes one markup annotation per line.
/// * pen: mouse drags are recorded as an ink annotation.
/// * rectangle / arrow: drag to draw a square or line annotation.
/// * text: click to add a free-text box.
/// * eraser: clicking an annotation removes it.
/// * right-click on an annotation (any tool): change color, edit text, delete.
///
/// Annotations are handed to the document through the callbacks so that they
/// are undoable and mark the document as edited.
final class ReaderPDFView: PDFView {
    var tool: AnnotationTool = .select {
        didSet {
            guard oldValue != tool else { return }
            if tool != .select { clearSelection() }
            cancelDrawing()
            window?.invalidateCursorRects(for: self)
        }
    }
    var annotationColor: NSColor = .systemYellow
    var inkLineWidth: CGFloat = 2.5
    var shapeLineWidth: CGFloat = 2

    var onAddAnnotations: (([PlacedAnnotation], String) -> Void)?
    var onRemoveAnnotations: (([PlacedAnnotation], String) -> Void)?
    var onSetColor: ((PDFAnnotation, PDFPage, NSColor) -> Void)?
    var onSetText: ((PDFAnnotation, PDFPage, String) -> Void)?

    /// Called when the system Find action (⌘F) hits this view; route to toolbar search.
    var onFindShortcut: (() -> Void)?

    // In-progress ink stroke or shape.
    private var drawPage: PDFPage?
    private var inkPath: NSBezierPath?
    private var shapeStart: NSPoint?
    private var shapeEnd: NSPoint?
    private var preview: PDFAnnotation?

    // MARK: Find (⌘F)

    /// Intercept ⌘F while the PDF view is first responder and route to toolbar search.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            onFindShortcut?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: Mouse handling

    override func mouseDown(with event: NSEvent) {
        switch tool {
        case .pen:
            beginInk(with: event)
        case .rectangle, .arrow:
            beginShape(with: event)
        case .text:
            addTextBox(at: event)
        case .eraser:
            erase(at: event)
        case .highlight, .underline, .strikethrough:
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
        case .rectangle, .arrow: continueShape(with: event)
        case .eraser, .text: break
        default: super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch tool {
        case .pen:
            endInk()
        case .rectangle, .arrow:
            endShape()
        case .eraser, .text:
            break
        case .highlight, .underline, .strikethrough:
            super.mouseUp(with: event)
            markUpSelection()
        case .select:
            super.mouseUp(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        switch tool {
        case .pen, .eraser, .rectangle, .arrow:
            NSCursor.crosshair.set()
        case .text:
            NSCursor.iBeam.set()
        case .highlight, .underline, .strikethrough:
            super.mouseMoved(with: event)
            NSCursor.iBeam.set()
        case .select:
            super.mouseMoved(with: event)
        }
    }

    // MARK: Hit testing

    private func pageAndPoint(for event: NSEvent, nearest: Bool) -> (PDFPage, NSPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = self.page(for: viewPoint, nearest: nearest) else { return nil }
        return (page, convert(viewPoint, to: page))
    }

    /// Topmost user annotation (markup, ink, shapes, text) under the point.
    private func userAnnotation(at point: NSPoint, on page: PDFPage) -> PDFAnnotation? {
        page.annotations.reversed().first { annotation in
            annotation.isUserMarkup && annotation !== preview
                && annotation.bounds.insetBy(dx: -3, dy: -3).contains(point)
        }
    }

    // MARK: Context menu on annotations

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let hit = pageAndPoint(for: event, nearest: false),
              let annotation = userAnnotation(at: hit.1, on: hit.0) else {
            return super.menu(for: event)
        }
        let page = hit.0
        let menu = NSMenu(title: annotation.kindTitle)
        let header = NSMenuItem(title: annotation.kindTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let colorItem = NSMenuItem(title: "颜色", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu(title: "颜色")
        for color in AnnotationColor.allCases {
            let item = ClosureMenuItem(title: color.title) { [weak self] in
                self?.onSetColor?(annotation, page, annotation.storedColor(for: color.nsColor))
            }
            item.image = color.swatch(selected: false)
            colorMenu.addItem(item)
        }
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        if annotation.hasEditableText {
            menu.addItem(ClosureMenuItem(title: "编辑文字…") { [weak self] in
                guard let self,
                      let text = self.promptForText(title: "编辑文字", initial: annotation.contents ?? "")
                else { return }
                self.onSetText?(annotation, page, text)
            })
        }

        if let text = page.selection(for: annotation.bounds)?.string,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !annotation.hasEditableText {
            menu.addItem(ClosureMenuItem(title: "拷贝标注文字") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            })
        }

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "删除标注") { [weak self] in
            self?.onRemoveAnnotations?([PlacedAnnotation(annotation: annotation, page: page)], "删除标注")
        })
        return menu
    }

    // MARK: Highlight / underline / strikethrough

    private func markUpSelection() {
        guard tool.isTextMarkup, let selection = currentSelection else { return }
        let subtype: PDFAnnotationSubtype
        let actionName: String
        switch tool {
        case .underline:
            subtype = .underline
            actionName = "下划线"
        case .strikethrough:
            subtype = .strikeOut
            actionName = "删除线"
        default:
            subtype = .highlight
            actionName = "高亮"
        }
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
        onAddAnnotations?(items, actionName)
    }

    // MARK: Preview helpers

    private func setPreview(_ annotation: PDFAnnotation?) {
        guard let page = drawPage else { return }
        if let preview { page.removeAnnotation(preview) }
        preview = annotation
        if let annotation { page.addAnnotation(annotation) }
    }

    private func cancelDrawing() {
        setPreview(nil)
        drawPage = nil
        inkPath = nil
        shapeStart = nil
        shapeEnd = nil
    }

    // MARK: Ink

    private func beginInk(with event: NSEvent) {
        cancelDrawing()
        guard let hit = pageAndPoint(for: event, nearest: true) else { return }
        let (page, point) = hit
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: point)
        drawPage = page
        inkPath = path
        setPreview(makeInkAnnotation(path: path, page: page, tightBounds: false))
    }

    private func continueInk(with event: NSEvent) {
        guard let page = drawPage, let path = inkPath else { return }
        let point = convert(convert(event.locationInWindow, from: nil), to: page)
        path.line(to: point)
        setPreview(makeInkAnnotation(path: path, page: page, tightBounds: false))
    }

    private func endInk() {
        guard let page = drawPage, let path = inkPath else { return }
        cancelDrawing()
        if path.elementCount < 2 {
            // A simple click: draw a dot.
            let p = path.currentPoint
            path.line(to: NSPoint(x: p.x + 0.1, y: p.y + 0.1))
        }
        let annotation = makeInkAnnotation(path: path, page: page, tightBounds: true)
        onAddAnnotations?([PlacedAnnotation(annotation: annotation, page: page)], "画笔")
    }

    private func makeInkAnnotation(path: NSBezierPath, page: PDFPage, tightBounds: Bool) -> PDFAnnotation {
        let bounds: NSRect
        if tightBounds {
            bounds = path.bounds.insetBy(dx: -inkLineWidth * 2, dy: -inkLineWidth * 2)
        } else {
            bounds = page.bounds(for: .mediaBox)
        }
        // Ink paths are expressed relative to the annotation's bounds origin.
        let relativePath = (path.copy() as? NSBezierPath) ?? NSBezierPath()
        relativePath.transform(using: AffineTransform(translationByX: -bounds.origin.x, byY: -bounds.origin.y))

        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = annotationColor
        let border = PDFBorder()
        border.lineWidth = inkLineWidth
        annotation.border = border
        annotation.add(relativePath)
        return annotation
    }

    // MARK: Rectangle / arrow

    private func beginShape(with event: NSEvent) {
        cancelDrawing()
        guard let hit = pageAndPoint(for: event, nearest: true) else { return }
        let (page, point) = hit
        drawPage = page
        shapeStart = point
        shapeEnd = point
    }

    private func continueShape(with event: NSEvent) {
        guard let page = drawPage, let start = shapeStart else { return }
        let end = convert(convert(event.locationInWindow, from: nil), to: page)
        shapeEnd = end
        setPreview(makeShape(from: start, to: end))
    }

    private func endShape() {
        guard let page = drawPage, let start = shapeStart, let end = shapeEnd else {
            cancelDrawing()
            return
        }
        cancelDrawing()
        // Ignore accidental clicks.
        guard hypot(end.x - start.x, end.y - start.y) > 4 else { return }
        guard let annotation = makeShape(from: start, to: end) else { return }
        onAddAnnotations?([PlacedAnnotation(annotation: annotation, page: page)], tool.title)
    }

    private func makeShape(from start: NSPoint, to end: NSPoint) -> PDFAnnotation? {
        let border = PDFBorder()
        border.lineWidth = shapeLineWidth
        switch tool {
        case .rectangle:
            let rect = NSRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            )
            guard rect.width > 0.5 || rect.height > 0.5 else { return nil }
            let annotation = PDFAnnotation(
                bounds: rect.insetBy(dx: -shapeLineWidth, dy: -shapeLineWidth),
                forType: .square, withProperties: nil
            )
            annotation.color = annotationColor
            annotation.border = border
            return annotation
        case .arrow:
            let padding: CGFloat = 12
            let rect = NSRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            ).insetBy(dx: -padding, dy: -padding)
            let annotation = PDFAnnotation(bounds: rect, forType: .line, withProperties: nil)
            // Line end points are relative to the annotation's bounds origin.
            annotation.startPoint = NSPoint(x: start.x - rect.origin.x, y: start.y - rect.origin.y)
            annotation.endPoint = NSPoint(x: end.x - rect.origin.x, y: end.y - rect.origin.y)
            annotation.startLineStyle = .none
            annotation.endLineStyle = .openArrow
            annotation.color = annotationColor
            annotation.border = border
            return annotation
        default:
            return nil
        }
    }

    // MARK: Text box

    private func addTextBox(at event: NSEvent) {
        guard let hit = pageAndPoint(for: event, nearest: false) else { return }
        let (page, point) = hit
        guard let text = promptForText(title: "添加文本框", initial: "") else { return }
        let annotation = PDFAnnotation(bounds: .zero, forType: .freeText, withProperties: nil)
        annotation.font = NSFont.systemFont(ofSize: 12)
        annotation.fontColor = .black
        annotation.alignment = .left
        annotation.color = annotationColor.withAlphaComponent(0.35)
        let border = PDFBorder()
        border.lineWidth = 0.5
        annotation.border = border
        annotation.contents = text
        annotation.bounds = Self.textBoxBounds(for: text, font: annotation.font, topLeft: point, page: page)
        onAddAnnotations?([PlacedAnnotation(annotation: annotation, page: page)], "文本框")
    }

    /// Bounds for a free-text box whose top-left corner is at `topLeft`,
    /// clamped to the page.
    static func textBoxBounds(for text: String, font: NSFont?, topLeft: NSPoint, page: PDFPage) -> NSRect {
        let font = font ?? NSFont.systemFont(ofSize: 12)
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: 260, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let width = ceil(measured.width) + 14
        let height = ceil(measured.height) + 10
        let pageBox = page.bounds(for: .mediaBox)
        var rect = NSRect(x: topLeft.x, y: topLeft.y - height, width: width, height: height)
        rect.origin.x = max(pageBox.minX, min(rect.origin.x, pageBox.maxX - width))
        rect.origin.y = max(pageBox.minY, min(rect.origin.y, pageBox.maxY - height))
        return rect
    }

    /// Modal multi-line text prompt. Returns nil when cancelled or empty.
    func promptForText(title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 90))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.contentView.bounds)
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.string = initial
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = textView

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: Eraser

    private func erase(at event: NSEvent) {
        guard let location = pageAndPoint(for: event, nearest: false),
              let hit = userAnnotation(at: location.1, on: location.0) else {
            NSSound.beep()
            return
        }
        onRemoveAnnotations?([PlacedAnnotation(annotation: hit, page: location.0)], "删除标注")
    }
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
