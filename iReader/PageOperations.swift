import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Page-level operations (rotate, insert, duplicate, extract, export). They act
/// on the pages selected in the sidebar, or the current page when nothing is
/// selected, and go through `PDFFileDocument` so they are undoable.
extension ViewerState {
    /// Pages to act on: the given ids, else the sidebar selection, else the current page.
    func targetPages(_ ids: Set<ObjectIdentifier>? = nil) -> [PDFPage] {
        guard let document else { return [] }
        let wanted = ids ?? selection
        if !wanted.isEmpty {
            return document.pages.filter { wanted.contains($0.pageID) }
        }
        return currentPage.map { [$0] } ?? []
    }

    var insertionIndexAfterTargets: Int {
        guard let document else { return 0 }
        let targets = targetPages()
        let indices = targets.map { document.pdf.index(for: $0) }.filter { $0 >= 0 && $0 < document.pdf.pageCount }
        return (indices.max() ?? (document.pdf.pageCount - 1)) + 1
    }

    func rotate(by degrees: Int, ids: Set<ObjectIdentifier>? = nil) {
        document?.rotate(targetPages(ids), by: degrees, undoManager: undoManager)
    }

    func deleteTargetPages() {
        guard let document else { return }
        let targets = targetPages()
        let indices = IndexSet(targets.map { document.pdf.index(for: $0) }.filter { $0 >= 0 && $0 < document.pdf.pageCount })
        guard !indices.isEmpty else { return }
        guard indices.count < document.pdf.pageCount else {
            showError("无法删除全部页面：PDF 文档至少需要保留一页。")
            return
        }
        document.deletePages(at: indices, undoManager: undoManager)
        selection.subtract(targets.map(\.pageID))
    }

    func insertBlankPage() {
        guard let document else { return }
        let reference = currentPage ?? document.pdf.page(at: 0)
        var size = reference?.bounds(for: .mediaBox).size ?? CGSize(width: 595, height: 842)
        if let reference, reference.rotation % 180 != 0 {
            size = CGSize(width: size.height, height: size.width)
        }
        if size.width < 10 || size.height < 10 { size = CGSize(width: 595, height: 842) }
        guard let page = document.makeBlankPage(size: size) else { return }
        let index = insertionIndexAfterTargets
        document.insert([page], at: index, actionName: "插入空白页", undoManager: undoManager)
        selection = [page.pageID]
    }

    func duplicatePages(ids: Set<ObjectIdentifier>? = nil) {
        guard let document else { return }
        let targets = targetPages(ids)
        let copies = targets.compactMap { $0.copy() as? PDFPage }
        guard !copies.isEmpty else { return }
        let indices = targets.map { document.pdf.index(for: $0) }.filter { $0 >= 0 && $0 < document.pdf.pageCount }
        let index = (indices.max() ?? (document.pdf.pageCount - 1)) + 1
        document.insert(copies, at: index, actionName: "复制页面", undoManager: undoManager)
        selection = Set(copies.map(\.pageID))
    }

    // MARK: Insert from other PDFs

    func insertPagesFromFile() {
        let panel = NSOpenPanel()
        panel.title = "选择要插入的 PDF"
        panel.prompt = "插入"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        insertPDFs(at: panel.urls, index: insertionIndexAfterTargets)
    }

    /// Inserts all pages of the given PDF files at `index`.
    func insertPDFs(at urls: [URL], index: Int) {
        guard let document else { return }
        var newPages: [PDFPage] = []
        var skipped: [String] = []
        for url in urls {
            guard let source = PDFDocument(url: url) else {
                skipped.append(url.lastPathComponent)
                continue
            }
            if source.isLocked, !unlock(source, name: url.lastPathComponent) {
                skipped.append(url.lastPathComponent)
                continue
            }
            document.retainSource(source)
            newPages.append(contentsOf: (0..<source.pageCount).compactMap { source.page(at: $0) })
        }
        if !newPages.isEmpty {
            document.insert(newPages, at: index, actionName: "插入页面", undoManager: undoManager)
            selection = Set(newPages.map(\.pageID))
        }
        if !skipped.isEmpty {
            let alert = NSAlert()
            alert.messageText = "部分文件未能插入"
            alert.informativeText = skipped.joined(separator: "\n")
            alert.runModal()
        }
    }

    /// Handles PDF files dropped onto the thumbnail list.
    func insertDroppedPDFs(_ providers: [NSItemProvider], at index: Int) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, !urls.isEmpty else { return }
            self.insertPDFs(at: urls.sorted { $0.lastPathComponent < $1.lastPathComponent }, index: index)
        }
    }

    private func unlock(_ source: PDFDocument, name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "「\(name)」受密码保护"
        alert.informativeText = "输入密码以插入其页面。"
        alert.addButton(withTitle: "解锁")
        alert.addButton(withTitle: "跳过")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return source.unlock(withPassword: field.stringValue)
    }

    // MARK: Extract / export

    private var baseName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "iReader"
    }

    /// Saves the target pages (with annotations) as a new PDF and opens it.
    func extractPages(ids: Set<ObjectIdentifier>? = nil) {
        guard document != nil else { return }
        let targets = targetPages(ids)
        guard !targets.isEmpty else { return }
        let output = PDFDocument()
        for (index, page) in targets.enumerated() {
            guard let copy = page.copy() as? PDFPage else { continue }
            output.insert(copy, at: index)
        }
        guard output.pageCount > 0 else { return }

        let panel = NSSavePanel()
        panel.title = "提取页面"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(baseName)-提取.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard output.write(to: url) else {
            showError("无法写入文件：\(url.path)")
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    /// Exports the target pages as PNG images (144 dpi, annotations included).
    func exportPagesAsPNG(ids: Set<ObjectIdentifier>? = nil) {
        exportImagesInteractive(format: .png, ids: ids)
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
