import SwiftUI

/// Preferences window (⌘,).
struct SettingsView: View {
    @AppStorage(Prefs.defaultColor) private var defaultColor = AnnotationColor.yellow.rawValue
    @AppStorage(Prefs.defaultLayout) private var defaultLayout = PageLayout.singleContinuous.rawValue
    @AppStorage(Prefs.rememberPosition) private var rememberPosition = true
    @AppStorage(Prefs.nightMode) private var nightMode = false
    @AppStorage(Prefs.preferTabsWhenOpening) private var preferTabsWhenOpening = true
    @ObservedObject private var updater = AppUpdater.shared
    @State private var clearedPositions = false
    @State private var isDefaultPDF = DefaultPDFApp.isDefault
    @State private var defaultPDFName = DefaultPDFApp.currentDefaultName
    @State private var defaultPDFMessage: String?

    var body: some View {
        Form {
            Section("阅读") {
                Picker("默认页面布局", selection: $defaultLayout) {
                    ForEach(PageLayout.allCases) { layout in
                        Text(layout.title).tag(layout.rawValue)
                    }
                }
                Toggle("新窗口默认使用夜间模式", isOn: $nightMode)
                Toggle("记住每个文件的阅读位置和缩放", isOn: $rememberPosition)
                Toggle("打开文件时使用标签页（同一窗口）", isOn: $preferTabsWhenOpening)
                    .onChange(of: preferTabsWhenOpening) { _ in
                        WindowTabbing.configureOpenWindows()
                    }
                Text("开启后，新打开的 PDF 会作为标签页加入当前窗口（⌘W 关闭当前标签）。也可在系统设置 › 桌面与程序坞中开启「打开文稿时优先使用标签页」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("清除阅读位置记录") {
                        UserDefaults.standard.removeObject(forKey: Prefs.positions)
                        clearedPositions = true
                    }
                    if clearedPositions {
                        Text("已清除").foregroundStyle(.secondary)
                    }
                }
            }

            Section("系统") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("默认 PDF 打开方式")
                        Text(isDefaultPDF ? "当前：iReader" : "当前：\(defaultPDFName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isDefaultPDF ? "已是默认" : "设为默认 PDF 打开方式") {
                        DefaultPDFApp.makeDefault { error in
                            isDefaultPDF = DefaultPDFApp.isDefault
                            defaultPDFName = DefaultPDFApp.currentDefaultName
                            if let error {
                                defaultPDFMessage = error.localizedDescription
                            } else if isDefaultPDF {
                                defaultPDFMessage = "已将 iReader 设为默认 PDF 应用。系统可能还会弹出一次确认。"
                            } else {
                                defaultPDFMessage = "已请求设为默认。若未生效，请在「系统设置 › 桌面与程序坞」或访达「显示简介」中确认。"
                            }
                        }
                    }
                    .disabled(isDefaultPDF)
                }
                if let defaultPDFMessage {
                    Text(defaultPDFMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("标注") {
                Picker("默认颜色", selection: $defaultColor) {
                    ForEach(AnnotationColor.allCases) { color in
                        Text(color.title).tag(color.rawValue)
                    }
                }
            }

            Section("更新") {
                Toggle("自动检查更新", isOn: $updater.autoCheckEnabled)
                HStack {
                    Text("当前版本 \(AppUpdater.currentVersion())（\(AppUpdater.currentBuild())）")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("检查更新…") { updater.checkForUpdatesFromMenu() }
                        .disabled(updater.isBusy)
                }
            }

            Text("布局、颜色和夜间模式的默认值对之后打开的窗口生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            isDefaultPDF = DefaultPDFApp.isDefault
            defaultPDFName = DefaultPDFApp.currentDefaultName
        }
    }
}
