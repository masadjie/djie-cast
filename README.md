<p align="center">
  <img src="docs/icon.png" width="112" alt="">
</p>

<h1 align="center">Djie Cast</h1>

<p align="center">
  Layar HP-mu, langsung di Mac.<br>
  Mirror dan kendalikan Android, tampilkan iPhone, kelola file, jalankan emulator, dan remote Mac lain.<br>
  Gratis, open source, tanpa terminal.
</p>

<p align="center">
  <a href="https://github.com/masadjie/djie-cast/releases/latest"><b>Download untuk Mac</b></a>
  &nbsp;·&nbsp;
  <a href="https://masadjie.github.io/djie-cast/">Website</a>
  &nbsp;·&nbsp;
  <a href="https://masadjie.github.io/djie-cast/#video">Video 30 detik</a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111?style=flat-square">
  <img alt="Apple Silicon & Intel" src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-universal-111?style=flat-square">
  <img alt="Lisensi MIT" src="https://img.shields.io/badge/lisensi-MIT-4f45e6?style=flat-square">
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/home-dark.jpg">
  <img src="docs/assets/home-light.jpg" alt="Beranda Djie Cast: jumlah perangkat yang terhubung dan pintasan cast Android & iPhone">
</picture>

Djie Cast berawal dari kebiasaan menjalankan `scrcpy` lewat terminal setiap kali mau menampilkan HP di Mac. Sekarang cukup colok kabel dan klik satu tombol. Semuanya berjalan di Mac-mu sendiri: tidak ada akun, server, atau iklan.

## Android

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/android-dark.jpg">
  <img src="docs/assets/android-light.jpg" alt="Halaman Android: kartu perangkat dengan spesifikasi, baterai, penyimpanan dan tombol kontrol">
</picture>

Setiap HP yang tersambung muncul sebagai kartu lengkap: layar terkini, versi Android, chipset, RAM, kondisi dan siklus baterai, sisa penyimpanan. Tekan **Mulai Cast**, jendela HP terbuka di Mac dan langsung bisa diklik, di-scroll, dan diketik.

- Lewat kabel USB atau Wi-Fi.
- Tombol Back, Home, Recent, volume, power, screenshot, dan rotasi.
- **Kamera HP**: tampilkan kamera depan atau belakang di Mac (Android 12+).
- Daftar aplikasi terinstal, uninstall, dan pasang APK dari Mac.
- Preset kualitas Hemat 1024p, Seimbang 1600p, Maksimal hingga 120 fps. Rekam layar ke folder Movies.

Keyboard Mac jadi remote HP: `⌘B` kembali, `⌘H` home, `⌘S` aplikasi terbaru, `⌘↑/↓` volume, `⌘R` putar layar, `⌘V` tempel teks.

## iPhone & iPad

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/ios-dark.jpg">
  <img src="docs/assets/ios-light.jpg" alt="Halaman iPhone & iPad di Djie Cast">
</picture>

| Jalur | Bisa apa | Butuh |
|---|---|---|
| USB | Lihat layar + audio | Kabel, ketuk "Percayai" di iPhone |
| iPhone Mirroring | Kontrol penuh | macOS 15 + iOS 18, Apple ID sama |
| AirPlay | Lihat layar | Wi-Fi sama, AirPlay Receiver aktif |
| Continuity Camera | Kamera iPhone di Mac | macOS 14 + iOS 17, Apple ID sama |

Apple hanya mengizinkan kontrol iPhone lewat iPhone Mirroring, jadi Djie Cast membukakannya dari halaman yang sama. Info iPhone (model, iOS, kesehatan dan siklus baterai, penyimpanan) dan daftar aplikasi terbaca lewat kabel.

## File

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/files-dark.jpg">
  <img src="docs/assets/files-light.jpg" alt="File manager Android di Djie Cast">
</picture>

Penyimpanan HP Android dibuka seperti Finder: unduh, seret file dari Mac untuk mengunggah, buat folder, ganti nama, hapus. Untuk iPhone, galeri foto dan video tampil lengkap dengan thumbnail dan bisa diunduh sekaligus.

## Emulator Android

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/emulator-dark.jpg">
  <img src="docs/assets/emulator-light.jpg" alt="Halaman Emulator Android di Djie Cast">
</picture>

Tanpa Android Studio. Pilih sendiri versi Android yang mau diunduh (langsung dari server resmi Google, dicek checksum-nya), buat emulator ponsel atau tablet, lalu jalankan dengan GPU Mac. Emulator yang sedang berjalan tampil dengan kartu spesifikasi yang sama seperti HP sungguhan.

## Remote Desktop

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/remote-dark.jpg">
  <img src="docs/assets/remote-light.jpg" alt="Halaman Remote Desktop di Djie Cast">
</picture>

Kendalikan Mac lain dengan kode 6 angka. Koneksinya terenkripsi TLS, videonya H.264 dari hardware Mac. Mac di jaringan yang sama langsung terdeteksi. Untuk lewat internet, Tailscale sudah tertanam: masuk sekali, sesi tersimpan. Mac yang sedang dikontrol selalu menampilkan panel merah dengan tombol Putuskan.

## Install

1. Unduh DMG dari [Releases](https://github.com/masadjie/djie-cast/releases/latest).
2. Seret **Djie Cast** ke **Applications**.
3. Pembukaan pertama: klik kanan → **Open** → **Open** (app belum dinotarisasi Apple). Kalau muncul pesan *rusak*:

```bash
xattr -dr com.apple.quarantine "/Applications/Djie Cast.app"
```

macOS 14 Sonoma atau lebih baru, Apple Silicon dan Intel. scrcpy dan adb sudah ada di dalam app.

## Build dari source

```bash
git clone https://github.com/masadjie/djie-cast.git
cd djie-cast
./build.sh
```

Butuh Xcode Command Line Tools dan Go (`brew install go`) untuk membangun libtailscale. Build pertama mengunduh scrcpy resmi dan mengecek SHA-256-nya. Hasilnya ada di `build/`.

## Dibangun di atas

- [scrcpy](https://github.com/Genymobile/scrcpy) dan adb untuk Android (Apache 2.0)
- [libimobiledevice](https://libimobiledevice.org) untuk info dan aplikasi iPhone (LGPL)
- [libtailscale](https://github.com/tailscale/libtailscale) untuk Remote Desktop lewat internet (BSD)

## Dukung proyek ini

Djie Cast gratis. Kalau membantu pekerjaanmu, traktir kopi lewat QRIS di bawah, lalu kabari ke WhatsApp **0812-6949-4591**.

<p align="center"><img src="Resources/qris.png" width="240" alt="QRIS donasi Djie Cast"></p>

Bug, ide, dan pull request sangat diterima lewat [Issues](https://github.com/masadjie/djie-cast/issues).

## Lisensi

[MIT](LICENSE) © 2026 Adjie Kurniawan.
