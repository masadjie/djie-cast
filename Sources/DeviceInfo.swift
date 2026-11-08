import SwiftUI
import AppKit

// MARK: - Shared device-detail model (Android via adb, iOS via libimobiledevice)

struct SpecRow: Identifiable, Hashable {
    let label: String
    let value: String
    var id: String { label }
}

struct InstalledApp: Identifiable, Hashable {
    let id: String            // package name / bundle id
    let name: String
    let version: String
    let installed: String
    let system: Bool
}

struct DeviceDetail {
    var title = ""                 // e.g. "Galaxy S24 Ultra"
    var subtitle = ""              // e.g. "Samsung · SM-S928B"
    var storagePill = ""           // e.g. "256 GB"
    var specs: [SpecRow] = []
    var batteryLevel: Int?         // 0…100
    var batteryHealth: String?     // "Baik", "100%", …
    var batteryCycles: String?
    var batteryState: String?      // "Mengisi daya (USB)" …
    var batteryExtra: [SpecRow] = []
    var storageTotal: Int64?
    var storageUsed: Int64?
    var ramTotal: Int64?
    var ramAvailable: Int64?
    var status: [SpecRow] = []
}

enum Fmt {
    static func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    static func uptime(_ secs: Int) -> String {
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        return d > 0 ? "\(d) hari \(h) jam" : h > 0 ? "\(h) jam \(m) menit" : "\(m) menit"
    }
}

// MARK: - Android

