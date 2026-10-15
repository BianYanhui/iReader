import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Headless export helpers used by the File menu and the `ireader://` AI bridge.
enum ExportService {
    enum Format: String, CaseIterable {
        case pdf
        case png
        case jpeg
        case md
        case txt
        case outline
        case json

        var title: String {
            switch self {
            case .pdf: return "PDF"
            case .png: return "PNG 图片"
            case .jpeg: return "JPEG 图片"
            case .md: return "标注（Markdown）"
            case .txt: return "标注（纯文本）"
            case .outline: return "目录"
            case .json: return "文档摘要 JSON"
            }
        }

        var isImage: Bool { self == .png || self == .jpeg }
        var isMultiFile: Bool { isImage }
    }

    enum ExportError: LocalizedError {
        case cannotOpen
        case locked
        case empty
        case invalidPages
        case writeFailed(String)
        case noAnnotations
        case noOutline
        case badOutput

        var errorDescription: String? {
            switch self {
            case .cannotOpen: return "无法打开 PDF。"
            case .locked: return "PDF 受密码保护，请先在 iReader 中解锁，或在 URL 中提供 password=。"
            case .empty: return "文档没有页面。"
            case .invalidPages: return "页码范围无效。"
            case .writeFailed(let path): return "写入失败：\(path)"
            case .noAnnotations: return "文档中没有可导出的标注。"
            case .noOutline: return "文档没有目录（书签）。"
            case .badOutput: return "输出路径无效。"
            }
        }
    }

