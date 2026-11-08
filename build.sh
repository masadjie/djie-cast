#!/bin/bash
# Build "Djie Cast.app" + DMG siap bagi — jalankan: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0 Beta"
BUILD_NUMBER="1"
DMG_NAME="DjieCast-1.0-beta"

APP="build/Djie Cast.app"

# scrcpy tidak disimpan di git — unduh otomatis bila belum ada.
[ -x vendor/scrcpy/scrcpy ] || ./scripts/fetch-scrcpy.sh
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/icon.iconset build/obj

echo "→ Compile Apple Silicon (arm64)..."
swiftc -O -parse-as-library -target arm64-apple-macos14 -o build/obj/DjieCast-arm64 Sources/*.swift
echo "→ Compile Intel (x86_64)..."
swiftc -O -parse-as-library -target x86_64-apple-macos14 -o build/obj/DjieCast-x86_64 Sources/*.swift
lipo -create build/obj/DjieCast-arm64 build/obj/DjieCast-x86_64 -output "$APP/Contents/MacOS/DjieCast"

echo "→ Icon..."
swift make_icon.swift build/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out build/icon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out build/icon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Djie Cast</string>
  <key>CFBundleDisplayName</key><string>Djie Cast</string>
  <key>CFBundleIdentifier</key><string>local.djiecast.app</string>
  <key>CFBundleExecutable</key><string>DjieCast</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Adjie Kurniawan · Open source (MIT)</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>Djie Cast perlu akses ini untuk menampilkan layar iPhone/iPad yang dicolok lewat USB.</string>
  <key>NSMicrophoneUsageDescription</key><string>Djie Cast perlu akses ini untuk memutar audio dari iPhone/iPad yang dicolok lewat USB.</string>
</dict>
</plist>
PLIST

echo "→ Bundel scrcpy $(cat vendor/scrcpy/VERSION)..."
cp vendor/scrcpy/scrcpy vendor/scrcpy/adb "$APP/Contents/MacOS/"
mkdir -p "$APP/Contents/Resources/scrcpy"
cp vendor/scrcpy/scrcpy-server vendor/scrcpy/scrcpy.png vendor/scrcpy/disconnected.png \
   vendor/scrcpy/LICENSE vendor/scrcpy/VERSION "$APP/Contents/Resources/scrcpy/"

cp Resources/qris.png "$APP/Contents/Resources/"

echo "→ Codesign..."
codesign --force -s - "$APP/Contents/MacOS/scrcpy" "$APP/Contents/MacOS/adb"
codesign --force -s - "$APP"

echo "→ DMG..."
STAGE="build/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/BACA DULU.txt" <<'TXT'
Djie Cast 1.0 Beta
==================

INSTALL
1. Seret "Djie Cast" ke folder Applications.
2. Buka pertama kali: klik kanan "Djie Cast" → Open → Open.
   (Kalau muncul "tidak bisa dibuka / damaged", buka Terminal lalu jalankan:
    xattr -dr com.apple.quarantine "/Applications/Djie Cast.app"
    lalu buka lagi.)

BUTUH
- macOS 14 (Sonoma) atau lebih baru. Apple Silicon & Intel didukung.

UNTUK CAST ANDROID:
- Tidak perlu install apa-apa, scrcpy & adb sudah ada di dalam app.
- Di HP: aktifkan Opsi Developer → USB Debugging, colok kabel,
  lalu ketuk "Izinkan" saat muncul dialog USB debugging di HP.

UNTUK CAST iOS:
- USB: tidak perlu install apa-apa. Izinkan akses Kamera saat diminta.
- iPhone Mirroring: macOS Sequoia+ dan iOS 18+, Apple ID sama.
- AirPlay: nyalakan AirPlay Receiver di Pengaturan Sistem.
TXT
hdiutil create -volname "Djie Cast" -srcfolder "$STAGE" -ov -format UDZO "build/${DMG_NAME}.dmg" >/dev/null
rm -rf "$STAGE" build/obj

echo "✅ Selesai:"
echo "   App : $APP"
echo "   DMG : build/${DMG_NAME}.dmg  ← kirim file ini ke Mac lain"
