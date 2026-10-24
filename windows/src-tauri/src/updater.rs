//! GitHub Releases updater for the Windows build.
//! Prefer `iReader-windows-portable.zip` and replace after process exit
//! (same idea as the macOS AppUpdater: never overwrite the running binary).

use serde::Serialize;
use std::fs::{self, File};
use std::io::{copy, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

const OWNER: &str = "BianYanhui";
const REPO: &str = "iReader";
const PORTABLE_ASSET: &str = "iReader-windows-portable.zip";
const SETUP_ASSET: &str = "iReader-windows-setup.exe";

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UpdateInfo {
    pub current_version: String,
    pub latest_version: String,
    pub tag_name: String,
    pub notes: String,
    pub update_available: bool,
    pub asset_name: String,
    pub download_url: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ApplyResult {
    pub message: String,
}

fn current_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

fn normalize_version(tag: &str) -> String {
    tag.trim().trim_start_matches('v').trim().to_string()
}

/// Compare dotted versions; returns true if `latest` is greater than `current`.
fn is_newer(latest: &str, current: &str) -> bool {
    fn parts(v: &str) -> Vec<u64> {
        v.split('.')
            .map(|p| p.chars().take_while(|c| c.is_ascii_digit()).collect::<String>())
            .map(|p| p.parse::<u64>().unwrap_or(0))
            .collect()
    }
    let a = parts(latest);
    let b = parts(current);
    let n = a.len().max(b.len());
    for i in 0..n {
        let x = a.get(i).copied().unwrap_or(0);
        let y = b.get(i).copied().unwrap_or(0);
        if x != y {
            return x > y;
        }
    }
    false
}

fn http_client() -> Result<reqwest::blocking::Client, String> {
    reqwest::blocking::Client::builder()
        .user_agent(format!("iReader-Windows/{}", current_version()))
        .timeout(std::time::Duration::from_secs(60))
        .build()
        .map_err(|e| e.to_string())
}

#[derive(serde::Deserialize)]
struct GhRelease {
    tag_name: String,
    body: Option<String>,
    assets: Vec<GhAsset>,
}

#[derive(serde::Deserialize)]
struct GhAsset {
    name: String,
    browser_download_url: String,
}

fn fetch_latest() -> Result<UpdateInfo, String> {
    let client = http_client()?;
    let url = format!("https://api.github.com/repos/{OWNER}/{REPO}/releases/latest");
    let resp = client
        .get(&url)
        .header("Accept", "application/vnd.github+json")
        .send()
        .map_err(|e| e.to_string())?;
    if resp.status().as_u16() == 404 {
        return Err("还没有 GitHub Release".into());
    }
    if !resp.status().is_success() {
        return Err(format!("GitHub HTTP {}", resp.status()));
    }
    let release: GhRelease = resp.json().map_err(|e| e.to_string())?;
    let latest = normalize_version(&release.tag_name);
    let current = current_version();

    // Prefer portable zip; fall back to setup.exe for Program Files installs.
    let asset = release
        .assets
        .iter()
        .find(|a| a.name == PORTABLE_ASSET)
        .or_else(|| release.assets.iter().find(|a| a.name == SETUP_ASSET))
        .ok_or_else(|| format!("Release 里没有 {PORTABLE_ASSET} / {SETUP_ASSET}"))?;

    let info = UpdateInfo {
        current_version: current.clone(),
        latest_version: latest.clone(),
        tag_name: release.tag_name.clone(),
        notes: release.body.clone().unwrap_or_default(),
        update_available: is_newer(&latest, &current),
        asset_name: asset.name.clone(),
        download_url: asset.browser_download_url.clone(),
    };
    Ok(info)
}

#[tauri::command]
pub fn get_app_version() -> String {
    current_version()
}

#[tauri::command]
pub fn check_for_updates() -> Result<UpdateInfo, String> {
    fetch_latest()
}

fn exe_dir() -> Result<PathBuf, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    exe.parent()
        .map(|p| p.to_path_buf())
        .ok_or_else(|| "无法定位程序目录".into())
}

fn is_program_files(path: &Path) -> bool {
    let s = path.to_string_lossy().to_lowercase();
    s.contains("\\program files") || s.contains("/program files")
}

fn download_to(url: &str, dest: &Path) -> Result<(), String> {
    let client = http_client()?;
    let mut resp = client.get(url).send().map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("下载失败 HTTP {}", resp.status()));
    }
    let mut file = File::create(dest).map_err(|e| e.to_string())?;
    copy(&mut resp, &mut file).map_err(|e| e.to_string())?;
    Ok(())
}

