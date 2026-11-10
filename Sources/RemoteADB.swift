import SwiftUI
import AppKit

// MARK: - Android over the internet (Tailscale)
//
// Setup happens once while the phone is on USB: Djie Cast installs Tailscale on the phone (Play Store, or
// straight from F-Droid for phones without Google such as Huawei), the user signs in with the same account,
// and adb is switched to network mode. From then on Djie Cast reaches the phone's adbd through its built-in
// Tailscale, wherever the phone is: every Android feature works as if the phone were plugged in.

struct RemotePhone: Codable, Identifiable, Hashable {
    var id: String { serial }
    let serial: String      // hardware serial, from the USB setup
    var name: String
    var ip: String          // Tailscale IP (100.x.y.z)
}

@MainActor
final class RemoteADB: ObservableObject {
    static let shared = RemoteADB()
    static let tailscalePackage = "com.tailscale.ipn"

    @Published var phones: [RemotePhone] = [] { didSet { save() } }
    @Published var connecting: Set<String> = []
    @Published var message: [String: String] = [:]

    private init() {
        if let d = UserDefaults.standard.data(forKey: "remotePhones"), let list = try? JSONDecoder().decode([RemotePhone].self, from: d) { phones = list }
    }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(phones), forKey: "remotePhones") }

    /// adb serials that go through the tunnel look like 127.0.0.1:<local port>.
    func remote(forSerial serial: String) -> RemotePhone? {
        guard serial.hasPrefix("127.0.0.1:"), let port = UInt16(serial.split(separator: ":").last ?? ""),
              let ip = TailnetModel.shared.tunnelIP(forLocalPort: port) else { return nil }
        return phones.first { $0.ip == ip }
    }
    func isRemote(_ serial: String) -> Bool { serial.hasPrefix("127.0.0.1:") }

    func online(_ p: RemotePhone) -> Bool { TailnetModel.shared.devices.first { $0.ip == p.ip }?.online ?? false }

    func connect(_ p: RemotePhone) async {
        guard let adb = Tools.adb else { return }
        connecting.insert(p.ip); message[p.ip] = nil
        defer { connecting.remove(p.ip) }
        if TailnetModel.shared.ip == nil {
            message[p.ip] = String(localized: "Aktifkan Tailscale di Djie Cast dulu (Remote Desktop → Remote lewat internet).")
            return
        }
        guard let port = TailnetModel.shared.adbTunnel(to: p.ip) else {
            message[p.ip] = String(localized: "Tidak bisa membuka jalur ke HP lewat Tailscale."); return
        }
        let out = await Tools.run(adb, ["connect", "127.0.0.1:\(port)"])
        LauncherModel.shared.append("→ adb connect \(p.name) lewat Tailscale (\(p.ip))\n" + out)
        try? await Task.sleep(for: .seconds(1))
        await LauncherModel.shared.refresh()
        let state = LauncherModel.shared.devices.first { $0.serial == "127.0.0.1:\(port)" }?.state
        if state == "device" { message[p.ip] = nil; return }
        _ = await Tools.run(adb, ["disconnect", "127.0.0.1:\(port)"])
        message[p.ip] = online(p)
            ? String(localized: "HP online di Tailscale tapi ADB-nya mati (biasanya karena HP restart). Colok USB sekali dan jalankan Siapkan remote lagi.")
            : String(localized: "HP sedang offline di Tailscale. Pastikan HP menyala, ada internet, dan aplikasi Tailscale di HP aktif.")
    }

    func disconnect(_ p: RemotePhone) async {
        guard let adb = Tools.adb, let port = TailnetModel.shared.adbTunnel(to: p.ip) else { return }
        _ = await Tools.run(adb, ["disconnect", "127.0.0.1:\(port)"])
        TailnetModel.shared.closeAdbTunnel(to: p.ip)
        await LauncherModel.shared.refresh()
    }

    func forget(_ p: RemotePhone) { phones.removeAll { $0.ip == p.ip } }

    /// Lighter stream settings for cellular / long-distance links.
    static let internetArgs = ["--max-size=1024", "--video-bit-rate=3M", "--max-fps=30", "--no-audio"]
}

// MARK: - Setup wizard (phone on USB)

