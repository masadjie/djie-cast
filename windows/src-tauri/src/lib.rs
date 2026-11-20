//! Djie Cast untuk Windows: backend tipis di atas adb & scrcpy yang dibundel.
//! Logika fitur (info perangkat, file, pembersih, dll.) ada di UI (ui/app.js);
//! di sini hanya menjalankan program, mengalirkan log, dan menyimpan file.

use base64::Engine;
use serde::Serialize;
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex, OnceLock};
use tauri::{AppHandle, Emitter, Manager, State};

#[cfg(windows)]
use std::os::windows::process::CommandExt;
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

const EXE: &str = if cfg!(windows) { ".exe" } else { "" };

// ---------- Lokasi adb & scrcpy ----------

#[derive(Clone, Serialize)]
struct Tools {
    adb: Option<String>,
    scrcpy: Option<String>,
    /// Folder scrcpy-server & ikon (bila scrcpy dibundel).
    res_dir: Option<String>,
    version: String,
    bundled: bool,
}

static TOOLS: OnceLock<Tools> = OnceLock::new();

fn which(name: &str) -> Option<PathBuf> {
    let file = format!("{name}{EXE}");
    let mut dirs: Vec<PathBuf> = std::env::var_os("PATH")
        .map(|p| std::env::split_paths(&p).collect())
        .unwrap_or_default();
    if !cfg!(windows) {
        dirs.extend(["/opt/homebrew/bin", "/usr/local/bin"].map(PathBuf::from));
    }
    if let Some(local) = std::env::var_os("LOCALAPPDATA") {
        dirs.push(PathBuf::from(local).join("Android/Sdk/platform-tools"));
    }
    dirs.into_iter().map(|d| d.join(&file)).find(|p| p.is_file())
}

fn find_tools(app: &AppHandle) -> Tools {
    // 1) DJIE_SCRCPY_DIR (pengembangan), 2) resource bawaan installer, 3) PATH.
    let mut candidates: Vec<PathBuf> = vec![];
    if let Some(d) = std::env::var_os("DJIE_SCRCPY_DIR") {
        candidates.push(PathBuf::from(d));
    }
    if let Ok(r) = app.path().resource_dir() {
        candidates.push(r.join("scrcpy"));
        candidates.push(r.join("resources/scrcpy"));
    }
    let dir = candidates
        .into_iter()
        .find(|d| d.join(format!("scrcpy{EXE}")).is_file() && d.join("scrcpy-server").is_file());

    let str_of = |p: PathBuf| p.to_string_lossy().into_owned();
    match dir {
        Some(d) => {
            let version = std::fs::read_to_string(d.join("VERSION"))
                .map(|s| s.trim().to_string())
                .unwrap_or_else(|_| "?".into());
            let bundled_adb = d.join(format!("adb{EXE}"));
            Tools {
                adb: Some(str_of(if bundled_adb.is_file() { bundled_adb } else { which("adb").unwrap_or(bundled_adb) })),
                scrcpy: Some(str_of(d.join(format!("scrcpy{EXE}")))),
                res_dir: Some(str_of(d)),
                version,
                bundled: true,
            }
        }
        None => Tools {
            adb: which("adb").map(str_of),
            scrcpy: which("scrcpy").map(str_of),
            res_dir: None,
            version: "sistem".into(),
            bundled: false,
        },
    }
}

fn tools() -> &'static Tools {
    TOOLS.get().expect("tools belum disiapkan")
}

fn command(exe: &str) -> Command {
    let t = tools();
    let mut c = Command::new(exe);
    if let Some(adb) = &t.adb {
        c.env("ADB", adb);
    }
    if let Some(dir) = &t.res_dir {
        c.env("SCRCPY_SERVER_PATH", Path::new(dir).join("scrcpy-server"));
        c.env("SCRCPY_ICON_PATH", Path::new(dir).join("scrcpy.png"));
        let mut paths = vec![PathBuf::from(dir)];
        if let Some(p) = std::env::var_os("PATH") {
            paths.extend(std::env::split_paths(&p));
        }
        if let Ok(joined) = std::env::join_paths(paths) {
            c.env("PATH", joined);
        }
    }
    c.stdin(Stdio::null());
    #[cfg(windows)]
    c.creation_flags(CREATE_NO_WINDOW);
    c
}

