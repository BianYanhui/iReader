import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// The document model: a thin wrapper around a `PDFDocument`.
///
/// `PDFDocument` is a reference type that PDFKit mutates in place, so this is a
/// `ReferenceFileDocument`. SwiftUI marks the document as edited whenever an
/// undo action is registered on the window's undo manager.
final class PDFFileDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    let pdf: PDFDocument

    /// Bumped after every structural or annotation change so views can refresh.
    @Published private(set) var revision = 0

    init() {
        pdf = PDFDocument()
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let document = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if document.isLocked {
            throw CocoaError(.fileReadNoPermission, userInfo: [
                NSLocalizedDescriptionKey: "iReader 暂不支持打开有密码保护的 PDF。"
            ])
        }
        pdf = document
    }

    // MARK: Pages

    /// The pages of the document, in order.
    var pages: [PDFPage] {
        (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }
    }

    /// Deletes the pages at `indices`. Refuses to delete every page.
    func deletePages(at indices: IndexSet, undoManager: UndoManager?) {
        let remaining = pages.enumerated()
            .filter { !indices.contains($0.offset) }
            .map(\.element)
        guard !remaining.isEmpty, remaining.count < pdf.pageCount else { return }
        let name = indices.count == 1 ? "删除页面" : "删除 \(indices.count) 个页面"
        setPages(remaining, actionName: name, undoManager: undoManager)
    }

    /// Moves pages like `Array.move(fromOffsets:toOffset:)` (used by List.onMove).
    func movePages(fromOffsets source: IndexSet, toOffset destination: Int, undoManager: UndoManager?) {
        var reordered = pages
        reordered.move(fromOffsets: source, toOffset: destination)
        guard reordered.map(ObjectIdentifier.init) != pages.map(ObjectIdentifier.init) else { return }
        setPages(reordered, actionName: "移动页面", undoManager: undoManager)
    }

    /// Makes the document contain exactly `newPages`, in that order, and
    /// registers an undo action that restores the previous page list.
    private func setPages(_ newPages: [PDFPage], actionName: String, undoManager: UndoManager?) {
        let oldPages = pages
        apply(pages: newPages)
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] document in
            document.setPages(oldPages, actionName: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
        revision += 1
    }

    private func apply(pages newPages: [PDFPage]) {
        // 1. Remove pages that are not part of the new list.
        let keep = Set(newPages.map(ObjectIdentifier.init))
        for index in stride(from: pdf.pageCount - 1, through: 0, by: -1) {
            if let page = pdf.page(at: index), !keep.contains(ObjectIdentifier(page)) {
                pdf.removePage(at: index)
            }
        }
        // 2. Insert / move pages into place, touching only what changed.
        for (index, page) in newPages.enumerated() {
            if index < pdf.pageCount, pdf.page(at: index) === page { continue }
            let current = pdf.index(for: page)
            if current >= 0, current < pdf.pageCount, pdf.page(at: current) === page {
                pdf.removePage(at: current)
            }
            pdf.insert(page, at: min(index, pdf.pageCount))
        }
    }

    // MARK: Saving

    func snapshot(contentType: UTType) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}
