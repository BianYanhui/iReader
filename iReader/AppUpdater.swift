import AppKit
import Foundation
import SwiftUI

/// Checks GitHub Releases for a newer `iReader.zip` and replaces this app in place.
///
/// Sparkle was considered but not used: it needs EdDSA keys, an appcast feed and
/// extra CI, and the project aims for zero third-party dependencies. Updates are
/// authenticated by HTTPS to the official repo, plus bundle-ID and version checks.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    static let owner = "BianYanhui"
    static let repo = "iReader"
    static let assetName = "iReader.zip"
    static let expectedBundleID = "io.github.bianyanhui.iReader"
    static let autoCheckKey = "iReader.autoCheckForUpdates"
    static let lastCheckKey = "iReader.lastUpdateCheck"

    @Published private(set) var isBusy = false
    @Published var autoCheckEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCheckEnabled, forKey: Self.autoCheckKey) }
    }

    private let session: URLSession
    private var progressAlert: NSAlert?
    private var progressIndicator: NSProgressIndicator?

    private init() {
        if UserDefaults.standard.object(forKey: Self.autoCheckKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.autoCheckKey)
        }
        autoCheckEnabled = UserDefaults.standard.bool(forKey: Self.autoCheckKey)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    private var didScheduleLaunchCheck = false

    /// Called once after launch. Silent when already up to date.
    func checkOnLaunchIfNeeded() {
        guard !didScheduleLaunchCheck else { return }
        didScheduleLaunchCheck = true
        guard autoCheckEnabled else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 60 * 60 else { return }
        Task { await checkForUpdates(interactive: false) }
    }

    /// Menu / Help action.
    func checkForUpdatesFromMenu() {
        Task { await checkForUpdates(interactive: true) }
    }

    func checkForUpdates(interactive: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let release = try await fetchLatestRelease()
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

            let current = Self.currentVersion()
            guard Self.isVersion(release.version, newerThan: current) else {
                if interactive {
                    presentInfo(
                        title: "已是最新版本",
                        message: "当前版本 \(current)，最新发布也是 \(release.version)。"
                    )
                }
                return
            }

            let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
            let message: String
            if let notes, !notes.isEmpty {
                message = "当前版本 \(current) → \(release.version)\n\n\(Self.plainText(fromMarkdown: notes))"
            } else {
                message = "当前版本 \(current)，可更新到 \(release.version)。"
            }

            let update = presentChoice(
                title: "发现新版本 \(release.version)",
                message: message + "\n\n更新将退出并重新打开 iReader。请先保存所有更改。",
                confirm: "立即更新",
                cancel: "稍后"
            )
            guard update else { return }

            if NSDocumentController.shared.documents.contains(where: \.isDocumentEdited) {
                presentInfo(
                    title: "请先保存",
                    message: "有未保存的文档。请先保存或关闭它们，然后再更新。"
                )
                return
            }

            try await downloadAndInstall(release)
        } catch {
            if interactive || !(error is CancellationError) {
                presentError(error)
            }
        }
    }

    // MARK: - GitHub Releases

    struct ReleaseInfo {
        let version: String
        let tagName: String
        let body: String?
        let downloadURL: URL
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("iReader/\(Self.currentVersion())", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 {
                throw UpdateError.noReleases
            }
            guard (200..<300).contains(http.statusCode) else {
                throw UpdateError.httpStatus(http.statusCode)
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw UpdateError.badResponse
        }

        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let asset = assets.first(where: { ($0["name"] as? String) == Self.assetName }),
              let download = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: download) else {
            throw UpdateError.missingAsset
        }

        return ReleaseInfo(
            version: Self.normalizedVersion(tag),
            tagName: tag,
            body: json["body"] as? String,
            downloadURL: downloadURL
        )
    }

    // MARK: - Download & install

    private func downloadAndInstall(_ release: ReleaseInfo) async throws {
        let destination = Bundle.main.bundleURL
        guard destination.pathExtension == "app" else {
            throw UpdateError.notInstalled
        }
        guard FileManager.default.isWritableFile(atPath: destination.path)
                || FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            throw UpdateError.notWritable(destination.path)
        }

        showProgress(title: "正在下载 iReader \(release.version)…")
        defer { hideProgress() }

        let (tempURL, response) = try await session.download(from: release.downloadURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.httpStatus(http.statusCode)
        }

        updateProgress(title: "正在安装…", indeterminate: true)

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iReader-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let zipPath = workDir.appendingPathComponent(Self.assetName)
        // `download(from:)` may place the file in a location that disappears; move it first.
        if FileManager.default.fileExists(atPath: zipPath.path) {
            try FileManager.default.removeItem(at: zipPath)
        }
        try FileManager.default.moveItem(at: tempURL, to: zipPath)

        let unzipDir = workDir.appendingPathComponent("unzipped", isDirectory: true)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        try Self.unzip(zipPath, into: unzipDir)

        let newApp = try Self.findAppBundle(in: unzipDir)
        try Self.validateAppBundle(newApp, expectedVersion: release.version)

        // Clear quarantine on the downloaded bundle before swapping.
        _ = try? Self.run("/usr/bin/xattr", arguments: ["-cr", newApp.path])

        try Self.launchReplacementScript(
            sourceApp: newApp,
            destinationApp: destination,
            pid: ProcessInfo.processInfo.processIdentifier
        )

        // Give the script a moment to start watching our PID, then exit.
        // Use exit(0) instead of terminate so unsaved-document panels cannot
        // cancel the quit and leave the installer script waiting forever.
        try await Task.sleep(nanoseconds: 300_000_000)
        hideProgress()
        exit(0)
    }

    private static func unzip(_ zip: URL, into directory: URL) throws {
        let result = try run("/usr/bin/ditto", arguments: ["-x", "-k", zip.path, directory.path])
        guard result == 0 else { throw UpdateError.unzipFailed }
    }

    private static func findAppBundle(in directory: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        if let direct = contents.first(where: { $0.lastPathComponent == "iReader.app" }) {
            return direct
        }
        // Nested zip-in-zip or unexpected layout: search one level deeper.
        for item in contents where item.hasDirectoryPath {
            let nested = try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
            if let app = nested.first(where: { $0.lastPathComponent == "iReader.app" }) {
                return app
            }
        }
        throw UpdateError.missingAppInZip
    }

    private static func validateAppBundle(_ app: URL, expectedVersion: String) throws {
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String else {
            throw UpdateError.invalidAppBundle
        }
        guard bundleID == expectedBundleID else {
            throw UpdateError.bundleIDMismatch(bundleID)
        }
        let version = (info["CFBundleShortVersionString"] as? String).map(normalizedVersion)
            ?? expectedVersion
        // Bundle must not be older than the release we asked for, and must be newer than us.
        if isVersion(expectedVersion, newerThan: version) {
            throw UpdateError.versionNotNewer(version)
        }
        if !isVersion(version, newerThan: currentVersion()) {
            throw UpdateError.versionNotNewer(version)
        }
        let executable = app.appendingPathComponent("Contents/MacOS/iReader")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UpdateError.invalidAppBundle
        }
    }

    /// Spawns a detached shell script that waits for this process to exit, then
    /// replaces the .app and relaunches it.
    private static func launchReplacementScript(sourceApp: URL, destinationApp: URL, pid: Int32) throws {
        // Keep the new app outside the work dir we delete in defer — copy to a sibling temp.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("iReader-new-\(UUID().uuidString).app", isDirectory: true)
        if FileManager.default.fileExists(atPath: staging.path) {
            try FileManager.default.removeItem(at: staging)
        }
        try FileManager.default.copyItem(at: sourceApp, to: staging)

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iReader-install-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        set -e
        PID="\(pid)"
        SRC="\(staging.path)"
        DST="\(destinationApp.path)"
        LOG="$HOME/Library/Logs/iReader-update.log"
        mkdir -p "$(dirname "$LOG")"
        exec >>"$LOG" 2>&1
        echo "$(date) updating iReader (pid=$PID)"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        sleep 0.4
        /usr/bin/xattr -cr "$SRC" || true
        /bin/rm -rf "$DST"
        /usr/bin/ditto "$SRC" "$DST"
        /usr/bin/codesign --force --deep --sign - "$DST" || true
        /usr/bin/xattr -cr "$DST" || true
        /bin/rm -rf "$SRC"
        /usr/bin/open "$DST"
        /bin/rm -f "$0"
        echo "$(date) done"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    @discardableResult
    private static func run(_ launchPath: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: - Version helpers

    static func currentVersion() -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return normalizedVersion(raw)
    }

    static func currentBuild() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static func normalizedVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") {
            s.removeFirst()
        }
        return s
    }

    /// True when `lhs` is strictly newer than `rhs` (semver-ish: major.minor.patch).
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let a = numericParts(lhs)
        let b = numericParts(rhs)
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func numericParts(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { part in
                let digits = part.prefix(while: { $0.isNumber })
                return Int(digits) ?? 0
            }
    }

    /// Very light Markdown → plain text for the alert body.
    static func plainText(fromMarkdown markdown: String) -> String {
        var text = markdown
        let patterns: [(String, String)] = [
            (#"```[\s\S]*?```"#, ""),
            (#"`([^`]*)`"#, "$1"),
            (#"!\[[^\]]*\]\([^)]*\)"#, ""),
            (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),
            (#"^#{1,6}\s+"#, ""),
            (#"^\s*[-*+]\s+"#, "• "),
            (#"\*\*([^*]+)\*\*"#, "$1"),
            (#"__([^_]+)__"#, "$1"),
            (#"\*([^*]+)\*"#, "$1"),
        ]
        for (pattern, template) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
            }
        }
        // Cap length so the alert stays readable.
        let maxLen = 1200
        if text.count > maxLen {
            let idx = text.index(text.startIndex, offsetBy: maxLen)
            text = String(text[..<idx]) + "…"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Alerts

    private func presentInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @discardableResult
    private func presentChoice(title: String, message: String, confirm: String, cancel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "检查更新失败"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        if case UpdateError.noReleases = error as? UpdateError {
            alert.addButton(withTitle: "打开 Releases 页面")
            if alert.runModal() == .alertSecondButtonReturn {
                if let url = URL(string: "https://github.com/\(Self.owner)/\(Self.repo)/releases") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }
        alert.runModal()
    }

    private func showProgress(title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "请稍候，不要退出 iReader。"
        alert.alertStyle = .informational

        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 260, height: 16))
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        alert.accessoryView = indicator

        progressIndicator = indicator
        progressAlert = alert

        // Show non-blocking so downloads can proceed on the main actor with awaits.
        let window = alert.window
        window.level = .floating
        alert.layout()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func updateProgress(title: String, indeterminate: Bool) {
        progressAlert?.messageText = title
        progressIndicator?.isIndeterminate = indeterminate
        if indeterminate {
            progressIndicator?.startAnimation(nil)
        }
    }

    private func hideProgress() {
        progressAlert?.window.orderOut(nil)
        progressAlert = nil
        progressIndicator = nil
    }
}

enum UpdateError: LocalizedError {
    case noReleases
    case missingAsset
    case badResponse
    case httpStatus(Int)
    case notInstalled
    case notWritable(String)
    case unzipFailed
    case missingAppInZip
    case invalidAppBundle
    case bundleIDMismatch(String)
    case versionNotNewer(String)
    case unsavedDocuments

    var errorDescription: String? {
        switch self {
        case .noReleases:
            return "还没有任何 GitHub Release。发布一个 v* 标签后，构建会自动附上 iReader.zip。"
        case .missingAsset:
            return "最新 Release 中没有找到 iReader.zip 资源。"
        case .badResponse:
            return "无法解析 GitHub 的响应。"
        case .httpStatus(let code):
            return "GitHub 返回了 HTTP \(code)。"
        case .notInstalled:
            return "当前不是从 .app 包运行（例如在 Xcode 里调试）。请先把 iReader.app 装到「应用程序」后再更新。"
        case .notWritable(let path):
            return "没有权限写入：\n\(path)\n请把应用拖到你的「应用程序」文件夹后再试。"
        case .unzipFailed:
            return "解压下载的更新包失败。"
        case .missingAppInZip:
            return "更新包里没有找到 iReader.app。"
        case .invalidAppBundle:
            return "更新包中的应用无效。"
        case .bundleIDMismatch(let id):
            return "更新包的 Bundle ID（\(id)）与当前应用不一致，已取消安装。"
        case .versionNotNewer(let v):
            return "下载到的版本（\(v)）不比当前版本新，已取消安装。"
        case .unsavedDocuments:
            return "有未保存的文档。请先保存或关闭它们，然后再更新。"
        }
    }
}
