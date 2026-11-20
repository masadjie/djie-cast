/* Djie Cast untuk Windows — UI. Semua kerja ke HP lewat adb/scrcpy di backend Rust. */
"use strict";

const TAURI = window.__TAURI__ || window.__DJIE_MOCK__;
const invoke = TAURI.core.invoke;
const listen = TAURI.event.listen;
const dialog = TAURI.dialog;
const opener = TAURI.opener;

// ---------- Utilitas ----------
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const q = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'"; // kutip untuk shell HP
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const chunk = (a, n) => Array.from({ length: Math.ceil(a.length / n) }, (_, i) => a.slice(i * n, i * n + n));
const baseName = (p) => p.split(/[\\/]/).filter(Boolean).pop() || p;

function bytes(b) {
  if (b == null || b < 0) return "–";
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (b >= 1000 && i < u.length - 1) { b /= 1000; i++; }
  return (i === 0 ? b : b.toFixed(b < 10 ? 1 : 0)) + " " + u[i];
}
/** Ukuran di kotak HP (230 GB terpakai → 256 GB). */
function marketing(b, ram) {
  const gb = ram ? b / 2 ** 30 : b / 1e9;
  const steps = ram ? [1, 1.5, 2, 3, 4, 6, 8, 10, 12, 16, 18, 24, 32] : [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048];
  const v = steps.find((s) => gb <= s * (ram ? 1.0 : 1.0)) ?? Math.round(gb);
  return v >= 1024 ? v / 1024 + " TB" : v + " GB";
}
function uptime(secs) {
  const d = Math.floor(secs / 86400), h = Math.floor((secs % 86400) / 3600), m = Math.floor((secs % 3600) / 60);
  return d > 0 ? t("{d} hari {h} jam", { d, h }) : h > 0 ? t("{h} jam {m} menit", { h, m }) : t("{m} menit", { m });
}

let toastTimer;
function toast(msg, ms = 3200) {
  const el = $("#toast");
  el.textContent = msg;
  el.classList.add("on");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("on"), ms);
}

function modal({ title, text = "", input = null, ok = t("OK"), danger = false, cancel = t("Batal") }) {
  return new Promise((resolve) => {
    const bg = document.createElement("div");
    bg.className = "modal-bg";
    bg.innerHTML = `<div class="modal"><h3>${esc(title)}</h3>${text ? `<p>${esc(text)}</p>` : ""}
      ${input !== null ? `<input value="${esc(input)}">` : ""}
      <div class="row">${cancel ? `<button class="btn" data-a="no">${esc(cancel)}</button>` : ""}
      <button class="btn ${danger ? "danger solid" : "primary"}" data-a="yes">${esc(ok)}</button></div></div>`;
    document.body.append(bg);
    const inp = $("input", bg);
    if (inp) { inp.focus(); inp.select(); }
    const done = (v) => { bg.remove(); resolve(v); };
    bg.addEventListener("click", (e) => {
      const a = e.target.dataset?.a;
      if (a === "yes") done(inp ? inp.value : true);
      else if (a === "no" || e.target === bg) done(inp ? null : false);
    });
    bg.addEventListener("keydown", (e) => {
      if (e.key === "Enter") done(inp ? inp.value : true);
      if (e.key === "Escape") done(inp ? null : false);
    });
    if (!inp) $("[data-a=yes]", bg).focus();
  });
}

function menu(anchor, items) {
  closeMenu();
  const m = document.createElement("div");
  m.className = "menu";
  m.id = "menu";
  m.innerHTML = items.map((it, i) => (it === "-" ? "<hr>" : `<button data-i="${i}">${icon(it.icon || "dot")}<span>${esc(it.label)}</span></button>`)).join("");
  document.body.append(m);
  const r = anchor.getBoundingClientRect();
  const w = m.offsetWidth, h = m.offsetHeight;
  m.style.left = Math.min(r.right - w, innerWidth - w - 8) + "px";
  m.style.top = (r.bottom + 4 + h > innerHeight ? r.top - h - 4 : r.bottom + 4) + "px";
  m.addEventListener("click", (e) => {
    const b = e.target.closest("button");
    if (!b) return;
    closeMenu();
    items[+b.dataset.i].run();
  });
  setTimeout(() => document.addEventListener("click", closeMenu, { once: true }), 0);
}
function closeMenu() { $("#menu")?.remove(); }

