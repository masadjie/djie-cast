import SwiftUI
import AppKit

// MARK: - Tool lookup (GUI apps don't inherit the shell PATH)

enum Tools {
    static let searchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        NSHomeDirectory() + "/Library/Android/sdk/platform-tools",
        "/usr/bin",
        "/bin",
    ]

    /// scrcpy + adb shipped inside the app (Contents/MacOS), server/icons in Resources/scrcpy.
    static let bundledBinDir = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS").path
    static let bundledResDir = Bundle.main.resourceURL?.appendingPathComponent("scrcpy").path ?? ""

    static func bundled(_ name: String) -> String? {
        let p = bundledBinDir + "/" + name
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    static func system(_ name: String) -> String? {
        for dir in searchPaths {
            let p = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Always use the bundled scrcpy so it matches its bundled server.
    static let scrcpy: String? = bundled("scrcpy") ?? system("scrcpy")
    /// Prefer an adb already on this Mac (avoids fighting Android Studio's adb server),
    /// otherwise use the bundled one — so nothing needs to be installed.
    static let adb: String? = system("adb") ?? bundled("adb")
    static var scrcpyIsBundled: Bool { scrcpy != nil && scrcpy == bundled("scrcpy") }
    static let scrcpyVersion: String = {
        (try? String(contentsOfFile: bundledResDir + "/VERSION", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "sistem"
    }()

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"] ?? ""
        env["PATH"] = ([bundledBinDir] + searchPaths + [existing]).joined(separator: ":")
        if let adb { env["ADB"] = adb }
        if scrcpyIsBundled {
            env["SCRCPY_SERVER_PATH"] = bundledResDir + "/scrcpy-server"
            env["SCRCPY_ICON_PATH"] = bundledResDir + "/scrcpy.png"
        }
        return env
    }

    /// Runs a short command and returns its combined output.
    static func run(_ exe: String, _ args: [String]) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                p.environment = environment
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    cont.resume(returning: String(decoding: data, as: UTF8.self))
                } catch {
                    cont.resume(returning: "Error: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Model

struct Device: Identifiable, Hashable {
    let serial: String
    let state: String
    let model: String
    var id: String { serial }
    var isWireless: Bool { serial.contains(":") || serial.contains("._adb-tls") }
    var displayName: String { model.isEmpty ? serial : model.replacingOccurrences(of: "_", with: " ") }
}

/// An Android phone advertising adb on the local network (Wireless debugging or `adb tcpip`).
struct NearbyDevice: Identifiable, Equatable {
    let ip: String
    var instance: String            // e.g. adb-R5CT30ABCDE-xY12zz
    var connectPort: Int?           // _adb-tls-connect (already paired) or _adb (tcpip)
    var pairPort: Int?              // _adb-tls-pairing: shown while "Pair with code" is open on the phone
    var legacy = false              // found via _adb._tcp (adb tcpip mode)
    var id: String { ip }
    /// The hardware serial is embedded in the service name.
    var serialHint: String {
        let parts = instance.split(separator: "-")
        return parts.count >= 2 && parts[0] == "adb" ? String(parts[1]) : instance
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    static let shared = LauncherModel()
    @Published var devices: [Device] = []
    @Published var nearby: [NearbyDevice] = []
    @Published var nearbyBusy: String?          // ip being connected / paired
    @Published var nearbyError: [String: String] = [:]
    @Published var selected: String?
    @Published var running: [String: Process] = [:]
    @Published var log: String = ""
    @Published var busy = false

    let scrcpyPath = Tools.scrcpy
    var readyCount: Int { devices.filter { $0.state == "device" }.count }
    let adbPath = Tools.adb

    func append(_ text: String) {
        log += text
        if log.count > 60_000 { log = String(log.suffix(40_000)) }
    }

    func refresh() async {
        if Demo.enabled {
            devices = [Device(serial: "R5CT30ABCDE", state: "device", model: "Galaxy_S24_Ultra"),
                       Device(serial: "192.168.1.24:5555", state: "device", model: "Pixel_8_Pro"),
                       Device(serial: "9A281FFAZ00", state: "unauthorized", model: "")]
            return
        }
        guard let adb = adbPath else {
            append("❌ adb tidak ditemukan.\n")
            return
        }
        let out = await Tools.run(adb, ["devices", "-l"])
        var list: [Device] = []
        for line in out.split(separator: "\n").dropFirst() {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let model = parts.first(where: { $0.hasPrefix("model:") })?.dropFirst(6) ?? ""
            list.append(Device(serial: parts[0], state: parts[1], model: String(model)))
        }
        devices = list
        if selected == nil || !list.contains(where: { $0.serial == selected }) {
            selected = list.first(where: { $0.state == "device" })?.serial
        }
    }

    func connectWireless(_ address: String) async {
        guard let adb = adbPath, !address.isEmpty else { return }
        busy = true
        let target = address.contains(":") ? address : address + ":5555"
        append("→ adb connect \(target)\n")
        append(await Tools.run(adb, ["connect", target]))
        busy = false
        await refresh()
    }

    // MARK: Nearby (mDNS)

    /// Phones on this network that advertise adb. Needs no setup beyond Wireless debugging on the phone.
    func scanNearby() async {
        guard let adb = adbPath else { return }
        if Demo.enabled {
            nearby = [NearbyDevice(ip: "192.168.1.31", instance: "adb-RFCX20KQ9LM-a1b2c3", connectPort: 41827, pairPort: nil),
                      NearbyDevice(ip: "192.168.1.44", instance: "adb-2B151FDH300ABC-k9", connectPort: nil, pairPort: 37115)]
            return
        }
        let out = await Tools.run(adb, ["mdns", "services"])
        var byIP: [String: NearbyDevice] = [:]
        for line in out.split(whereSeparator: \.isNewline) {
            let cols = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init).filter { !$0.isEmpty }
            guard cols.count >= 3, let hp = cols.last, let colon = hp.lastIndex(of: ":"), let port = Int(hp[hp.index(after: colon)...]) else { continue }
            let ip = String(hp[..<colon]), type = cols[1], name = cols[0]
            var d = byIP[ip] ?? NearbyDevice(ip: ip, instance: name)
            if type.contains("_adb-tls-pairing") { d.pairPort = port }
            else if type.contains("_adb-tls-connect") { d.connectPort = port; d.instance = name }
            else if type.contains("_adb._tcp") { d.connectPort = port; d.legacy = true; d.instance = name }
            byIP[ip] = d
        }
        let list = byIP.values.sorted { $0.ip < $1.ip }
        if list != nearby { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { nearby = list } }
    }

    /// True when this nearby phone is already in the adb device list.
    func isConnected(_ n: NearbyDevice) -> Bool {
        devices.contains { $0.state == "device" && ($0.serial.hasPrefix(n.ip + ":") || $0.serial.hasPrefix(n.instance)) }
    }

    /// Friendly name: the model once connected, otherwise the serial from the service name.
    func name(of n: NearbyDevice) -> String {
        devices.first { $0.serial.hasPrefix(n.ip + ":") || $0.serial.hasPrefix(n.instance) }?.displayName ?? "HP Android · \(n.serialHint)"
    }

    func connectNearby(_ n: NearbyDevice) async {
        guard let adb = adbPath, let port = n.connectPort else { return }
        nearbyBusy = n.ip; nearbyError[n.ip] = nil
        let out = await Tools.run(adb, ["connect", "\(n.ip):\(port)"])
        append("→ adb connect \(n.ip):\(port)\n" + out)
        if !out.contains("connected to") || out.contains("failed") {
            nearbyError[n.ip] = "Belum dipasangkan. Di HP buka Wireless debugging → Pasangkan perangkat dengan kode pairing."
        }
        nearbyBusy = nil
        await refresh()
    }

    /// `adb pair` with the 6-digit code shown on the phone, then connect.
    func pairNearby(_ n: NearbyDevice, code: String) async {
        guard let adb = adbPath, let port = n.pairPort else { return }
        nearbyBusy = n.ip; nearbyError[n.ip] = nil
        let out = await Tools.run(adb, ["pair", "\(n.ip):\(port)", code.trimmingCharacters(in: .whitespaces)])
        append("→ adb pair \(n.ip):\(port)\n" + out)
        nearbyBusy = nil
        guard out.localizedCaseInsensitiveContains("successfully paired") else {
            nearbyError[n.ip] = "Kode salah atau sudah kedaluwarsa. Buka lagi dialog pairing di HP dan coba kode yang baru."
            return
        }
        // the connect service appears a moment after pairing
        for _ in 0..<6 {
            try? await Task.sleep(for: .seconds(1))
            await scanNearby()
            if let fresh = nearby.first(where: { $0.ip == n.ip }), fresh.connectPort != nil { await connectNearby(fresh); return }
        }
    }

    func enableTcpip(_ serial: String) async {
        guard let adb = adbPath else { return }
        busy = true
        append("→ adb -s \(serial) tcpip 5555\n")
        append(await Tools.run(adb, ["-s", serial, "tcpip", "5555"]))
        let ipOut = await Tools.run(adb, ["-s", serial, "shell", "ip", "route"])
        if let ip = ipOut.split(separator: " ").drop(while: { $0 != "src" }).dropFirst().first {
            append("ℹ️ IP HP: \(ip) — cabut kabel lalu klik Connect.\n")
        }
        busy = false
    }

    func disconnect(_ serial: String) async {
        guard let adb = adbPath else { return }
        append(await Tools.run(adb, ["disconnect", serial]))
        await refresh()
    }

    func start(serial: String, args: [String]) {
        guard let scrcpy = scrcpyPath else {
            append("❌ scrcpy tidak ditemukan di dalam app — coba unduh ulang Djie Cast\n")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: scrcpy)
        p.arguments = ["-s", serial] + args
        p.environment = Tools.environment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }
            let s = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.append(s) }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.running[serial] = nil
                self?.append("■ scrcpy (\(serial)) selesai, kode \(proc.terminationStatus)\n")
            }
        }
        do {
            append("▶ scrcpy " + p.arguments!.joined(separator: " ") + "\n")
            try p.run()
            running[serial] = p
        } catch {
            append("❌ Gagal menjalankan scrcpy: \(error.localizedDescription)\n")
        }
    }

    /// Shows the phone's camera on the Mac instead of its screen (scrcpy camera source, Android 12+).
    func startCamera(serial: String, front: Bool, name: String) {
        if running[serial] != nil { stop(serial) }
        let args = ["--video-source=camera", "--camera-facing=\(front ? "front" : "back")",
                    "--max-size=1920", "--camera-fps=30", "--no-audio",
                    "--window-title=Kamera \(front ? "depan" : "belakang") — \(name)"]
        // give a previous session a moment to release the device
        DispatchQueue.main.asyncAfter(deadline: .now() + (running[serial] == nil ? 0 : 0.6)) { [weak self] in
            self?.start(serial: serial, args: args)
        }
    }

    /// Sends an Android key event (works with or without an open cast window).
    func key(_ serial: String, _ code: String) {
        guard let adb = adbPath, !Demo.enabled else { return }
        Task { _ = await Tools.run(adb, ["-s", serial, "shell", "input", "keyevent", code]) }
    }

    /// Saves a PNG screenshot of the phone to the Desktop and reveals it.
    func screenshot(_ serial: String) {
        guard let adb = adbPath, !Demo.enabled else { return }
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: adb)
            p.arguments = ["-s", serial, "exec-out", "screencap", "-p"]
            p.environment = Tools.environment
            let pipe = Pipe()
            p.standardOutput = pipe
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd-HHmmss"
            let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                .appendingPathComponent("DjieCast-\(df.string(from: Date())).png")
            guard data.count > 100, (try? data.write(to: url)) != nil else {
                await MainActor.run { LauncherModel.shared.append("❌ Gagal mengambil screenshot\n") }
                return
            }
            await MainActor.run {
                LauncherModel.shared.append("📸 Screenshot disimpan: \(url.path)\n")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    enum Orientation { case portrait, landscape, auto }

    /// Rotates the phone itself (the cast window follows automatically).
    /// Apps that force an orientation (e.g. some games) may ignore this.
    func setOrientation(_ serial: String, _ o: Orientation) {
        guard let adb = adbPath, !Demo.enabled else { return }
        let cmd: String
        switch o {
        case .portrait:
            cmd = "settings put system accelerometer_rotation 0; settings put system user_rotation 0; cmd window user-rotation lock 0 >/dev/null 2>&1"
        case .landscape:
            cmd = "settings put system accelerometer_rotation 0; settings put system user_rotation 1; cmd window user-rotation lock 1 >/dev/null 2>&1"
        case .auto:
            cmd = "cmd window user-rotation free >/dev/null 2>&1; settings put system accelerometer_rotation 1"
        }
        Task { _ = await Tools.run(adb, ["-s", serial, "shell", cmd]) }
        append("↻ Orientasi \(serial): \(o)\n")
    }

    func stop(_ serial: String) {
        running[serial]?.terminate()
    }

    func stopAll() {
        running.values.forEach { $0.terminate() }
    }
}


// MARK: - Quality presets

enum QualityPreset: String, CaseIterable, Identifiable {
    case hemat = "Hemat", seimbang = "Seimbang", maksimal = "Maksimal", kustom = "Kustom"
    var id: String { rawValue }
    var values: (size: Int, bitrate: Int, fps: Int)? {
        switch self {
        case .hemat: return (1024, 4, 30)
        case .seimbang: return (1600, 8, 60)
        case .maksimal: return (0, 24, 120)
        case .kustom: return nil
        }
    }
    var hint: String {
        switch self {
        case .hemat: return "1024p · 4 Mbps · 30 fps — ringan, cocok untuk Wi-Fi"
        case .seimbang: return "1600p · 8 Mbps · 60 fps — tajam & lancar"
        case .maksimal: return "Resolusi asli · 24 Mbps · 120 fps — terbaik via USB"
        case .kustom: return "Atur sendiri resolusi, bitrate & FPS"
        }
    }
}

// MARK: - Android view

struct AndroidCastView: View {
    @ObservedObject var model = LauncherModel.shared
    @AppStorage("maxSize") var maxSize = 1600
    @AppStorage("bitrate") var bitrate = 8
    @AppStorage("maxFps") var maxFps = 60
    @AppStorage("audio") var audio = true
    @AppStorage("turnScreenOff") var turnScreenOff = false
    @AppStorage("stayAwake") var stayAwake = true
    @AppStorage("alwaysOnTop") var alwaysOnTop = false
    @AppStorage("fullscreen") var fullscreen = false
    @AppStorage("showTouches") var showTouches = false
    @AppStorage("borderless") var borderless = false
    @AppStorage("displayOrientation") var displayOrientation = 0
    @AppStorage("noControl") var noControl = false
    @AppStorage("record") var record = false
    @AppStorage("extraArgs") var extraArgs = ""
    @AppStorage("wirelessIP") private var wirelessIP = ""
    @State private var showWifiHelp = false
    @State private var showManualIP = false
    @State private var pairCodes: [String: String] = [:]
    @AppStorage("androidInspector") private var showInspector = true
    @State private var showConsole = false
    @State private var showGuide = false
    @State private var detailSerial: String?

    func scrcpyArgs() -> [String] {
        var a: [String] = []
        if maxSize > 0 { a += ["--max-size=\(maxSize)"] }
        a += ["--video-bit-rate=\(bitrate)M", "--max-fps=\(maxFps)"]
        if !audio { a.append("--no-audio") }
        if turnScreenOff { a.append("--turn-screen-off") }
        if stayAwake { a.append("--stay-awake") }
        if alwaysOnTop { a.append("--always-on-top") }
        if fullscreen { a.append("--fullscreen") }
        if showTouches { a.append("--show-touches") }
        if borderless { a.append("--window-borderless") }
        if displayOrientation != 0 { a.append("--display-orientation=\(displayOrientation)") }
        if noControl { a.append("--no-control") }
        if record {
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd-HHmmss"
            let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
            a.append("--record=\(dir.path)/DjieCast-\(df.string(from: Date())).mp4")
        }
        a += extraArgs.split(separator: " ").map(String.init)
        return a
    }

    private var preset: Binding<QualityPreset> {
        Binding {
            QualityPreset.allCases.first { p in
                guard let v = p.values else { return false }
                return v.size == maxSize && v.bitrate == bitrate && v.fps == maxFps
            } ?? .kustom
        } set: { p in
            guard let v = p.values else { return }
            maxSize = v.size; bitrate = v.bitrate; maxFps = v.fps
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if Demo.env["DJIE_FOCUS"] == "wireless" { wirelessPanel }   // snapshot aid
                PageHeader(icon: "smartphone", colors: Theme.android, title: "Android",
                           subtitle: "Mirror & kontrol HP Android lewat USB atau Wi-Fi") {
                    StatusPill(count: model.readyCount, noun: "perangkat")
                }

                if !model.devices.isEmpty {
                    RequirementBanner(guide: .android) { showGuide = true }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Perangkat", detail: "· diperbarui otomatis")
                    if model.devices.isEmpty {
                        Panel(padding: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Belum ada HP Android tersambung").font(.headline)
                                Text("Ikuti langkah ini sekali saja, lalu HP akan muncul di sini otomatis.")
                                    .font(.callout).foregroundStyle(.secondary)
                                GuideStepsList(guide: .android).padding(.top, 6)
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            ForEach(model.devices) { d in
                                if d.state == "device" {
                                    let running = model.running[d.serial] != nil
                                    DeviceSummaryCard(backend: AndroidBackend(serial: d.serial), fallbackTitle: d.displayName,
                                                      fallbackSubtitle: d.serial, live: running,
                                                      connection: d.isWireless ? "Wi-Fi" : "USB", showScreen: true,
                                                      onDetails: { detailSerial = d.serial }) {
                                        if running {
                                            Button { model.stop(d.serial) } label: { Label("Hentikan", systemImage: "stop.fill") }
                                                .buttonStyle(SoftButtonStyle(tint: .red)).fixedSize()
                                        } else {
                                            Button { model.start(serial: d.serial, args: scrcpyArgs()) } label: { Label("Mulai Cast", systemImage: "play.fill") }
                                                .buttonStyle(GradientButtonStyle(colors: Theme.android)).fixedSize()
                                        }
                                        ControlBar(serial: d.serial).frame(width: 290)
                                        Menu {
                                            Section("Kamera HP · Android 12+") {
                                                Button("Kamera belakang", systemImage: "camera.fill") { model.startCamera(serial: d.serial, front: false, name: d.displayName) }
                                                Button("Kamera depan", systemImage: "camera.rotate") { model.startCamera(serial: d.serial, front: true, name: d.displayName) }
                                            }
                                        } label: { Label("Kamera", systemImage: "camera.fill") }
                                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Theme.android[1].opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                        .help("Tampilkan kamera HP di Mac")
                                        Menu {
                                            if !d.isWireless {
                                                Button("Aktifkan Wi-Fi", systemImage: "wifi") { Task { await model.enableTcpip(d.serial) } }
                                            } else {
                                                Button("Putuskan", systemImage: "xmark.circle") { Task { await model.disconnect(d.serial) } }
                                            }
                                            Button("Buka File", systemImage: "folder") {
                                                AndroidFilesModel.shared.select(serial: d.serial); Nav.shared.page = .files
                                            }
                                            Button("Salin serial", systemImage: "doc.on.doc") {
                                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(d.serial, forType: .string)
                                            }
                                        } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                    }
                                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                                } else {
                                    AndroidDeviceCard(device: d, running: false, busy: model.busy,
                                                      onStart: {}, onStop: {},
                                                      onWifi: { Task { await model.enableTcpip(d.serial) } },
                                                      onDisconnect: { Task { await model.disconnect(d.serial) } },
                                                      onInfo: { detailSerial = d.serial })
                                    .frame(maxWidth: 360, alignment: .leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                                }
                            }
                        }
                    }
                }

                controlTips

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Wireless")
                    wirelessPanel
                }

                consolePanel
            }
            .padding(28)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.devices.map(\.serial))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: Array(model.running.keys))
        .sheet(isPresented: $showGuide) { SetupGuideSheet(guide: .android) }
        .sheet(item: Binding(get: { detailSerial.map { SerialItem(id: $0) } }, set: { detailSerial = $0?.id })) { item in
            DeviceDetailSheet(backend: AndroidBackend(serial: item.id))
        }
        .inspector(isPresented: $showInspector) {
            settingsForm
                .inspectorColumnWidth(min: 260, ideal: 290, max: 360)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Cari ulang perangkat")
                Button { showGuide = true } label: { Label("Panduan USB Debugging", systemImage: "questionmark.circle") }
                    .help("Cara mengaktifkan USB Debugging")
                Button { showInspector.toggle() } label: { Label("Pengaturan", systemImage: "sidebar.trailing") }
                    .help("Tampilkan/sembunyikan pengaturan")
            }
        }
    }

    // MARK: Control tips

    private var controlTips: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconBadge(icon: "cursorarrow.click.2", colors: Theme.android, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kontrol penuh dari Mac").font(.headline)
                        Text("Klik, scroll, drag & ketik langsung di jendela cast — tidak perlu menyentuh HP.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach([("⌘ B", "Kembali"), ("⌘ H", "Home"), ("⌘ S", "Aplikasi terbaru"),
                             ("⌘ ↑ / ↓", "Volume"), ("⌘ P", "Power"), ("⌘ F", "Fullscreen"),
                             ("⌘ R", "Putar layar HP"), ("⌘ ← / →", "Putar jendela"),
                             ("⌘ V", "Tempel teks ke HP"), ("Klik kanan", "Kembali")], id: \.0) { k, v in
                        HStack(spacing: 8) {
                            Text(k)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
                            Text(v).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Wireless

    private var wirelessPanel: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        IconBadge(icon: "wifi", colors: Theme.airplay, size: 44)
                        RadarRings(color: Theme.airplay[1]).frame(width: 44, height: 44).allowsHitTesting(false)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("HP di jaringan ini").font(.headline)
                        Text("HP Android dengan **Wireless debugging** menyala di Wi-Fi yang sama muncul otomatis di sini.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button { showWifiHelp.toggle() } label: { Label("Cara menyalakan", systemImage: "questionmark.circle") }
                        .buttonStyle(.borderless).fixedSize()
                }

                if showWifiHelp {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(["Mac dan HP tersambung ke Wi-Fi yang sama",
                                       "Di HP: Opsi pengembang → Wireless debugging → nyalakan",
                                       "Pertama kali: ketuk “Pasangkan perangkat dengan kode pairing”, lalu masukkan kodenya di sini",
                                       "Setelah itu HP cukup diklik Sambungkan — tanpa kabel, tanpa kode lagi"].enumerated()), id: \.offset) { i, t in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(String(format: "%02d", i + 1)).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.airplay[1])
                                Text(t).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if model.nearby.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Mencari HP di jaringan…").font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.nearby) { n in nearbyRow(n) }
                    }
                }

                DisclosureGroup(isExpanded: $showManualIP) {
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "network").foregroundStyle(.secondary)
                            TextField("Alamat IP HP, mis. 192.168.1.10 atau 192.168.1.10:5555", text: $wirelessIP)
                                .textFieldStyle(.plain)
                                .onSubmit { Task { await model.connectWireless(wirelessIP) } }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: 380)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                        Button { Task { await model.connectWireless(wirelessIP) } } label: {
                            if model.busy { ProgressView().controlSize(.small) } else { Label("Sambungkan", systemImage: "link") }
                        }
                        .buttonStyle(SoftButtonStyle(tint: Theme.airplay[1])).fixedSize()
                        .disabled(wirelessIP.isEmpty || model.busy)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Masukkan IP manual").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showWifiHelp)
        .task {
            while !Task.isCancelled {
                await model.scanNearby()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    @ViewBuilder private func nearbyRow(_ n: NearbyDevice) -> some View {
        let connected = model.isConnected(n)
        let busy = model.nearbyBusy == n.ip
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "smartphone")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.android[1])
                    .frame(width: 34, height: 34)
                    .background(Theme.android[1].opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name(of: n)).font(.callout.weight(.semibold))
                    Text(n.ip + (n.connectPort.map { ":\($0)" } ?? "")).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if connected {
                    Label("Terhubung", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.live)
                } else if n.pairPort != nil && (n.connectPort == nil || model.nearbyError[n.ip] != nil) {
                    Pill(text: "Minta pairing", color: .orange)
                } else if n.connectPort != nil {
                    Button { Task { await model.connectNearby(n) } } label: {
                        if busy { ProgressView().controlSize(.small) } else { Label("Sambungkan", systemImage: "link") }
                    }
                    .buttonStyle(GradientButtonStyle(colors: Theme.airplay)).fixedSize()
                    .disabled(busy)
                }
            }
            if !connected, n.pairPort != nil, n.connectPort == nil || model.nearbyError[n.ip] != nil {
                HStack(spacing: 8) {
                    Text("Kode pairing di HP").font(.caption).foregroundStyle(.secondary)
                    TextField("123456", text: Binding(get: { pairCodes[n.ip] ?? "" }, set: { pairCodes[n.ip] = String($0.filter(\.isNumber).prefix(6)) }))
                        .textFieldStyle(.roundedBorder).font(.body.monospacedDigit()).frame(width: 110)
                        .onSubmit { Task { await model.pairNearby(n, code: pairCodes[n.ip] ?? "") } }
                    Button { Task { await model.pairNearby(n, code: pairCodes[n.ip] ?? "") } } label: {
                        if busy { ProgressView().controlSize(.small) } else { Label("Pasangkan", systemImage: "key.fill") }
                    }
                    .buttonStyle(GradientButtonStyle(colors: Theme.airplay)).fixedSize()
                    .disabled((pairCodes[n.ip] ?? "").count != 6 || busy)
                }
                .padding(.leading, 46)
            }
            if let err = model.nearbyError[n.ip], !connected {
                Label(err, systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 46)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Console

    private var consolePanel: some View {
        Panel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { showConsole.toggle() } } label: {
                    HStack {
                        Image(systemName: "terminal").foregroundStyle(.secondary)
                        Text("Console").font(.callout.weight(.semibold))
                        if !model.log.isEmpty {
                            Text("\(model.log.split(separator: "\n").count) baris").font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if showConsole {
                            Button("Bersihkan") { model.log = "" }
                                .buttonStyle(.borderless).controlSize(.small)
                        }
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showConsole ? 0 : -90))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showConsole {
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(model.log.isEmpty ? "Belum ada output." : model.log)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(model.log.isEmpty ? .tertiary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(14)
                                .id("bottom")
                        }
                        .frame(height: 180)
                        .onChange(of: model.log) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                }
            }
        }
    }

    // MARK: Settings inspector

    private var settingsForm: some View {
        Form {
            Section {
                Picker("Preset", selection: preset) {
                    ForEach(QualityPreset.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(preset.wrappedValue.hint).font(.caption).foregroundStyle(.secondary)
                if preset.wrappedValue == .kustom {
                    Picker("Resolusi", selection: $maxSize) {
                        Text("Asli").tag(0)
                        ForEach([1920, 1600, 1280, 1024, 800], id: \.self) { Text("\($0)p").tag($0) }
                    }
                    Picker("Bitrate", selection: $bitrate) {
                        ForEach([2, 4, 8, 16, 24, 32], id: \.self) { Text("\($0) Mbps").tag($0) }
                    }
                    Picker("FPS", selection: $maxFps) {
                        ForEach([30, 60, 90, 120], id: \.self) { Text("\($0)").tag($0) }
                    }
                }
            } header: { Label("Kualitas", systemImage: "sparkles.tv") }

            Section {
                Toggle("Selalu di atas", isOn: $alwaysOnTop)
                Toggle("Fullscreen", isOn: $fullscreen)
                Toggle("Tanpa bingkai jendela", isOn: $borderless)
                Picker("Putar tampilan", selection: $displayOrientation) {
                    Text("Normal").tag(0)
                    Text("90° kanan").tag(90)
                    Text("180°").tag(180)
                    Text("90° kiri").tag(270)
                }
            } header: { Label("Jendela", systemImage: "macwindow") }

            Section {
                Toggle("Teruskan audio", isOn: $audio)
                Toggle("Matikan layar HP", isOn: $turnScreenOff)
                Toggle("Jaga HP tetap menyala", isOn: $stayAwake)
                Toggle("Tampilkan sentuhan", isOn: $showTouches)
                Toggle("Mode lihat saja", isOn: $noControl)
            } header: { Label("Perangkat", systemImage: "iphone.gen3") }

            Section {
                Toggle("Rekam layar", isOn: $record)
                if record {
                    Text("Disimpan ke folder Movies").font(.caption).foregroundStyle(.secondary)
                }
            } header: { Label("Rekam", systemImage: "record.circle") }

            Section {
                TextField("Argumen", text: $extraArgs, prompt: Text("--crop=1080:1920:0:0"))
                    .font(.system(.body, design: .monospaced))
                LabeledContent("Mesin", value: Tools.scrcpyIsBundled ? "scrcpy \(Tools.scrcpyVersion) · bawaan" : "scrcpy sistem")
                    .font(.caption)
            } header: { Label("Lanjutan", systemImage: "slider.horizontal.3") }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Device card

struct AndroidDeviceCard: View {
    let device: Device
    let running: Bool
    let busy: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onWifi: () -> Void
    let onDisconnect: () -> Void
    let onInfo: () -> Void

    private var ready: Bool { device.state == "device" }

    var body: some View {
        Panel(highlight: running ? Theme.live : nil) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    IconBadge(icon: "smartphone", colors: ready ? Theme.android : [.gray, .gray.opacity(0.7)], size: 44)
                    Spacer()
                    if running { LiveBadge() }
                    Pill(text: device.isWireless ? "Wi-Fi" : "USB",
                         icon: device.isWireless ? "wifi" : "cable.connector",
                         color: device.isWireless ? .blue : .secondary)
                    Button(action: onInfo) { Image(systemName: "info.circle").font(.system(size: 15)) }
                        .buttonStyle(.borderless)
                        .help("Info perangkat & aplikasi")
                        .disabled(!ready)
                    Menu {
                        Button("Info perangkat & aplikasi", systemImage: "info.circle", action: onInfo).disabled(!ready)
                        if !device.isWireless {
                            Button("Aktifkan Wi-Fi", systemImage: "wifi", action: onWifi).disabled(!ready || busy)
                        } else {
                            Button("Putuskan", systemImage: "xmark.circle", action: onDisconnect)
                        }
                        Button("Buka File", systemImage: "folder") {
                            AndroidFilesModel.shared.select(serial: device.serial)
                            Nav.shared.page = .files
                        }.disabled(!ready)
                        Button("Salin serial", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(device.serial, forType: .string)
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.displayName).font(.headline).lineLimit(1)
                    Text(device.serial).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
                statusLine
                if ready { ControlBar(serial: device.serial) }
                if running {
                    Button(action: onStop) { Label("Hentikan", systemImage: "stop.fill") }
                        .buttonStyle(SoftButtonStyle(tint: .red))
                } else {
                    Button(action: onStart) { Label("Mulai Cast", systemImage: "play.fill") }
                        .buttonStyle(GradientButtonStyle(colors: Theme.android))
                        .disabled(!ready)
                }
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch device.state {
        case "device":
            Label(running ? "Sedang ditampilkan" : "Siap", systemImage: running ? "dot.radiowaves.left.and.right" : "checkmark.circle.fill")
                .font(.caption).foregroundStyle(running ? Theme.live : .secondary)
        case "unauthorized":
            Label("Ketuk \"Izinkan\" di HP", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        default:
            Label("Status: \(device.state)", systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

// MARK: - Quick controls (adb key events)

struct ControlBar: View {
    let serial: String
    private let model = LauncherModel.shared

    private let keys: [(icon: String, help: String, code: String)] = [
        ("chevron.backward", "Kembali", "KEYCODE_BACK"),
        ("circle", "Home", "KEYCODE_HOME"),
        ("square.on.square", "Aplikasi terbaru", "KEYCODE_APP_SWITCH"),
        ("speaker.minus.fill", "Volume turun", "KEYCODE_VOLUME_DOWN"),
        ("speaker.plus.fill", "Volume naik", "KEYCODE_VOLUME_UP"),
        ("power", "Power / kunci layar", "KEYCODE_POWER"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(keys, id: \.code) { k in
                Button { model.key(serial, k.code) } label: {
                    Image(systemName: k.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(k.help)
            }
            Divider().frame(height: 16)
            Menu {
                Button("Portrait", systemImage: "rectangle.portrait") { model.setOrientation(serial, .portrait) }
                Button("Landscape", systemImage: "rectangle") { model.setOrientation(serial, .landscape) }
                Divider()
                Button("Putar otomatis", systemImage: "arrow.triangle.2.circlepath") { model.setOrientation(serial, .auto) }
            } label: {
                Image(systemName: "rectangle.portrait.rotate")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Putar layar: portrait / landscape")
            .tint(.secondary)
            Button { model.screenshot(serial) } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Screenshot ke Desktop")
        }
        .foregroundStyle(.secondary)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SerialItem: Identifiable { let id: String }


/// Two soft rings expanding from an icon: "searching the network".
struct RadarRings: View {
    let color: Color
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let p = ((t / 2.2) + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    RoundedRectangle(cornerRadius: 12 + 10 * p)
                        .stroke(color.opacity(0.45 * (1 - p)), lineWidth: 1.5)
                        .scaleEffect(1 + 0.55 * p)
                }
            }
        }
    }
}