@MainActor
final class RemoteSetup: ObservableObject {
    enum Step: Int { case tailnet, install, login, adb, done }
    let serial: String
    let name: String
    @Published var step: Step = .tailnet
    @Published var phoneIP: String?
    @Published var busy = false
    @Published var progress: Double?
    @Published var note: String?
    private var poll: Task<Void, Never>?

    init(serial: String, name: String) { self.serial = serial; self.name = name }

    func evaluate() async {
        guard let adb = Tools.adb else { return }
        if TailnetModel.shared.ip == nil { step = .tailnet; return }
        let path = await Tools.run(adb, ["-s", serial, "shell", "pm", "path", RemoteADB.tailscalePackage])
        if !path.contains("package:") { step = .install; return }
        if let ip = await phoneTailscaleIP() { phoneIP = ip; if step.rawValue < Step.adb.rawValue { step = .adb } }
        else { step = .login }
    }

    /// The phone's own 100.x address, read from its Tailscale interface.
    func phoneTailscaleIP() async -> String? {
        guard let adb = Tools.adb else { return nil }
        let out = await Tools.run(adb, ["-s", serial, "shell", "ip", "-4", "addr"])
        for line in out.split(whereSeparator: \.isNewline) where line.contains("inet 100.") {
            if let ip = line.split(separator: " ").drop(while: { $0 != "inet" }).dropFirst().first?.split(separator: "/").first {
                return String(ip)
            }
        }
        return nil
    }

    func openPlayStore() {
        guard let adb = Tools.adb else { return }
        Task { _ = await Tools.run(adb, ["-s", serial, "shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", "market://details?id=\(RemoteADB.tailscalePackage)"]) }
        note = String(localized: "Play Store terbuka di HP. Ketuk Pasang, lalu kembali ke sini.")
        watch()
    }

    /// For phones without Google Play (Huawei, etc.): fetch the official Tailscale build from F-Droid and install over USB.
    func installFromFDroid() async {
        guard let adb = Tools.adb else { return }
        busy = true; progress = 0; note = String(localized: "Mencari versi terbaru Tailscale…")
        defer { busy = false; progress = nil }
        do {
            let (meta, _) = try await URLSession.shared.data(from: URL(string: "https://f-droid.org/api/v1/packages/\(RemoteADB.tailscalePackage)")!)
            guard let obj = try JSONSerialization.jsonObject(with: meta) as? [String: Any],
                  let code = obj["suggestedVersionCode"] as? Int else { throw RemoteSetupError.message(String(localized: "F-Droid tidak menjawab.")) }
            let url = URL(string: "https://f-droid.org/repo/\(RemoteADB.tailscalePackage)_\(code).apk")!
            note = String(localized: "Mengunduh Tailscale…")
            let file = try await download(url)
            note = String(localized: "Memasang Tailscale di HP…")
            let out = await Tools.run(adb, ["-s", serial, "install", "-r", file.path])
            try? FileManager.default.removeItem(at: file)
            guard out.contains("Success") else { throw RemoteSetupError.message(out.trimmingCharacters(in: .whitespacesAndNewlines)) }
            note = nil
            await evaluate()
            if step == .login { openTailscaleOnPhone() }
        } catch {
            note = (error as? RemoteSetupError)?.text ?? error.localizedDescription
        }
    }

