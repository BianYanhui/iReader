import SwiftUI

/// Preferences window (⌘,).
struct SettingsView: View {
    @AppStorage(Prefs.defaultColor) private var defaultColor = AnnotationColor.yellow.rawValue
    @AppStorage(Prefs.defaultLayout) private var defaultLayout = PageLayout.singleContinuous.rawValue
    @AppStorage(Prefs.rememberPosition) private var rememberPosition = true
    @AppStorage(Prefs.nightMode) private var nightMode = false
    @ObservedObject private var updater = AppUpdater.shared
    @State private var clearedPositions = false

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
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
