#!/usr/bin/env python3
"""Builds the static guide pages under docs/ (one page per search intent) and the sitemap.

Each page is plain HTML with its own title, description, canonical URL, HowTo/FAQ structured data
and links back to the main page, so search engines can rank Djie Cast for more than one query.
Run: python3 scripts/gen-guides.py
"""
import html, json, pathlib, datetime

SITE = "https://masadjie.github.io/djie-cast/"
DMG = "https://github.com/masadjie/djie-cast/releases/latest"
ROOT = pathlib.Path(__file__).resolve().parent.parent / "docs"
TODAY = datetime.date.today().isoformat()

GUIDES = [
    {
        "slug": "scrcpy-mac",
        "title": "scrcpy untuk Mac tanpa terminal — GUI gratis",
        "h1": "scrcpy di Mac, tanpa terminal.",
        "desc": "Pakai scrcpy di macOS dengan satu klik: Djie Cast membungkus scrcpy dan adb dalam aplikasi Mac gratis. Tanpa Homebrew, tanpa perintah, lengkap dengan preset kualitas.",
        "lead": "scrcpy adalah cara terbaik menampilkan dan mengontrol HP Android dari komputer, tapi di Mac biasanya harus dipasang lewat Homebrew dan dijalankan dari terminal. Djie Cast membawa scrcpy dan adb di dalam aplikasinya, jadi kamu cukup colok kabel dan tekan satu tombol.",
        "shot": "android",
        "steps": [
            ("Unduh Djie Cast", "Ambil file DMG terbaru dari halaman rilis GitHub, lalu seret Djie Cast ke folder Applications. scrcpy dan adb sudah ada di dalamnya."),
            ("Aktifkan USB Debugging", "Di HP: Pengaturan → Tentang ponsel → ketuk Nomor build 7 kali, lalu buka Opsi pengembang dan nyalakan USB Debugging."),
            ("Colok kabel dan izinkan", "Sambungkan HP ke Mac, lalu ketuk Izinkan pada dialog “Izinkan USB debugging?” di HP."),
            ("Tekan Mulai Cast", "HP muncul sebagai kartu di halaman Android. Satu klik, jendela HP terbuka dan langsung bisa dikontrol dengan mouse dan keyboard."),
        ],
        "body": [
            ("Semua opsi scrcpy, tanpa menghafal flag", "Kualitas video, bitrate, fps, audio, matikan layar HP, tetap menyala, tampilkan sentuhan, selalu di atas, layar penuh, dan rekam layar tersedia sebagai tombol dan sakelar. Pengguna lanjutan tetap bisa menambahkan argumen sendiri."),
            ("Lebih dari sekadar mirror", "Kartu perangkat menampilkan spesifikasi HP, kondisi dan siklus baterai, serta sisa penyimpanan. Ada juga file manager Android, daftar aplikasi dengan tombol uninstall, dan mode kamera HP."),
        ],
        "faq": [
            ("Apakah perlu memasang scrcpy lewat Homebrew?", "Tidak. Djie Cast sudah membawa scrcpy dan adb resmi di dalam aplikasinya."),
            ("Apakah bisa lewat Wi-Fi?", "Bisa. Colok sekali lewat USB, aktifkan mode Wi-Fi dari kartu perangkat, lalu kabel boleh dicabut."),
            ("Apakah Djie Cast gratis?", "Ya, gratis dan open source dengan lisensi MIT."),
        ],
    },
    {
        "slug": "mirror-android-ke-mac",
        "title": "Cara mirror HP Android ke Mac (USB & Wi-Fi) — gratis",
        "h1": "Cara mirror HP Android ke Mac.",
        "desc": "Panduan menampilkan dan mengontrol layar HP Android di MacBook atau iMac lewat kabel USB atau Wi-Fi dengan aplikasi gratis Djie Cast. Bisa klik, ketik, dan rekam layar.",
        "lead": "Dengan Djie Cast, layar HP Android tampil di Mac dalam hitungan detik, dan kamu bisa mengontrolnya dengan mouse dan keyboard Mac. Cocok untuk presentasi, demo aplikasi, live streaming, atau sekadar membalas chat tanpa mengangkat HP.",
        "shot": "android",
        "steps": [
            ("Pasang Djie Cast", "Unduh DMG, seret ke Applications. Pembukaan pertama: klik kanan → Open."),
            ("Nyalakan USB Debugging di HP", "Pengaturan → Tentang ponsel → ketuk Nomor build 7 kali → Opsi pengembang → USB Debugging. Di HP Xiaomi, nyalakan juga “USB debugging (Pengaturan keamanan)”."),
            ("Sambungkan kabel", "Pakai kabel data, lalu ketuk Izinkan di HP. Centang “Selalu izinkan dari komputer ini” agar tidak ditanya lagi."),
            ("Mulai cast", "Buka halaman Android di Djie Cast dan tekan Mulai Cast. Untuk Wi-Fi, pilih Aktifkan Wi-Fi di menu kartu, lalu cabut kabel."),
        ],
        "body": [
            ("Keyboard Mac jadi remote HP", "⌘B kembali, ⌘H home, ⌘S aplikasi terbaru, ⌘↑ dan ⌘↓ volume, ⌘R putar layar, ⌘V tempel teks dari Mac ke HP. Klik kanan juga berfungsi sebagai tombol kembali."),
            ("Untuk OBS dan live streaming", "Jendela cast bisa ditangkap OBS, Streamlabs, atau Ecamm Live lewat Window Capture. Nyalakan “Tanpa bingkai jendela” untuk gambar yang bersih."),
        ],
        "faq": [
            ("HP tidak terdeteksi, kenapa?", "Biasanya USB Debugging belum aktif, kabel hanya untuk mengisi daya, atau dialog izin di HP belum diketuk. Djie Cast punya panduan langkah demi langkah di halaman Android."),
            ("Apakah suaranya ikut?", "Ya, untuk Android 11 ke atas audio HP ikut diteruskan ke Mac."),
            ("Apakah HP perlu di-root?", "Tidak perlu root dan tidak perlu memasang aplikasi apa pun di HP."),
        ],
    },
    {
        "slug": "mirror-iphone-ke-mac",
        "title": "Cara menampilkan layar iPhone di Mac — USB, AirPlay, iPhone Mirroring",
        "h1": "Layar iPhone di Mac, tiga cara.",
        "desc": "Tampilkan layar iPhone atau iPad di Mac lewat kabel USB (dengan audio), AirPlay, atau iPhone Mirroring untuk kontrol penuh. Ditambah kamera iPhone dan galeri foto lewat Djie Cast.",
        "lead": "Apple menyediakan beberapa jalur untuk membawa layar iPhone ke Mac, dan masing-masing punya batasan. Djie Cast mengumpulkannya di satu halaman supaya kamu tinggal memilih yang paling cocok.",
        "shot": "ios",
        "steps": [
            ("Colok kabel USB", "Sambungkan iPhone ke Mac dengan kabel data dan buka kunci layarnya."),
            ("Ketuk “Percayai”", "Saat iPhone bertanya “Percayai Komputer Ini?”, ketuk Percayai dan masukkan kode sandi."),
            ("Izinkan Kamera untuk Djie Cast", "macOS membaca layar iPhone sebagai sumber video, jadi izinkan akses Kamera saat diminta."),
            ("Tekan Mulai Cast", "Layar dan audio iPhone tampil di jendela Mac yang ikut berputar saat iPhone dimiringkan."),
        ],
        "body": [
            ("Mau mengontrol iPhone dari Mac?", "Apple hanya mengizinkan kontrol lewat iPhone Mirroring (macOS 15 dan iOS 18 ke atas, Apple ID yang sama). Djie Cast membukanya langsung dari halaman iPhone."),
            ("Kamera iPhone dan galeri", "Dengan Continuity Camera, kamera belakang iPhone bisa tampil di Mac tanpa kabel. Lewat kabel, galeri foto dan video iPhone bisa dilihat dan diunduh, lengkap dengan info baterai dan penyimpanan."),
        ],
        "faq": [
            ("Apakah perlu memasang aplikasi di iPhone?", "Tidak. Semua jalur memakai fitur bawaan iOS dan macOS."),
            ("Kenapa iPhone tidak muncul?", "Pastikan kabel mendukung data, layar iPhone tidak terkunci, dan sudah menekan Percayai."),
            ("Bisa lewat Wi-Fi?", "Bisa dengan AirPlay (hanya lihat) atau iPhone Mirroring (kontrol penuh)."),
        ],
    },
    {
        "slug": "emulator-android-mac",
        "title": "Emulator Android ringan untuk Mac tanpa Android Studio — gratis",
        "h1": "Emulator Android di Mac, tanpa Android Studio.",
        "desc": "Buat dan jalankan emulator Android di Mac Apple Silicon tanpa Android Studio. Pilih versi Android sendiri dari server resmi Google, jalan cepat dengan GPU Mac. Gratis lewat Djie Cast.",
        "lead": "Android Studio berukuran besar kalau kamu hanya butuh emulator untuk mencoba aplikasi atau game. Djie Cast mengunduh hanya bahan yang kamu pilih, membuat emulatornya, dan menjalankannya dengan akselerasi hardware Mac.",
        "shot": "emulator",
        "steps": [
            ("Buka halaman Emulator Android", "Di bagian Bahan, unduh Android Emulator dan satu system image, misalnya Android 15 dengan Google Play."),
            ("Atur perangkat", "Pilih ponsel, ponsel kecil, atau tablet, lalu tentukan RAM, jumlah core, dan penyimpanan."),
            ("Buat emulator", "Tekan Buat emulator. File konfigurasinya disimpan di lokasi standar Android sehingga juga terbaca oleh Android Studio."),
            ("Jalankan", "Tekan Jalankan. Setelah menyala, emulator tampil dengan kartu spesifikasi dan bisa langsung di-cast."),
        ],
        "body": [
            ("Unduhan yang bisa dipercaya", "Semua bahan diambil dari repository resmi Google, dicek checksum-nya, dan lisensinya ditampilkan sebelum diunduh. Unduhan disimpan di cache supaya tidak perlu diulang."),
            ("Dibuat untuk Apple Silicon", "System image arm64 berjalan native di chip M, dengan GPU Mac dan Quick Boot sehingga menyala dalam hitungan detik."),
        ],
        "faq": [
            ("Apakah bisa memasang Play Store?", "Ya, pilih system image Google Play."),
            ("Berapa ruang yang dibutuhkan?", "Sekitar 2 sampai 3 GB per versi Android, ditambah ukuran penyimpanan emulator yang kamu pilih."),
            ("Apakah bisa dipakai bersama Android Studio?", "Bisa. Djie Cast memakai lokasi SDK yang sama, ~/Library/Android/sdk."),
        ],
    },
    {
        "slug": "remote-desktop-mac",
        "title": "Remote desktop Mac ke Mac gratis — alternatif AnyDesk",
        "h1": "Remote desktop Mac ke Mac, gratis.",
        "desc": "Kendalikan Mac lain dari mana saja dengan kode 6 angka. Terenkripsi TLS, tanpa server pihak ketiga, dan lewat internet dengan Tailscale bawaan. Gratis di Djie Cast.",
        "lead": "Butuh membantu keluarga atau mengakses Mac kantor dari rumah? Djie Cast punya remote desktop Mac ke Mac yang bekerja seperti AnyDesk, tetapi tanpa akun, tanpa server perantara, dan gratis.",
        "shot": "remote",
        "steps": [
            ("Di Mac yang akan dikontrol", "Buka Remote Desktop, nyalakan Izinkan diakses, lalu berikan izin Perekaman Layar dan Aksesibilitas."),
            ("Bagikan kode", "Kode 6 angka muncul di layar. Kode bisa diganti kapan saja."),
            ("Di Mac pengontrol", "Mac di jaringan yang sama langsung terdeteksi. Pilih, masukkan kode, lalu sambungkan."),
            ("Lewat internet", "Masuk Tailscale sekali di kedua Mac. Setelah itu Mac di jaringan mana pun bisa terhubung."),
        ],
        "body": [
            ("Aman sejak awal", "Koneksi terenkripsi TLS dengan kunci dari kode akses, dan kode yang salah langsung ditolak. Mac yang sedang dikontrol selalu menampilkan panel merah dengan tombol Putuskan."),
            ("Terasa lokal", "Video dikodekan H.264 oleh hardware Mac. Mouse, klik kanan, scroll, keyboard, dan shortcut ⌘ dikirim ke Mac tujuan."),
        ],
        "faq": [
            ("Apakah bisa dari Windows?", "Saat ini Mac ke Mac saja."),
            ("Apakah lewat server Djie Cast?", "Tidak ada server Djie Cast. Di jaringan lokal koneksinya langsung; lewat internet memakai jaringan pribadi Tailscale milikmu."),
            ("Kenapa izin diminta lagi?", "macOS meminta izin Perekaman Layar dan Aksesibilitas sekali. Kalau masih “Belum” setelah diizinkan, pakai tombol Reset izin di halaman Remote Desktop."),
        ],
    },
]