    /// Parses "1-3,5,8" (1-based, inclusive) into an IndexSet of 0-based indices.
    static func pageIndexSet(from spec: String?, pageCount: Int) throws -> IndexSet {
        guard let spec, !spec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return IndexSet(integersIn: 0..<pageCount)
        }
        var set = IndexSet()
        for part in spec.split(separator: ",") {
            let token = part.trimmingCharacters(in: .whitespaces)
            if token.contains("-") {
                let ends = token.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard ends.count == 2, let a = Int(ends[0]), let b = Int(ends[1]), a >= 1, b >= a else {
                    throw ExportError.invalidPages
                }
                let lo = max(0, a - 1)
                let hi = min(pageCount - 1, b - 1)
                if lo <= hi { set.insert(integersIn: lo...hi) }
            } else {
                guard let n = Int(token), n >= 1, n <= pageCount else { throw ExportError.invalidPages }
                set.insert(n - 1)
            }
        }
        guard !set.isEmpty else { throw ExportError.invalidPages }
        return set
    }

    static func openDocument(at url: URL, password: String?) throws -> PDFDocument {
        guard let pdf = PDFDocument(url: url) else { throw ExportError.cannotOpen }
        if pdf.isLocked {
            guard let password, pdf.unlock(withPassword: password) else { throw ExportError.locked }
        }
        guard pdf.pageCount > 0 else { throw ExportError.empty }
        return pdf
    }

    /// Exports `pdf` to `output`. For image formats, `output` must be a directory;
    /// for other formats it is a single file path. Returns written file URLs.
    ///
    /// PDF export keeps annotations as real PDF annotations (not flattened), so
    /// other readers still see highlights / ink / text boxes.
    @discardableResult
    static func export(
        pdf: PDFDocument,
        format: Format,
        pages: IndexSet,
        output: URL,
        baseName: String
    ) throws -> [URL] {
        let indices = pages.sorted()
        guard !indices.isEmpty else { throw ExportError.invalidPages }

        switch format {
        case .pdf:
            let out = PDFDocument()
            for (dst, src) in indices.enumerated() {
                guard let page = pdf.page(at: src), let copy = page.copy() as? PDFPage else { continue }
                out.insert(copy, at: dst)
            }
            guard out.pageCount > 0 else { throw ExportError.empty }
            try prepareFileParent(output)
            guard out.write(to: output) else { throw ExportError.writeFailed(output.path) }
            return [output]

        case .png, .jpeg:
            try prepareDirectory(output)
            var written: [URL] = []
            var failures = 0
            for src in indices {
                guard let page = pdf.page(at: src) else { failures += 1; continue }
                let box = page.bounds(for: .cropBox)
                var size = box.size
                if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
                let scale: CGFloat = 2
                let image = page.thumbnail(
                    of: CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale)),
                    for: .cropBox
                )
                guard let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff) else {
                    failures += 1
                    continue
                }
                let fileType: NSBitmapImageRep.FileType = format == .png ? .png : .jpeg
                let props: [NSBitmapImageRep.PropertyKey: Any] = format == .jpeg ? [.compressionFactor: 0.9] : [:]
                guard let data = bitmap.representation(using: fileType, properties: props) else {
                    failures += 1
                    continue
                }
                let ext = format == .png ? "png" : "jpg"
                let file = output.appendingPathComponent("\(baseName)-第\(src + 1)页.\(ext)")
                do {
                    try data.write(to: file, options: .atomic)
                    written.append(file)
                } catch {
                    failures += 1
                }
            }
            if written.isEmpty { throw ExportError.writeFailed(output.path) }
            return written

        case .md:
            let text = annotationMarkdown(from: pdf, pages: IndexSet(indices))
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ExportError.noAnnotations
            }
            try prepareFileParent(output)
            try text.write(to: output, atomically: true, encoding: .utf8)
            return [output]

        case .txt:
            let text = annotationPlainText(from: pdf, pages: IndexSet(indices))
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ExportError.noAnnotations
            }
            try prepareFileParent(output)
            try text.write(to: output, atomically: true, encoding: .utf8)
            return [output]

        case .outline:
            let text = outlineMarkdown(from: pdf)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ExportError.noOutline
            }
            try prepareFileParent(output)
            try text.write(to: output, atomically: true, encoding: .utf8)
            return [output]

        case .json:
            let payload = documentSummaryJSON(pdf: pdf, sourceName: baseName, pages: IndexSet(indices))
            try prepareFileParent(output)
            try payload.write(to: output, atomically: true, encoding: .utf8)
            return [output]
        }
    }

    // MARK: - Annotation / outline text

    struct AnnotationRecord {
        let pageIndex: Int
        let kind: String
        let text: String
    }

    static func annotationRecords(from pdf: PDFDocument, pages: IndexSet) -> [AnnotationRecord] {
        var result: [AnnotationRecord] = []
        for index in pages.sorted() {
            guard let page = pdf.page(at: index) else { continue }
            for annotation in page.annotations where annotation.isUserMarkup {
                let text = annotationText(annotation, on: page)
                result.append(AnnotationRecord(pageIndex: index, kind: annotation.kindTitle, text: text))
            }
        }
        return result
    }

    static func annotationMarkdown(from pdf: PDFDocument, pages: IndexSet) -> String {
        let records = annotationRecords(from: pdf, pages: pages)
        guard !records.isEmpty else { return "" }
        var lines = ["# 标注导出", ""]
        for record in records {
            let body = record.text.isEmpty ? "" : " \(record.text)"
            lines.append("- p.\(record.pageIndex + 1) [\(record.kind)]\(body)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func annotationPlainText(from pdf: PDFDocument, pages: IndexSet) -> String {
        let records = annotationRecords(from: pdf, pages: pages)
        guard !records.isEmpty else { return "" }
        return records.map { record in
            let body = record.text.isEmpty ? "" : "\t\(record.text)"
            return "p.\(record.pageIndex + 1)\t\(record.kind)\(body)"
        }.joined(separator: "\n") + "\n"
    }

    private static func annotationText(_ annotation: PDFAnnotation, on page: PDFPage) -> String {
        let raw: String
        if annotation.hasEditableText {
            raw = annotation.contents ?? ""
        } else if ["highlight", "underline", "strikeout", "squiggly"].contains(annotation.normalizedType) {
            raw = page.selection(for: annotation.bounds)?.string ?? ""
        } else {
            raw = annotation.contents ?? ""
        }
        return raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func outlineMarkdown(from pdf: PDFDocument) -> String {
        guard let root = pdf.outlineRoot else { return "" }
        var lines = ["# 目录", ""]
        func walk(_ outline: PDFOutline, depth: Int) {
            guard depth < 16 else { return }
            for i in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: i) else { continue }
                let label = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                var pageRef = ""
                if let destination = child.destination, let page = destination.page {
                    let index = pdf.index(for: page)
                    if index >= 0 { pageRef = " — p.\(index + 1)" }
                } else if let action = child.action as? PDFActionGoTo, let page = action.destination.page {
                    let index = pdf.index(for: page)
                    if index >= 0 { pageRef = " — p.\(index + 1)" }
                }
                let indent = String(repeating: "  ", count: max(0, depth))
                lines.append("\(indent)- \(label.isEmpty ? "（无标题）" : label)\(pageRef)")
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        lines.append("")
        return lines.count > 3 ? lines.joined(separator: "\n") : ""
    }

    static func documentSummaryJSON(pdf: PDFDocument, sourceName: String, pages: IndexSet) -> String {
        let annotations = annotationRecords(from: pdf, pages: pages).map { record -> [String: Any] in
            [
                "page": record.pageIndex + 1,
                "kind": record.kind,
                "text": record.text,
            ]
        }
        let pageList = pages.sorted().map { $0 + 1 }
        let payload: [String: Any] = [
            "app": "iReader",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "source": sourceName,
            "pageCount": pdf.pageCount,
            "pages": pageList,
            "annotationCount": annotations.count,
            "annotations": annotations,
            "hasOutline": pdf.outlineRoot != nil,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}\n"
        }
        return text
    }

    // MARK: - Paths

    private static func prepareFileParent(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private static func prepareDirectory(_ url: URL) throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue { throw ExportError.badOutput }
            return
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
