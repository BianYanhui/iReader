import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import * as pdfjsLib from "pdfjs-dist";
import { PDFDocument, degrees } from "pdf-lib";
// Vite resolves the worker URL at build time.
pdfjsLib.GlobalWorkerOptions.workerSrc = new URL(
  "pdfjs-dist/build/pdf.worker.min.mjs",
  import.meta.url,
).toString();

type OpenedFile = { path: string; data_base64: string; name: string };

const $ = <T extends HTMLElement>(id: string) =>
  document.getElementById(id) as T;

const ui = {
  open: $<HTMLButtonElement>("btn-open"),
  openEmpty: $<HTMLButtonElement>("btn-open-empty"),
  save: $<HTMLButtonElement>("btn-save"),
  saveAs: $<HTMLButtonElement>("btn-save-as"),
  prev: $<HTMLButtonElement>("btn-prev"),
  next: $<HTMLButtonElement>("btn-next"),
  pageLabel: $<HTMLSpanElement>("page-label"),
  zoomIn: $<HTMLButtonElement>("btn-zoom-in"),
  zoomOut: $<HTMLButtonElement>("btn-zoom-out"),
  fit: $<HTMLButtonElement>("btn-fit"),
  searchInput: $<HTMLInputElement>("search-input"),
  search: $<HTMLButtonElement>("btn-search"),
  searchPrev: $<HTMLButtonElement>("btn-search-prev"),
  searchNext: $<HTMLButtonElement>("btn-search-next"),
  deletePage: $<HTMLButtonElement>("btn-delete-page"),
  rotate: $<HTMLButtonElement>("btn-rotate"),
  update: $<HTMLButtonElement>("btn-update"),
  status: $<HTMLSpanElement>("status"),
  empty: $<HTMLDivElement>("empty"),
  pages: $<HTMLDivElement>("pages"),
  thumbs: $<HTMLElement>("thumbs"),
  viewer: $<HTMLElement>("viewer"),
};

let filePath: string | null = null;
let fileName = "document.pdf";
let rawBytes: Uint8Array | null = null;
let pdfDoc: pdfjsLib.PDFDocumentProxy | null = null;
let dirty = false; // mirrored in window title / status
let scale = 1.25;
let currentPage = 1; // 1-based
let fitWidth = false;
let searchQuery = "";
let searchHits: { page: number; index: number }[] = [];
let searchCursor = -1;
let renderToken = 0;

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToB64(bytes: Uint8Array): string {
  let s = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    s += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(s);
}

function setStatus(msg: string) {
  ui.status.textContent = msg;
}

function setEnabled(hasDoc: boolean) {
  for (const b of [
    ui.save,
    ui.saveAs,
    ui.prev,
    ui.next,
    ui.zoomIn,
    ui.zoomOut,
    ui.fit,
    ui.search,
    ui.searchPrev,
    ui.searchNext,
    ui.deletePage,
    ui.rotate,
  ]) {
    b.disabled = !hasDoc;
  }
  ui.searchInput.disabled = !hasDoc;
  ui.empty.hidden = hasDoc;
  ui.pages.hidden = !hasDoc;
}

function updatePageLabel() {
  if (!pdfDoc) {
    ui.pageLabel.textContent = "–";
    return;
  }
  ui.pageLabel.textContent = `${currentPage} / ${pdfDoc.numPages}`;
  ui.prev.disabled = currentPage <= 1;
  ui.next.disabled = currentPage >= pdfDoc.numPages;
}

async function loadFromOpened(file: OpenedFile) {
  filePath = file.path;
  fileName = file.name;
  rawBytes = b64ToBytes(file.data_base64);
  dirty = false;
  searchHits = [];
  searchCursor = -1;
  ui.searchInput.value = "";
  await reloadPdfjs();
  await refreshTitle();
  setStatus(filePath);
}

async function refreshTitle() {
  const mark = dirty ? " •" : "";
  try {
    await getCurrentWindow().setTitle(`${fileName}${mark} — iReader`);
  } catch {
    // Title permission may be missing on older builds; never block opening.
    document.title = `${fileName}${mark} — iReader`;
  }
}

