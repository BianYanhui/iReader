import SwiftUI
import PDFKit

/// Sidebar with tabs: thumbnails, outline (bookmarks) and search results.
struct SidebarView: View {
    @ObservedObject var document: PDFFileDocument
    @ObservedObject var viewer: ViewerState
    let onDelete: (Set<ObjectIdentifier>) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("侧栏", selection: $viewer.sidebarMode) {
                ForEach(SidebarMode.allCases) { mode in
                    Image(systemName: mode.symbolName)
                        .help(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            switch viewer.sidebarMode {
            case .thumbnails:
                ThumbnailSidebar(document: document, viewer: viewer, onDelete: onDelete)
            case .outline:
                OutlineSidebar(document: document, viewer: viewer)
            case .search:
                SearchResultsSidebar(viewer: viewer)
            }
        }
    }
}

// MARK: - Outline

private struct OutlineNode: Identifiable {
    let id: Int
    let label: String
    let outline: PDFOutline
    let children: [OutlineNode]?
}

private struct OutlineSidebar: View {
    @ObservedObject var document: PDFFileDocument
    @ObservedObject var viewer: ViewerState
    @State private var nodes: [OutlineNode] = []

    var body: some View {
        Group {
            if nodes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.indent")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("此 PDF 没有目录")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(nodes, children: \.children) { node in
                    Button {
                        open(node)
                    } label: {
                        Text(node.label)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(node.label)
                }
                .listStyle(.sidebar)
            }
        }
        .task(id: document.structureRevision) {
            nodes = Self.buildNodes(document.pdf)
        }
    }

    private func open(_ node: OutlineNode) {
        if let destination = node.outline.destination {
            viewer.go(to: destination)
        } else if let action = node.outline.action as? PDFActionGoTo {
            viewer.go(to: action.destination)
        }
    }

    private static func buildNodes(_ pdf: PDFDocument) -> [OutlineNode] {
        guard let root = pdf.outlineRoot else { return [] }
        var counter = 0
        func build(_ outline: PDFOutline, depth: Int) -> [OutlineNode] {
            guard depth < 16 else { return [] }
            var result: [OutlineNode] = []
            for index in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: index) else { continue }
                counter += 1
                let id = counter
                let children = build(child, depth: depth + 1)
                let label = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(OutlineNode(
                    id: id,
                    label: label.isEmpty ? "（无标题）" : label,
                    outline: child,
                    children: children.isEmpty ? nil : children
                ))
            }
            return result
        }
        return build(root, depth: 0)
    }
}

// MARK: - Search results

private struct SearchResultsSidebar: View {
    @ObservedObject var viewer: ViewerState

    var body: some View {
        if viewer.searchResults.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(viewer.lastSearchedText.isEmpty ? "在工具栏输入关键词后按回车搜索（⌘F）" : "没有找到「\(viewer.lastSearchedText)」")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(viewer.searchResults) { result in
                        Button {
                            viewer.selectSearchResult(at: result.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("第 \(result.pageIndex + 1) 页")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(result.context)
                                    .font(.callout)
                                    .lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            result.id == viewer.currentSearchIndex
                                ? Color.accentColor.opacity(0.2) : Color.clear
                        )
                        .id(result.id)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: viewer.currentSearchIndex) { index in
                    if let index { proxy.scrollTo(index) }
                }
                .safeAreaInset(edge: .bottom) {
                    Text("共 \(viewer.searchResults.count) 处匹配")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
        }
    }
}