enum AndroidInspector {
    /// One adb round-trip that prints key=value lines for everything we show.
    static let script = #"""
    p(){ echo "$1=$(getprop $2)"; }
    p brand ro.product.brand; p manufacturer ro.product.manufacturer; p model ro.product.model
    p market ro.product.marketname; p vmarket ro.product.vendor.marketname; p device ro.product.device
    p release ro.build.version.release; p sdk ro.build.version.sdk; p display ro.build.display.id
    p patch ro.build.version.security_patch; p socm ro.soc.manufacturer; p soc ro.soc.model
    p platform ro.board.platform; p abi ro.product.cpu.abi; p bootloader ro.bootloader
    p kernelver ro.kernel.version; p locale persist.sys.locale; p oem ro.boot.verifiedbootstate
    echo "cpus=$(cat /sys/devices/system/cpu/possible 2>/dev/null)"
    echo "wm=$(wm size 2>/dev/null | tail -1)"; echo "dpi=$(wm density 2>/dev/null | tail -1)"
    echo "memtotal=$(grep MemTotal /proc/meminfo | tr -s ' ' | cut -d' ' -f2)"
    echo "memavail=$(grep MemAvailable /proc/meminfo | tr -s ' ' | cut -d' ' -f2)"
    echo "df=$(df /data 2>/dev/null | tail -1 | tr -s ' ')"
    echo "uptime=$(cut -d. -f1 /proc/uptime)"
    echo "cycles=$(cat /sys/class/power_supply/battery/cycle_count 2>/dev/null)"
    echo "kernel=$(uname -r)"
    echo "su=$(command -v su)"
    dumpsys battery | sed -n 's/^ *\([A-Za-z ]*\): \(.*\)$/bat.\1=\2/p'
    """#

    static func load(serial: String) async -> DeviceDetail {
        guard let adb = Tools.adb else { return DeviceDetail(title: "adb tidak ditemukan") }
        let out = await Tools.run(adb, ["-s", serial, "shell", script])
        var kv: [String: String] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[1].isEmpty { kv[parts[0]] = parts[1] }
        }
        var d = DeviceDetail()
        let brand = (kv["manufacturer"] ?? kv["brand"] ?? "Android").capitalized
        let market = kv["market"] ?? kv["vmarket"]
        d.title = market ?? (kv["model"] ?? "Android").replacingOccurrences(of: "_", with: " ")
        d.subtitle = "\(brand) · \(kv["model"] ?? "-")"

        // storage: df /data → "<fs> <1K-blocks> <used> <avail> <use%> <mount>"
        let df = (kv["df"] ?? "").split(separator: " ")
        if df.count >= 4, let total = Int64(df[1]), let used = Int64(df[2]) {
            d.storageTotal = total * 1024; d.storageUsed = used * 1024
            d.storagePill = marketingSize(total * 1024)
        }
        if let t = Int64(kv["memtotal"] ?? "") { d.ramTotal = t * 1024 }
        if let a = Int64(kv["memavail"] ?? "") { d.ramAvailable = a * 1024 }

        let cores: String = {
            guard let r = kv["cpus"], let last = r.split(separator: "-").last, let n = Int(last) else { return "-" }
            return "\(n + 1) core"
        }()
        let soc = [kv["socm"], kv["soc"]].compactMap { $0 }.joined(separator: " ")
        let screen = (kv["wm"] ?? "").components(separatedBy: ": ").last ?? "-"
        let dpi = (kv["dpi"] ?? "").components(separatedBy: ": ").last ?? ""
        d.specs = [
            SpecRow(label: "Versi Android", value: "Android \(kv["release"] ?? "?") (API \(kv["sdk"] ?? "?"))"),
            SpecRow(label: "Build", value: kv["display"] ?? "-"),
            SpecRow(label: "Patch keamanan", value: kv["patch"] ?? "-"),
            SpecRow(label: "Serial", value: serial.contains(":") ? "\(serial) (Wi-Fi)" : serial),
            SpecRow(label: "Model", value: "\(kv["model"] ?? "-") (\(kv["device"] ?? "-"))"),
            SpecRow(label: "Chipset", value: soc.isEmpty ? (kv["platform"] ?? "-") : soc),
            SpecRow(label: "CPU", value: "\(cores) · \(kv["abi"] ?? "-")"),
            SpecRow(label: "RAM", value: d.ramTotal.map { marketingSize($0, ram: true) } ?? "-"),
            SpecRow(label: "Layar", value: dpi.isEmpty ? screen : "\(screen) · \(dpi) dpi"),
            SpecRow(label: "Kernel", value: kv["kernel"] ?? "-"),
            SpecRow(label: "Root", value: (kv["su"] ?? "").isEmpty ? "Tidak" : "Ya"),
            SpecRow(label: "Aktif sejak", value: Int(kv["uptime"] ?? "").map(Fmt.uptime) ?? "-"),
        ]

        // battery (dumpsys battery)
        d.batteryLevel = Int(kv["bat.level"] ?? "")
        let health = ["1": "Tidak diketahui", "2": "Baik", "3": "Terlalu panas", "4": "Rusak", "5": "Tegangan berlebih", "6": "Gagal", "7": "Dingin"]
        d.batteryHealth = health[kv["bat.health"] ?? ""]
        d.batteryCycles = kv["cycles"]
        let status = kv["bat.status"] ?? ""
        let source = kv["bat.AC powered"] == "true" ? "adaptor" : kv["bat.USB powered"] == "true" ? "USB" : kv["bat.Wireless powered"] == "true" ? "nirkabel" : nil
        d.batteryState = status == "2" ? "Mengisi daya\(source.map { " (\($0))" } ?? "")" : status == "5" ? "Penuh" : "Tidak mengisi"
        if let t = Double(kv["bat.temperature"] ?? "") { d.batteryExtra.append(SpecRow(label: "Suhu", value: String(format: "%.1f °C", t / 10))) }
        if let v = Double(kv["bat.voltage"] ?? "") { d.batteryExtra.append(SpecRow(label: "Tegangan", value: String(format: "%.2f V", v / 1000))) }
        if let tech = kv["bat.technology"] { d.batteryExtra.append(SpecRow(label: "Teknologi", value: tech)) }

        d.status = [
            SpecRow(label: "Koneksi", value: serial.contains(":") ? "Wi-Fi" : "USB"),
            SpecRow(label: "Verified boot", value: (kv["oem"] ?? "-").capitalized),
            SpecRow(label: "Bootloader", value: kv["bootloader"] ?? "-"),
            SpecRow(label: "Bahasa", value: kv["locale"] ?? "-"),
        ]
        return d
    }

    /// Rounds to the size printed on the box (e.g. 230 GB usable → 256 GB).
    static func marketingSize(_ bytes: Int64, ram: Bool = false) -> String {
        let gb = Double(bytes) / 1_000_000_000
        let steps: [Double] = ram ? [1, 2, 3, 4, 6, 8, 12, 16, 18, 24, 32] : [8, 16, 32, 64, 128, 256, 512, 1024, 2048]
        let pick = steps.first { $0 >= gb * (ram ? 0.85 : 0.85) } ?? gb.rounded()
        return pick >= 1024 ? "\(Int(pick / 1024)) TB" : "\(Int(pick)) GB"
    }

    static func screenshot(serial: String) async -> NSImage? {
        guard let adb = Tools.adb else { return nil }
        return await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: adb)
            p.arguments = ["-s", serial, "exec-out", "screencap", "-p"]
            p.environment = Tools.environment
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return NSImage(data: data)
        }.value
    }

    static func apps(serial: String, includeSystem: Bool) async -> [InstalledApp] {
        guard let adb = Tools.adb else { return [] }
        async let userList = Tools.run(adb, ["-s", serial, "shell", "pm list packages -3"])
        async let sysList = includeSystem ? Tools.run(adb, ["-s", serial, "shell", "pm list packages -s"]) : ""
        async let dump = Tools.run(adb, ["-s", serial, "shell", "dumpsys package packages | grep -E '^  Package \\[|versionName=|firstInstallTime='"])
        let user = Set((await userList).split(separator: "\n").map { $0.replacingOccurrences(of: "package:", with: "").trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let system = Set((await sysList).split(separator: "\n").map { $0.replacingOccurrences(of: "package:", with: "").trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        var info: [String: (String, String)] = [:]
        var current: String?
        for line in (await dump).split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("Package ["), let a = l.firstIndex(of: "["), let b = l.firstIndex(of: "]") {
                current = String(l[l.index(after: a)..<b]); continue
            }
            guard let c = current else { continue }
            if l.hasPrefix("versionName="), info[c]?.0 == nil || info[c]!.0.isEmpty {
                info[c] = (String(l.dropFirst("versionName=".count)), info[c]?.1 ?? "")
            } else if l.hasPrefix("firstInstallTime="), (info[c]?.1 ?? "").isEmpty {
                info[c] = (info[c]?.0 ?? "", String(l.dropFirst("firstInstallTime=".count).prefix(10)))
            }
        }
        let all = user.map { ($0, false) } + system.subtracting(user).map { ($0, true) }
        return all.map { pkg, sys in
            InstalledApp(id: pkg, name: friendlyName(pkg), version: info[pkg]?.0 ?? "", installed: info[pkg]?.1 ?? "", system: sys)
        }
        .sorted { ($0.system ? 1 : 0, $0.name.lowercased()) < ($1.system ? 1 : 0, $1.name.lowercased()) }
    }

    static func uninstall(serial: String, package: String) async -> String {
        guard let adb = Tools.adb else { return "adb tidak ditemukan" }
        return await Tools.run(adb, ["-s", serial, "uninstall", package]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func install(serial: String, apk: URL) async -> String {
        guard let adb = Tools.adb else { return "adb tidak ditemukan" }
        return await Tools.run(adb, ["-s", serial, "install", "-r", apk.path]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func reboot(serial: String, powerOff: Bool) async {
        guard let adb = Tools.adb else { return }
        _ = await Tools.run(adb, ["-s", serial, "shell", powerOff ? "reboot -p" : "reboot"])
    }

    /// Readable name from a package id when no label is available over adb.
    static func friendlyName(_ pkg: String) -> String {
        let known = ["com.whatsapp": "WhatsApp", "com.whatsapp.w4b": "WhatsApp Business", "com.instagram.android": "Instagram",
                     "com.facebook.katana": "Facebook", "com.facebook.orca": "Messenger", "com.zhiliaoapp.musically": "TikTok",
                     "com.ss.android.ugc.trill": "TikTok", "org.telegram.messenger": "Telegram", "com.twitter.android": "X",
                     "com.spotify.music": "Spotify", "com.google.android.youtube": "YouTube", "com.netflix.mediaclient": "Netflix",
                     "com.shopee.id": "Shopee", "com.tokopedia.tkpd": "Tokopedia", "com.gojek.app": "Gojek", "com.grabtaxi.passenger": "Grab",
                     "id.dana": "DANA", "ovo.id": "OVO", "com.bca": "BCA mobile", "id.co.bri.brimo": "BRImo", "com.bankmandiri.livin": "Livin' by Mandiri",
                     "com.discord": "Discord", "com.linkedin.android": "LinkedIn", "com.zoom.videomeetings": "Zoom", "us.zoom.videomeetings": "Zoom",
                     "com.android.chrome": "Chrome", "com.google.android.gm": "Gmail", "com.google.android.apps.maps": "Google Maps"]
        if let k = known[pkg] { return k }
        let skip: Set<String> = ["com", "org", "net", "id", "co", "android", "app", "apps", "mobile", "client", "google", "ss", "free", "lite"]
        let parts = pkg.split(separator: ".").map(String.init).filter { !skip.contains($0.lowercased()) }
        let word = parts.last ?? pkg
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}
