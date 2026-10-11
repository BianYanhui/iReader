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
    /// Bumped only when pages are added, removed, moved or rotated.
    @Published private(set) var structureRevision = 0
    /// Per-page change counters, so only edited pages re-render thumbnails.
    @Published private(set) var pageStamps: [ObjectIdentifier: Int] = [:]

    /// Password used to unlock an encrypted PDF; reused when saving so the
    /// file stays protected.
    private(set) var password: String?

    init() {
        pdf = PDFDocument()
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let document = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Locked (password-protected) documents are opened as-is; the window
        // asks for the password before showing any content.
        pdf = document
    }

    var isLocked: Bool { pdf.isLocked }

    /// Tries to unlock an encrypted document. Returns false for a wrong password.
    func unlock(with password: String) -> Bool {
        guard pdf.unlock(withPassword: password) else { return false }
        self.password = password
        revision += 1
        structureRevision += 1
        return true
    }

    func stamp(for page: PDFPage) -> Int {
        pageStamps[page.pageID] ?? 0
    }

    /// Marks pages as changed (thumbnails re-render).
    func touch(_ pages: [PDFPage]) {
        for page in pages {
            pageStamps[page.pageID, default: 0] += 1
        }
    }

    /// True when `page` currently belongs to this document.
    func contains(_ page: PDFPage) -> Bool {
        let index = pdf.index(for: page)
        return index >= 0 && index < pdf.pageCount && pdf.page(at: index) === page
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
        structureRevision += 1
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

    // MARK: Annotations

    func addAnnotations(_ items: [PlacedAnnotation], actionName: String, undoManager: UndoManager?) {
        guard !items.isEmpty else { return }
        for item in items {
            item.page.addAnnotation(item.annotation)
        }
        touch(items.map(\.page))
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] document in
            document.removeAnnotations(items, actionName: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
        revision += 1
    }

    func removeAnnotations(_ items: [PlacedAnnotation], actionName: String, undoManager: UndoManager?) {
        guard !items.isEmpty else { return }
        for item in items {
            item.page.removeAnnotation(item.annotation)
        }
        touch(items.map(\.page))
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] document in
            document.addAnnotations(items, actionName: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
        revision += 1
    }

    /// Changes an annotation's color (undoable).
    func setColor(_ color: NSColor, for annotation: PDFAnnotation, on page: PDFPage, undoManager: UndoManager?) {
        let oldColor = annotation.color
        annotation.color = color
        refresh(annotation, on: page)
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] document in
            document.setColor(oldColor, for: annotation, on: page, undoManager: undoManager)
        }
        undoManager?.setActionName("更改标注颜色")
    }

    /// Changes the text of a text box / note (undoable). Text boxes are resized
    /// to fit, keeping their top-left corner, unless `bounds` is given.
    func setText(
        _ text: String,
        bounds newBounds: NSRect? = nil,
        for annotation: PDFAnnotation,
        on page: PDFPage,
        undoManager: UndoManager?
    ) {
        let oldText = annotation.contents ?? ""
        let oldBounds = annotation.bounds
        annotation.contents = text
        if let newBounds {
            annotation.bounds = newBounds
        } else if annotation.normalizedType == "freetext" {
            let topLeft = NSPoint(x: oldBounds.minX, y: oldBounds.maxY)
            annotation.bounds = ReaderPDFView.textBoxBounds(
                for: text, font: annotation.font, topLeft: topLeft, page: page
            )
        }
        refresh(annotation, on: page)
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] document in
            document.setText(oldText, bounds: oldBounds, for: annotation, on: page, undoManager: undoManager)
        }
        undoManager?.setActionName("编辑文字")
    }

    /// Re-adds an annotation so PDFKit redraws it after a property change.
    private func refresh(_ annotation: PDFAnnotation, on page: PDFPage) {
        if page.annotations.contains(where: { $0 === annotation }) {
            page.removeAnnotation(annotation)
            page.addAnnotation(annotation)
        }
        touch([page])
        revision += 1
    }

    // MARK: Saving

    /// Serializes the document, including all annotations, as PDF data.
    /// Used by Save, Save As / Duplicate and autosave.
    func snapshot(contentType: UTType) throws -> Data {
        guard !pdf.isLocked else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [
                NSLocalizedDescriptionKey: "文档尚未解锁，无法保存。"
            ])
        }
        guard pdf.pageCount > 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "空文档无法保存。请先打开一个 PDF 文件。"
            ])
        }
        let data: Data?
        if let password, pdf.isEncrypted {
            // Keep the password protection when writing the file back.
            data = pdf.dataRepresentation(options: [
                PDFDocumentWriteOption.userPasswordOption: password,
                PDFDocumentWriteOption.ownerPasswordOption: password,
            ])
        } else {
            data = pdf.dataRepresentation()
        }
        guard let data else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "无法生成 PDF 数据。"
            ])
        }
        return data
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}

/// An annotation together with the page it belongs to.
struct PlacedAnnotation {
    let annotation: PDFAnnotation
    let page: PDFPage
}
