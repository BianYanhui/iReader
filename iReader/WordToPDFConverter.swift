import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Converts `.doc` / `.docx` files to PDF without a third-party Swift package.
///
/// Engines tried in order:
/// 1. **Cocoa** — `NSAttributedString` loads the Word file (macOS built-in importers)
///    and we paginate into a PDF with `NSLayoutManager`.
/// 2. **textutil** — Apple's CLI (`textutil -convert pdf`), when available.
/// 3. **LibreOffice** — `soffice --headless --convert-to pdf`, when installed.
///
/// CI only compiles this code; conversion is exercised on a real Mac. The UI
/// explains which engines were tried when all fail.
enum WordToPDFConverter {
    struct Result {
        var outputs: [URL]
        var failed: [URL]
        var mergedPath: String?
        var engine: String
    }

    enum ConverterError: LocalizedError {
        case noInput
        case nothingConverted(String)
        case cannotCreateOutput

        var errorDescription: String? {
            switch self {
            case .noInput: return "没有选择 Word 文件。"
            case .nothingConverted(let detail): return "未能转换成 PDF。\n\(detail)"
            case .cannotCreateOutput: return "无法创建输出目录。"
            }
        }
    }

    static var supportedTypes: [UTType] {
        var types: [UTType] = []
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        types.append(contentsOf: [.pdf]) // ignore if user drops mixed; filtered later
        return types.filter { $0.identifier != "com.adobe.pdf" }
    }

    /// Interactive batch conversion: pick Word files → pick folder → convert → optional merge.
    @MainActor
    static func runInteractive() {
        let open = NSOpenPanel()
        open.title = "选择 Word 文件"
        open.message = "可多选 .doc / .docx。将逐个转为 PDF；可选再合并为一个文件。"
        open.prompt = "选择"
        open.allowsMultipleSelection = true
        open.allowedContentTypes = {
            var list: [UTType] = []
            if let docx = UTType(filenameExtension: "docx") { list.append(docx) }
            if let doc = UTType(filenameExtension: "doc") { list.append(doc) }
            return list
        }()
        guard open.runModal() == .OK, !open.urls.isEmpty else { return }

        let folder = NSOpenPanel()
        folder.title = "选择 PDF 输出文件夹"
        folder.prompt = "导出"
        folder.canChooseDirectories = true
        folder.canChooseFiles = false
        folder.canCreateDirectories = true
        guard folder.runModal() == .OK, let outDir = folder.url else { return }

        let mergeAlert = NSAlert()
        mergeAlert.messageText = "转换完成后是否合并为一个 PDF？"
        mergeAlert.informativeText = "每个 Word 仍会单独保存一份 PDF；若选择合并，会额外生成「合并.pdf」。"
        mergeAlert.addButton(withTitle: "转换并合并")
        mergeAlert.addButton(withTitle: "仅分别转换")
        mergeAlert.addButton(withTitle: "取消")
        let mergeResponse = mergeAlert.runModal()
        if mergeResponse == .alertThirdButtonReturn { return }
        let merge = mergeResponse == .alertFirstButtonReturn

        do {
            let result = try convert(urls: open.urls, outputDirectory: outDir, merge: merge)
            let alert = NSAlert()
            if result.outputs.isEmpty {
                alert.messageText = "没有成功转换的文件"
                alert.informativeText = """
                失败 \(result.failed.count) 个。引擎：\(result.engine)

                可尝试：
                • 确认文件未损坏，且为 .doc / .docx
                • 安装 LibreOffice（https://www.libreoffice.org）后重试
                • 用「文本编辑」打开该 Word 再另存为 PDF
                """
                alert.alertStyle = .warning
            } else {
                alert.messageText = "已转换 \(result.outputs.count) 个 PDF"
                var info = "引擎：\(result.engine)\n输出：\(outDir.path)"
                if let merged = result.mergedPath {
                    info += "\n合并文件：\(merged)"
                }
                if !result.failed.isEmpty {
                    info += "\n\n失败：\n" + result.failed.map(\.lastPathComponent).joined(separator: "\n")
                }
                alert.informativeText = info
            }
            alert.runModal()
            if !result.outputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "批量转换失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    static func convert(urls: [URL], outputDirectory: URL, merge: Bool) throws -> Result {
        let inputs = urls.filter { isWordFile($0) }
        guard !inputs.isEmpty else { throw ConverterError.noInput }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var outputs: [URL] = []
        var failed: [URL] = []
        var enginesUsed = Set<String>()

        for url in inputs {
            let dest = outputDirectory.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".pdf")
            if let engine = convertOne(url, to: dest) {
                outputs.append(dest)
                enginesUsed.insert(engine)
            } else {
                failed.append(url)
            }
        }

        var mergedPath: String?
        if merge, outputs.count >= 2 {
            let mergedURL = outputDirectory.appendingPathComponent("合并.pdf")
            if mergePDFs(outputs, into: mergedURL) {
                mergedPath = mergedURL.path
                outputs.append(mergedURL)
            }
        }

        let engineLabel = enginesUsed.sorted().joined(separator: "+")
        if outputs.isEmpty {
            throw ConverterError.nothingConverted(failureHint(failedCount: failed.count))
        }
        return Result(outputs: outputs, failed: failed, mergedPath: mergedPath, engine: engineLabel.isEmpty ? "none" : engineLabel)
    }