fn unzip_to(zip_path: &Path, dest: &Path) -> Result<(), String> {
    let file = File::open(zip_path).map_err(|e| e.to_string())?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;
    fs::create_dir_all(dest).map_err(|e| e.to_string())?;
    for i in 0..archive.len() {
        let mut file = archive.by_index(i).map_err(|e| e.to_string())?;
        let outpath = match file.enclosed_name() {
            Some(p) => dest.join(p),
            None => continue,
        };
        if file.name().ends_with('/') {
            fs::create_dir_all(&outpath).map_err(|e| e.to_string())?;
        } else {
            if let Some(parent) = outpath.parent() {
                fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            }
            let mut outfile = File::create(&outpath).map_err(|e| e.to_string())?;
            copy(&mut file, &mut outfile).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

fn find_new_exe(dir: &Path) -> Result<PathBuf, String> {
    // Prefer known names, then any .exe that isn't an installer helper.
    let preferred = ["ireader-windows.exe", "iReader.exe", "ireader.exe"];
    for name in preferred {
        let p = dir.join(name);
        if p.is_file() {
            return Ok(p);
        }
    }
    fn walk(dir: &Path, out: &mut Vec<PathBuf>) -> Result<(), String> {
        for entry in fs::read_dir(dir).map_err(|e| e.to_string())? {
            let entry = entry.map_err(|e| e.to_string())?;
            let path = entry.path();
            if path.is_dir() {
                walk(&path, out)?;
            } else if path
                .extension()
                .and_then(|e| e.to_str())
                .map(|e| e.eq_ignore_ascii_case("exe"))
                .unwrap_or(false)
            {
                let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
                if !name.to_lowercase().contains("setup") && !name.to_lowercase().contains("uninstall")
                {
                    out.push(path);
                }
            }
        }
        Ok(())
    }
    let mut found = Vec::new();
    walk(dir, &mut found)?;
    found
        .into_iter()
        .next()
        .ok_or_else(|| "更新包里没有可执行文件".into())
}

fn write_and_launch_helper(script: &str) -> Result<(), String> {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let helper = std::env::temp_dir().join(format!("iReader-update-{stamp}.cmd"));
    let mut f = File::create(&helper).map_err(|e| e.to_string())?;
    // cmd scripts on Windows prefer CRLF; UTF-8 without BOM is fine for ASCII paths.
    write!(f, "{script}").map_err(|e| e.to_string())?;
    drop(f);

    Command::new("cmd")
        .args(["/C", &helper.to_string_lossy()])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn apply_update(download_url: String, asset_name: String) -> Result<ApplyResult, String> {
    let install_dir = exe_dir()?;
    let current_exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let pid = std::process::id();

    let work = std::env::temp_dir().join(format!("iReader-update-work-{pid}"));
    let _ = fs::remove_dir_all(&work);
    fs::create_dir_all(&work).map_err(|e| e.to_string())?;
    let download_path = work.join(&asset_name);
    download_to(&download_url, &download_path)?;

    if asset_name.eq_ignore_ascii_case(SETUP_ASSET)
        || asset_name.to_lowercase().contains("setup")
    {
        // Installed build / setup: run installer after we quit.
        let setup = download_path;
        let script = format!(
            "@echo off\r\n\
             setlocal\r\n\
             :wait\r\n\
             tasklist /FI \"PID eq {pid}\" | find \"{pid}\" >nul\r\n\
             if not errorlevel 1 (\r\n\
               timeout /t 1 /nobreak >nul\r\n\
               goto wait\r\n\
             )\r\n\
             start \"\" \"{setup}\"\r\n\
             del \"%~f0\"\r\n",
            pid = pid,
            setup = setup.to_string_lossy().replace('"', "")
        );
        write_and_launch_helper(&script)?;
        return Ok(ApplyResult {
            message: "安装程序将在退出后启动".into(),
        });
    }

    // Portable zip path.
    if is_program_files(&install_dir) {
        return Err("当前安装在 Program Files，请下载安装包手动更新，或使用便携版目录".into());
    }

    let unzip_dir = work.join("unzipped");
    unzip_to(&download_path, &unzip_dir)?;
    let new_exe = find_new_exe(&unzip_dir)?;
    let new_dir = new_exe
        .parent()
        .ok_or_else(|| "无效的更新包布局".to_string())?
        .to_path_buf();

    // Stage a full copy outside the running dir.
    let staging = std::env::temp_dir().join(format!("iReader-new-{pid}"));
    let _ = fs::remove_dir_all(&staging);
    copy_dir_recursive(&new_dir, &staging)?;

    let install = install_dir.to_string_lossy().replace('"', "");
    let staging_s = staging.to_string_lossy().replace('"', "");
    let exe_name = current_exe
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("ireader-windows.exe");
    // Copy staged files into install dir after exit, then relaunch.
    let script = format!(
        "@echo off\r\n\
         setlocal\r\n\
         :wait\r\n\
         tasklist /FI \"PID eq {pid}\" | find \"{pid}\" >nul\r\n\
         if not errorlevel 1 (\r\n\
           timeout /t 1 /nobreak >nul\r\n\
           goto wait\r\n\
         )\r\n\
         xcopy /E /Y /I /Q \"{staging}\\*\" \"{install}\\\" >nul\r\n\
         start \"\" \"{install}\\{exe}\"\r\n\
         rmdir /S /Q \"{staging}\"\r\n\
         del \"%~f0\"\r\n",
        pid = pid,
        staging = staging_s,
        install = install,
        exe = exe_name
    );
    write_and_launch_helper(&script)?;
    let _ = fs::remove_dir_all(&work);

    Ok(ApplyResult {
        message: "将退出并完成更新".into(),
    })
}

fn copy_dir_recursive(from: &Path, to: &Path) -> Result<(), String> {
    fs::create_dir_all(to).map_err(|e| e.to_string())?;
    for entry in fs::read_dir(from).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        let dest = to.join(entry.file_name());
        if path.is_dir() {
            copy_dir_recursive(&path, &dest)?;
        } else {
            fs::copy(&path, &dest).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}
