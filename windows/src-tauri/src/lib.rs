mod updater;

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use serde::Serialize;
use std::fs;
use std::path::PathBuf;
use tauri::{Emitter, Manager};
use tauri_plugin_dialog::DialogExt;

#[derive(Serialize)]
struct OpenedFile {
    path: String,
    data_base64: String,
    name: String,
}

#[tauri::command]
fn read_pdf(path: String) -> Result<OpenedFile, String> {
    let path_buf = PathBuf::from(&path);
    let bytes = fs::read(&path_buf).map_err(|e| e.to_string())?;
    let name = path_buf
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("document.pdf")
        .to_string();
    Ok(OpenedFile {
        path,
        data_base64: B64.encode(bytes),
        name,
    })
}

#[tauri::command]
fn write_pdf(path: String, data_base64: String) -> Result<(), String> {
    let bytes = B64.decode(data_base64).map_err(|e| e.to_string())?;
    if let Some(parent) = PathBuf::from(&path).parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
    }
    fs::write(&path, bytes).map_err(|e| e.to_string())
}

#[tauri::command]
fn quit_app(app: tauri::AppHandle) {
    app.exit(0);
}

#[tauri::command]
fn pick_open_pdf(app: tauri::AppHandle) -> Result<Option<OpenedFile>, String> {
    let path = app
        .dialog()
        .file()
        .add_filter("PDF", &["pdf"])
        .blocking_pick_file();
    let Some(file_path) = path else {
        return Ok(None);
    };
    let path_buf = file_path.into_path().map_err(|e| e.to_string())?;
    let path_str = path_buf.to_string_lossy().to_string();
    Ok(Some(read_pdf(path_str)?))
}

#[tauri::command]
fn pick_save_pdf(app: tauri::AppHandle, default_name: String) -> Result<Option<String>, String> {
    let path = app
        .dialog()
        .file()
        .add_filter("PDF", &["pdf"])
        .set_file_name(&default_name)
        .blocking_save_file();
    let Some(file_path) = path else {
        return Ok(None);
    };
    let path_buf = file_path.into_path().map_err(|e| e.to_string())?;
    Ok(Some(path_buf.to_string_lossy().to_string()))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![
            read_pdf,
            write_pdf,
            pick_open_pdf,
            pick_save_pdf,
            updater::get_app_version,
            updater::check_for_updates,
            updater::apply_update,
            quit_app
        ])
        .setup(|app| {
            if let Some(path) = std::env::args().nth(1) {
                if path.to_lowercase().ends_with(".pdf") {
                    if let Some(win) = app.get_webview_window("main") {
                        let _ = win.emit("open-path", path);
                    }
                }
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
