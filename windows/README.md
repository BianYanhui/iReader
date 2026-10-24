# iReader for Windows

Windows 版 iReader（Tauri 2 + pdf.js + pdf-lib）。

## 功能（1.5.2）

- 打开 / 保存 / 另存为 PDF
- 连续翻页、缩略图、适合宽度缩放
- 全文搜索（Ctrl+F / Ctrl+G）
- 删除当前页、旋转 90°
- **检查更新**：工具栏按钮；启动后静默检查（每天最多一次）。便携版下载 `iReader-windows-portable.zip` 旁路替换后重启；安装版会拉起 setup
- 拖到 exe 或命令行传入 PDF 路径可直接打开

macOS 原生版（SwiftUI + PDFKit）仍在仓库根目录，功能更完整。Windows 版会按批次补齐标注、合并等能力。

## 开发

需要 Node 20+、Rust stable、Windows 上的 WebView2（Win10/11 通常已带）。

```bash
cd windows
npm install
npm run tauri dev
```

打包：

```bash
npm run tauri build
```

产物在 `src-tauri/target/release/bundle/`（NSIS / MSI）以及 `target/release/ireader-windows.exe`。

## CI

`.github/workflows/build-windows.yml` 在改动 `windows/` 或打 `v*` tag 时于 `windows-latest` 构建，并把安装包挂到 Release。
