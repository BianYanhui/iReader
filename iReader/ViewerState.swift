import SwiftUI
import PDFKit

/// Per-window state shared between the toolbar, menu commands and the PDF view.
final class ViewerState: ObservableObject {
    @Published var tool: AnnotationTool = .select
    @Published var color: AnnotationColor = .yellow
    /// The page currently shown in the PDF view (kept in sync with scrolling).
    @Published var currentPageID: ObjectIdentifier?

    /// The PDF view of this window (set by `PDFKitView`).
    weak var pdfView: ReaderPDFView?

    func zoomIn() { pdfView?.zoomIn(nil) }

    func zoomOut() { pdfView?.zoomOut(nil) }

    func actualSize() {
        guard let pdfView else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = 1.0
    }

    func zoomToFit() { pdfView?.autoScales = true }

    func go(to page: PDFPage) { pdfView?.go(to: page) }

    var currentPage: PDFPage? { pdfView?.currentPage }
}
