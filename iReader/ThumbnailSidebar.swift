import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Sidebar listing page thumbnails. Supports multi-selection, deleting
/// (Delete key, context menu) and reordering by drag and drop.
struct ThumbnailSidebar: View {
    @ObservedObject var document: PDFFileDocument
    @ObservedObject var viewer: ViewerState
    let onDelete: (Set<ObjectIdentifier>) -> Void

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let pages = document.pages
        ScrollViewReader { proxy in
            List(selection: $viewer.selection) {
                ForEach(Array(pages.enumerated()), id: \.element.pageID) { index, page in
                    ThumbnailRow(
                        page: page,
                        pageNumber: index + 1,
                        isCurrent: page.pageID == viewer.currentPageID,
                        stamp: document.stamp(for: page)
                    )
                    .tag(page.pageID)
                    .id(page.pageID)
                }
                .onMove { source, destination in
                    document.movePages(fromOffsets: source, toOffset: destination, undoManager: undoManager)
                }
                .onInsert(of: [.fileURL]) { index, providers in
                    // Dropping PDF files between thumbnails inserts their pages.
                    viewer.insertDroppedPDFs(providers, at: index)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: viewer.currentPageID) { id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .onDeleteCommand {
            onDelete(viewer.selection)
        }
        .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
            if !ids.isEmpty {
                Button("向左旋转") { viewer.rotate(by: -90, ids: ids) }
                Button("向右旋转") { viewer.rotate(by: 90, ids: ids) }
                Divider()
                Button(ids.count == 1 ? "复制页面（本页副本）" : "复制 \(ids.count) 个页面（本页副本）") { viewer.duplicatePages(ids: ids) }
                Button("拷贝页面到剪贴板") { viewer.copyPagesToClipboard(ids: ids) }
                Button("粘贴页面") { viewer.pastePagesFromClipboard() }
                Button("插入空白页") {
                    viewer.selection = ids
                    viewer.insertBlankPage()
                }
                Button("从文件插入页面…") {
                    viewer.selection = ids
                    viewer.insertPagesFromFile()
                }
                Button("合并到当前文档…") {
                    viewer.selection = ids
                    viewer.mergePDFsIntoCurrentDocument()
                }
                Divider()
                Button("提取为新 PDF…") { viewer.extractPages(ids: ids) }
                Button("导出 PDF…") { viewer.exportPDFInteractive(ids: ids) }
                Button("导出为 PNG…") { viewer.exportImagesInteractive(format: .png, ids: ids) }
                Button("导出为 JPEG…") { viewer.exportImagesInteractive(format: .jpeg, ids: ids) }
                Divider()
                Button(ids.count == 1 ? "删除页面" : "删除 \(ids.count) 个页面", role: .destructive) {
                    onDelete(ids)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("共 \(pages.count) 页")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }
}

extension PDFPage {
    var pageID: ObjectIdentifier { ObjectIdentifier(self) }
}

/// Small in-memory cache of rendered thumbnails. Entries hold the page weakly
/// so a recycled object address can never return a stale image.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private final class Entry {
        weak var page: PDFPage?
        let stamp: Int
        let image: NSImage

        init(page: PDFPage, stamp: Int, image: NSImage) {
            self.page = page
            self.stamp = stamp
            self.image = image
        }
    }

    private let cache: NSCache<NSNumber, Entry> = {
        let cache = NSCache<NSNumber, Entry>()
        cache.countLimit = 600
        return cache
    }()

    private func key(_ page: PDFPage) -> NSNumber {
        NSNumber(value: UInt(bitPattern: ObjectIdentifier(page).hashValue))
    }

    func image(for page: PDFPage, stamp: Int) -> NSImage? {
        guard let entry = cache.object(forKey: key(page)),
              entry.page === page, entry.stamp == stamp else { return nil }
        return entry.image
    }

    func store(_ image: NSImage, for page: PDFPage, stamp: Int) {
        cache.setObject(Entry(page: page, stamp: stamp, image: image), forKey: key(page))
    }
}

private struct ThumbnailRow: View {
    let page: PDFPage
    let pageNumber: Int
    let isCurrent: Bool
    let stamp: Int

    @State private var image: NSImage?

    private struct RenderKey: Equatable {
        let page: ObjectIdentifier
        let stamp: Int
        let rotation: Int
    }

    /// Width / height of the page as displayed (honouring rotation).
    private var aspectRatio: CGFloat {
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return 0.75 }
        let rotated = page.rotation % 180 != 0
        return rotated ? bounds.height / bounds.width : bounds.width / bounds.height
    }

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.white)
                        .aspectRatio(aspectRatio, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 180)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)

            Text("\(pageNumber)")
                .font(.caption)
                .fontWeight(isCurrent ? .bold : .regular)
                .foregroundColor(isCurrent ? .accentColor : .secondary)
        }
        .padding(.vertical, 4)
        .task(id: RenderKey(page: page.pageID, stamp: stamp, rotation: page.rotation)) {
            if let cached = ThumbnailCache.shared.image(for: page, stamp: stamp &+ page.rotation) {
                image = cached
                return
            }
            // Let fast scrolling cancel rows that scroll out before rendering.
            await Task.yield()
            if Task.isCancelled { return }
            let rendered = page.thumbnail(of: CGSize(width: 220, height: 320), for: .cropBox)
            ThumbnailCache.shared.store(rendered, for: page, stamp: stamp &+ page.rotation)
            image = rendered
        }
    }
}