async function reloadPdfjs() {
  if (!rawBytes) return;
  const token = ++renderToken;
  if (pdfDoc) {
    try {
      pdfDoc.destroy();
    } catch {
      /* ignore */
    }
  }
  const loading = pdfjsLib.getDocument({ data: rawBytes.slice() }).promise;
  pdfDoc = await loading;
  if (token !== renderToken) return;
  currentPage = Math.min(currentPage, pdfDoc.numPages) || 1;
  setEnabled(true);
  updatePageLabel();
  await renderAll();
}

async function pageScale(page: pdfjsLib.PDFPageProxy): Promise<number> {
  if (!fitWidth) return scale;
  const base = page.getViewport({ scale: 1 });
  const avail = Math.max(320, ui.viewer.clientWidth - 48);
  return avail / base.width;
}

async function renderAll() {
  if (!pdfDoc) return;
  const token = renderToken;
  ui.pages.innerHTML = "";
  ui.thumbs.innerHTML = "";

  for (let i = 1; i <= pdfDoc.numPages; i++) {
    if (token !== renderToken) return;
    const page = await pdfDoc.getPage(i);
    const s = await pageScale(page);
    const dpr = window.devicePixelRatio || 1;
    const viewport = page.getViewport({ scale: s });
    const wrap = document.createElement("div");
    wrap.className = "page-wrap";
    wrap.dataset.page = String(i);
    wrap.id = `page-${i}`;
    const canvas = document.createElement("canvas");
    canvas.width = Math.floor(viewport.width * dpr);
    canvas.height = Math.floor(viewport.height * dpr);
    canvas.style.width = `${Math.floor(viewport.width)}px`;
    canvas.style.height = `${Math.floor(viewport.height)}px`;
    wrap.appendChild(canvas);
    ui.pages.appendChild(wrap);
    const ctx = canvas.getContext("2d")!;
    const transform = dpr !== 1 ? [dpr, 0, 0, dpr, 0, 0] : undefined;
    await page.render({ canvasContext: ctx, viewport, transform, canvas }).promise;

    // thumbnail (also crisp on HiDPI)
    const thumbScale = 0.2;
    const tv = page.getViewport({ scale: thumbScale });
    const t = document.createElement("div");
    t.className = "thumb" + (i === currentPage ? " active" : "");
    t.dataset.page = String(i);
    const tc = document.createElement("canvas");
    tc.width = Math.floor(tv.width * dpr);
    tc.height = Math.floor(tv.height * dpr);
    tc.style.width = `${Math.floor(tv.width)}px`;
    tc.style.height = `${Math.floor(tv.height)}px`;
    const label = document.createElement("div");
    label.className = "n";
    label.textContent = String(i);
    t.appendChild(tc);
    t.appendChild(label);
    t.addEventListener("click", () => goToPage(i));
    ui.thumbs.appendChild(t);
    const tctx = tc.getContext("2d")!;
    const tTransform = dpr !== 1 ? [dpr, 0, 0, dpr, 0, 0] : undefined;
    await page.render({
      canvasContext: tctx,
      viewport: tv,
      transform: tTransform,
      canvas: tc,
    }).promise;
  }
  highlightThumb();
  scrollCurrentIntoView(false);
}

function highlightThumb() {
  ui.thumbs.querySelectorAll(".thumb").forEach((el) => {
    el.classList.toggle(
      "active",
      Number((el as HTMLElement).dataset.page) === currentPage,
    );
  });
}

function scrollCurrentIntoView(smooth: boolean) {
  const el = document.getElementById(`page-${currentPage}`);
  el?.scrollIntoView({ behavior: smooth ? "smooth" : "auto", block: "nearest" });
}

function goToPage(n: number) {
  if (!pdfDoc) return;
  currentPage = Math.max(1, Math.min(pdfDoc.numPages, n));
  updatePageLabel();
  highlightThumb();
  scrollCurrentIntoView(true);
}

async function openPdf() {
  try {
    const file = await invoke<OpenedFile | null>("pick_open_pdf");
    if (!file) return;
    await loadFromOpened(file);
  } catch (e) {
    setStatus(`打开失败：${e}`);
  }
}

async function openPath(path: string) {
  try {
    const file = await invoke<OpenedFile>("read_pdf", { path });
    await loadFromOpened(file);
  } catch (e) {
    setStatus(`打开失败：${e}`);
  }
}

