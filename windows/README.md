# Djie Cast untuk Windows

Versi Windows Djie Cast (Tauri: Rust + HTML/JS). Fitur: mirror Android lewat USB & Wi-Fi
(scrcpy), kamera HP, kontrol cepat, info HP, aplikasi di jendela sendiri, pasang/hapus APK,
file manager, dan pembersih sampah. Mirroring iPhone & Simulator iPhone hanya ada di Mac.

## Struktur
- `ui/` — antarmuka (HTML/CSS/JS tanpa bundler). `mock.js` memberi data demo bila dibuka di browser biasa.
- `src-tauri/src/lib.rs` — backend: menjalankan adb/scrcpy yang dibundel, mengalirkan log, screenshot.
- `scripts/fetch-scrcpy-win.sh` — unduh scrcpy resmi untuk Windows (cek SHA-256) ke `src-tauri/resources/scrcpy`.

## Build installer dari Mac (cross-compile)
Sekali: `brew install nsis llvm lld`, `cargo install --locked cargo-xwin`,
`rustup target add x86_64-pc-windows-msvc`.

```bash
cd windows && ./scripts/fetch-scrcpy-win.sh && npm install
PATH=/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:$PATH \
  npx tauri build --runner cargo-xwin --target x86_64-pc-windows-msvc
```
Hasil: `src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/Djie Cast_<versi>_x64-setup.exe`.

Atau lewat GitHub Actions: workflow **Windows build** (manual, atau tag `win-v*`).

## Coba UI di Mac
`DJIE_SCRCPY_DIR=../vendor/scrcpy npx tauri dev` memakai scrcpy versi Mac dari `vendor/`.
