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
        var structureRevision: Int?
        var observers: [NSObjectProtocol] = []

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ReaderPDFView {
        let view = ReaderPDFView()
        view.displayMode = viewer.layout.displayMode
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.autoScales = true
        view.document = document.pdf
        viewer.pdfView = view
        viewer.document = document
        viewer.applyViewOptions()
        let viewerState = self.viewer
        view.onFindShortcut = { [weak viewerState] in
            viewerState?.requestSearchFocus()
        }

        // Keep the sidebar / position store in sync with the page being viewed.
        let viewer = self.viewer
        context.coordinator.observers.append(NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged, object: view, queue: .main
        ) { _ in
            viewer.pageDidChange()
        })
        context.coordinator.observers.append(NotificationCenter.default.addObserver(
            forName: .PDFViewScaleChanged, object: view, queue: .main
        ) { _ in
            viewer.savePosition()
        })
        DispatchQueue.main.async {
            viewer.restorePositionIfNeeded()
            viewer.pageDidChange()
        }
        return view
    }

    static func dismantleNSView(_ view: ReaderPDFView, coordinator: Coordinator) {
        for observer in coordinator.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        coordinator.observers.removeAll()
        view.onAddAnnotations = nil
        view.onRemoveAnnotations = nil
        view.onSetColor = nil
        view.onSetText = nil
        view.onFindShortcut = nil
    }

    func updateNSView(_ view: ReaderPDFView, context: Context) {
        if view.document !== document.pdf {
            view.document = document.pdf
        }
        viewer.pdfView = view
        let viewerState = self.viewer
        view.onFindShortcut = { [weak viewerState] in
            viewerState?.requestSearchFocus()
        }
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
        view.onSetColor = { annotation, page, color in
            document.setColor(color, for: annotation, on: page, undoManager: undoManager)
        }
        view.onSetText = { annotation, page, text in
            document.setText(text, for: annotation, on: page, undoManager: undoManager)
        }

        viewer.document = document
        if let undoManager { viewer.undoManager = undoManager }
        if context.coordinator.structureRevision != document.structureRevision {
            if context.coordinator.structureRevision != nil {
                let viewer = self.viewer
                DispatchQueue.main.async { viewer.documentStructureDidChange() }
            }
            context.coordinator.structureRevision = document.structureRevision
        }
        if context.coordinator.revision != revision {
            if context.coordinator.revision != nil {
                view.layoutDocumentView()
            }
            context.coordinator.revision = revision
        }
    }
}