    private static func isWordFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "doc" || ext == "docx"
    }

    /// Returns the engine name on success.
    private static func convertOne(_ source: URL, to destination: URL) -> String? {
        if convertWithCocoa(source, to: destination) { return "cocoa" }
        if convertWithTextutil(source, to: destination) { return "textutil" }
        if convertWithLibreOffice(source, to: destination) { return "libreoffice" }
        return nil
    }

    // MARK: - Cocoa (NSAttributedString → PDF)

    private static func convertWithCocoa(_ source: URL, to destination: URL) -> Bool {
        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
            let attributed = try NSAttributedString(url: source, options: options, documentAttributes: nil)
            guard attributed.length > 0 else { return false }
            let data = renderPDF(from: attributed)
            guard !data.isEmpty else { return false }
            try data.write(to: destination, options: .atomic)
            return PDFDocument(url: destination)?.pageCount ?? 0 > 0
        } catch {
            return false
        }
    }

    /// Paginate an attributed string into an A4 PDF.
    private static func renderPDF(from attributed: NSAttributedString) -> Data {
        let pageSize = CGSize(width: 595.28, height: 841.89) // A4
        let margin: CGFloat = 56
        let contentWidth = pageSize.width - margin * 2
        let contentHeight = pageSize.height - margin * 2

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        var glyphIndex = 0
        let totalGlyphs = layoutManager.numberOfGlyphs
        if totalGlyphs == 0 {
            // Still emit one blank-ish page with a note? Skip — treat as failure upstream.
            context.closePDF()
            return Data()
        }

        while glyphIndex < totalGlyphs {
            let container = NSTextContainer(size: CGSize(width: contentWidth, height: contentHeight))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)

            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.length == 0 {
                layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
                break
            }

            context.beginPDFPage(nil)
            context.saveGState()
            // AppKit draws flipped; PDF is not.
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            let origin = CGPoint(x: margin, y: margin)
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
            context.restoreGState()
            context.endPDFPage()

            glyphIndex = NSMaxRange(glyphRange)
            layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
        }

        context.closePDF()
        return data as Data
    }

    // MARK: - textutil

    private static func convertWithTextutil(_ source: URL, to destination: URL) -> Bool {
        let tool = "/usr/bin/textutil"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return false }
        // textutil writes next to the source unless -output is given (supported on modern macOS).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["-convert", "pdf", "-output", destination.path, source.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: destination.path)
        } catch {
            return false
        }
    }

    // MARK: - LibreOffice

    private static func convertWithLibreOffice(_ source: URL, to destination: URL) -> Bool {
        let candidates = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/usr/local/bin/soffice",
            "/opt/homebrew/bin/soffice",
        ]
        guard let soffice = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return false
        }
        let outDir = destination.deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: soffice)
        process.arguments = [
            "--headless",
            "--nologo",
            "--nofirststartwizard",
            "--convert-to", "pdf",
            "--outdir", outDir.path,
            source.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let produced = outDir.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".pdf")
            if produced.path != destination.path, FileManager.default.fileExists(atPath: produced.path) {
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.moveItem(at: produced, to: destination)
            }
            return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: destination.path)
        } catch {
            return false
        }
    }

    private static func mergePDFs(_ urls: [URL], into destination: URL) -> Bool {
        let output = PDFDocument()
        var cursor = 0
        for url in urls {
            guard let doc = PDFDocument(url: url) else { continue }
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i), let copy = page.copy() as? PDFPage else { continue }
                output.insert(copy, at: cursor)
                cursor += 1
            }
        }
        guard output.pageCount > 0 else { return false }
        return output.write(to: destination)
    }

    private static func failureHint(failedCount: Int) -> String {
        """
        失败 \(failedCount) 个文件。已尝试：Cocoa 导入、textutil、LibreOffice。
        若文件较复杂，请安装 LibreOffice 后重试，或在「文本编辑」中打开再导出 PDF。
        """
    }
}
