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

    init() {
        pdf = PDFDocument()
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let document = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if document.isLocked {
            throw CocoaError(.fileReadNoPermission, userInfo: [
                NSLocalizedDescriptionKey: "iReader 暂不支持打开有密码保护的 PDF。"
            ])
        }
        pdf = document
    }

    // MARK: Saving

    func snapshot(contentType: UTType) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}
