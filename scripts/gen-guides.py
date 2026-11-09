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


def page(g):
    url = SITE + g["slug"] + "/"
    e = html.escape
    howto = {"@context": "https://schema.org", "@type": "HowTo", "name": g["h1"].rstrip("."), "description": g["desc"],
             "image": SITE + f"assets/{g['shot']}-light.jpg", "tool": [{"@type": "HowToTool", "name": "Djie Cast untuk macOS"}],
             "step": [{"@type": "HowToStep", "position": i + 1, "name": n, "text": t} for i, (n, t) in enumerate(g["steps"])]}
    faq = {"@context": "https://schema.org", "@type": "FAQPage",
           "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in g["faq"]]}
    crumbs = {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": 1, "name": "Djie Cast", "item": SITE},
        {"@type": "ListItem", "position": 2, "name": g["h1"].rstrip("."), "item": url}]}
    ld = "".join(f'<script type="application/ld+json">{json.dumps(x, ensure_ascii=False)}</script>' for x in (howto, faq, crumbs))
    steps = "".join(f"<li><div><h3>{e(n)}</h3><p>{e(t)}</p></div></li>" for n, t in g["steps"])
    body = "".join(f"<div><h3>{e(h)}</h3><p>{e(t)}</p></div>" for h, t in g["body"])
    faqs = "".join(f"<dt>{e(q)}</dt><dd>{e(a)}</dd>" for q, a in g["faq"])
    more = "".join(f'<a href="../{s}/">{e(LINKS[s])} →</a>' for s in ALL if s != g["slug"])
    return f"""<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{e(g['title'])} | Djie Cast</title>
<meta name="description" content="{e(g['desc'])}">
<link rel="canonical" href="{url}">
<meta name="robots" content="index, follow, max-image-preview:large">
<meta name="theme-color" content="#4f45e6">
<link rel="icon" type="image/svg+xml" href="../assets/logo.svg">
<link rel="apple-touch-icon" href="../assets/icon.png">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Djie Cast">
<meta property="og:locale" content="id_ID">
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
<header><div class="wrap"><a class="logo" href="../"><img src="../assets/icon.png" alt="" width="28" height="28">Djie Cast</a><a class="btn" href="{DMG}">Download gratis</a></div></header>
<main class="wrap">
<nav class="crumbs" aria-label="Breadcrumb"><a href="../">Djie Cast</a> / Panduan</nav>
<h1>{e(g['h1'])}</h1>
<p class="lead">{e(g['lead'])}</p>
<div class="cta"><a class="btn" href="{DMG}">Download untuk Mac</a><a class="btn line" href="../">Lihat semua fitur</a></div>
<figure><picture><source media="(prefers-color-scheme: dark)" srcset="../assets/{g['shot']}-dark.jpg"><img src="../assets/{g['shot']}-light.jpg" alt="{e(g['h1'].rstrip('.'))} dengan Djie Cast" width="1600" height="1000" loading="eager"></picture></figure>
<h2>Langkah-langkahnya</h2>
<ol class="steps">{steps}</ol>
<div class="pair">{body}</div>
<h2>Pertanyaan umum</h2>
<dl class="faq">{faqs}</dl>
<h2>Panduan lain</h2>
<div class="more">{more}</div>
</main>
<footer><div class="wrap">© 2026 Adjie Kurniawan · Djie Cast gratis dan open source (MIT) · <a href="https://github.com/masadjie/djie-cast">GitHub</a></div></footer>
</body>
</html>
"""


def main():
    for g in GUIDES:
        d = ROOT / g["slug"]
        d.mkdir(exist_ok=True)
        (d / "index.html").write_text(page(g), encoding="utf-8")
    urls = [("", "1.0", "weekly")] + [(g["slug"] + "/", "0.8", "monthly") for g in GUIDES]
    items = "\n".join(f"""  <url>
    <loc>{SITE}{u}</loc>
    <lastmod>{TODAY}</lastmod>
    <changefreq>{f}</changefreq>
    <priority>{p}</priority>{'''
    <xhtml:link rel="alternate" hreflang="id" href="''' + SITE + '''"/>
    <xhtml:link rel="alternate" hreflang="en" href="''' + SITE + '''?lang=en"/>''' if not u else ''}
    <image:image><image:loc>{SITE}assets/{'home' if not u else next(g['shot'] for g in GUIDES if g['slug'] + '/' == u)}-light.jpg</image:loc></image:image>
  </url>""" for u, p, f in urls)
    (ROOT / "sitemap.xml").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
{items}
</urlset>
""", encoding="utf-8")
    print("wrote", len(GUIDES), "guides + sitemap")


if __name__ == "__main__":
    main()