GUIDES_EN = [
    {
        "slug": "scrcpy-mac", "shot": "android",
        "title": "scrcpy for Mac without the terminal — free GUI",
        "h1": "scrcpy on Mac, no terminal.",
        "desc": "Use scrcpy on macOS with one click: Djie Cast bundles scrcpy and adb in a free Mac app. No Homebrew, no commands, with quality presets and device info.",
        "lead": "scrcpy is the best way to show and control an Android phone from a computer, but on a Mac it usually means Homebrew and the terminal. Djie Cast ships scrcpy and adb inside the app, so you plug in a cable and press one button.",
        "steps": [
            ("Download Djie Cast", "Get the latest DMG from the GitHub releases page and drag Djie Cast to Applications. scrcpy and adb are already inside."),
            ("Turn on USB Debugging", "On the phone: Settings → About phone → tap Build number 7 times, then open Developer options and turn on USB Debugging."),
            ("Plug in and allow", "Connect the phone to the Mac and tap Allow on the “Allow USB debugging?” prompt."),
            ("Press Start Cast", "The phone appears as a card on the Android page. One click and its window opens, ready for mouse and keyboard."),
        ],
        "body": [
            ("Every scrcpy option, no flags to remember", "Quality, bitrate, fps, audio, screen off, stay awake, show touches, always on top, fullscreen and recording are switches and buttons. Power users can still add their own arguments."),
            ("More than mirroring", "Device cards show the phone's specs, battery health and cycles, and free storage. There's also an Android file manager, an app list with uninstall, and a phone-camera mode."),
        ],
        "faq": [
            ("Do I need to install scrcpy with Homebrew?", "No. Djie Cast bundles the official scrcpy and adb."),
            ("Does it work over Wi-Fi?", "Yes. Phones with Wireless debugging on the same network show up automatically; pair once with the 6-digit code."),
            ("Is Djie Cast free?", "Yes, free and open source under the MIT license."),
        ],
    },
    {
        "slug": "mirror-android-ke-mac", "shot": "android",
        "title": "How to mirror an Android phone to a Mac (USB & Wi-Fi) — free",
        "h1": "Mirror your Android phone to your Mac.",
        "desc": "Show and control your Android phone's screen on a MacBook or iMac over USB or Wi-Fi with the free Djie Cast app. Click, type and record the screen.",
        "lead": "With Djie Cast your Android screen appears on your Mac in seconds and you control it with the Mac's mouse and keyboard. Handy for presentations, app demos, live streaming, or just answering chats without picking up the phone.",
        "steps": [
            ("Install Djie Cast", "Download the DMG and drag it to Applications. First launch: right-click → Open."),
            ("Turn on USB Debugging", "Settings → About phone → tap Build number 7 times → Developer options → USB Debugging. On Xiaomi also enable “USB debugging (Security settings)”."),
            ("Plug in the cable", "Use a data cable and tap Allow on the phone. Tick “Always allow from this computer”."),
            ("Start casting", "Open the Android page and press Start Cast. For Wi-Fi, turn on Wireless debugging and pick the phone under Phones on this network."),
        ],
        "body": [
            ("Your Mac keyboard becomes a remote", "⌘B back, ⌘H home, ⌘S recent apps, ⌘↑ and ⌘↓ volume, ⌘R rotate, ⌘V paste text from the Mac to the phone. Right-click also works as back."),
            ("For OBS and live streaming", "OBS, Streamlabs or Ecamm Live can capture the cast window with Window Capture. Turn on Borderless window for a clean picture."),
        ],
        "faq": [
            ("My phone isn't detected — why?", "Usually USB Debugging is off, the cable is charge-only, or the permission prompt on the phone wasn't tapped. Djie Cast has a step-by-step guide on the Android page."),
            ("Is the audio forwarded?", "Yes, on Android 11 and later the phone's audio plays on the Mac."),
            ("Does the phone need root?", "No root and nothing to install on the phone."),
        ],
    },
    {
        "slug": "mirror-iphone-ke-mac", "shot": "ios",
        "title": "How to show your iPhone screen on a Mac — USB, AirPlay, iPhone Mirroring",
        "h1": "Your iPhone on your Mac, three ways.",
        "desc": "Show your iPhone or iPad on a Mac over USB (with audio), AirPlay, or iPhone Mirroring for full control. Plus iPhone camera and photo gallery with Djie Cast.",
        "lead": "Apple offers several routes to get an iPhone screen onto a Mac, each with its own limits. Djie Cast puts them on one page so you can pick the one that fits.",
        "steps": [
            ("Plug in a USB cable", "Connect the iPhone to the Mac with a data cable and unlock it."),
            ("Tap “Trust”", "When the iPhone asks “Trust This Computer?”, tap Trust and enter your passcode."),
            ("Allow Camera for Djie Cast", "macOS reads the iPhone screen as a video source, so allow Camera access when asked."),
            ("Press Start Cast", "The iPhone's screen and audio appear in a Mac window that turns when the iPhone does."),
        ],
        "body": [
            ("Want to control the iPhone from the Mac?", "Apple only allows control through iPhone Mirroring (macOS 15 and iOS 18 or later, same Apple ID). Djie Cast opens it from the iPhone page."),
            ("iPhone camera and gallery", "With Continuity Camera, the iPhone's back camera shows on the Mac without a cable. Over the cable you can browse and download the photo and video gallery, with battery and storage info."),
        ],
        "faq": [
            ("Do I need to install an app on the iPhone?", "No. Every route uses built-in iOS and macOS features."),
            ("Why doesn't my iPhone show up?", "Check that the cable supports data, the iPhone is unlocked, and you tapped Trust."),
            ("Does it work over Wi-Fi?", "Yes, with AirPlay (view only) or iPhone Mirroring (full control)."),
        ],
    },
    {
        "slug": "emulator-android-mac", "shot": "emulator",
        "title": "Lightweight Android emulator for Mac without Android Studio — free",
        "h1": "Android emulator on Mac, no Android Studio.",
        "desc": "Create and run Android emulators on Apple Silicon Macs without Android Studio. Choose your Android version from Google's official servers and run it fast on the Mac GPU. Free with Djie Cast.",
        "lead": "Android Studio is a big download if all you need is an emulator to try an app or game. Djie Cast downloads only the parts you choose, creates the emulator, and runs it with hardware acceleration.",
        "steps": [
            ("Open the Android Emulator page", "Under Components, download Android Emulator and one system image, for example Android 15 with Google Play."),
            ("Set up the device", "Pick a phone, small phone or tablet, then choose RAM, cores and storage."),
            ("Create the emulator", "Press Create emulator. Its configuration is stored in Android's standard location, so Android Studio can read it too."),
            ("Run it", "Press Run. Once booted, the emulator gets a spec card and can be cast right away."),
        ],
        "body": [
            ("Downloads you can trust", "Everything comes from Google's official repository, is checksum-verified, and shows its license before download. Downloads are cached so you don't fetch them twice."),
            ("Made for Apple Silicon", "arm64 system images run natively on M-series chips, with the Mac GPU and Quick Boot, so they start in seconds."),
        ],
        "faq": [
            ("Can I get the Play Store?", "Yes, choose a Google Play system image."),
            ("How much space does it need?", "About 2 to 3 GB per Android version, plus the emulator storage you choose."),
            ("Can I use it alongside Android Studio?", "Yes. Djie Cast uses the same SDK location, ~/Library/Android/sdk."),
        ],
    },
    {
        "slug": "remote-desktop-mac", "shot": "remote",
        "title": "Free Mac to Mac remote desktop — an AnyDesk alternative",
        "h1": "Mac to Mac remote desktop, free.",
        "desc": "Control another Mac from anywhere with a 6-digit code. TLS-encrypted, no third-party server, and over the internet with built-in Tailscale. Free in Djie Cast.",
        "lead": "Need to help family or reach your office Mac from home? Djie Cast has a Mac to Mac remote desktop that works like AnyDesk, without an account, without a relay server, and for free.",
        "steps": [
            ("On the Mac to be controlled", "Open Remote Desktop, turn on Allow this Mac to be accessed, and grant Screen Recording and Accessibility."),
            ("Share the code", "A 6-digit code appears. You can change it any time."),
            ("On the controlling Mac", "Macs on the same network appear automatically. Pick one, enter the code, and connect."),
            ("Over the internet", "Sign in to Tailscale once on both Macs. After that, Macs on any network can connect."),
        ],
        "body": [
            ("Secure from the start", "The connection is TLS-encrypted with a key derived from the access code, and wrong codes are rejected. A controlled Mac always shows a red panel with a Disconnect button."),
            ("Feels local", "Video is H.264-encoded by the Mac's hardware. Mouse, right-click, scrolling, keyboard and ⌘ shortcuts go straight to the other Mac."),
        ],
        "faq": [
            ("Can I connect from Windows?", "Not yet — Mac to Mac only for now."),
            ("Does it go through a Djie Cast server?", "There is no Djie Cast server. On a local network the connection is direct; over the internet it uses your private Tailscale network."),
            ("Why does it keep asking for permission?", "macOS asks for Screen Recording and Accessibility once. If it still says Not yet after allowing, use Reset permissions on the Remote Desktop page."),
        ],
    },
]