async function mutatePdf(
  mutator: (doc: PDFDocument) => Promise<void> | void,
): Promise<void> {
  if (!rawBytes) return;
  const doc = await PDFDocument.load(rawBytes, { ignoreEncryption: true });
  await mutator(doc);
  const saved = await doc.save({ useObjectStreams: false });
  rawBytes = saved;
  dirty = true;
  setStatus(`${fileName}（未保存）`);
  await refreshTitle();
  await reloadPdfjs();
}

async function deleteCurrentPage() {
  if (!pdfDoc || pdfDoc.numPages <= 1) {
    setStatus("至少保留一页");
    return;
  }
  const idx = currentPage - 1;
  await mutatePdf((doc) => {
    doc.removePage(idx);
  });
  currentPage = Math.min(currentPage, (pdfDoc?.numPages ?? 1));
}

async function rotateCurrentPage() {
  if (!rawBytes) return;
  const idx = currentPage - 1;
  await mutatePdf((doc) => {
    const page = doc.getPage(idx);
    const current = page.getRotation().angle;
    page.setRotation(degrees((current + 90) % 360));
  });
}

async function save(toNewPath: boolean) {
  if (!rawBytes) return;
  try {
    let path = filePath;
    if (toNewPath || !path) {
      const picked = await invoke<string | null>("pick_save_pdf", {
        defaultName: fileName.endsWith(".pdf") ? fileName : `${fileName}.pdf`,
      });
      if (!picked) return;
      path = picked;
    }
    await invoke("write_pdf", {
      path,
      dataBase64: bytesToB64(rawBytes),
    });
    filePath = path;
    fileName = path.split(/[/\\]/).pop() || fileName;
    dirty = false;
    await refreshTitle();
    setStatus(`已保存：${path}`);
  } catch (e) {
    setStatus(`保存失败：${e}`);
  }
}

async function runSearch() {
  if (!pdfDoc) return;
  searchQuery = ui.searchInput.value.trim();
  searchHits = [];
  searchCursor = -1;
  if (!searchQuery) {
    setStatus("输入关键词后查找");
    return;
  }
  const q = searchQuery.toLowerCase();
  for (let i = 1; i <= pdfDoc.numPages; i++) {
    const page = await pdfDoc.getPage(i);
    const text = await page.getTextContent();
    const hay = text.items
      .map((it) => ("str" in it ? String(it.str) : ""))
      .join(" ")
      .toLowerCase();
    let from = 0;
    let idx = 0;
    while ((idx = hay.indexOf(q, from)) !== -1) {
      searchHits.push({ page: i, index: idx });
      from = idx + q.length;
    }
  }
  if (searchHits.length === 0) {
    setStatus(`未找到「${searchQuery}」`);
    return;
  }
  setStatus(`找到 ${searchHits.length} 处`);
  searchCursor = 0;
  goToPage(searchHits[0].page);
}

function jumpSearch(delta: number) {
  if (searchHits.length === 0) return;
  searchCursor = (searchCursor + delta + searchHits.length) % searchHits.length;
  goToPage(searchHits[searchCursor].page);
  setStatus(`结果 ${searchCursor + 1}/${searchHits.length}`);
}

function onScroll() {
  if (!pdfDoc) return;
  const wraps = [...ui.pages.querySelectorAll(".page-wrap")] as HTMLElement[];
  const mid = ui.viewer.scrollTop + ui.viewer.clientHeight / 3;
  let best = currentPage;
  let bestDist = Infinity;
  for (const w of wraps) {
    const top = w.offsetTop;
    const dist = Math.abs(top - mid);
    if (dist < bestDist) {
      bestDist = dist;
      best = Number(w.dataset.page);
    }
  }
  if (best !== currentPage) {
    currentPage = best;
    updatePageLabel();
    highlightThumb();
  }
}

