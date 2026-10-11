# iReader

一个**轻量、快速、原生**的 macOS PDF 阅读 / 编辑器，基于 SwiftUI + PDFKit，没有任何第三方依赖。

macOS 自带的「预览」删除页面、做简单标注都不够顺手，而现有的 PDF 工具又太重。iReader 只做最常用的几件事，并尽量做到顺手。

## 功能

- **打开 PDF**：「文件 > 打开…」、把 PDF 拖到窗口或 Dock 图标上；支持「打开最近使用」、多窗口
- **阅读**：连续滚动；放大 / 缩小 / 实际大小 / 适合窗口（工具栏、「显示」菜单 `⌘=` `⌘-` `⌘0` `⌘9`，或触控板捏合）
- **缩略图侧栏**：显示所有页面及页码，点击跳转
- **删除页面**：在侧栏中单选或多选（`⌘`/`⇧` 点击）后按 `Delete`、右键「删除页面」，或点工具栏垃圾桶（未选中时删除当前页）
- **调整页面顺序**：在侧栏中拖动缩略图
- **标注**
  - 高亮、下划线：选择工具后直接拖选文字
  - 画笔：在页面上自由绘制
  - 橡皮擦：点击已有的高亮 / 下划线 / 笔迹将其删除
  - 6 种颜色可选；「标注」菜单 `⌘1`–`⌘5` 快速切换工具
- **撤销 / 重做**：删除、排序和所有标注操作都可以 `⌘Z` / `⇧⌘Z`
- **保存 / 另存为**：`⌘S` 保存，`⌥⇧⌘S` 另存为；标注写入为标准 PDF 注释，在「预览」、Acrobat 等阅读器中同样可见

系统要求：macOS 13 Ventura 或更高版本（Apple Silicon 与 Intel 通用）。

## 下载

### 从 GitHub Actions 下载（每次提交自动构建）

1. 打开本仓库的 [Actions](https://github.com/BianYanhui/iReader/actions/workflows/build.yml) 页面（需要登录 GitHub）
2. 点击最新一次成功（绿色 ✓）的 **Build** 运行
3. 在页面底部 **Artifacts** 中下载 **iReader.zip**
4. 解压得到 `iReader.app`（双击 zip 即可），拖到「应用程序」文件夹

### 从 Releases 下载

推送 `v*` 标签（如 `v1.0.0`）时，构建好的 `iReader.zip` 会自动附加到 [Releases](https://github.com/BianYanhui/iReader/releases) 页面，解压一次即可。

## 首次打开（未签名应用）

iReader 没有使用 Apple 开发者证书签名或公证（只做了 ad-hoc 签名），第一次打开时 macOS 会阻止运行。任选一种方式：

- **右键打开**：在「访达」中右键（或按住 Control 点按）`iReader.app` → 「打开」→ 在弹窗中再点「打开」。之后即可正常双击打开。
  - macOS 15 Sequoia 及以上如果没有「打开」按钮：先双击一次，然后到「系统设置 > 隐私与安全性」底部点「仍要打开」。
- **终端去除隔离属性**：

  ```bash
  xattr -cr /Applications/iReader.app
  ```

  若提示「已损坏，无法打开」，同样执行上面的命令即可。

## 从源码构建

需要 Xcode 16 或更高版本：

```bash
git clone https://github.com/BianYanhui/iReader.git
cd iReader
open iReader.xcodeproj   # 然后在 Xcode 中运行（⌘R）
```

或命令行：

```bash
xcodebuild -project iReader.xcodeproj -scheme iReader -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Release/iReader.app
```

`iReader/` 目录是 Xcode 的「文件夹同步组」，在其中新增的 Swift 文件会自动加入编译，无需修改工程文件。

## 项目结构

```
iReader/
├── iReaderApp.swift        # 应用入口（DocumentGroup）
├── PDFFileDocument.swift   # 文档模型：读取 / 保存、页面与标注操作（含撤销）
├── ContentView.swift       # 窗口：侧栏 + 阅读区 + 工具栏
├── ThumbnailSidebar.swift  # 缩略图侧栏
├── PDFKitView.swift        # PDFView 封装与标注工具实现
├── AnnotationTool.swift    # 工具与颜色
├── ViewerState.swift       # 每个窗口的工具 / 缩放状态
└── ViewerCommands.swift    # 菜单命令
```

## 已知限制

- 暂不支持打开有密码保护的 PDF
- 标注创建后不能移动或修改颜色（可用橡皮擦删除后重画）
- 编辑会按 macOS 文档应用的惯例自动保存；如需回到旧版本，可用「文件 > 复原到」

## 许可证

[MIT](LICENSE)
