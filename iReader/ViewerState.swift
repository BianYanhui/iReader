import AppKit
import CoreImage
import PDFKit
import SwiftUI

/// Sidebar tabs.
enum SidebarMode: String, CaseIterable, Identifiable {
    case thumbnails
    case outline
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thumbnails: return "缩略图"
        case .outline: return "目录"
        case .search: return "搜索结果"
        }
    }

    var symbolName: String {
        switch self {
        case .thumbnails: return "square.grid.2x2"
        case .outline: return "list.bullet.indent"
        case .search: return "magnifyingglass"
        }
    }
}

/// One hit of a text search.
struct SearchResult: Identifiable {
    let id: Int
    let selection: PDFSelection
    let pageIndex: Int
    let context: String
}

/// Per-window state shared between the toolbar, sidebar, menu commands and
/// the PDF view.
final class ViewerState: ObservableObject {
    @Published var tool: AnnotationTool = .select
    @Published var color: AnnotationColor
    /// The page currently shown in the PDF view (kept in sync with scrolling).
    @Published var currentPageID: ObjectIdentifier?
    @Published var currentPageIndex = 0
    @Published var sidebarMode: SidebarMode = .thumbnails
    /// Pages selected in the thumbnail sidebar.
    @Published var selection = Set<ObjectIdentifier>()

    @Published var layout: PageLayout {
        didSet { applyViewOptions() }
    }
    @Published var nightMode: Bool {
        didSet { applyViewOptions() }
    }

    // Search
    @Published var searchText = ""
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var currentSearchIndex: Int?
    @Published private(set) var lastSearchedText = ""
    /// Bumped to move keyboard focus into the search field (⌘F).
    @Published var searchFocusRequest = 0

    @Published var showGoToPage = false

    /// The PDF view of this window (set by `PDFKitView`).
    weak var pdfView: ReaderPDFView?
    weak var document: PDFFileDocument?
    weak var undoManager: UndoManager?
    /// File URL of the document, used to remember the reading position.
    var fileURL: URL?
    private var didRestorePosition = false

    init() {
        let defaults = UserDefaults.standard
        color = AnnotationColor(rawValue: defaults.string(forKey: Prefs.defaultColor) ?? "") ?? .yellow
        layout = PageLayout(rawValue: defaults.string(forKey: Prefs.defaultLayout) ?? "") ?? .singleContinuous
        nightMode = defaults.bool(forKey: Prefs.nightMode)
    }

    var pageCount: Int { document?.pdf.pageCount ?? 0 }

    // MARK: Zoom

    func zoomIn() { pdfView?.zoomIn(nil) }

    func zoomOut() { pdfView?.zoomOut(nil) }

    func actualSize() {
        guard let pdfView else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = 1.0
    }

    func zoomToFit() { pdfView?.autoScales = true }

    /// Scales so the page width fills the view.
    func fitWidth() {
        guard let pdfView, let page = pdfView.currentPage else { return }
        let box = page.bounds(for: pdfView.displayBox)
        var width = page.rotation % 180 == 0 ? box.width : box.height
        if layout.isTwoUp { width *= 2 }
        let available = pdfView.bounds.width - 32
        guard width > 0, available > 0 else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = max(pdfView.minScaleFactor, min(pdfView.maxScaleFactor, available / width))
        pdfView.go(to: page)
    }

    /// Scales so a whole page fits in the view.
    func fitPage() {
        guard let pdfView else { return }
        let page = pdfView.currentPage
        pdfView.autoScales = false
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        if let page { pdfView.go(to: page) }
    }

    // MARK: Navigation

    func go(to page: PDFPage) {
        guard document?.contains(page) == true else { return }
        pdfView?.go(to: page)
    }

    func go(to destination: PDFDestination) {
        guard let page = destination.page, document?.contains(page) == true else { return }
        pdfView?.go(to: destination)
    }

    func go(toPageIndex index: Int) {
        guard let pdf = document?.pdf, index >= 0, index < pdf.pageCount,
              let page = pdf.page(at: index) else { return }
        pdfView?.go(to: page)
    }

    func goToNextPage() { pdfView?.goToNextPage(nil) }
    func goToPreviousPage() { pdfView?.goToPreviousPage(nil) }
    func goToFirstPage() { pdfView?.goToFirstPage(nil) }
    func goToLastPage() { pdfView?.goToLastPage(nil) }

    var currentPage: PDFPage? { pdfView?.currentPage }

    /// Called by the PDF view whenever the visible page changes.
    func pageDidChange() {
        guard let pdfView, let page = pdfView.currentPage else { return }
        let id = ObjectIdentifier(page)
        if currentPageID != id { currentPageID = id }
        if let index = document?.pdf.index(for: page), index >= 0, index != currentPageIndex,
           index < pageCount {
            currentPageIndex = index
        }
        savePosition()
    }