#[derive(Serialize)]
struct RunOut {
    code: i32,
    out: String,
}

fn run_blocking(exe: &str, args: &[String]) -> RunOut {
    match command(exe).args(args).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn() {
        Ok(mut child) => {
            // stderr dibaca di thread lain supaya pipa tidak macet.
            let mut err = child.stderr.take().unwrap();
            let h = std::thread::spawn(move || {
                let mut s = Vec::new();
                let _ = err.read_to_end(&mut s);
                s
            });
            let mut out = Vec::new();
            let _ = child.stdout.take().unwrap().read_to_end(&mut out);
            let code = child.wait().map(|s| s.code().unwrap_or(-1)).unwrap_or(-1);
            out.extend(h.join().unwrap_or_default());
            RunOut { code, out: String::from_utf8_lossy(&out).into_owned() }
        }
        Err(e) => RunOut { code: -1, out: format!("Error: {e}") },
    }
}

async fn run_tool(exe: Option<&String>, args: Vec<String>) -> Result<RunOut, String> {
    let exe = exe.ok_or("tool-missing")?.clone();
    tauri::async_runtime::spawn_blocking(move || run_blocking(&exe, &args))
        .await
        .map_err(|e| e.to_string())
}

// ---------- Perintah untuk UI ----------

#[tauri::command]
fn tools_info() -> Tools {
    tools().clone()
}

/// `adb <args>` — keluaran gabungan stdout+stderr.
#[tauri::command]
async fn adb(args: Vec<String>) -> Result<RunOut, String> {
    run_tool(tools().adb.as_ref(), args).await
}

/// scrcpy yang selesai sendiri (mis. `--list-apps`).
#[tauri::command]
async fn scrcpy_run(args: Vec<String>) -> Result<RunOut, String> {
    run_tool(tools().scrcpy.as_ref(), args).await
}

#[derive(Default)]
struct Sessions(Arc<Mutex<HashMap<String, Child>>>);

#[derive(Clone, Serialize)]
struct ExitEvent {
    key: String,
    code: i32,
}

/// Menjalankan jendela scrcpy. `key` membedakan sesi (serial, atau serial|paket untuk jendela aplikasi).
#[tauri::command]
fn scrcpy_start(app: AppHandle, sessions: State<Sessions>, key: String, args: Vec<String>) -> Result<(), String> {
    let exe = tools().scrcpy.clone().ok_or("tool-missing")?;
    let mut map = sessions.0.lock().unwrap();
    if map.contains_key(&key) {
        return Err("already-running".into());
    }
    let _ = app.emit("log", format!("▶ scrcpy {}\n", args.join(" ")));
    let mut child = command(&exe)
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;

    for pipe in [child.stdout.take().map(|p| Box::new(p) as Box<dyn Read + Send>),
                 child.stderr.take().map(|p| Box::new(p) as Box<dyn Read + Send>)]
        .into_iter()
        .flatten()
    {
        let app = app.clone();
        std::thread::spawn(move || {
            for line in BufReader::new(pipe).lines().map_while(Result::ok) {
                let _ = app.emit("log", format!("{line}\n"));
            }
        });
    }
    map.insert(key.clone(), child);
    drop(map);

    // Pantau sampai jendela ditutup.
    let all = sessions.0.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(std::time::Duration::from_millis(300));
        let mut map = all.lock().unwrap();
        let Some(child) = map.get_mut(&key) else { return };
        match child.try_wait() {
            Ok(Some(status)) => {
                map.remove(&key);
                drop(map);
                let code = status.code().unwrap_or(-1);
                let _ = app.emit("log", format!("■ scrcpy ({key}) selesai, kode {code}\n"));
                let _ = app.emit("scrcpy-exit", ExitEvent { key, code });
                return;
            }
            Ok(None) => {}
            Err(_) => {
                map.remove(&key);
                return;
            }
        }
    });
    Ok(())
}