UI = {
    "id": {"guides": "Panduan", "steps": "Langkah-langkahnya", "faq": "Pertanyaan umum", "more": "Panduan lain", "dl": "Download untuk Mac", "dlfree": "Download gratis", "all": "Lihat semua fitur", "alt": "dengan Djie Cast", "foot": "Djie Cast gratis dan open source (MIT)", "locale": "id_ID", "tool": "Djie Cast untuk macOS"},
    "en": {"guides": "Guides", "steps": "Step by step", "faq": "Questions", "more": "More guides", "dl": "Download for Mac", "dlfree": "Free download", "all": "See all features", "alt": "with Djie Cast", "foot": "Djie Cast is free and open source (MIT)", "locale": "en_US", "tool": "Djie Cast for macOS"},
}

ALL = [g["slug"] for g in GUIDES]
LINKS = {g["slug"]: g["h1"].rstrip(".") for g in GUIDES}

CSS = """
:root{--paper:#f3f4f9;--panel:#fff;--ink:#12142b;--ink-2:#4a4e6b;--ink-3:#868aa3;--line:#dcdeea;--signal:#4f45e6;--signal-ink:#fff;color-scheme:light}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--paper:#0b0c18;--panel:#14162a;--ink:#eceef8;--ink-2:#a8abc6;--ink-3:#6c7090;--line:#262944;--signal:#8a84ff;--signal-ink:#0b0c18;color-scheme:dark}}
:root[data-theme=dark]{--paper:#0b0c18;--panel:#14162a;--ink:#eceef8;--ink-2:#a8abc6;--ink-3:#6c7090;--line:#262944;--signal:#8a84ff;--signal-ink:#0b0c18;color-scheme:dark}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--paper);color:var(--ink);font:400 17px/1.65 "Instrument Sans",-apple-system,"Segoe UI",sans-serif;-webkit-font-smoothing:antialiased}
a{color:inherit}img{display:block;max-width:100%;height:auto}
.wrap{max-width:860px;margin-inline:auto;padding-left:max(20px,env(safe-area-inset-left,0px));padding-right:max(20px,env(safe-area-inset-right,0px))}
header{border-bottom:1px solid var(--line)}header .wrap{display:flex;align-items:center;justify-content:space-between;gap:16px;padding-block:16px}
.logo{display:flex;align-items:center;gap:10px;font:800 18px/1 "Archivo",sans-serif;text-decoration:none}.logo img{width:28px;height:28px;border-radius:7px}
.crumbs{font:500 12px/1.4 "Martian Mono",ui-monospace,monospace;letter-spacing:.06em;text-transform:uppercase;color:var(--ink-3);padding-top:48px}
.crumbs a{text-decoration:none}
h1,h2,h3{font-family:"Archivo",sans-serif;font-stretch:112%;letter-spacing:-.02em;text-wrap:balance}
h1{font-size:clamp(36px,6vw,60px);line-height:1;font-weight:850;margin:14px 0 18px}
h2{font-size:clamp(24px,3.4vw,32px);line-height:1.1;font-weight:800;margin:56px 0 14px}
h3{font-size:19px;font-weight:750;margin-bottom:4px}
.lead{font-size:19px;color:var(--ink-2);max-width:62ch}
p{max-width:66ch;color:var(--ink-2)}p+p{margin-top:12px}
.btn{display:inline-flex;align-items:center;gap:8px;padding:12px 20px;border-radius:12px;font-weight:650;text-decoration:none;background:var(--ink);color:var(--paper)}
.btn.line{background:transparent;color:var(--ink);border:1px solid var(--line)}
.cta{display:flex;flex-wrap:wrap;gap:10px;margin-top:26px}
figure{margin-top:40px;border-radius:14px;overflow:hidden;box-shadow:0 30px 60px -30px rgba(18,20,43,.45),0 0 0 1px var(--line)}
ol.steps{list-style:none;counter-reset:s;display:grid;gap:0;border-top:1px solid var(--line)}
ol.steps li{counter-increment:s;display:grid;grid-template-columns:3em minmax(0,1fr);gap:12px;padding:18px 0;border-bottom:1px solid var(--line)}
ol.steps li::before{content:counter(s,decimal-leading-zero);font:600 13px/1.9 "Martian Mono",monospace;color:var(--signal)}
.pair{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:28px;margin-top:8px}
dl.faq dt{font-weight:700;margin-top:18px}dl.faq dd{color:var(--ink-2);max-width:66ch}
.more{display:grid;gap:8px;margin-top:10px}.more a{color:var(--signal);font-weight:600;text-decoration:none}
footer{border-top:1px solid var(--line);margin-top:80px;padding-block:28px;color:var(--ink-3);font-size:14px}
@media (max-width:640px){.pair{grid-template-columns:minmax(0,1fr)}}
"""

