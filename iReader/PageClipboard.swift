import AppKit
import Foundation
import PDFKit

/// Cross-document page clipboard. Pages are serialized as a small PDF excerpt
/// (not live object pointers), so paste works across windows and after the
/// source document is closed.
enum PageClipboard {
    static let pasteboardType = NSPasteboard.PasteboardType("io.github.bianyanhui.iReader.pages.pdf")

    private static var supportFile: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("iReader", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("page-clipboard.pdf")
    }

    /// Number of pages currently on the clipboard, or 0.
    static var pageCount: Int {
        if let data = NSPasteboard.general.data(forType: pasteboardType),
           let doc = PDFDocument(data: data) {
            return doc.pageCount
        }
        if let doc = PDFDocument(url: supportFile) {
            return doc.pageCount
        }
        return 0
    }

    static var hasPages: Bool { pageCount > 0 }

    /// Copies the given pages (with annotations) onto the clipboard as PDF data.
    @discardableResult
    static func copy(_ pages: [PDFPage]) -> Int {
        let excerpt = PDFDocument()
        for (index, page) in pages.enumerated() {
            if let copy = page.copy() as? PDFPage {
                excerpt.insert(copy, at: index)
            }
        }
        guard excerpt.pageCount > 0, let data = excerpt.dataRepresentation() else { return 0 }

        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: pasteboardType)
        // Also expose as a PDF file promise-ish via support file for resilience.
        try? data.write(to: supportFile, options: .atomic)
        // Human-readable hint on the general pasteboard.
        board.setString("iReader 页面剪贴板：\(excerpt.pageCount) 页", forType: .string)
        return excerpt.pageCount
    }

    /// Loads the clipboard into a PDFDocument whose pages can be inserted.
    static func loadExcerpt() -> PDFDocument? {
        if let data = NSPasteboard.general.data(forType: pasteboardType),
           let doc = PDFDocument(data: data), doc.pageCount > 0 {
            return doc
        }
        if let doc = PDFDocument(url: supportFile), doc.pageCount > 0 {
            return doc
        }
        return nil
    }
}

extension ViewerState {
    /// Copies the target pages (selection or current) onto the cross-document clipboard.
    func copyPagesToClipboard(ids: Set<ObjectIdentifier>? = nil) {
        let pages = targetPages(ids)
        let count = PageClipboard.copy(pages)
        if count == 0 {
            showError("没有可复制的页面。")
        }
    }

    /// Pastes clipboard pages into the current document. Placement:
    /// after selection / current page by default.
    func pastePagesFromClipboard(atEnd: Bool = false) {
        guard let document else { return }
        guard let excerpt = PageClipboard.loadExcerpt() else {
            showError("页面剪贴板为空。请先在某个文档中「复制页面」。")
            return
        }
        // Re-copy so the destination retains independent page objects, and keep
        // the excerpt document alive via retainSource.
        document.retainSource(excerpt)
        var newPages: [PDFPage] = []
        for i in 0..<excerpt.pageCount {
            if let page = excerpt.page(at: i), let copy = page.copy() as? PDFPage {
                newPages.append(copy)
            } else if let page = excerpt.page(at: i) {
                newPages.append(page)
            }
        }
        guard !newPages.isEmpty else {
            showError("剪贴板中的页面无法读取。")
            return
        }
        let index = atEnd ? document.pdf.pageCount : insertionIndexAfterTargets
        document.insert(newPages, at: index, actionName: "粘贴页面", undoManager: undoManager)
        selection = Set(newPages.map(\.pageID))
        if let first = newPages.first {
            go(to: first)
        }
    }
}
