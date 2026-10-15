import AppKit
import Foundation
import PDFKit

/// Local URL-scheme bridge so other agents / scripts on the same Mac can drive
/// iReader without clicking the GUI.
///
/// Scheme: `ireader://`
///
/// Examples:
/// ```
/// open 'ireader://export?path=/tmp/a.pdf&format=md&out=/tmp/a.md&status=/tmp/a.status.json'
/// open 'ireader://export?path=/tmp/a.pdf&format=png&pages=1-3&out=/tmp/pages&status=/tmp/s.json'
/// open 'ireader://convert-word?paths=/tmp/a.docx|/tmp/b.docx&outdir=/tmp/pdfs&merge=1&status=/tmp/s.json'
/// open 'ireader://ping?status=/tmp/ping.json'
/// ```
enum AIBridge {
    static let scheme = "ireader"

    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == scheme else { return }
        let action = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let query = Self.queryItems(url)

        switch action {
        case "export":
            handleExport(query)
        case "convert-word", "convert_word", "word2pdf":
            handleConvertWord(query)
        case "ping":
            writeStatus(query["status"], ok: true, action: "ping", outputs: [], extra: [
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            ])
        default:
            writeStatus(query["status"], ok: false, action: action, outputs: [], error: "未知动作：\(action)。支持 export / convert-word / ping。")
        }
    }

    // MARK: - export

    @MainActor
    private static func handleExport(_ query: [String: String]) {
        let statusPath = query["status"]
        do {
            guard let path = query["path"], !path.isEmpty else {
                throw BridgeError.missing("path")
            }
            guard let formatRaw = query["format"], let format = ExportService.Format(rawValue: formatRaw.lowercased()) else {
                throw BridgeError.badFormat
            }
            guard let outRaw = query["out"], !outRaw.isEmpty else {
                throw BridgeError.missing("out")
            }

            let pdfURL = URL(fileURLWithPath: expand(path))
            let output = URL(fileURLWithPath: expand(outRaw))
            let password = query["password"]
            let pdf = try ExportService.openDocument(at: pdfURL, password: password)
            let pages = try ExportService.pageIndexSet(from: query["pages"], pageCount: pdf.pageCount)
            let base = pdfURL.deletingPathExtension().lastPathComponent

            if format.isMultiFile {
                // out must be a directory for images
                let dir = output
                let written = try ExportService.export(pdf: pdf, format: format, pages: pages, output: dir, baseName: base)
                writeStatus(statusPath, ok: true, action: "export", outputs: written.map(\.path), extra: [
                    "format": format.rawValue,
                    "pageCount": pages.count,
                ])
            } else {
                let written = try ExportService.export(pdf: pdf, format: format, pages: pages, output: output, baseName: base)
                writeStatus(statusPath, ok: true, action: "export", outputs: written.map(\.path), extra: [
                    "format": format.rawValue,
                    "pageCount": pages.count,
                ])
            }
        } catch {
            writeStatus(statusPath, ok: false, action: "export", outputs: [], error: error.localizedDescription)
        }
    }

    // MARK: - convert-word

    @MainActor
    private static func handleConvertWord(_ query: [String: String]) {
        let statusPath = query["status"]
        do {
            guard let pathsRaw = query["paths"], !pathsRaw.isEmpty else {
                throw BridgeError.missing("paths")
            }
            guard let outDirRaw = query["outdir"], !outDirRaw.isEmpty else {
                throw BridgeError.missing("outdir")
            }
            let paths = pathsRaw
                .split(whereSeparator: { $0 == "|" || $0 == "\n" })
                .map { URL(fileURLWithPath: expand(String($0).trimmingCharacters(in: .whitespaces))) }
                .filter { !$0.path.isEmpty }
            guard !paths.isEmpty else { throw BridgeError.missing("paths") }

            let outDir = URL(fileURLWithPath: expand(outDirRaw))
            let merge = ["1", "true", "yes"].contains((query["merge"] ?? "").lowercased())
            let result = try WordToPDFConverter.convert(urls: paths, outputDirectory: outDir, merge: merge)
            var extra: [String: Any] = [
                "engine": result.engine,
                "failed": result.failed.map(\.lastPathComponent),
            ]
            if let merged = result.mergedPath {
                extra["merged"] = merged
            } else {
                extra["merged"] = NSNull()
            }
            writeStatus(statusPath, ok: true, action: "convert-word", outputs: result.outputs.map(\.path), extra: extra)
        } catch {
            writeStatus(statusPath, ok: false, action: "convert-word", outputs: [], error: error.localizedDescription)
        }
    }

    // MARK: - helpers

    private static func queryItems(_ url: URL) -> [String: String] {
        var result: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                if let value = item.value {
                    result[item.name.lowercased()] = value
                }
            }
        }
        // Also accept a path-only form: ireader://export/path?... already covered by host.
        return result
    }

    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func writeStatus(
        _ path: String?,
        ok: Bool,
        action: String,
        outputs: [String],
        error: String? = nil,
        extra: [String: Any] = [:]
    ) {
        guard let path, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: expand(path))
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        var payload: [String: Any] = [
            "ok": ok,
            "action": action,
            "outputs": outputs,
            "finishedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        payload["error"] = error ?? NSNull()
        for (key, value) in extra {
            payload[key] = value
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    enum BridgeError: LocalizedError {
        case missing(String)
        case badFormat

        var errorDescription: String? {
            switch self {
            case .missing(let name): return "缺少参数：\(name)"
            case .badFormat: return "format 无效。支持：pdf, png, jpeg, md, txt, outline, json"
            }
        }
    }
}

/// Routes `ireader://` URLs into `AIBridge`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { @MainActor in
                AIBridge.handle(url)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cold-start with a URL is delivered via application(_:open:).
    }
}