    // MARK: View options

    func applyViewOptions() {
        guard let pdfView else { return }
        if pdfView.displayMode != layout.displayMode {
            let page = pdfView.currentPage
            pdfView.displayMode = layout.displayMode
            if let page { pdfView.go(to: page) }
        }
        if nightMode {
            pdfView.wantsLayer = true
            pdfView.layerUsesCoreImageFilters = true
            var filters: [CIFilter] = []
            if let invert = CIFilter(name: "CIColorInvert") { filters.append(invert) }
            if let hue = CIFilter(name: "CIHueAdjust") {
                // Rotate hues back so colors (highlights, figures) stay recognizable.
                hue.setValue(Double.pi, forKey: "inputAngle")
                filters.append(hue)
            }
            pdfView.contentFilters = filters
        } else if !pdfView.contentFilters.isEmpty {
            pdfView.contentFilters = []
        }
    }

    // MARK: Reading position

    func savePosition() {
        guard didRestorePosition,
              UserDefaults.standard.bool(forKey: Prefs.rememberPosition),
              let url = fileURL, let pdfView, let page = pdfView.currentPage,
              let index = document?.pdf.index(for: page), index >= 0, index < pageCount else { return }
        let scale = pdfView.autoScales ? 0 : Double(pdfView.scaleFactor)
        PositionStore.save(.init(pageIndex: index, scale: scale), for: url)
    }

    func restorePositionIfNeeded() {
        guard !didRestorePosition else { return }
        defer { didRestorePosition = true }
        guard UserDefaults.standard.bool(forKey: Prefs.rememberPosition),
              let url = fileURL, let pdfView,
              let position = PositionStore.load(for: url) else { return }
        if position.scale > 0 {
            pdfView.autoScales = false
            pdfView.scaleFactor = CGFloat(position.scale)
        }
        if position.pageIndex > 0 {
            go(toPageIndex: position.pageIndex)
        }
    }

    // MARK: Search

    func requestSearchFocus() {
        searchFocusRequest += 1
    }

    func performSearch() {
        guard let pdf = document?.pdf, let pdfView else { return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        if query == lastSearchedText, !searchResults.isEmpty {
            findNext()
            return
        }
        let found = pdf.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
        let limited = Array(found.prefix(1000))
        var results: [SearchResult] = []
        results.reserveCapacity(limited.count)
        for (offset, selection) in limited.enumerated() {
            let page = selection.pages.first
            let index = page.map { pdf.index(for: $0) } ?? 0
            var context = selection.string ?? query
            if let extended = selection.copy() as? PDFSelection {
                extended.extend(atStart: 24)
                extended.extend(atEnd: 48)
                context = extended.string ?? context
            }
            context = context
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            results.append(SearchResult(id: offset, selection: selection, pageIndex: index, context: context))
        }
        for selection in limited.prefix(500) {
            selection.color = NSColor.systemYellow.withAlphaComponent(0.55)
        }
        pdfView.highlightedSelections = Array(limited.prefix(500))
        searchResults = results
        lastSearchedText = query
        sidebarMode = .search
        if results.isEmpty {
            currentSearchIndex = nil
            NSSound.beep()
        } else {
            // Start at the first hit on or after the current page.
            let start = results.firstIndex { $0.pageIndex >= currentPageIndex } ?? 0
            selectSearchResult(at: start)
        }
    }

    func selectSearchResult(at index: Int) {
        guard let pdfView, searchResults.indices.contains(index) else { return }
        let result = searchResults[index]
        guard let page = result.selection.pages.first, document?.contains(page) == true else { return }
        currentSearchIndex = index
        pdfView.setCurrentSelection(result.selection, animate: false)
        pdfView.go(to: result.selection)
    }

    func findNext() {
        guard !searchResults.isEmpty else {
            performSearch()
            return
        }
        let next = ((currentSearchIndex ?? -1) + 1) % searchResults.count
        selectSearchResult(at: next)
    }

    func findPrevious() {
        guard !searchResults.isEmpty else { return }
        let current = currentSearchIndex ?? 0
        let previous = (current - 1 + searchResults.count) % searchResults.count
        selectSearchResult(at: previous)
    }

    func clearSearch() {
        searchResults = []
        currentSearchIndex = nil
        lastSearchedText = ""
        pdfView?.highlightedSelections = nil
        if sidebarMode == .search { sidebarMode = .thumbnails }
    }

    /// Search hits reference pages; drop them when pages change structurally.
    func documentStructureDidChange() {
        guard !searchResults.isEmpty else { return }
        let text = searchText
        clearSearch()
        searchText = text
    }

    // MARK: Printing

    func printDocument() {
        guard let pdfView, document?.isLocked == false else { return }
        pdfView.print(with: NSPrintInfo.shared, autoRotate: true, pageScaling: .pageScaleDownToFit)
    }
}
