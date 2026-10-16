import AppKit
import UniformTypeIdentifiers

/// Registers (or reports) iReader as the default handler for PDF files.
enum DefaultPDFApp {
    /// `true` when the default app for `com.adobe.pdf` is this bundle.
    static var isDefault: Bool {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: UTType.pdf) else {
            return false
        }
        return url.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath()
    }

    /// Display name of the current default PDF app, if any.
    static var currentDefaultName: String {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: UTType.pdf) else {
            return "未知"
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    /// Asks macOS to make iReader the default PDF opener. The system may still
    /// show a confirmation sheet once.
    static func makeDefault(completion: @escaping (Error?) -> Void) {
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: UTType.pdf) { error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }
}