#[tauri::command]
fn scrcpy_stop(sessions: State<Sessions>, key: String) {
    if let Some(child) = sessions.0.lock().unwrap().get_mut(&key) {
        let _ = child.kill();
    }
}

#[tauri::command]
fn scrcpy_running(sessions: State<Sessions>) -> Vec<String> {
    sessions.0.lock().unwrap().keys().cloned().collect()
}

fn stamp() -> String {
    chrono::Local::now().format("%Y%m%d-%H%M%S").to_string()
}

#[derive(Serialize)]
struct Shot {
    path: String,
    data_url: String,
}

/// Screenshot layar HP: disimpan ke folder Gambar\Djie Cast dan dikembalikan sebagai data URL.
#[tauri::command]
async fn screenshot(app: AppHandle, serial: String, save: bool) -> Result<Shot, String> {
    let adb = tools().adb.clone().ok_or("tool-missing")?;
    let dir = app.path().picture_dir().map_err(|e| e.to_string())?.join("Djie Cast");
    tauri::async_runtime::spawn_blocking(move || {
        let out = command(&adb)
            .args(["-s", &serial, "exec-out", "screencap", "-p"])
            .stderr(Stdio::null())
            .output()
            .map_err(|e| e.to_string())?;
        if out.stdout.len() < 100 || !out.stdout.starts_with(b"\x89PNG") {
            return Err("screenshot-failed".into());
        }
        let mut path = String::new();
        if save {
            std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
            let p = dir.join(format!("DjieCast-{}.png", stamp()));
            std::fs::write(&p, &out.stdout).map_err(|e| e.to_string())?;
            path = p.to_string_lossy().into_owned();
        }
        let b64 = base64::engine::general_purpose::STANDARD.encode(&out.stdout);
        Ok(Shot { path, data_url: format!("data:image/png;base64,{b64}") })
    })
    .await
    .map_err(|e| e.to_string())?
}

/// Lokasi standar untuk file yang dibuat app.
#[tauri::command]
fn paths(app: AppHandle) -> HashMap<String, String> {
    let p = app.path();
    let mut m = HashMap::new();
    let mut put = |k: &str, v: Option<PathBuf>| {
        if let Some(v) = v {
            m.insert(k.to_string(), v.to_string_lossy().into_owned());
        }
    };
    put("videos", p.video_dir().ok().map(|d| d.join("Djie Cast")));
    put("pictures", p.picture_dir().ok().map(|d| d.join("Djie Cast")));
    put("downloads", p.download_dir().ok());
    put("temp", p.app_cache_dir().ok().map(|d| d.join("open")));
    m
}

#[tauri::command]
fn ensure_dir(path: String) -> Result<(), String> {
    std::fs::create_dir_all(path).map_err(|e| e.to_string())
}

#[tauri::command]
fn timestamp() -> String {
    stamp()
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .manage(Sessions::default())
        .setup(|app| {
            let t = find_tools(app.handle());
            let _ = TOOLS.set(t.clone());
            // Nyalakan server adb lebih awal supaya daftar perangkat pertama cepat muncul.
            if let Some(adb) = t.adb {
                std::thread::spawn(move || {
                    let _ = run_blocking(&adb, &["start-server".into()]);
                });
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            // Tutup semua jendela scrcpy saat app ditutup.
            if let tauri::WindowEvent::Destroyed = event {
                let sessions = window.state::<Sessions>();
                for (_, mut c) in sessions.0.lock().unwrap().drain() {
                    let _ = c.kill();
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            tools_info,
            adb,
            scrcpy_run,
            scrcpy_start,
            scrcpy_stop,
            scrcpy_running,
            screenshot,
            paths,
            ensure_dir,
            timestamp
        ])
        .run(tauri::generate_context!())
        .expect("gagal menjalankan Djie Cast");
}