// ---------- Ikon (garis, 24px) ----------
const ICONS = {
  phone: '<rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M11 18h2"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  folderplus: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><path d="M12 10v6M9 13h6"/>',
  file: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
  sparkle: '<path d="M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/>',
  terminal: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 9l3 3-3 3M13 15h4"/>',
  heart: '<path d="M12 20s-7-4.4-9-9a4.8 4.8 0 0 1 9-3 4.8 4.8 0 0 1 9 3c-2 4.6-9 9-9 9z"/>',
  play: '<path d="M7 5l12 7-12 7z"/>',
  stop: '<rect x="6" y="6" width="12" height="12" rx="2"/>',
  camera: '<path d="M4 8a2 2 0 0 1 2-2h2l1.5-2h5L16 6h2a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"/><circle cx="12" cy="12.5" r="3.5"/>',
  more: '<circle cx="5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/>',
  wifi: '<path d="M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"/><path d="M12 19.5h.01"/>',
  usb: '<path d="M12 3v15M8 7l4-4 4 4M7 11v2l5 3M17 10v3l-5 3"/><circle cx="12" cy="19.5" r="1.5"/>',
  unlink: '<path d="M9 15l6-6M7 11l-2 2a3.5 3.5 0 0 0 5 5l2-2M17 13l2-2a3.5 3.5 0 0 0-5-5l-2 2"/>',
  image: '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.8"/><path d="M21 16l-5-5-9 9"/>',
  rotate: '<path d="M4 12a8 8 0 0 1 14-5.3L20 9M20 4v5h-5M20 12a8 8 0 0 1-14 5.3L4 15M4 20v-5h5"/>',
  refresh: '<path d="M20 11a8 8 0 0 0-14.3-4.9L4 8M4 3v5h5M4 13a8 8 0 0 0 14.3 4.9L20 16M20 21v-5h-5"/>',
  download: '<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>',
  upload: '<path d="M12 20V9M7 14l5-5 5 5M5 4h14"/>',
  up: '<path d="M12 19V5M6 11l6-6 6 6"/>',
  pencil: '<path d="M4 20h4L19 9l-4-4L4 16z"/>',
  trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
  home: '<path d="M4 11l8-7 8 7v9H4z"/>',
  back: '<path d="M15 5l-7 7 7 7"/>',
  recents: '<rect x="5" y="5" width="14" height="14" rx="2"/>',
  power: '<path d="M12 3v8M7 6a8 8 0 1 0 10 0"/>',
  volup: '<path d="M4 10v4h4l5 4V6L8 10z"/><path d="M17 9a4 4 0 0 1 0 6M19.5 6.5a8 8 0 0 1 0 11"/>',
  voldown: '<path d="M4 10v4h4l5 4V6L8 10z"/><path d="M17 9a4 4 0 0 1 0 6"/>',
  mute: '<path d="M4 10v4h4l5 4V6L8 10z"/><path d="M17 9l5 6M22 9l-5 6"/>',
  window: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18"/>',
  globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
  dot: '<circle cx="12" cy="12" r="2"/>',
  check: '<path d="M5 12l5 5 9-10"/>',
};
const icon = (n) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICONS[n] || ""}</svg>`;

// ---------- Pengaturan ----------
const DEFAULTS = {
  maxSize: 1600, bitrate: 8, maxFps: 60, audio: true, turnScreenOff: false, stayAwake: true, alwaysOnTop: false,
  fullscreen: false, showTouches: false, clipboardSync: true, borderless: false, noControl: false, record: false,
  appSize: "phone", lang: "", lastIP: "",
};
const S = {
  set: Object.assign({}, DEFAULTS, (() => { try { return JSON.parse(localStorage.getItem("djie") || "{}"); } catch { return {}; } })()),
  devices: [],
  sel: null,
  running: new Set(),
  stopping: new Set(),
  page: "devices",
  paths: {},
  tools: {},
  nearby: [],
  nearbyBusy: null,
  nearbyErr: {},
};
function save() { try { localStorage.setItem("djie", JSON.stringify(S.set)); } catch {} }

const PRESETS = [
  { id: "hemat", name: "Hemat", v: [1024, 4, 30], hint: "1024p · 4 Mbps · 30 fps — ringan, cocok untuk Wi-Fi" },
  { id: "seimbang", name: "Seimbang", v: [1600, 8, 60], hint: "1600p · 8 Mbps · 60 fps — tajam & lancar" },
  { id: "maksimal", name: "Maksimal", v: [0, 24, 120], hint: "Resolusi asli · 24 Mbps · 120 fps — terbaik via USB" },
  { id: "kustom", name: "Kustom", v: null, hint: "Atur sendiri resolusi, bitrate & FPS" },
];
const OPTIONS = [
  ["audio", "Teruskan suara HP"], ["stayAwake", "Layar HP tetap menyala"], ["turnScreenOff", "Matikan layar HP saat mirror"],
  ["clipboardSync", "Sinkron clipboard"], ["alwaysOnTop", "Jendela selalu di atas"], ["fullscreen", "Mulai layar penuh"],
  ["borderless", "Jendela tanpa bingkai"], ["showTouches", "Tampilkan sentuhan"], ["noControl", "Hanya tonton (tanpa kontrol)"],
  ["record", "Rekam ke video"],
];

// ---------- Log ----------
let logText = "";
function log(s) {
  logText += s;
  if (logText.length > 80000) logText = logText.slice(-60000);
  const el = $("#log");
  if (!el) return;
  const atEnd = el.scrollTop + el.clientHeight >= el.scrollHeight - 30;
  el.textContent = logText;
  if (atEnd) el.scrollTop = el.scrollHeight;
}

// ---------- adb ----------
async function adb(args, quiet) {
  try {
    const r = await invoke("adb", { args });
    if (!quiet) log("→ adb " + args.join(" ") + "\n" + r.out);
    return r.out;
  } catch (e) {
    if (String(e) === "tool-missing") toast(t("adb tidak ditemukan. Coba pasang ulang Djie Cast."));
    return "Error: " + e;
  }
}
const sh = (serial, cmd) => adb(["-s", serial, "shell", cmd], true);
const selDev = () => S.devices.find((d) => d.serial === S.sel);
const ready = () => S.devices.filter((d) => d.state === "device");
const isWireless = (s) => s.includes(":") || s.includes("._adb-tls");
const devName = (d) => (d.model ? d.model.replace(/_/g, " ") : d.serial);

async function refreshDevices() {
  const out = await adb(["devices", "-l"], true);
  const list = [];
  for (const line of out.split(/\r?\n/).slice(1)) {
    const p = line.trim().split(/\s+/);
    if (p.length < 2 || !p[0] || line.startsWith("*")) continue;
    const model = (p.find((x) => x.startsWith("model:")) || "").slice(6);
    list.push({ serial: p[0], state: p[1], model });
  }
  const changed = JSON.stringify(list) !== JSON.stringify(S.devices);
  S.devices = list;
  if (!S.sel || !list.some((d) => d.serial === S.sel && d.state === "device")) {
    const prev = S.sel;
    S.sel = list.find((d) => d.state === "device")?.serial || null;
    if (prev !== S.sel) onSelChange();
  }
  if (changed) renderDevices();
}

function onSelChange() {
  info.data = null;
  files.path = "/sdcard";
  files.items = [];
  files.picked.clear();
  cleaner.reset();
  renderPage();
}

// ---------- Mirror ----------
function castArgs() {
  const s = S.set, a = [];
  if (+s.maxSize > 0) a.push(`--max-size=${s.maxSize}`);
  a.push(`--video-bit-rate=${s.bitrate}M`, `--max-fps=${s.maxFps}`);
  if (!s.audio) a.push("--no-audio");
  if (s.turnScreenOff) a.push("--turn-screen-off");
  if (s.stayAwake) a.push("--stay-awake");
  if (s.alwaysOnTop) a.push("--always-on-top");
  if (s.fullscreen) a.push("--fullscreen");
  if (s.showTouches) a.push("--show-touches");
  if (!s.clipboardSync) a.push("--no-clipboard-autosync");
  if (s.borderless) a.push("--window-borderless");
  if (s.noControl) a.push("--no-control");
  return a;
}

async function startScrcpy(key, serial, args) {
  try {
    await invoke("scrcpy_start", { key, args: ["-s", serial, ...args] });
    S.running.add(key);
    renderDevices();
    return true;
  } catch (e) {
    toast(String(e) === "tool-missing" ? t("scrcpy tidak ditemukan. Coba pasang ulang Djie Cast.") : t("Gagal menjalankan scrcpy: {e}", { e }));
    return false;
  }
}

async function mirror(d) {
  const args = [...castArgs(), `--window-title=${devName(d)}`];
  if (S.set.record) {
    const dir = S.paths.videos;
    await invoke("ensure_dir", { path: dir });
    const sep = dir.includes("\\") ? "\\" : "/";
    // MKV tetap bisa diputar walau jendela ditutup paksa.
    args.push(`--record=${dir}${sep}DjieCast-${await invoke("timestamp")}.mkv`);
  }
  if (await startScrcpy(d.serial, d.serial, args)) toast(t("Membuka layar {n}…", { n: devName(d) }));
}

async function stopKey(key) {
  S.stopping.add(key);
  await invoke("scrcpy_stop", { key });
}

async function camera(d, front) {
  if (S.running.has(d.serial)) { await stopKey(d.serial); await sleep(700); }
  startScrcpy(d.serial, d.serial, [
    "--video-source=camera", `--camera-facing=${front ? "front" : "back"}`, "--max-size=1920", "--camera-fps=30", "--no-audio",
    `--window-title=${front ? t("Kamera depan") : t("Kamera belakang")} — ${devName(d)}`,
  ]);
}

function key(serial, code) { sh(serial, "input keyevent " + code); }

async function screenshotSave(serial) {
  try {
    const r = await invoke("screenshot", { serial, save: true });
    toast(t("Screenshot disimpan: {p}", { p: r.path }));
    opener.revealItemInDir(r.path).catch(() => {});
  } catch { toast(t("Gagal mengambil screenshot")); }
}

function orientation(serial, o) {
  const cmd = {
    portrait: "settings put system accelerometer_rotation 0; settings put system user_rotation 0; cmd window user-rotation lock 0 >/dev/null 2>&1",
    landscape: "settings put system accelerometer_rotation 0; settings put system user_rotation 1; cmd window user-rotation lock 1 >/dev/null 2>&1",
    auto: "cmd window user-rotation free >/dev/null 2>&1; settings put system accelerometer_rotation 1",
  }[o];
  sh(serial, cmd);
}

// ---------- Wi-Fi ----------
function wifiMsg(text, kind = "") {
  $("#wifiMsg").innerHTML = text ? `<div class="note ${kind}">${esc(text)}</div>` : "";
}

function explainConnect(out, target) {
  if (/connected to/.test(out) && !/failed/.test(out)) { wifiMsg(""); return true; }
  if (/refused/i.test(out)) wifiMsg(t("HP menolak koneksi di {t}. Colok USB sekali, pilih ••• → Aktifkan Wi-Fi, lalu coba lagi. HP yang di-restart perlu diaktifkan ulang.", { t: target }), "warn");
  else if (/timed out|No route/i.test(out)) wifiMsg(t("HP tidak menjawab. Pastikan HP dan PC di Wi-Fi yang sama, layar HP menyala, dan alamat IP-nya benar. Bila Windows Firewall bertanya, izinkan adb."), "warn");
  else wifiMsg(out.trim(), "warn");
  return false;
}

async function connectIP(addr) {
  addr = addr.trim();
  if (!addr) return;
  const target = addr.includes(":") ? addr : addr + ":5555";
  $("#ipConnect").disabled = true;
  const out = await adb(["connect", target]);
  $("#ipConnect").disabled = false;
  if (explainConnect(out, target)) { S.set.lastIP = addr; save(); toast(t("Tersambung ke {t}", { t: target })); }
  refreshDevices();
}

async function enableWifi(d) {
  toast(t("Mengaktifkan Wi-Fi di {n}…", { n: devName(d) }));
  const route = await sh(d.serial, "ip route");
  const m = route.match(/\bsrc\s+(\d+\.\d+\.\d+\.\d+)/);
  await adb(["-s", d.serial, "tcpip", "5555"]);
  if (!m) { wifiMsg(t("HP belum tersambung ke Wi-Fi. Sambungkan HP ke Wi-Fi yang sama dengan PC, lalu coba lagi."), "warn"); return; }
  $("#ipInput").value = m[1];
  S.set.lastIP = m[1]; save();
  await sleep(2000);
  const out = await adb(["connect", m[1] + ":5555"]);
  if (explainConnect(out, m[1] + ":5555")) wifiMsg(t("Wi-Fi aktif di {ip}. Kabel USB boleh dicabut.", { ip: m[1] }));
  refreshDevices();
}

async function scanNearby() {
  const out = await adb(["mdns", "services"], true);
  const byIP = {};
  for (const line of out.split(/\r?\n/)) {
    const c = line.trim().split(/\s+/).filter(Boolean);
    if (c.length < 3) continue;
    const hp = c[c.length - 1], i = hp.lastIndexOf(":"), port = +hp.slice(i + 1);
    if (i < 0 || !port) continue;
    const ip = hp.slice(0, i), type = c[1], name = c[0];
    const d = byIP[ip] || (byIP[ip] = { ip, instance: name, connectPort: null, pairPort: null });
    if (type.includes("_adb-tls-pairing")) d.pairPort = port;
    else if (type.includes("_adb-tls-connect")) { d.connectPort = port; d.instance = name; }
    else if (type.includes("_adb._tcp")) { d.connectPort = port; d.instance = name; }
  }
  const list = Object.values(byIP).sort((a, b) => a.ip.localeCompare(b.ip));
  if (JSON.stringify(list) !== JSON.stringify(S.nearby)) { S.nearby = list; renderNearby(); }
}

const nearConnected = (n) => S.devices.some((d) => d.state === "device" && (d.serial.startsWith(n.ip + ":") || d.serial.startsWith(n.instance)));
function nearName(n) {
  const d = S.devices.find((d) => d.serial.startsWith(n.ip + ":") || d.serial.startsWith(n.instance));
  if (d && d.model) return devName(d);
  const p = n.instance.split("-");
  return t("HP Android · {s}", { s: p.length >= 2 && p[0] === "adb" ? p[1] : n.instance });
}

async function connectNearby(n) {
  S.nearbyBusy = n.ip; S.nearbyErr[n.ip] = null; renderNearby();
  const out = await adb(["connect", `${n.ip}:${n.connectPort}`]);
  if (!/connected to/.test(out) || /failed/.test(out))
    S.nearbyErr[n.ip] = t("Belum dipasangkan. Di HP buka Wireless debugging → Pasangkan perangkat dengan kode pairing.");
  S.nearbyBusy = null;
  await refreshDevices();
  renderNearby();
}

async function pairNearby(n, code) {
  S.nearbyBusy = n.ip; S.nearbyErr[n.ip] = null; renderNearby();
  const out = await adb(["pair", `${n.ip}:${n.pairPort}`, code.trim()]);
  S.nearbyBusy = null;
  if (!/successfully paired/i.test(out)) {
    S.nearbyErr[n.ip] = t("Kode salah atau sudah kedaluwarsa. Buka lagi dialog pairing di HP dan coba kode yang baru.");
    renderNearby();
    return;
  }
  toast(t("Berhasil dipasangkan"));
  for (let i = 0; i < 6; i++) {
    await sleep(1000);
    await scanNearby();
    const fresh = S.nearby.find((x) => x.ip === n.ip);
    if (fresh?.connectPort) return connectNearby(fresh);
  }
  renderNearby();
}

// ---------- Render: Perangkat ----------
function renderDevices() {
  const list = $("#devList");
  const n = ready().length;
  $("#readyPill").className = "pill" + (n ? " live" : "");
  $("#readyPill").innerHTML = `<span class="dot ${n ? "on" : ""}"></span>${esc(t("{n} perangkat", { n }))}`;
  $("#navCount").hidden = !n;
  $("#navCount").textContent = n;
  $("#devHint").textContent = S.devices.length ? t("Klik untuk memilih") : "";

  if (!S.devices.length) {
    list.innerHTML = `<div class="empty">${icon("phone")}<b>${esc(t("Belum ada HP tersambung"))}</b>
      <ol class="steps">
        <li>${esc(t("Di HP: Pengaturan → Tentang ponsel → ketuk Nomor build 7 kali."))}</li>
        <li>${esc(t("Buka Opsi developer → nyalakan USB debugging."))}</li>
        <li>${esc(t("Colok HP ke PC dengan kabel USB, lalu ketuk Izinkan di HP."))}</li>
      </ol></div>`;
  } else {
    list.innerHTML = S.devices.map((d) => {
      const ok = d.state === "device", run = S.running.has(d.serial);
      const kind = isWireless(d.serial) ? "Wi-Fi" : "USB";
      const state = ok ? "" : d.state === "unauthorized" ? t("Menunggu izin di HP") : d.state === "offline" ? t("Offline") : d.state;
      return `<div class="dev ${d.serial === S.sel ? "on" : ""}" data-serial="${esc(d.serial)}">
        <div class="phone">${icon(kind === "USB" ? "usb" : "wifi")}</div>
        <div class="meta"><b>${esc(devName(d))}</b><span class="selectable">${esc(d.serial)} · ${kind}</span></div>
        <div class="acts">
          ${state ? `<span class="pill warn">${esc(state)}</span>` : ""}
          ${run ? `<span class="pill live"><span class="dot on"></span>${esc(t("Tampil"))}</span>` : ""}
          ${ok ? (run
            ? `<button class="btn" data-act="stop">${icon("stop")}${esc(t("Berhenti"))}</button>`
            : `<button class="btn primary" data-act="mirror">${icon("play")}${esc(t("Mirror"))}</button>`) : ""}
          ${ok ? `<button class="btn icon" data-act="cam" title="${esc(t("Kamera HP"))}">${icon("camera")}</button>` : ""}
          <button class="btn icon" data-act="more">${icon("more")}</button>
        </div></div>`;
    }).join("");
  }
  const un = S.devices.some((d) => d.state === "unauthorized");
  $("#devNote").innerHTML = un ? `<div class="note warn">${esc(t("Buka kunci HP dan ketuk Izinkan pada dialog \"Izinkan USB debugging?\". Centang \"Selalu izinkan dari komputer ini\" agar tidak ditanya lagi."))}</div>` : "";

  const d = selDev();
  $("#controlCard").hidden = !d;
  if (d) {
    $("#controlFor").textContent = devName(d);
    const keys = [["back", "KEYCODE_BACK", "Kembali"], ["home", "KEYCODE_HOME", "Beranda"], ["recents", "KEYCODE_APP_SWITCH", "Aplikasi terbaru"],
      ["voldown", "KEYCODE_VOLUME_DOWN", "Volume −"], ["volup", "KEYCODE_VOLUME_UP", "Volume +"], ["mute", "KEYCODE_VOLUME_MUTE", "Bisu"],
      ["power", "KEYCODE_POWER", "Layar nyala/mati"]];
    $("#keys").innerHTML = keys.map(([i, c, l]) => `<button class="btn" data-key="${c}">${icon(i)}${esc(t(l))}</button>`).join("") +
      `<button class="btn" data-act="shot">${icon("image")}${esc(t("Screenshot"))}</button>`;
  }
  renderNearby();
}

function renderNearby() {
  const box = $("#nearby");
  $("#nearbyEmpty").hidden = S.nearby.length > 0;
  box.innerHTML = S.nearby.map((n) => {
    const con = nearConnected(n), busy = S.nearbyBusy === n.ip, err = S.nearbyErr[n.ip];
    let act;
    if (con) act = `<span class="pill live">${icon("check")}${esc(t("Tersambung"))}</span>`;
    else if (busy) act = `<span class="spin"></span>`;
    else if (n.pairPort) act = `<input data-code="${esc(n.ip)}" maxlength="6" placeholder="${esc(t("Kode"))}"><button class="btn primary" data-pair="${esc(n.ip)}">${esc(t("Pasangkan"))}</button>`;
    else act = `<button class="btn primary" data-near="${esc(n.ip)}">${esc(t("Sambungkan"))}</button>`;
    return `<div class="item">${icon("wifi")}<div><b>${esc(nearName(n))}</b><br><span class="muted small">${esc(n.ip)}${n.pairPort && !con ? " · " + esc(t("menunggu kode pairing")) : ""}</span>
      ${err ? `<div class="small" style="color:var(--danger)">${esc(err)}</div>` : ""}</div><div class="spacer"></div>${act}</div>`;
  }).join("");
}

function renderQuality() {
  const s = S.set;
  const cur = PRESETS.find((p) => p.v && p.v[0] == s.maxSize && p.v[1] == s.bitrate && p.v[2] == s.maxFps) || PRESETS[3];
  $("#presets").innerHTML = PRESETS.map((p) => `<button class="${p === cur ? "on" : ""}" data-preset="${p.id}">${esc(t(p.name))}</button>`).join("");
  $("#presetHint").textContent = t(cur.hint);
  $("#maxSize").value = s.maxSize; $("#bitrate").value = s.bitrate; $("#maxFps").value = s.maxFps;
  $("#opts").innerHTML = OPTIONS.map(([k, l]) => `<label class="chk"><input type="checkbox" data-opt="${k}" ${s[k] ? "checked" : ""}>${esc(t(l))}</label>`).join("");
}

function deviceMenu(btn, d) {
  const items = [];
  const ok = d.state === "device";
  if (ok && !isWireless(d.serial)) items.push({ icon: "wifi", label: t("Aktifkan Wi-Fi (cabut kabel)"), run: () => enableWifi(d) });
  if (isWireless(d.serial)) items.push({ icon: "unlink", label: t("Putuskan"), run: async () => { await adb(["disconnect", d.serial]); refreshDevices(); } });
  if (ok) {
    items.push({ icon: "image", label: t("Screenshot"), run: () => screenshotSave(d.serial) });
    items.push("-");
    items.push({ icon: "phone", label: t("Putar ke potret"), run: () => orientation(d.serial, "portrait") });
    items.push({ icon: "rotate", label: t("Putar ke lanskap"), run: () => orientation(d.serial, "landscape") });
    items.push({ icon: "refresh", label: t("Rotasi otomatis"), run: () => orientation(d.serial, "auto") });
    items.push("-");
    items.push({ icon: "info", label: t("Info HP"), run: () => { S.sel = d.serial; onSelChange(); go("info"); } });
    items.push({ icon: "folder", label: t("File"), run: () => { S.sel = d.serial; onSelChange(); go("files"); } });
  }
  if (!items.length) items.push({ icon: "refresh", label: t("Muat ulang"), run: refreshDevices });
  menu(btn, items);
}

function bindDevices() {
  $("#devList").addEventListener("click", (e) => {
    const card = e.target.closest(".dev");
    if (!card) return;
    const d = S.devices.find((x) => x.serial === card.dataset.serial);
    const act = e.target.closest("[data-act]")?.dataset.act;
    if (act === "mirror") mirror(d);
    else if (act === "stop") stopKey(d.serial);
    else if (act === "more") deviceMenu(e.target.closest("button"), d);
    else if (act === "cam") menu(e.target.closest("button"), [
      { icon: "camera", label: t("Kamera belakang"), run: () => camera(d, false) },
      { icon: "camera", label: t("Kamera depan"), run: () => camera(d, true) },
      { icon: "info", label: t("Butuh Android 12 atau lebih baru"), run: () => {} },
    ]);
    if (d.serial !== S.sel && d.state === "device") { S.sel = d.serial; onSelChange(); renderDevices(); }
  });
  $("#keys").addEventListener("click", (e) => {
    const b = e.target.closest("button");
    if (!b || !S.sel) return;
    if (b.dataset.key) key(S.sel, b.dataset.key);
    if (b.dataset.act === "shot") screenshotSave(S.sel);
  });
  $("#presets").addEventListener("click", (e) => {
    const p = PRESETS.find((x) => x.id === e.target.dataset.preset);
    if (!p) return;
    if (p.v) [S.set.maxSize, S.set.bitrate, S.set.maxFps] = p.v;
    save(); renderQuality();
  });
  for (const id of ["maxSize", "bitrate", "maxFps"]) $("#" + id).addEventListener("change", (e) => { S.set[id] = +e.target.value; save(); renderQuality(); });
  $("#opts").addEventListener("change", (e) => {
    const k = e.target.dataset.opt;
    if (!k) return;
    S.set[k] = e.target.checked; save();
    if (k === "record" && e.target.checked) toast(t("Rekaman disimpan di {p}", { p: S.paths.videos }));
  });
  $("#ipInput").value = S.set.lastIP;
  $("#ipConnect").onclick = () => connectIP($("#ipInput").value);
  $("#ipInput").addEventListener("keydown", (e) => { if (e.key === "Enter") connectIP(e.target.value); });
  $("#nearby").addEventListener("click", (e) => {
    const ip = e.target.dataset.near || e.target.dataset.pair;
    const n = S.nearby.find((x) => x.ip === ip);
    if (!n) return;
    if (e.target.dataset.near) connectNearby(n);
    else {
      const code = $(`[data-code="${CSS.escape(ip)}"]`).value;
      if (!/^\d{6}$/.test(code.trim())) { toast(t("Masukkan 6 angka kode pairing dari HP")); return; }
      pairNearby(n, code);
    }
  });
}

// ---------- Info HP ----------
const INFO_SCRIPT = `p(){ echo "$1=$(getprop $2)"; }
p brand ro.product.brand; p manufacturer ro.product.manufacturer; p model ro.product.model
p market ro.product.marketname; p vmarket ro.product.vendor.marketname; p device ro.product.device
p release ro.build.version.release; p sdk ro.build.version.sdk; p display ro.build.display.id
p patch ro.build.version.security_patch; p socm ro.soc.manufacturer; p soc ro.soc.model
p platform ro.board.platform; p abi ro.product.cpu.abi; p bootloader ro.bootloader
p locale persist.sys.locale; p oem ro.boot.verifiedbootstate
echo "cpus=$(cat /sys/devices/system/cpu/possible 2>/dev/null)"
echo "wm=$(wm size 2>/dev/null | tail -1)"; echo "dpi=$(wm density 2>/dev/null | tail -1)"
echo "memtotal=$(grep MemTotal /proc/meminfo | tr -s ' ' | cut -d' ' -f2)"
echo "memavail=$(grep MemAvailable /proc/meminfo | tr -s ' ' | cut -d' ' -f2)"
echo "df=$(df /data 2>/dev/null | tail -1 | tr -s ' ')"
echo "uptime=$(cut -d. -f1 /proc/uptime)"
echo "cycles=$(cat /sys/class/power_supply/battery/cycle_count 2>/dev/null)"
echo "kernel=$(uname -r)"
echo "su=$(command -v su)"
dumpsys battery | sed -n 's/^ *\\([A-Za-z ]*\\): \\(.*\\)$/bat.\\1=\\2/p'`;

const info = { data: null, shot: null, loading: false };

async function loadInfo(force) {
  const d = selDev();
  if (!d || info.loading || (info.data && !force)) return renderInfo();
  info.loading = true; renderInfo();
  const out = await sh(d.serial, INFO_SCRIPT);
  const kv = {};
  for (const line of out.split(/\r?\n/)) {
    const i = line.indexOf("=");
    if (i > 0) { const v = line.slice(i + 1).trim(); if (v) kv[line.slice(0, i).trim()] = v; }
  }
  info.data = kv;
  info.loading = false;
  renderInfo();
  invoke("screenshot", { serial: d.serial, save: false }).then((r) => { info.shot = r.data_url; renderInfo(); }).catch(() => { info.shot = "none"; renderInfo(); });
}

function ring(p, color, title, lines) {
  const r = 30, c = 2 * Math.PI * r, v = Math.max(0, Math.min(1, p || 0));
  return `<div class="ring"><svg viewBox="0 0 74 74"><circle cx="37" cy="37" r="${r}" fill="none" stroke="var(--line)" stroke-width="8"/>
    <circle cx="37" cy="37" r="${r}" fill="none" stroke="${color}" stroke-width="8" stroke-linecap="round" stroke-dasharray="${v * c} ${c}"/></svg>
    <div class="lbl"><b>${esc(title)}</b>${lines.map((l) => `<span>${esc(l)}</span>`).join("")}</div></div>`;
}

function renderInfo() {
  const body = $("#infoBody");
  const d = selDev();
  if (!d) { body.innerHTML = noDevice(); return; }
  if (!info.data) { body.innerHTML = `<div class="card empty"><span class="spin"></span><b>${esc(t("Membaca info HP…"))}</b></div>`; return; }
  const kv = info.data;
  const brand = (kv.manufacturer || kv.brand || "Android").replace(/^\w/, (c) => c.toUpperCase());
  const title = kv.market || kv.vmarket || (kv.model || "Android").replace(/_/g, " ");
  const df = (kv.df || "").split(" ");
  const sTotal = +df[1] * 1024, sUsed = +df[2] * 1024;
  const rTotal = +kv.memtotal * 1024, rAvail = +kv.memavail * 1024;
  const lvl = +kv["bat.level"];
  const health = { 1: "Tidak diketahui", 2: "Baik", 3: "Terlalu panas", 4: "Rusak", 5: "Tegangan berlebih", 6: "Gagal", 7: "Dingin" }[kv["bat.health"]];
  const src = kv["bat.AC powered"] === "true" ? t("adaptor") : kv["bat.USB powered"] === "true" ? "USB" : kv["bat.Wireless powered"] === "true" ? t("nirkabel") : null;
  const st = kv["bat.status"] === "2" ? t("Mengisi daya") + (src ? ` (${src})` : "") : kv["bat.status"] === "5" ? t("Penuh") : t("Tidak mengisi");
  const cores = (() => { const n = +(kv.cpus || "").split("-").pop(); return n >= 0 && kv.cpus ? `${n + 1} core` : "-"; })();
  const soc = [kv.socm, kv.soc].filter(Boolean).join(" ");
  const screen = (kv.wm || "").split(": ").pop() || "-", dpi = (kv.dpi || "").split(": ").pop();
  const specs = [
    ["Versi Android", `Android ${kv.release || "?"} (API ${kv.sdk || "?"})`], ["Build", kv.display], ["Patch keamanan", kv.patch],
    ["Serial", d.serial], ["Model", `${kv.model || "-"} (${kv.device || "-"})`], ["Chipset", soc || kv.platform],
    ["CPU", `${cores} · ${kv.abi || "-"}`], ["RAM", rTotal ? marketing(rTotal, true) : "-"], ["Layar", dpi ? `${screen} · ${dpi} dpi` : screen],
    ["Kernel", kv.kernel], ["Root", kv.su ? t("Ya") : t("Tidak")], ["Aktif sejak", kv.uptime ? uptime(+kv.uptime) : "-"],
    ["Koneksi", isWireless(d.serial) ? "Wi-Fi" : "USB"], ["Verified boot", kv.oem], ["Bootloader", kv.bootloader], ["Bahasa", kv.locale],
  ];
  const bat = [["Status", st], ["Kesehatan", health ? t(health) : "-"]];
  if (kv.cycles) bat.push(["Siklus isi daya", kv.cycles]);
  if (kv["bat.temperature"]) bat.push(["Suhu", (+kv["bat.temperature"] / 10).toFixed(1) + " °C"]);
  if (kv["bat.voltage"]) bat.push(["Tegangan", (+kv["bat.voltage"] / 1000).toFixed(2) + " V"]);
  if (kv["bat.technology"]) bat.push(["Teknologi", kv["bat.technology"]]);
  const specHTML = (rows) => rows.map(([l, v]) => `<div class="spec"><span>${esc(t(l))}</span><b>${esc(v || "-")}</b></div>`).join("");

  body.innerHTML = `
    <div class="card"><div class="shot">
      ${info.shot && info.shot !== "none" ? `<img src="${info.shot}" alt="">` : `<div style="width:180px;height:320px;border-radius:14px;border:1px solid var(--line);display:grid;place-items:center;color:var(--muted)">${info.shot ? icon("phone") : `<span class="spin"></span>`}</div>`}
      <div style="flex:1;min-width:0">
        <div class="hero"><div><h2>${esc(title)}</h2><span class="muted">${esc(brand)} · ${esc(kv.model || "-")}</span></div></div>
        <div class="rings" style="margin:20px 0">
          ${ring(sTotal ? sUsed / sTotal : 0, "#e8a13a", t("Penyimpanan"), sTotal ? [marketing(sTotal), t("{u} terpakai", { u: bytes(sUsed) }), t("{f} kosong", { f: bytes(sTotal - sUsed) })] : ["-"])}
          ${ring(rTotal ? (rTotal - rAvail) / rTotal : 0, "#7b61ff", "RAM", rTotal ? [marketing(rTotal, true), t("{f} tersedia", { f: bytes(rAvail) })] : ["-"])}
          ${ring(lvl / 100, lvl <= 20 ? "var(--danger)" : "var(--live)", t("Baterai"), [isNaN(lvl) ? "-" : lvl + "%", st])}
        </div>
        <div class="row">
          <button class="btn" data-i="shot">${icon("image")}${esc(t("Simpan screenshot"))}</button>
          <button class="btn" data-i="reboot">${icon("refresh")}${esc(t("Restart HP"))}</button>
          <button class="btn danger" data-i="off">${icon("power")}${esc(t("Matikan HP"))}</button>
        </div>
      </div></div></div>
    <div class="grid2">
      <div class="card"><h2>${esc(t("Spesifikasi"))}</h2><div>${specHTML(specs)}</div></div>
      <div class="card"><h2>${esc(t("Baterai"))}</h2><div>${specHTML(bat)}</div></div>
    </div>`;
}

function bindInfo() {
  $("#infoReload").onclick = () => { info.shot = null; loadInfo(true); };
  $("#infoBody").addEventListener("click", async (e) => {
    const a = e.target.closest("[data-i]")?.dataset.i, d = selDev();
    if (!a || !d) return;
    if (a === "shot") screenshotSave(d.serial);
    if (a === "reboot" && await modal({ title: t("Restart {n}?", { n: devName(d) }), ok: t("Restart") })) sh(d.serial, "reboot");
    if (a === "off" && await modal({ title: t("Matikan {n}?", { n: devName(d) }), text: t("HP harus dinyalakan lagi dengan tombol daya."), ok: t("Matikan"), danger: true })) sh(d.serial, "reboot -p");
  });
}

function noDevice() {
  return `<div class="card empty">${icon("phone")}<b>${esc(t("Belum ada HP tersambung"))}</b>${esc(t("Sambungkan HP di halaman Perangkat."))}</div>`;
}

// ---------- Aplikasi ----------
const apps = { list: {}, loading: false, filter: "user", search: "", error: null };
const APP_SIZES = { phone: ["Seperti layar HP", "--new-display"], tall: ["Ponsel ringkas", "--new-display=720x1440/280"], wide: ["Lebar (tablet)", "--new-display=1920x1200/240"] };
const AV_COLORS = ["#0c9a72", "#3b82f6", "#8b5cf6", "#ec4899", "#f59e0b", "#ef4444", "#14b8a6", "#6366f1"];

async function loadApps(force) {
  const d = selDev();
  if (!d || apps.loading || (apps.list[d.serial] && !force)) return renderApps();
  apps.loading = true; apps.error = null; renderApps();
  let out = "";
  try { out = (await invoke("scrcpy_run", { args: ["-s", d.serial, "--list-apps"] })).out; } catch (e) { out = String(e); }
  const list = [];
  for (const raw of out.split(/\r?\n/)) {
    const l = raw.trim();
    if (!(l.startsWith("* ") || l.startsWith("- "))) continue;
    const body = l.slice(2), sp = body.lastIndexOf(" ");
    if (sp < 0) continue;
    const pkg = body.slice(sp + 1), name = body.slice(0, sp).trim();
    if (!pkg.includes(".")) continue;
    list.push({ pkg, name: name || pkg, system: l.startsWith("*") });
  }
  list.sort((a, b) => a.name.localeCompare(b.name));
  apps.list[d.serial] = list;
  if (!list.length) { apps.error = t("Tidak bisa membaca daftar aplikasi. Fitur ini butuh Android 10 atau lebih baru."); log(out); }
  apps.loading = false;
  renderApps();
}

function renderApps() {
  const body = $("#appsBody");
  const d = selDev();
  $("#appFilter").innerHTML = [["user", "Aplikasi saya"], ["system", "Sistem"]].map(([k, l]) => `<button class="${apps.filter === k ? "on" : ""}" data-f="${k}">${esc(t(l))}</button>`).join("");
  if (!d) { body.innerHTML = noDevice(); return; }
  if (apps.loading) { body.innerHTML = `<div class="empty"><span class="spin"></span><b>${esc(t("Membaca daftar aplikasi…"))}</b></div>`; return; }
  if (apps.error) { body.innerHTML = `<div class="note warn">${esc(apps.error)}</div>`; return; }
  const s = apps.search.toLowerCase();
  const list = (apps.list[d.serial] || []).filter((a) => (apps.filter === "system") === a.system && (!s || a.name.toLowerCase().includes(s) || a.pkg.includes(s)));
  if (!list.length) { body.innerHTML = `<div class="empty">${esc(t("Tidak ada aplikasi."))}</div>`; return; }
  body.innerHTML = `<p class="muted small" style="margin-top:0">${esc(t("Buka di jendela: aplikasi tampil di layar virtual terpisah, layar HP tidak ikut berubah. Butuh Android 10+."))}</p><div class="apps">` +
    list.map((a) => {
      const k = d.serial + "|" + a.pkg, open = S.running.has(k);
      const col = AV_COLORS[[...a.pkg].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7) % AV_COLORS.length];
      return `<div class="app"><div class="av" style="background:${col}">${esc(a.name.trim()[0]?.toUpperCase() || "?")}</div>
        <b title="${esc(a.name)}">${esc(a.name)}</b><small title="${esc(a.pkg)}">${esc(a.pkg)}</small>
        <div class="row">${open ? `<button class="btn" data-close="${esc(a.pkg)}">${esc(t("Tutup"))}</button>` : `<button class="btn primary" data-open="${esc(a.pkg)}">${icon("window")}${esc(t("Buka"))}</button>`}
        ${a.system ? "" : `<button class="btn icon danger" data-del="${esc(a.pkg)}" title="${esc(t("Hapus aplikasi"))}">${icon("trash")}</button>`}</div></div>`;
    }).join("") + "</div>";
}

async function installFiles(serial, paths) {
  for (const p of paths) {
    const name = baseName(p);
    if (/\.apk$/i.test(name)) {
      toast(t("Memasang {n}…", { n: name }), 60000);
      const out = await adb(["-s", serial, "install", "-r", p]);
      toast(/Success/.test(out) ? t("{n} terpasang", { n: name }) : t("Gagal memasang {n}: {e}", { n: name, e: out.trim().split("\n").pop() }), 6000);
    } else {
      toast(t("Mengirim {n}…", { n: name }), 60000);
      const dest = "/sdcard/Download/" + name;
      const out = await adb(["-s", serial, "push", p, dest]);
      sh(serial, `am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d ${q("file://" + dest)} >/dev/null`);
      toast(/error|failed/i.test(out) ? t("Gagal mengirim {n}", { n: name }) : t("{n} dikirim ke Download di HP", { n: name }), 5000);
    }
  }
}

function bindApps() {
  $("#appSearch").placeholder = t("Cari aplikasi…");
  $("#appSearch").addEventListener("input", (e) => { apps.search = e.target.value; renderApps(); });
  $("#appFilter").addEventListener("click", (e) => { if (e.target.dataset.f) { apps.filter = e.target.dataset.f; renderApps(); } });
  $("#appReload").onclick = () => loadApps(true);
  $("#appSize").addEventListener("change", (e) => { S.set.appSize = e.target.value; save(); });
  $("#installApk").onclick = async () => {
    const d = selDev();
    if (!d) return toast(t("Belum ada HP tersambung"));
    const picked = await dialog.open({ multiple: true, filters: [{ name: "APK", extensions: ["apk"] }] });
    if (!picked) return;
    await installFiles(d.serial, [].concat(picked));
    loadApps(true);
  };
  $("#appsBody").addEventListener("click", async (e) => {
    const d = selDev(), b = e.target.closest("button");
    if (!d || !b) return;
    const list = apps.list[d.serial] || [];
    if (b.dataset.open) {
      const a = list.find((x) => x.pkg === b.dataset.open);
      const ok = await startScrcpy(d.serial + "|" + a.pkg, d.serial, [APP_SIZES[S.set.appSize]?.[1] || "--new-display", `--start-app=${a.pkg}`, "--no-audio",
        "--no-vd-destroy-content", "--video-bit-rate=8M", "--max-fps=60", `--window-title=${a.name} — ${devName(d)}`]);
      if (ok) renderApps();
    }
    if (b.dataset.close) stopKey(d.serial + "|" + b.dataset.close);
    if (b.dataset.del) {
      const a = list.find((x) => x.pkg === b.dataset.del);
      if (!(await modal({ title: t("Hapus {n}?", { n: a.name }), text: t("Aplikasi dan datanya akan dihapus dari HP."), ok: t("Hapus"), danger: true }))) return;
      const out = await adb(["-s", d.serial, "uninstall", a.pkg]);
      toast(/Success/.test(out) ? t("{n} dihapus", { n: a.name }) : t("Gagal menghapus: {e}", { e: out.trim() }));
      loadApps(true);
    }
  });
}

// ---------- File ----------
const files = { path: "/sdcard", items: [], picked: new Set(), loading: false, err: null, last: null };
const QUICK = [["Penyimpanan", "/sdcard"], ["Download", "/sdcard/Download"], ["Kamera", "/sdcard/DCIM/Camera"], ["Gambar", "/sdcard/Pictures"],
  ["Dokumen", "/sdcard/Documents"], ["Musik", "/sdcard/Music"], ["Video", "/sdcard/Movies"], ["WhatsApp", "/sdcard/Android/media/com.whatsapp/WhatsApp/Media"]];

async function loadFiles() {
  const d = selDev();
  if (!d) return renderFiles();
  files.loading = true; files.err = null; renderFiles();
  const path = files.path;
  const out = await sh(d.serial, `ls -lA ${q(path.endsWith("/") ? path : path + "/")}`);
  if (path !== files.path) return;
  const re = /^([\-dlcbps][rwxsStT\-]{9}\S*)\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s(.+)$/;
  const list = [];
  for (const raw of out.split(/\r?\n/)) {
    const m = raw.trim().match(re);
    if (!m) continue;
    let name = m[4];
    const link = m[1][0] === "l";
    if (link && name.includes(" -> ")) name = name.split(" -> ")[0];
    list.push({ name, path: (path === "/" ? "" : path.replace(/\/$/, "")) + "/" + name, dir: m[1][0] === "d" || link, size: +m[2], mod: m[3] });
  }
  list.sort((a, b) => (a.dir !== b.dir ? (a.dir ? -1 : 1) : a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" })));
  files.items = list;
  files.picked.clear();
  if (!list.length && /denied|No such|error/i.test(out)) files.err = out.trim();
  files.loading = false;
  renderFiles();
}

function goPath(p) { files.path = p || "/"; loadFiles(); }

function renderFiles() {
  const d = selDev();
  $("#quick").innerHTML = QUICK.map(([l, p]) => `<button class="btn ${files.path === p ? "primary" : ""}" data-q="${esc(p)}">${esc(t(l))}</button>`).join("");
  const parts = files.path.split("/").filter(Boolean);
  $("#crumbs").innerHTML = `<a data-c="/">/</a>` + parts.map((p, i) => `<a data-c="${esc("/" + parts.slice(0, i + 1).join("/"))}">${esc(p)}</a>`).join("<span class=muted>›</span>");
  const n = files.picked.size;
  $("#fDownload").disabled = !n; $("#fDelete").disabled = !n; $("#fRename").disabled = n !== 1;
  $("#fUpload").disabled = !d;
  const body = $("#filesBody");
  if (!d) { body.innerHTML = noDevice(); return; }
  if (files.loading) { body.innerHTML = `<div class="empty"><span class="spin"></span></div>`; return; }
  if (files.err) { body.innerHTML = `<div class="note err" style="margin:10px">${esc(files.err)}</div>`; return; }
  if (!files.items.length) { body.innerHTML = `<div class="empty">${esc(t("Folder kosong"))}</div>`; return; }
  body.innerHTML = `<table><thead><tr><th>${esc(t("Nama"))}</th><th style="text-align:right">${esc(t("Ukuran"))}</th><th style="text-align:right">${esc(t("Diubah"))}</th></tr></thead><tbody>` +
    files.items.map((f, i) => `<tr class="clickable ${files.picked.has(f.path) ? "sel" : ""}" data-i="${i}">
      <td><span class="fi ${f.dir ? "dir" : ""}">${icon(f.dir ? "folder" : "file")}${esc(f.name)}</span></td>
      <td class="num">${f.dir ? "" : bytes(f.size)}</td><td class="num">${esc(f.mod)}</td></tr>`).join("") + "</tbody></table>";
  $("#fStatus").textContent = n ? t("{n} dipilih", { n }) : t("{n} item · klik dua kali untuk membuka", { n: files.items.length });
}

async function openRemote(f) {
  const d = selDev();
  const dir = S.paths.temp;
  await invoke("ensure_dir", { path: dir });
  const sep = dir.includes("\\") ? "\\" : "/";
  const local = dir + sep + f.name;
  toast(t("Membuka {n}…", { n: f.name }));
  await adb(["-s", d.serial, "pull", f.path, local]);
  opener.openPath(local).catch((e) => toast(String(e)));
}

function bindFiles() {
  $("#quick").addEventListener("click", (e) => { if (e.target.dataset.q) goPath(e.target.dataset.q); });
  $("#crumbs").addEventListener("click", (e) => { if (e.target.dataset.c) goPath(e.target.dataset.c); });
  $("#fUp").onclick = () => goPath(files.path.replace(/\/[^/]+\/?$/, "") || "/");
  $("#fReload").onclick = loadFiles;
  $("#filesBody").addEventListener("click", (e) => {
    const tr = e.target.closest("tr[data-i]");
    if (!tr) return;
    const f = files.items[+tr.dataset.i];
    if (e.ctrlKey || e.metaKey) files.picked.has(f.path) ? files.picked.delete(f.path) : files.picked.add(f.path);
    else if (e.shiftKey && files.last != null) {
      const [a, b] = [files.last, +tr.dataset.i].sort((x, y) => x - y);
      files.items.slice(a, b + 1).forEach((x) => files.picked.add(x.path));
    } else { files.picked.clear(); files.picked.add(f.path); }
    files.last = +tr.dataset.i;
    renderFiles();
  });
  $("#filesBody").addEventListener("dblclick", (e) => {
    const tr = e.target.closest("tr[data-i]");
    if (!tr) return;
    const f = files.items[+tr.dataset.i];
    f.dir ? goPath(f.path) : openRemote(f);
  });
  $("#fDownload").onclick = async () => {
    const d = selDev();
    const dest = await dialog.open({ directory: true, defaultPath: S.paths.downloads, title: t("Simpan ke folder") });
    if (!dest) return;
    const sel = files.items.filter((f) => files.picked.has(f.path));
    for (const [i, f] of sel.entries()) {
      $("#fStatus").textContent = t("Menyalin {n} ({i}/{c})…", { n: f.name, i: i + 1, c: sel.length });
      await adb(["-s", d.serial, "pull", f.path, dest]);
    }
    toast(t("{n} item disalin ke {p}", { n: sel.length, p: dest }));
    opener.openPath(dest).catch(() => {});
    renderFiles();
  };
  $("#fUpload").onclick = async () => {
    const d = selDev();
    const picked = await dialog.open({ multiple: true, title: t("Kirim ke HP") });
    if (!picked) return;
    for (const p of [].concat(picked)) {
      $("#fStatus").textContent = t("Mengirim {n}…", { n: baseName(p) });
      await adb(["-s", d.serial, "push", p, files.path.replace(/\/?$/, "/")]);
    }
    loadFiles();
  };
  $("#fNew").onclick = async () => {
    const name = await modal({ title: t("Folder baru"), input: t("Folder baru"), ok: t("Buat") });
    if (!name?.trim()) return;
    await sh(S.sel, `mkdir -p ${q(files.path.replace(/\/$/, "") + "/" + name.trim().replace(/\//g, "_"))}`);
    loadFiles();
  };
  $("#fRename").onclick = async () => {
    const f = files.items.find((x) => files.picked.has(x.path));
    const name = await modal({ title: t("Ganti nama"), input: f.name, ok: t("Simpan") });
    if (!name?.trim() || name === f.name) return;
    await sh(S.sel, `mv ${q(f.path)} ${q(f.path.replace(/[^/]+$/, "") + name.trim().replace(/\//g, "_"))}`);
    loadFiles();
  };
  $("#fDelete").onclick = async () => {
    const sel = files.items.filter((f) => files.picked.has(f.path));
    const ok = await modal({ title: sel.length === 1 ? t("Hapus {n}?", { n: sel[0].name }) : t("Hapus {n} item?", { n: sel.length }),
      text: t("File dihapus permanen dari HP."), ok: t("Hapus"), danger: true });
    if (!ok) return;
    await sh(S.sel, "rm -rf " + sel.map((f) => q(f.path)).join(" "));
    loadFiles();
  };
  // Seret file dari Explorer ke jendela: kirim ke folder yang sedang dibuka (atau pasang APK).
  TAURI.webviewWindow?.getCurrentWebviewWindow?.().onDragDropEvent?.((ev) => {
    if (ev.payload.type !== "drop" || !S.sel) return;
    const paths = ev.payload.paths || [];
    if (S.page === "files") {
      (async () => {
        for (const p of paths) { $("#fStatus").textContent = t("Mengirim {n}…", { n: baseName(p) }); await adb(["-s", S.sel, "push", p, files.path.replace(/\/?$/, "/")]); }
        loadFiles();
      })();
    } else installFiles(S.sel, paths);
  });
}

// ---------- Pembersih ----------
const STANDARD = new Set(["Alarms", "Audiobooks", "DCIM", "Documents", "Download", "Movies", "Music", "Notifications", "Pictures", "Podcasts", "Recordings", "Ringtones"]);
const cleaner = {
  phase: "idle", groups: [], big: [], pickedBig: new Set(), status: "", freed: 0,
  reset() { this.phase = "idle"; this.groups = []; this.big = []; this.pickedBig = new Set(); this.status = ""; },
};

function sizes(out, kb) {
  let total = 0; const paths = [];
  for (const l of out.split(/\r?\n/)) {
    const m = l.match(/^\s*(\d+)\s+(.+)$/);
    if (!m) continue;
    total += kb ? +m[1] * 1024 : +m[1];
    paths.push(m[2].trim());
  }
  return [total, paths];
}

async function freeKB(serial) {
  const c = (await sh(serial, "df -k /data | tail -1")).trim().split(/\s+/);
  return c.length >= 4 ? +c[3] || 0 : 0;
}

async function scanJunk() {
  const d = selDev();
  if (!d) return;
  const s = d.serial;
  cleaner.reset(); cleaner.phase = "scanning";
  const root = "/storage/emulated/0", skip = `-path ${root}/Android -prune -o`;
  const step = (m) => { cleaner.status = t(m); renderCleaner(); };
  step("Memeriksa cache aplikasi…");
  const [extB, extP] = sizes(await sh(s, "du -sk /sdcard/Android/data/*/cache 2>/dev/null | awk '$1>0'"), true);
  step("Mencari file APK sisa instalasi…");
  const [apkB, apkP] = sizes(await sh(s, `find ${root} ${skip} -type f -iname '*.apk' -exec stat -c '%s %n' {} + 2>/dev/null`), false);
  step("Memeriksa cache thumbnail…");
  const [thB, thP] = sizes(await sh(s, `find ${root} ${skip} -type d -name .thumbnails -exec du -sk {} + 2>/dev/null`), true);
  step("Mencari file sementara & log…");
  const [tmpB, tmpP] = sizes(await sh(s, `find ${root} ${skip} -type f \\( -iname '*.tmp' -o -iname '*.temp' -o -iname '*.log' -o -iname '*.bak' \\) -exec stat -c '%s %n' {} + 2>/dev/null`), false);
  const empty = (await sh(s, `find ${root} ${skip} -mindepth 1 -type d -empty -print 2>/dev/null`)).split(/\r?\n/).map((x) => x.trim())
    .filter((p) => p && !p.includes("/.") && !STANDARD.has(p.replace(root + "/", "")));
  step("Mencari file besar…");
  const big = await sh(s, `find ${root} ${skip} -type f -size +50M -exec stat -c '%s %n' {} + 2>/dev/null | sort -rn | head -20`);
  cleaner.big = big.split(/\r?\n/).map((l) => l.trim().match(/^(\d+)\s+(.+)$/)).filter(Boolean)
    .map((m) => ({ bytes: +m[1], path: m[2] })).filter((f) => !/\.apk$/i.test(f.path));
  const apkNames = apkP.slice(0, 3).map(baseName).join(", ") + (apkP.length > 3 ? " …" : "");
  cleaner.groups = [
    { id: "sys", title: "Cache semua aplikasi", detail: "Data sementara yang disimpan aplikasi. Aman dihapus; aplikasi membuatnya lagi bila perlu.", bytes: -1, paths: [], sel: true },
    { id: "ext", title: "Cache aplikasi di penyimpanan", detail: "Folder cache aplikasi di penyimpanan internal (gambar, video sementara).", bytes: extB, paths: extP, sel: true },
    { id: "apk", title: "File APK sisa instalasi", detail: apkNames, raw: true, bytes: apkB, paths: apkP, sel: true },
    { id: "thumb", title: "Cache thumbnail", detail: "Gambar kecil pratinjau galeri. Dibuat ulang otomatis.", bytes: thB, paths: thP, sel: true },
    { id: "tmp", title: "File sementara & log", detail: "File .tmp, .log, dan .bak yang tertinggal.", bytes: tmpB, paths: tmpP, sel: true },
    { id: "empty", title: "Folder kosong tersisa", detail: "Folder tanpa isi yang tertinggal dari aplikasi yang sudah dihapus.", bytes: 0, paths: empty, sel: true },
  ].filter((g) => g.id === "sys" || g.paths.length);
  cleaner.status = ""; cleaner.phase = "ready";
  renderCleaner();
}

async function cleanJunk() {
  const s = S.sel;
  cleaner.phase = "cleaning";
  const before = await freeKB(s);
  for (const g of cleaner.groups.filter((g) => g.sel)) {
    cleaner.status = t("Membersihkan {g}…", { g: t(g.title) }); renderCleaner();
    if (g.id === "sys") await sh(s, "pm trim-caches 9999G");
    else if (g.id === "ext" || g.id === "thumb") for (const c of chunk(g.paths, 30)) await sh(s, c.map((p) => `rm -rf ${q(p)}/* ${q(p)}/.[!.]* 2>/dev/null`).join("; "));
    else if (g.id === "empty") for (const c of chunk(g.paths, 40)) await sh(s, "rmdir " + c.map(q).join(" ") + " 2>/dev/null");
    else for (const c of chunk(g.paths, 40)) await sh(s, "rm -f " + c.map(q).join(" "));
  }
  const big = cleaner.big.filter((f) => cleaner.pickedBig.has(f.path)).map((f) => f.path);
  if (big.length) {
    cleaner.status = t("Menghapus file besar yang dipilih…"); renderCleaner();
    for (const c of chunk(big, 20)) await sh(s, "rm -f " + c.map(q).join(" "));
  }
  await sh(s, "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard >/dev/null 2>&1");
  cleaner.freed = Math.max(0, ((await freeKB(s)) - before) * 1024);
  cleaner.status = ""; cleaner.phase = "done";
  renderCleaner();
}

function renderCleaner() {
  const body = $("#cleanBody");
  const d = selDev();
  if (!d) { body.innerHTML = noDevice(); return; }
  const c = cleaner;
  if (c.phase === "idle") {
    body.innerHTML = `<div class="card empty">${icon("sparkle")}<b>${esc(t("Periksa sampah di {n}", { n: devName(d) }))}</b>
      <p>${esc(t("Pemindaian hanya membaca. Tidak ada yang dihapus sebelum kamu menekan Bersihkan."))}</p>
      <button class="btn primary big" data-c="scan">${esc(t("Mulai pindai"))}</button></div>`;
    return;
  }
  if (c.phase === "scanning" || c.phase === "cleaning") {
    body.innerHTML = `<div class="card empty"><span class="spin" style="width:30px;height:30px"></span><b>${esc(c.status)}</b></div>`;
    return;
  }
  if (c.phase === "done") {
    body.innerHTML = `<div class="card empty">${icon("check")}<b>${esc(t("Selesai!"))}</b>
      <div class="bigtotal">${bytes(c.freed)}</div><p>${esc(t("ruang kosong bertambah di HP"))}</p>
      <button class="btn" data-c="scan">${esc(t("Pindai lagi"))}</button></div>`;
    return;
  }
  const total = c.groups.filter((g) => g.sel && g.bytes > 0).reduce((a, g) => a + g.bytes, 0) + c.big.filter((f) => c.pickedBig.has(f.path)).reduce((a, f) => a + f.bytes, 0);
  body.innerHTML = `
    <div class="card"><div class="row"><div><span class="muted">${esc(t("Bisa dibersihkan"))}</span><div class="bigtotal">${bytes(total)}${c.groups.some((g) => g.sel && g.id === "sys") ? " +" : ""}</div></div>
      <div class="spacer"></div><button class="btn" data-c="scan">${esc(t("Pindai lagi"))}</button>
      <button class="btn primary big" data-c="clean" ${c.groups.some((g) => g.sel) || c.pickedBig.size ? "" : "disabled"}>${esc(t("Bersihkan"))}</button></div></div>
    <div class="card">${c.groups.map((g, i) => `<label class="junk"><input type="checkbox" data-g="${i}" ${g.sel ? "checked" : ""}>
      <div class="t"><b>${esc(t(g.title))}${g.paths.length ? ` <span class="muted small">· ${esc(t("{n} item", { n: g.paths.length }))}</span>` : ""}</b><span>${esc(g.raw ? g.detail : t(g.detail))}</span></div>
      <span class="sz">${g.bytes < 0 ? esc(t("dihitung saat dibersihkan")) : g.bytes ? bytes(g.bytes) : ""}</span></label>`).join("")}</div>
    ${c.big.length ? `<div class="card"><h2>${esc(t("File besar"))}<span class="sub">${esc(t("Pilih sendiri yang mau dihapus"))}</span></h2>
      ${c.big.map((f, i) => `<label class="junk"><input type="checkbox" data-b="${i}" ${c.pickedBig.has(f.path) ? "checked" : ""}>
        <div class="t"><b>${esc(baseName(f.path))}</b><span class="selectable">${esc(f.path.replace("/storage/emulated/0", ""))}</span></div><span class="sz">${bytes(f.bytes)}</span></label>`).join("")}</div>` : ""}`;
}

function bindCleaner() {
  $("#cleanBody").addEventListener("click", async (e) => {
    const a = e.target.closest("[data-c]")?.dataset.c;
    if (a === "scan") scanJunk();
    if (a === "clean") {
      const d = selDev();
      if (await modal({ title: t("Bersihkan {n}?", { n: devName(d) }), text: t("File yang dipilih dihapus permanen dari HP."), ok: t("Bersihkan"), danger: true })) cleanJunk();
    }
  });
  $("#cleanBody").addEventListener("change", (e) => {
    if (e.target.dataset.g) cleaner.groups[+e.target.dataset.g].sel = e.target.checked;
    if (e.target.dataset.b) { const f = cleaner.big[+e.target.dataset.b]; e.target.checked ? cleaner.pickedBig.add(f.path) : cleaner.pickedBig.delete(f.path); }
    renderCleaner();
  });
}

// ---------- Navigasi ----------
function go(page) {
  S.page = page;
  $$("nav.side a").forEach((a) => a.classList.toggle("on", a.dataset.page === page));
  $$(".page").forEach((p) => p.classList.toggle("on", p.id === "page-" + page));
  renderPage();
}

function renderPage() {
  switch (S.page) {
    case "devices": renderDevices(); renderQuality(); break;
    case "info": loadInfo(); break;
    case "apps": renderApps(); loadApps(); break;
    case "files": if (!files.items.length && !files.loading) loadFiles(); else renderFiles(); break;
    case "cleaner": renderCleaner(); break;
    case "log": log(""); $("#log").scrollTop = 1e9; break;
  }
}

function applyStatic() {
  document.documentElement.lang = LANG;
  $$("[data-t]").forEach((el) => {
    if (!el.dataset.src) el.dataset.src = el.textContent.trim();
    el.textContent = t(el.dataset.src);
  });
  $$("[data-icon]").forEach((el) => { el.innerHTML = icon(el.dataset.icon); });
  $("#appSize").innerHTML = Object.entries(APP_SIZES).map(([k, [l]]) => `<option value="${k}" ${S.set.appSize === k ? "selected" : ""}>${esc(t(l))}</option>`).join("");
  $("#maxSize option[value='0']").textContent = t("Asli");
  $("#appSearch").placeholder = t("Cari aplikasi…");
}

// ---------- Mulai ----------
(async function init() {
  setLang(S.set.lang || (navigator.language || "id").slice(0, 2));
  $("#lang").value = LANG;
  $("#lang").onchange = (e) => { S.set.lang = e.target.value; save(); setLang(e.target.value); applyStatic(); renderPage(); };
  applyStatic();
  $$("nav.side a").forEach((a) => (a.onclick = () => go(a.dataset.page)));
  bindDevices(); bindInfo(); bindApps(); bindFiles(); bindCleaner();
  $("#logClear").onclick = () => { logText = ""; log(""); };
  $("#logCopy").onclick = () => navigator.clipboard.writeText(logText).then(() => toast(t("Log disalin")));
  $("#openSite").onclick = () => opener.openUrl("https://masadjie.github.io/djie-cast/");

  S.tools = await invoke("tools_info");
  S.paths = await invoke("paths");
  const ver = (await TAURI.app?.getVersion?.()) || "1.0";
  $("#verLine").textContent = `v${ver} · scrcpy ${S.tools.version}`;
  $("#aboutVer").textContent = t("Versi {v} untuk Windows", { v: ver });
  $("#aboutTools").textContent = `scrcpy ${S.tools.version} · adb: ${S.tools.adb || t("tidak ditemukan")}`;
  if (!S.tools.adb || !S.tools.scrcpy) log("❌ adb/scrcpy tidak ditemukan\n");

  await listen("log", (e) => log(e.payload));
  await listen("scrcpy-exit", (e) => {
    const { key: k, code } = e.payload;
    S.running.delete(k);
    const asked = S.stopping.delete(k);
    if (!asked && code !== 0) {
      toast(k.includes("|")
        ? t("Aplikasi tidak bisa dibuka di jendela terpisah. Fitur ini butuh Android 10 atau lebih baru; lihat Log untuk detail.")
        : t("Mirror berhenti (kode {c}). Lihat Log untuk detail.", { c: code }), 6000);
    }
    renderDevices();
    if (S.page === "apps") renderApps();
  });

  go("devices");
  await refreshDevices();
  setInterval(refreshDevices, 2500);
  setInterval(() => { if (S.page === "devices" && !document.hidden) scanNearby(); }, 4000);
  scanNearby();
})();
