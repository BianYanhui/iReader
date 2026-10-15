import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Interactive (save-panel) export actions for the focused document window.
extension ViewerState {
    private var exportBaseName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "iReader"
    }

    private func pagesForExport(ids: Set<ObjectIdentifier>?, wholeDocument: Bool) -> (PDFDocument, IndexSet)? {
        guard let document, !document.isLocked else { return nil }
        let pdf = document.pdf
        if wholeDocument {
            return (pdf, IndexSet(integersIn: 0..<pdf.pageCount))
        }
        let targets = targetPages(ids)
        if targets.isEmpty {
            return (pdf, IndexSet(integersIn: 0..<pdf.pageCount))
        }
        var set = IndexSet()
        for page in targets {
            let index = pdf.index(for: page)
            if index >= 0 { set.insert(index) }
        }
        return set.isEmpty ? nil : (pdf, set)
    }

    /// Returns `true` for whole document, `false` for selection only, `nil` if cancelled.
    private func resolveScope(ids: Set<ObjectIdentifier>?) -> Bool? {
        let hasSelection = !(ids ?? selection).isEmpty
        guard hasSelection else { return true }
        let alert = NSAlert()
        alert.messageText = "导出范围"
        alert.addButton(withTitle: "仅选中页面")
        alert.addButton(withTitle: "整个文档")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return false
        case .alertSecondButtonReturn: return true
        default: return nil
        }
    }

    func exportPDFInteractive(ids: Set<ObjectIdentifier>? = nil) {
        guard let whole = resolveScope(ids: ids),
              let (pdf, pages) = pagesForExport(ids: ids, wholeDocument: whole) else { return }
        let panel = NSSavePanel()
        panel.title = "导出 PDF"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = whole ? "\(exportBaseName)-导出.pdf" : "\(exportBaseName)-选页.pdf"
        panel.message = "保留 PDF 标注（高亮、批注等），其他阅读器可见。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try ExportService.export(pdf: pdf, format: .pdf, pages: pages, output: url, baseName: exportBaseName)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showError(error.localizedDescription)
        }
    }

    func exportImagesInteractive(format: ExportService.Format, ids: Set<ObjectIdentifier>? = nil) {
        guard format.isImage else { return }
        guard let whole = resolveScope(ids: ids),
              let (pdf, pages) = pagesForExport(ids: ids, wholeDocument: whole) else { return }
        let panel = NSOpenPanel()
        panel.title = "导出为 \(format == .png ? "PNG" : "JPEG") — 选择文件夹"
        panel.prompt = "导出"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let written = try ExportService.export(pdf: pdf, format: format, pages: pages, output: folder, baseName: exportBaseName)
            NSWorkspace.shared.activateFileViewerSelecting(written)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func exportAnnotationsInteractive(asMarkdown: Bool) {
        guard let document, !document.isLocked else { return }
        let pdf = document.pdf
        let pages = IndexSet(integersIn: 0..<pdf.pageCount)
        let format: ExportService.Format = asMarkdown ? .md : .txt
        let panel = NSSavePanel()
        panel.title = asMarkdown ? "导出标注为 Markdown" : "导出标注为纯文本"
        panel.allowedContentTypes = asMarkdown
            ? [UTType(filenameExtension: "md") ?? .plainText]
            : [.plainText]
        panel.nameFieldStringValue = "\(exportBaseName)-标注.\(asMarkdown ? "md" : "txt")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try ExportService.export(pdf: pdf, format: format, pages: pages, output: url, baseName: exportBaseName)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showError(error.localizedDescription)
        }
    }

    func exportOutlineInteractive() {
        guard let document, !document.isLocked else { return }
        let pdf = document.pdf
        let panel = NSSavePanel()
        panel.title = "导出目录"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(exportBaseName)-目录.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try ExportService.export(
                pdf: pdf, format: .outline,
                pages: IndexSet(integersIn: 0..<max(pdf.pageCount, 1)),
                output: url, baseName: exportBaseName
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showError(error.localizedDescription)
        }
    }

    func exportSummaryJSONInteractive() {
        guard let document, !document.isLocked else { return }
        let pdf = document.pdf
        let panel = NSSavePanel()
        panel.title = "导出文档摘要 JSON"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(exportBaseName)-summary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try ExportService.export(
                pdf: pdf, format: .json,
                pages: IndexSet(integersIn: 0..<pdf.pageCount),
                output: url, baseName: exportBaseName
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showError(error.localizedDescription)
        }
    }
}