FONTS = '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@62..125,500..900&family=Instrument+Sans:wght@400..700&family=Martian+Mono:wght@500;600&display=swap">'


def page(g, lang="id", guides=None):
    guides = guides or GUIDES
    t = UI[lang]
    base = "../" if lang == "id" else "../../"
    url = SITE + ("" if lang == "id" else "en/") + g["slug"] + "/"
    alt_id, alt_en = SITE + g["slug"] + "/", SITE + "en/" + g["slug"] + "/"
    links = {x["slug"]: x["h1"].rstrip(".") for x in guides}
    e = html.escape
    howto = {"@context": "https://schema.org", "@type": "HowTo", "name": g["h1"].rstrip("."), "description": g["desc"],
             "image": SITE + f"assets/{g['shot']}-light.jpg", "tool": [{"@type": "HowToTool", "name": t["tool"]}],
             "step": [{"@type": "HowToStep", "position": i + 1, "name": n, "text": t} for i, (n, t) in enumerate(g["steps"])]}
    faq = {"@context": "https://schema.org", "@type": "FAQPage",
           "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in g["faq"]]}
    crumbs = {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": 1, "name": "Djie Cast", "item": SITE if lang == "id" else SITE + "?lang=en"},
        {"@type": "ListItem", "position": 2, "name": g["h1"].rstrip("."), "item": url}]}
    ld = "".join(f'<script type="application/ld+json">{json.dumps(x, ensure_ascii=False)}</script>' for x in (howto, faq, crumbs))
    steps = "".join(f"<li><div><h3>{e(n)}</h3><p>{e(t)}</p></div></li>" for n, t in g["steps"])
    body = "".join(f"<div><h3>{e(h)}</h3><p>{e(t)}</p></div>" for h, t in g["body"])
    faqs = "".join(f"<dt>{e(q)}</dt><dd>{e(a)}</dd>" for q, a in g["faq"])
    more = "".join(f'<a href="../{x}/">{e(links[x])} →</a>' for x in ALL if x != g["slug"])
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{e(g['title'])} | Djie Cast</title>
<meta name="description" content="{e(g['desc'])}">
<link rel="canonical" href="{url}">
<link rel="alternate" hreflang="id" href="{alt_id}">
<link rel="alternate" hreflang="en" href="{alt_en}">
<link rel="alternate" hreflang="x-default" href="{alt_id}">
<meta name="robots" content="index, follow, max-image-preview:large">
<meta name="theme-color" content="#4f45e6">
<link rel="icon" type="image/svg+xml" href="{base}assets/logo.svg">
<link rel="apple-touch-icon" href="{base}assets/icon.png">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Djie Cast">
<meta property="og:locale" content="{t['locale']}">
<meta property="og:title" content="{e(g['title'])}">
<meta property="og:description" content="{e(g['desc'])}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SITE}assets/{g['shot']}-light.jpg">
<meta name="twitter:card" content="summary_large_image">
{ld}
{FONTS}
<style>{CSS}</style>
</head>
<body>
<header><div class="wrap"><a class="logo" href="{base}{'' if lang == 'id' else '?lang=en'}"><img src="{base}assets/icon.png" alt="" width="28" height="28">Djie Cast</a><a class="btn" href="{DMG}">{t['dlfree']}</a></div></header>
<main class="wrap">
<nav class="crumbs" aria-label="Breadcrumb"><a href="{base}">Djie Cast</a> / {t['guides']} · <a href="{alt_en if lang == 'id' else alt_id}">{'English' if lang == 'id' else 'Bahasa Indonesia'}</a></nav>
<h1>{e(g['h1'])}</h1>
<p class="lead">{e(g['lead'])}</p>
<div class="cta"><a class="btn" href="{DMG}">{t['dl']}</a><a class="btn line" href="{base}{'' if lang == 'id' else '?lang=en'}">{t['all']}</a></div>
<figure><picture><source media="(prefers-color-scheme: dark)" srcset="{base}assets/{g['shot']}-dark.jpg"><img src="{base}assets/{g['shot']}-light.jpg" alt="{e(g['h1'].rstrip('.'))} {t['alt']}" width="1600" height="1000" loading="eager"></picture></figure>
<h2>{t['steps']}</h2>
<ol class="steps">{steps}</ol>
<div class="pair">{body}</div>
<h2>{t['faq']}</h2>
<dl class="faq">{faqs}</dl>
<h2>{t['more']}</h2>
<div class="more">{more}</div>
</main>
<footer><div class="wrap">© 2026 Adjie Kurniawan · {t['foot']} · <a href="https://github.com/masadjie/djie-cast">GitHub</a></div></footer>
</body>
</html>
"""


def main():
    for g in GUIDES:
        d = ROOT / g["slug"]
        d.mkdir(exist_ok=True)
        (d / "index.html").write_text(page(g), encoding="utf-8")
    for g in GUIDES_EN:
        d = ROOT / "en" / g["slug"]
        d.mkdir(parents=True, exist_ok=True)
        (d / "index.html").write_text(page(g, "en", GUIDES_EN), encoding="utf-8")
    urls = [("", "1.0", "weekly")] + [(g["slug"] + "/", "0.8", "monthly") for g in GUIDES] + [("en/" + g["slug"] + "/", "0.7", "monthly") for g in GUIDES_EN]
    items = "\n".join(f"""  <url>
    <loc>{SITE}{u}</loc>
    <lastmod>{TODAY}</lastmod>
    <changefreq>{f}</changefreq>
    <priority>{p}</priority>{'''
    <xhtml:link rel="alternate" hreflang="id" href="''' + SITE + '''"/>
    <xhtml:link rel="alternate" hreflang="en" href="''' + SITE + '''?lang=en"/>''' if not u else ''}
    <image:image><image:loc>{SITE}assets/{'home' if not u else next(g['shot'] for g in GUIDES if u.endswith(g['slug'] + '/'))}-light.jpg</image:loc></image:image>
  </url>""" for u, p, f in urls)
    (ROOT / "sitemap.xml").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
{items}
</urlset>
""", encoding="utf-8")
    print("wrote", len(GUIDES), "guides + sitemap")


if __name__ == "__main__":
    main()
