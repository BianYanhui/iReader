import SwiftUI
import PDFKit

/// SwiftUI wrapper around `PDFView`.
struct PDFKitView: NSViewRepresentable {
    let document: PDFFileDocument
    let viewer: ViewerState
    /// Passed in so that SwiftUI calls `updateNSView` after document changes.
    let revision: Int

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
        if context.coordinator.revision != revision {
            if context.coordinator.revision != nil {
                view.layoutDocumentView()
            }
            context.coordinator.revision = revision
        }
    }
}

/// `PDFView` subclass; annotation tools hook in here.
final class ReaderPDFView: PDFView {
}
