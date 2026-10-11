import AppKit
import PDFKit
import SwiftUI

/// Sidebar tab listing every markup in the document.
struct AnnotationListSidebar: View {
    @ObservedObject var document: PDFFileDocument
    @ObservedObject var viewer: ViewerState
    @Environment(\.undoManager) private var undoManager
    @State private var entries: [Entry] = []

    struct Entry: Identifiable {
        let id: ObjectIdentifier
        let annotation: PDFAnnotation
        let page: PDFPage
        let pageIndex: Int
        let text: String
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "highlighter")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("还没有标注")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
                .listStyle(.sidebar)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Text("共 \(entries.count) 条")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("拷贝全部") { copyAll() }
                            .controlSize(.small)
                            .help("以 Markdown 列表拷贝所有标注（含页码与文字）")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
        .task(id: document.revision) {
            entries = Self.collect(from: document)
        }
    }

    private func row(_ entry: Entry) -> some View {
        Button {
            viewer.go(to: entry.annotation, on: entry.page)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: entry.annotation.kindSymbol)
                    .foregroundColor(Color(nsColor: entry.annotation.color.withAlphaComponent(1)))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("第 \(entry.pageIndex + 1) 页 · \(entry.annotation.kindTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !entry.text.isEmpty {
                        Text(entry.text)
                            .font(.callout)
                            .lineLimit(4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("颜色") {
                ForEach(AnnotationColor.allCases) { color in
                    Button(color.title) {
                        document.setColor(
                            entry.annotation.storedColor(for: color.nsColor),
                            for: entry.annotation, on: entry.page, undoManager: undoManager
                        )
                    }
                }
            }
            if !entry.text.isEmpty {
                Button("拷贝文字") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                }
            }
            Divider()
            Button("删除标注", role: .destructive) {
                document.removeAnnotations(
                    [PlacedAnnotation(annotation: entry.annotation, page: entry.page)],
                    actionName: "删除标注", undoManager: undoManager
                )
            }
        }
    }

    private func copyAll() {
        let lines = entries.map { entry -> String in
            let text = entry.text.isEmpty ? "" : " \(entry.text)"
            return "- p.\(entry.pageIndex + 1) [\(entry.annotation.kindTitle)]\(text)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    static func collect(from document: PDFFileDocument) -> [Entry] {
        var result: [Entry] = []
        for (index, page) in document.pages.enumerated() {
            for annotation in page.annotations where annotation.isUserMarkup {
                result.append(Entry(
                    id: ObjectIdentifier(annotation),
                    annotation: annotation,
                    page: page,
                    pageIndex: index,
                    text: text(of: annotation, on: page)
                ))
            }
        }
        return result
    }

    private static func text(of annotation: PDFAnnotation, on page: PDFPage) -> String {
        let raw: String
        if annotation.hasEditableText {
            raw = annotation.contents ?? ""
        } else if ["highlight", "underline", "strikeout", "squiggly"].contains(annotation.normalizedType) {
            raw = page.selection(for: annotation.bounds)?.string ?? ""
        } else {
            raw = annotation.contents ?? ""
        }
        let collapsed = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.count > 300 ? String(collapsed.prefix(300)) + "…" : collapsed
    }
}