    private func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.downloadTask(with: url) { tmp, resp, err in
                if let err { cont.resume(throwing: err); return }
                guard let tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else { cont.resume(throwing: RemoteSetupError.message(String(localized: "Unduhan gagal."))); return }
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("tailscale.apk")
                try? FileManager.default.removeItem(at: dest)
                do { try FileManager.default.moveItem(at: tmp, to: dest); cont.resume(returning: dest) } catch { cont.resume(throwing: error) }
            }
            let p = task.progress
            Task { @MainActor in while !p.isFinished { self.progress = p.fractionCompleted; try? await Task.sleep(for: .milliseconds(200)) } }
            task.resume()
        }
    }

    func openTailscaleOnPhone() {
        guard let adb = Tools.adb else { return }
        Task { _ = await Tools.run(adb, ["-s", serial, "shell", "monkey", "-p", RemoteADB.tailscalePackage, "-c", "android.intent.category.LAUNCHER", "1"]) }
        note = nil
        watch()
    }

    /// Re-checks every 2 s while the user installs or signs in on the phone.
    func watch() {
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                let before = self.step
                await self.evaluate()
                if self.step.rawValue > before.rawValue, self.step == .login { self.openTailscaleOnPhone(); return }
                if self.step == .adb { return }
            }
        }
    }

    /// adb over the network on port 5555 (stays on until the phone restarts), then remember the phone.
    func enableADB() async {
        guard let adb = Tools.adb, let ip = phoneIP else { return }
        busy = true; defer { busy = false }
        let out = await Tools.run(adb, ["-s", serial, "tcpip", "5555"])
        LauncherModel.shared.append("→ adb tcpip 5555 (\(name))\n" + out)
        let phone = RemotePhone(serial: serial, name: name, ip: ip)
        RemoteADB.shared.phones.removeAll { $0.serial == serial || $0.ip == ip }
        RemoteADB.shared.phones.append(phone)
        step = .done
    }

    func stop() { poll?.cancel() }
}

enum RemoteSetupError: Error {
    case message(String)
    var text: String { if case .message(let m) = self { return m }; return "" }
}

struct RemoteSetupSheet: View {
    @StateObject private var setup: RemoteSetup
    @ObservedObject private var tailnet = TailnetModel.shared
    @Environment(\.dismiss) private var dismiss

