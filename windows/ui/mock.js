/* Data demo bila UI dibuka di browser biasa (tanpa Tauri) — untuk melihat tampilan saja. */
"use strict";
if (!window.__TAURI__) {
  const running = new Set();
  const handlers = {};
  const out = (s) => ({ code: 0, out: s });
  const shell = (cmd) => {
    if (cmd.includes("getprop")) return ["brand=samsung", "manufacturer=samsung", "model=SM-S928B", "market=Galaxy S24 Ultra", "device=e3q",
      "release=15", "sdk=35", "display=AP3A.240905.015", "patch=2026-10-01", "socm=Qualcomm", "soc=SM8650", "abi=arm64-v8a",
      "bootloader=S928BXXS4AXJ1", "locale=id-ID", "oem=green", "cpus=0-7", "wm=Physical size: 1440x3120", "dpi=Physical density: 600",
      "memtotal=11534336", "memavail=4718592", "df=/dev/block/dm-48 242791600 151231944 91559656 63% /data", "uptime=273600",
      "kernel=6.1.75-android14", "su=", "bat.level=78", "bat.health=2", "bat.status=2", "bat.USB powered=true", "bat.temperature=312",
      "bat.voltage=4120", "bat.technology=Li-ion"].join("\n");
    if (cmd.startsWith("ls -lA")) return ["drwxrwx--x 2 root sdcard_rw 3452 2026-11-18 09:12 Alarms", "drwxrwx--x 5 root sdcard_rw 3452 2026-11-19 20:41 DCIM",
      "drwxrwx--x 2 root sdcard_rw 3452 2026-11-20 08:03 Download", "drwxrwx--x 4 root sdcard_rw 3452 2026-11-12 11:30 Pictures",
      "drwxrwx--x 2 root sdcard_rw 3452 2026-10-02 07:55 Documents", "-rw-rw---- 1 root sdcard_rw 2481934 2026-11-20 08:01 laporan-november.pdf",
      "-rw-rw---- 1 root sdcard_rw 184223 2026-11-19 16:22 catatan.txt"].join("\n");
    if (cmd.includes("du -sk /sdcard/Android/data")) return "182340 /sdcard/Android/data/com.instagram.android/cache\n96210 /sdcard/Android/data/com.zhiliaoapp.musically/cache";
    if (cmd.includes("*.apk")) return "48211033 /storage/emulated/0/Download/app-release.apk";
    if (cmd.includes("-size +50M")) return "1288490188 /storage/emulated/0/Movies/rekaman-layar.mp4\n734003200 /storage/emulated/0/Download/film.mkv";
    if (cmd.includes("-empty")) return "/storage/emulated/0/Tencent\n/storage/emulated/0/Oppo";
    if (cmd.includes("df -k")) return "/dev/block/dm-48 242791600 151231944 91559656 63% /data";
    return "";
  };
  window.__DJIE_MOCK__ = {
    core: {
      async invoke(cmd, a = {}) {
        await new Promise((r) => setTimeout(r, 120));
        switch (cmd) {
          case "tools_info": return { adb: "C:\\Program Files\\Djie Cast\\scrcpy\\adb.exe", scrcpy: "scrcpy.exe", version: "5.0.1", bundled: true };
          case "paths": return { videos: "C:\\Users\\demo\\Videos\\Djie Cast", pictures: "C:\\Users\\demo\\Pictures\\Djie Cast", downloads: "C:\\Users\\demo\\Downloads", temp: "C:\\Temp" };
          case "timestamp": return "20261120-101500";
          case "ensure_dir": return null;
          case "adb": {
            const g = a.args;
            if (g[0] === "devices") return out("List of devices attached\nR5CT30ABCDE device usb:1-1 product:e3qxxx model:SM_S928B device:e3q transport_id:1\n192.168.1.24:5555 device product:husky model:Pixel_8_Pro device:husky transport_id:2\n9A281FFAZ00 unauthorized usb:1-2 transport_id:3\n");
            if (g[0] === "mdns") return out("List of discovered mdns services\nadb-RFCX20KQ9LM-a1b2c3\t_adb-tls-connect._tcp\t192.168.1.31:41827\nadb-2B151FDH300-k9\t_adb-tls-pairing._tcp\t192.168.1.44:37115\n");
            if (g[2] === "shell") return out(shell(g[3]));
            return out("");
          }
          case "scrcpy_run": return out(["- WhatsApp com.whatsapp", "- Instagram com.instagram.android", "- TikTok com.zhiliaoapp.musically", "- Shopee com.shopee.id",
            "- Gojek com.gojek.app", "- Tokopedia com.tokopedia.tkpd", "- Spotify com.spotify.music", "* YouTube com.google.android.youtube", "* Kamera com.sec.android.app.camera"].join("\n"));
          case "scrcpy_start": running.add(a.key); return null;
          case "scrcpy_stop": running.delete(a.key); setTimeout(() => handlers["scrcpy-exit"]?.({ payload: { key: a.key, code: 1 } }), 200); return null;
          case "screenshot": throw "screenshot-failed";
        }
        return null;
      },
    },
    event: { async listen(name, fn) { handlers[name] = fn; return () => {}; } },
    dialog: { async open() { return null; } },
    opener: { async openPath() {}, async openUrl(u) { window.open(u); }, async revealItemInDir() {} },
  };
}
