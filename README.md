# iReader

一个**轻量、快速、原生**的 macOS PDF 阅读 / 编辑器，基于 SwiftUI + PDFKit，没有任何第三方依赖。

macOS 自带的「预览」删除页面、做简单标注都不够顺手，而现有的 PDF 工具又太重。iReader 只做最常用的几件事，并尽量做到顺手。

## 功能

**阅读与导航**
- 打开 PDF：「文件 > 打开…」、拖到窗口或 Dock 图标；「打开最近使用」、多窗口
- 侧栏四个标签：**缩略图**、**目录**（PDF 书签，可展开）、**标注**列表、**搜索结果**（`⌥⌘1`–`⌥⌘4`）
- **全文搜索**：`⌘F` 输入关键词后回车，侧栏列出所有匹配及上下文；`⌘G` / `⇧⌘G` 在结果间跳转，匹配处高亮
- 工具栏显示「当前页 / 总页数」，点击或 `⌥⌘G` **前往页面**；「前往」菜单可上一页 / 下一页 / 首页 / 末页
- **页面布局**：单页、单页连续、双页、双页连续
- 缩放：放大 / 缩小 / 实际大小 / 自动 / **适合宽度** / **适合整页**，或触控板捏合
- **夜间模式**（`⌥⌘N`）：反色阅读，同时保留颜色色相
- **记住每个文件的阅读位置和缩放**，下次打开自动回到上次的页面
- **密码保护的 PDF**：打开时输入密码解锁，保存后仍保留密码
- 打印（`⌘P`）

**标注**
- 高亮、下划线、**删除线**：选择工具后拖选文字
- 画笔自由绘制，**矩形**框、**箭头**：拖动绘制
- **文本框**：点击页面输入文字（批注）
- 橡皮擦：点击任意标注删除
- **右键任意标注**：改颜色、编辑文本框文字、拷贝被标注的文字、删除
- **标注列表**：列出全部标注（页码、类型、文字），点击跳转；「拷贝全部」以 Markdown 列表导出，方便整理读书笔记
- 6 种颜色；「标注」菜单 `⌘1`–`⌘9` 切换工具
- 标注写入为标准 PDF 注释，在「预览」、Acrobat 等阅读器中同样可见

**页面操作**（作用于侧栏选中的页面，未选中时作用于当前页；工具栏「页面」按钮、「页面」菜单或侧栏右键）
- 删除（侧栏中按 `Delete`）、拖动缩略图**调整顺序**
- **旋转**（`⌘L` / `⌘R`）
- **插入空白页**、**复制页面**
- **从其他 PDF 插入页面**，或直接把 PDF 文件**拖到侧栏缩略图之间**合并
- **合并 PDF**：
  - 「文件 > 合并 PDF…」（`⌥⇧⌘M`）：多选若干 PDF → 调整顺序 → 保存为一个新文件并打开（无需先打开文档）
  - 「页面 > 合并到当前文档…」（`⌥⌘M`）：把其他 PDF 合并进正在编辑的文档，可选追加到末尾 / 插入到选中页之后 / 插入到开头，可撤销
- **提取所选页面为新 PDF**
- **导出为 PNG**（144 dpi，包含标注）

