import SwiftUI
import PDFKit

/// Sidebar listing page thumbnails. Supports multi-selection, deleting
/// (Delete key, context menu) and reordering by drag and drop.
struct ThumbnailSidebar: View {
    @ObservedObject var document: PDFFileDocument
    @Binding var selection: Set<ObjectIdentifier>
    let onDelete: (Set<ObjectIdentifier>) -> Void

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let pages = document.pages
        List(selection: $selection) {
            ForEach(Array(pages.enumerated()), id: \.element.pageID) { index, page in
                ThumbnailRow(page: page, pageNumber: index + 1, revision: document.revision)
                    .tag(page.pageID)
            }
            .onMove { source, destination in
                document.movePages(fromOffsets: source, toOffset: destination, undoManager: undoManager)
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            onDelete(selection)
        }
        .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
            if !ids.isEmpty {
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

private struct ThumbnailRow: View {
    let page: PDFPage
    let pageNumber: Int
    let revision: Int

    @State private var image: NSImage?

    private struct RenderKey: Equatable {
        let page: ObjectIdentifier
        let revision: Int
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
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .task(id: RenderKey(page: page.pageID, revision: revision)) {
            image = page.thumbnail(of: CGSize(width: 240, height: 360), for: .cropBox)
        }
    }
}