    init(serial: String, name: String) { _setup = StateObject(wrappedValue: RemoteSetup(serial: serial, name: name)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ANDROID · INTERNET").font(.system(size: 10.5, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(Theme.android[1])
                    Text("Siapkan remote lewat internet").font(.title2.weight(.bold))
                    Text("Sekali saja selagi \(setup.name) tercolok USB. Setelah itu HP bisa dibuka dari mana saja lewat Tailscale.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Selesai") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            VStack(spacing: 10) {
                row(.tailnet, "Tailscale di Mac ini", tailnet.account.map { String(localized: "Masuk sebagai \($0)") } ?? String(localized: "Masuk ke akun Tailscale (gratis)")) {
                    Button { tailnet.start() } label: { Label("Aktifkan & masuk", systemImage: "network") }
                        .buttonStyle(GradientButtonStyle(colors: Theme.android)).fixedSize()
                }
                row(.install, "Pasang Tailscale di HP", String(localized: "Aplikasi resmi Tailscale, gratis")) {
                    HStack(spacing: 8) {
                        Button { setup.openPlayStore() } label: { Label("Buka Play Store di HP", systemImage: "bag") }
                            .buttonStyle(SoftButtonStyle(tint: Theme.android[1])).fixedSize()
                        Button { Task { await setup.installFromFDroid() } } label: { Label("Pasang otomatis", systemImage: "arrow.down.app") }
                            .buttonStyle(GradientButtonStyle(colors: Theme.android)).fixedSize()
                            .help("Tanpa Play Store: diunduh dari F-Droid lalu dipasang lewat USB (cocok untuk Huawei)")
                    }
                }
                row(.login, "Masuk Tailscale di HP", tailnet.account.map { String(localized: "Di HP: ketuk OK pada izin VPN, lalu masuk dengan akun yang sama: \($0)") } ?? String(localized: "Di HP: ketuk OK pada izin VPN, lalu masuk dengan akun yang sama dengan Mac ini")) {
                    Button { setup.openTailscaleOnPhone() } label: { Label("Buka Tailscale di HP", systemImage: "iphone.and.arrow.forward") }
                        .buttonStyle(GradientButtonStyle(colors: Theme.android)).fixedSize()
                }
                row(.adb, "Izinkan akses dari jauh", setup.phoneIP.map { String(localized: "HP terdeteksi di Tailscale: \($0)") } ?? String(localized: "Mengaktifkan ADB lewat jaringan")) {
                    Button { Task { await setup.enableADB() } } label: { Label("Aktifkan", systemImage: "checkmark.shield") }
                        .buttonStyle(GradientButtonStyle(colors: Theme.android)).fixedSize()
                }
            }

            if let p = setup.progress { ProgressView(value: p).tint(Theme.android[1]) }
            if let n = setup.note {
                Label(L(n), systemImage: setup.busy ? "hourglass" : "info.circle").font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if setup.step == .done {
                Label("Siap! \(setup.name) muncul di bagian “HP lewat internet”. Kabel boleh dicabut dan HP boleh dibawa ke mana saja.", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(Theme.live).fixedSize(horizontal: false, vertical: true)
            }
            Text("ADB jaringan mati saat HP dinyalakan ulang. Kalau itu terjadi, colok USB sekali dan buka panduan ini lagi.")
                .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 640)
        .task { await setup.evaluate(); if setup.step == .login { setup.watch() } }
        .onChange(of: tailnet.ip) { _, _ in Task { await setup.evaluate() } }
        .onDisappear { setup.stop() }
    }

    @ViewBuilder
    private func row<Action: View>(_ step: RemoteSetup.Step, _ title: String, _ detail: String, @ViewBuilder action: () -> Action) -> some View {
        let done = setup.step.rawValue > step.rawValue
        let current = setup.step == step
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(done ? Theme.live : current ? Theme.android[1] : Color.primary.opacity(0.08)).frame(width: 28, height: 28)
                if done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                else { Text("\(step.rawValue + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(current ? .white : .secondary) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).font(.callout.weight(.semibold)).foregroundStyle(current || done ? .primary : .secondary)
                Text(L(detail)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if current {
                if setup.busy { ProgressView().controlSize(.small) } else { action() }
            }
        }
        .padding(12)
        .background(current ? Theme.android[1].opacity(0.07) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(current ? Theme.android[1].opacity(0.35) : .clear))
    }
}

// MARK: - Panel on the Android page

struct RemotePhonesPanel: View {
    @ObservedObject private var remote = RemoteADB.shared
    @ObservedObject private var tailnet = TailnetModel.shared
    @ObservedObject private var launcher = LauncherModel.shared

    var body: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    IconBadge(icon: "globe.asia.australia.fill", colors: Theme.android, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("HP lewat internet").font(.headline)
                        Text("Buka HP Android yang jauh — di rumah, di kantor, atau di tangan orang lain — lewat Tailscale. Semua fitur jalan seperti dicolok USB.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if tailnet.ip == nil {
                        Button { tailnet.start() } label: { Label("Aktifkan Tailscale", systemImage: "network") }
                            .buttonStyle(SoftButtonStyle(tint: Theme.android[1])).fixedSize()
                    } else {
                        Label("Tailscale aktif", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.live)
                    }
                }
                if remote.phones.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "cable.connector").foregroundStyle(.secondary)
                        Text("Belum ada HP. Colok HP lewat USB, lalu pilih ••• → Siapkan remote internet di kartu HP.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ForEach(remote.phones) { p in phoneRow(p) }
                }
            }
        }
    }

    private func phoneRow(_ p: RemotePhone) -> some View {
        let online = remote.online(p)
        let connected = launcher.devices.contains { $0.state == "device" && remote.remote(forSerial: $0.serial)?.ip == p.ip }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "smartphone").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.android[1])
                    .frame(width: 34, height: 34).background(Theme.android[1].opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: p.name).font(.callout.weight(.semibold))
                    HStack(spacing: 6) {
                        Circle().fill(online ? Theme.live : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                        Text(online ? "Online" : "Offline").font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: "· \(p.ip)").font(.caption.monospaced()).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if connected {
                    Label("Terhubung", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.live)
                    Button("Putuskan") { Task { await remote.disconnect(p) } }.buttonStyle(.borderless)
                } else {
                    Button { Task { await remote.connect(p) } } label: {
                        if remote.connecting.contains(p.ip) { ProgressView().controlSize(.small) } else { Label("Sambungkan", systemImage: "link") }
                    }
                    .buttonStyle(GradientButtonStyle(colors: Theme.android)).fixedSize()
                    .disabled(remote.connecting.contains(p.ip))
                }
                Menu {
                    Button("Lupakan HP ini", systemImage: "trash", role: .destructive) { remote.forget(p) }
                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            if let m = remote.message[p.ip] {
                Label(L(m), systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 46)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}