**其他**
- 所有页面与标注操作都可撤销 / 重做（`⌘Z` / `⇧⌘Z`）
- 保存 `⌘S`、另存为 `⌥⇧⌘S`
- **设置**（`⌘,`）：默认页面布局、默认标注颜色、默认夜间模式、是否记住阅读位置、自动检查更新
- **帮助 > 键盘快捷键**（`⇧⌘/`）
- **检查更新**：应用菜单或「帮助」里的「检查更新…」；从 [GitHub Releases](https://github.com/BianYanhui/iReader/releases) 下载最新 `iReader.zip` 并重启。若当前是从临时目录运行的，会安装到「应用程序」文件夹（无需第三方更新框架）

## 键盘快捷键

| 操作 | 快捷键 |
| --- | --- |
| 搜索 / 下一个 / 上一个 | `⌘F` / `⌘G` / `⇧⌘G` |
| 前往页面 | `⌥⌘G` |
| 下一页 / 上一页 | `⌥⌘↓` / `⌥⌘↑` |
| 首页 / 末页 | `⌥⇧⌘↑` / `⌥⇧⌘↓` |
| 放大 / 缩小 / 实际大小 | `⌘=` / `⌘-` / `⌘0` |
| 自动缩放 / 适合宽度 / 适合整页 | `⌘9` / `⌘8` / `⌘7` |
| 夜间模式 | `⌥⌘N` |
| 侧栏标签 | `⌥⌘1`–`⌥⌘4` |
| 标注工具（选择…橡皮擦） | `⌘1`–`⌘9` |
| 向左 / 向右旋转页面 | `⌘L` / `⌘R` |
| 插入空白页 / 复制页面 | `⌥⌘B` / `⌥⌘D` |
| 从文件插入页面 | `⌥⌘I` |
| 合并到当前文档 / 合并为新文件 | `⌥⌘M` / `⌥⇧⌘M` |
| 提取为新 PDF / 导出 PNG | `⌥⌘E` / `⌥⇧⌘E` |
| 删除页面 | 侧栏 `⌫` 或 `⌥⌘⌫` |
| 打印 / 保存 / 另存为 | `⌘P` / `⌘S` / `⌥⇧⌘S` |
| 撤销 / 重做 | `⌘Z` / `⇧⌘Z` |
| 设置 / 快捷键一览 | `⌘,` / `⇧⌘/` |

系统要求：macOS 13 Ventura 或更高版本（Apple Silicon 与 Intel 通用）。

## 下载

### 从 GitHub Actions 下载（每次提交自动构建）

1. 打开本仓库的 [Actions](https://github.com/BianYanhui/iReader/actions/workflows/build.yml) 页面（需要登录 GitHub）
2. 点击最新一次成功（绿色 ✓）的 **Build** 运行
3. 在页面底部 **Artifacts** 中下载 **iReader.zip**
4. 解压得到 `iReader.app`（双击 zip 即可），**务必拖到「应用程序」文件夹**后再打开（不要直接在下载/临时目录里长期运行，否则系统清理临时文件可能导致崩溃）

### 从 Releases 下载

推送 `v*` 标签（如 `v1.1.0`）时，构建好的 `iReader.zip` 会自动附加到 [Releases](https://github.com/BianYanhui/iReader/releases) 页面，解压一次即可。应用内「检查更新…」也从这里取最新版。

## 发布新版本（给维护者）

应用通过 **GitHub Releases** 做应用内更新（自建逻辑，不用 Sparkle，因此也不需要付费的 Apple 开发者证书）。流程：

1. 在 `iReader.xcodeproj` 里把 `MARKETING_VERSION`（以及需要时的 `CURRENT_PROJECT_VERSION`）改成新版本号，例如 `1.1.1`，并提交到 `main`
2. 打并推送标签（必须带 `v` 前缀，且与版本号一致）：

   ```bash
   git tag v1.1.1
   git push origin v1.1.1
   ```

3. GitHub Actions 在 macOS 上构建、ad-hoc 签名，把 `iReader.zip` 挂到该标签对应的 Release 上
4. 已安装的旧版 iReader 在「检查更新…」或自动检查时会看到新版本，确认后下载 zip、替换 `.app` 并重新打开

**测试更新流程建议：**

1. 先发布一个基准版（例如把当前 `1.1.0` 打成 `v1.1.0`），从 Release 安装
2. 再把版本升到 `1.1.1`，推送 `v1.1.1`
3. 打开旧版，选「iReader > 检查更新…」→「立即更新」

版本比较只看 `CFBundleShortVersionString` / 标签名（去掉前缀 `v`），按 major.minor.patch 数值比较。

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
├── iReaderApp.swift          # 应用入口（DocumentGroup、设置、快捷键窗口）
├── PDFFileDocument.swift     # 文档模型：读取 / 保存 / 解锁，页面与标注操作（含撤销）
├── ContentView.swift         # 窗口：侧栏 + 阅读区 + 工具栏（搜索、页码）
├── SidebarView.swift         # 侧栏标签：目录、搜索结果
├── ThumbnailSidebar.swift    # 缩略图侧栏（缓存）
├── AnnotationListSidebar.swift # 标注列表
├── PDFKitView.swift          # PDFView 的 SwiftUI 封装
├── ReaderPDFView.swift       # PDFView 子类：标注工具、右键菜单
├── PageOperations.swift      # 旋转、插入、复制、提取、导出
├── PDFMerger.swift           # 合并 PDF（新建 / 并入当前文档）
├── AnnotationTool.swift      # 工具与颜色
├── ViewerState.swift         # 每个窗口的状态：缩放、布局、搜索、阅读位置
├── ViewerCommands.swift      # 菜单命令
├── Preferences.swift         # 设置项与阅读位置存储
├── SettingsView.swift        # 设置窗口
├── ShortcutsView.swift       # 快捷键一览
├── AppUpdater.swift          # 基于 GitHub Releases 的应用内更新
└── UpdateCommands.swift      # 「检查更新…」与帮助菜单
```

## 已知限制

- 标注创建后不能拖动移动或缩放（可右键改颜色 / 文字，或删除后重画）
- 夜间模式是整体反色，图片也会被反色
- 搜索为同步执行，超大文档（上千页）搜索时可能短暂卡顿；结果最多列出 1000 条
- 编辑会按 macOS 文档应用的惯例自动保存；如需回到旧版本，可用「文件 > 复原到」
- **应用内更新**依赖官方仓库的 GitHub Releases（HTTPS + Bundle ID / 版本校验），不做 Sparkle 式的 EdDSA 签名校验；请只从 [BianYanhui/iReader](https://github.com/BianYanhui/iReader) 更新
- 更新后的应用仍是 ad-hoc 签名：若 Gatekeeper 再次拦截，请用右键「打开」或 `xattr -cr iReader.app`（与首次安装相同）
- 更新需要能写入当前 `.app` 所在目录（例如「应用程序」文件夹）；在 Xcode 调试产物上更新没有意义
- 有未保存文档时会拒绝更新；安装日志在 `~/Library/Logs/iReader-update.log`
- 更新助手会等旧进程完全退出后再替换 `.app`；从 `/var/folders` 等临时路径启动时，新版本会装到 `/Applications`（或 `~/Applications`），避免边跑边删正在用的二进制

## 许可证

[MIT](LICENSE)