ui.open.addEventListener("click", openPdf);
ui.openEmpty.addEventListener("click", openPdf);
ui.save.addEventListener("click", () => save(false));
ui.saveAs.addEventListener("click", () => save(true));
ui.prev.addEventListener("click", () => goToPage(currentPage - 1));
ui.next.addEventListener("click", () => goToPage(currentPage + 1));
ui.zoomIn.addEventListener("click", async () => {
  fitWidth = false;
  scale = Math.min(3, scale + 0.15);
  await renderAll();
});
ui.zoomOut.addEventListener("click", async () => {
  fitWidth = false;
  scale = Math.max(0.4, scale - 0.15);
  await renderAll();
});
ui.fit.addEventListener("click", async () => {
  fitWidth = true;
  await renderAll();
});
ui.search.addEventListener("click", runSearch);
ui.searchPrev.addEventListener("click", () => jumpSearch(-1));
ui.searchNext.addEventListener("click", () => jumpSearch(1));
ui.deletePage.addEventListener("click", () => void deleteCurrentPage());
ui.rotate.addEventListener("click", () => void rotateCurrentPage());
ui.searchInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") void runSearch();
});
ui.viewer.addEventListener("scroll", onScroll, { passive: true });

window.addEventListener("keydown", (e) => {
  const meta = e.ctrlKey || e.metaKey;
  if (meta && e.key.toLowerCase() === "o") {
    e.preventDefault();
    void openPdf();
  } else if (meta && e.key.toLowerCase() === "s") {
    e.preventDefault();
    void save(e.shiftKey);
  } else if (meta && e.key.toLowerCase() === "f") {
    e.preventDefault();
    ui.searchInput.focus();
    ui.searchInput.select();
  } else if (meta && e.key.toLowerCase() === "g") {
    e.preventDefault();
    jumpSearch(e.shiftKey ? -1 : 1);
  } else if (e.key === "PageDown" || (e.key === "ArrowRight" && meta)) {
    goToPage(currentPage + 1);
  } else if (e.key === "PageUp" || (e.key === "ArrowLeft" && meta)) {
    goToPage(currentPage - 1);
  }
});

window.addEventListener("resize", () => {
  if (fitWidth) void renderAll();
});

void listen<string>("open-path", (ev) => {
  void openPath(ev.payload);
});


type UpdateInfo = {
  currentVersion: string;
  latestVersion: string;
  tagName: string;
  notes: string;
  updateAvailable: boolean;
  assetName: string;
  downloadUrl: string;
};

async function checkUpdates(interactive: boolean) {
  try {
    ui.update.disabled = true;
    setStatus("正在检查更新…");
    const info = await invoke<UpdateInfo>("check_for_updates");
    if (!info.updateAvailable) {
      setStatus(interactive ? `已是最新（${info.currentVersion}）` : `v${info.currentVersion}`);
      return;
    }
    const ok = confirm(
      `发现新版本 ${info.latestVersion}（当前 ${info.currentVersion}）\n\n更新将退出并重新打开 iReader，请先保存未保存的 PDF。\n\n立即更新？`,
    );
    if (!ok) {
      setStatus(`可更新到 ${info.latestVersion}`);
      return;
    }
    if (dirty && !confirm("有未保存的更改，仍要更新吗？未保存内容会丢失。")) {
      setStatus("已取消更新");
      return;
    }
    setStatus(`正在下载 ${info.latestVersion}…`);
    await invoke("apply_update", {
      downloadUrl: info.downloadUrl,
      assetName: info.assetName,
    });
    setStatus("即将退出并完成更新…");
    await invoke("quit_app");
  } catch (e) {
    setStatus(`更新失败：${e}`);
    if (interactive) alert(`更新失败：${e}`);
  } finally {
    ui.update.disabled = false;
  }
}

ui.update.addEventListener("click", () => void checkUpdates(true));

// Silent launch check at most once per day.
void (async () => {
  try {
    const ver = await invoke<string>("get_app_version");
    setStatus(`v${ver}`);
    const key = "iReader.lastWinUpdateCheck";
    const last = Number(localStorage.getItem(key) || "0");
    if (Date.now() - last < 24 * 60 * 60 * 1000) return;
    localStorage.setItem(key, String(Date.now()));
    const info = await invoke<UpdateInfo>("check_for_updates");
    if (info.updateAvailable) {
      setStatus(`有新版本 ${info.latestVersion}，点「检查更新」`);
    }
  } catch {
    /* offline / no release yet */
  }
})();

setEnabled(false);

