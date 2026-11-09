import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

// MARK: - 1. Wi-Fi pairing with a QR code (Android 11+)
//
// The phone's "Pair device with QR code" scanner reads `WIFI:T:ADB;S:<name>;P:<password>;;`, then advertises
// a pairing service named <name>. We watch for it over mDNS and answer with `adb pair ip:port password`.

@MainActor
final class QRPairing: ObservableObject {
    enum Phase: Equatable { case waiting, pairing(String), connecting(String), done(String), failed(String) }
    @Published var phase: Phase = .waiting
    let name = "djiecast-" + String((0..<6).map { _ in "abcdefghjkmnpqrstuvwxyz23456789".randomElement()! })
    let password = String((0..<8).map { _ in "0123456789".randomElement()! })
    var payload: String { "WIFI:T:ADB;S:\(name);P:\(password);;" }
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self, let adb = Tools.adb else { return }
            // 1) wait for the phone to advertise our pairing service (up to 3 minutes)
            var target: String?
            for _ in 0..<180 where !Task.isCancelled {
                let out = await Tools.run(adb, ["mdns", "services"])
                for line in out.split(whereSeparator: \.isNewline) where line.contains(self.name) && line.contains("_adb-tls-pairing") {
                    target = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).last.map(String.init)
                }
                if target != nil { break }
                try? await Task.sleep(for: .seconds(1))
            }
            guard let target, !Task.isCancelled else { return }
            let ip = String(target.split(separator: ":").first ?? "")
            self.phase = .pairing(ip)
            let out = await Tools.run(adb, ["pair", target, self.password])
            guard out.localizedCaseInsensitiveContains("successfully paired") else {
                self.phase = out.localizedCaseInsensitiveContains("No route to host")
                    ? .failed(String(localized: "macOS memblokir akses jaringan lokal untuk Djie Cast. Izinkan di Pengaturan Sistem → Privasi & Keamanan → Jaringan Lokal."))
                    : .failed(out.trimmingCharacters(in: .whitespacesAndNewlines))
                return
            }
            // 2) the connect service appears a moment after pairing
            self.phase = .connecting(ip)
            for _ in 0..<15 where !Task.isCancelled {
                await LauncherModel.shared.scanNearby()
                if let n = LauncherModel.shared.nearby.first(where: { $0.ip == ip }), n.connectPort != nil {
                    await LauncherModel.shared.connectNearby(n)
                    if LauncherModel.shared.isConnected(n) { self.phase = .done(LauncherModel.shared.name(of: n)); return }
                }
                try? await Task.sleep(for: .seconds(1))
            }
            self.phase = .done(ip)   // paired; it will show up under "Phones on this network"
        }
    }

    func stop() { task?.cancel(); task = nil }

    static func image(for text: String, size: CGFloat) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: size / out.extent.width, y: size / out.extent.height))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size); img.addRepresentation(rep)
        return img
    }
}

struct QRPairSheet: View {
    @StateObject private var pairing = QRPairing()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ANDROID · WI-FI").font(.system(size: 10.5, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(Theme.android[1])
                    Text("Pasangkan dengan QR code").font(.title2.weight(.bold))
                }
                Spacer()
                Button("Selesai") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .top, spacing: 28) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(.white)
                    if let img = QRPairing.image(for: pairing.payload, size: 220) {
                        Image(nsImage: img).interpolation(.none).resizable().frame(width: 220, height: 220)
                    }
                    if case .done = pairing.phase {
                        RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.92))
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.live)
                    }
                }
                .frame(width: 252, height: 252)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)

                VStack(alignment: .leading, spacing: 12) {
                    step(1, "HP dan Mac di Wi-Fi yang sama")
                    step(2, "Di HP: Opsi pengembang → Wireless debugging → nyalakan")
                    step(3, "Ketuk “Pasangkan perangkat dengan kode QR”")
                    step(4, "Arahkan kamera HP ke kode ini")
                    Divider().padding(.vertical, 4)
                    status
                }
                .frame(width: 300, alignment: .leading)
            }
            Text("Android 11 ke atas. Untuk Android 10 ke bawah, colok USB lalu pilih ••• → Aktifkan Wi-Fi di kartu HP.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(26)
        .frame(width: 640)
        .onAppear { pairing.start(); LauncherModel.shared.primeLocalNetwork() }
        .onDisappear { pairing.stop() }
    }

    @ViewBuilder private var status: some View {
        switch pairing.phase {
        case .waiting:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Menunggu HP memindai…").foregroundStyle(.secondary) }
        case .pairing(let ip):
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Memasangkan \(ip)…") }
        case .connecting(let ip):
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Tersambung, membuka \(ip)…") }
        case .done(let name):
            Label("\(name) terhubung lewat Wi-Fi", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.live).font(.callout.weight(.semibold))
        case .failed(let msg):
            Label(L(msg), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(format: "%02d", n)).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.android[1])
            Text(L(text)).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 2. Android apps as their own Mac windows (scrcpy virtual display, Android 10+)

struct PhoneApp: Identifiable, Hashable {
    let id: String      // package
    let name: String
    let system: Bool
}

@MainActor
final class AppWindows: ObservableObject {
    static let shared = AppWindows()
    @Published var open: [String: Process] = [:]        // "serial|package"
    @Published var apps: [String: [PhoneApp]] = [:]     // per serial
    @Published var loading: Set<String> = []
    @Published var error: String?

    func key(_ serial: String, _ pkg: String) -> String { serial + "|" + pkg }
    func count(for serial: String) -> Int { open.keys.filter { $0.hasPrefix(serial + "|") }.count }

    /// `scrcpy --list-apps` gives the real app labels; "*" marks system apps, "-" user apps.
    func loadApps(_ serial: String) async {
        guard let scrcpy = LauncherModel.shared.scrcpyPath, !loading.contains(serial) else { return }
        if Demo.enabled {
            apps[serial] = ["WhatsApp:com.whatsapp", "Instagram:com.instagram.android", "TikTok:com.zhiliaoapp.musically", "Shopee:com.shopee.id",
                            "Gojek:com.gojek.app", "Tokopedia:com.tokopedia.tkpd", "Spotify:com.spotify.music", "YouTube:com.google.android.youtube"]
                .map { let p = $0.split(separator: ":"); return PhoneApp(id: String(p[1]), name: String(p[0]), system: false) }
            return
        }
        loading.insert(serial)
        let out = await Tools.run(scrcpy, ["-s", serial, "--list-apps"])
        var list: [PhoneApp] = []
        for line in out.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("* ") || t.hasPrefix("- ") else { continue }
            let body = t.dropFirst(2)
            guard let lastSpace = body.lastIndex(of: " ") else { continue }
            let pkg = String(body[body.index(after: lastSpace)...])
            let name = body[..<lastSpace].trimmingCharacters(in: .whitespaces)
            guard pkg.contains(".") else { continue }
            list.append(PhoneApp(id: pkg, name: name.isEmpty ? pkg : name, system: t.hasPrefix("*")))
        }
        apps[serial] = list.sorted { ($0.system ? 1 : 0, $0.name.lowercased()) < ($1.system ? 1 : 0, $1.name.lowercased()) }
        if list.isEmpty { error = String(localized: "Tidak bisa membaca daftar aplikasi. Fitur ini butuh Android 10 atau lebih baru.") }
        loading.remove(serial)
    }

    enum Size: String, CaseIterable, Identifiable {
        case phone, tall, wide
        var id: String { rawValue }
        var label: String { ["phone": "Seperti layar HP", "tall": "Ponsel ringkas", "wide": "Lebar (tablet)"][rawValue]! }
        var arg: String { ["phone": "--new-display", "tall": "--new-display=720x1440/280", "wide": "--new-display=1920x1200/240"][rawValue]! }
    }

    func launch(serial: String, device: String, app: PhoneApp, size: Size) {
        let k = key(serial, app.id)
        guard open[k] == nil, let scrcpy = LauncherModel.shared.scrcpyPath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: scrcpy)
        // A separate virtual display per app: the phone's own screen is left alone.
        p.arguments = ["-s", serial, size.arg, "--start-app=\(app.id)", "--no-audio", "--no-vd-destroy-content",
                       "--video-bit-rate=8M", "--max-fps=60", "--window-title=\(app.name) — \(device)"]
        p.environment = Tools.environment
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            let s = String(decoding: d, as: UTF8.self)
            Task { @MainActor in LauncherModel.shared.append(s) }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.open[k] = nil
                if proc.terminationStatus != 0 && proc.terminationStatus != 15 {
                    self?.error = String(localized: "\(app.name) tidak bisa dibuka di jendela terpisah. Fitur ini butuh Android 10 atau lebih baru; lihat Console untuk detail.")
                }
            }
        }
        do { try p.run(); open[k] = p; error = nil } catch { self.error = error.localizedDescription }
    }

    func close(serial: String, pkg: String) { open[key(serial, pkg)]?.terminate() }
    func closeAll() { open.values.forEach { $0.terminate() } }
}

struct AppWindowsSheet: View {
    let serial: String
    let device: String
    @ObservedObject private var model = AppWindows.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showSystem = false
    @AppStorage("appWindowSize") private var size = AppWindows.Size.phone.rawValue

    private var list: [PhoneApp] {
        let all = model.apps[serial] ?? []
        let includeSystem = showSystem || !all.contains { !$0.system }   // nothing user-installed: show everything
        return all.filter { (includeSystem || !$0.system) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: device.uppercased()).font(.system(size: 10.5, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(Theme.android[1])
                    Text("Aplikasi sebagai jendela Mac").font(.title2.weight(.bold))
                    Text("Tiap aplikasi terbuka di jendelanya sendiri, berdampingan dengan aplikasi Mac. Layar HP tidak ikut berubah.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Selesai") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Cari aplikasi", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                Picker("Ukuran", selection: $size) {
                    ForEach(AppWindows.Size.allCases) { s in Text(L(s.label)).tag(s.rawValue) }
                }
                .fixedSize()
                Toggle("Aplikasi sistem", isOn: $showSystem).toggleStyle(.checkbox).fixedSize()
            }
            if let e = model.error {
                Label(L(e), systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                if model.apps[serial] == nil {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Membaca daftar aplikasi…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(list) { app in tile(app) }
                    }
                }
            }
            .frame(height: 380)
        }
        .padding(24)
        .frame(width: 720)
        .task { await model.loadApps(serial) }
    }

    private func tile(_ app: PhoneApp) -> some View {
        let isOpen = model.open[model.key(serial, app.id)] != nil
        let hue = Double(abs(app.id.hashValue % 360)) / 360
        return HStack(spacing: 10) {
            Text(String(app.name.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color(hue: hue, saturation: 0.55, brightness: 0.78), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: app.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(verbatim: app.id).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if isOpen {
                Button { model.close(serial: serial, pkg: app.id) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.red).help("Tutup jendela")
            } else {
                Button { model.launch(serial: serial, device: device, app: app, size: AppWindows.Size(rawValue: size) ?? .phone) } label: {
                    Image(systemName: "macwindow.badge.plus")
                }
                .buttonStyle(.borderless).foregroundStyle(Theme.android[1]).help("Buka di jendela Mac")
            }
        }
        .padding(10)
        .background(isOpen ? Theme.live.opacity(0.1) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOpen ? Theme.live.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !isOpen { model.launch(serial: serial, device: device, app: app, size: AppWindows.Size(rawValue: size) ?? .phone) } }
    }
}

// MARK: - 3. Quick file sending (drag & drop onto a phone card)

@MainActor
final class FileSender: ObservableObject {
    static let shared = FileSender()
    @Published var status: [String: String] = [:]      // serial → progress / result
    @Published var targeted: String?

    /// APKs are installed; everything else lands in the phone's Download folder and is indexed for Gallery/Files.
    func send(_ urls: [URL], to serial: String) {
        guard let adb = Tools.adb, !urls.isEmpty else { return }
        Task {
            var sent = 0, installed = 0, failed = 0
            for (i, url) in urls.enumerated() {
                status[serial] = String(localized: "Mengirim \(i + 1)/\(urls.count): \(url.lastPathComponent)")
                if url.pathExtension.lowercased() == "apk" {
                    let out = await Tools.run(adb, ["-s", serial, "install", "-r", url.path])
                    if out.contains("Success") { installed += 1 } else { failed += 1 }
                } else {
                    let dest = "/sdcard/Download/" + url.lastPathComponent
                    let out = await Tools.run(adb, ["-s", serial, "push", url.path, dest])
                    if out.contains("pushed") || out.contains("1 file") {
                        sent += 1
                        _ = await Tools.run(adb, ["-s", serial, "shell", "am", "broadcast", "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE", "-d", "file://" + dest])
                    } else { failed += 1 }
                }
            }
            var parts: [String] = []
            if sent > 0 { parts.append(String(localized: "\(sent) file terkirim ke Download")) }
            if installed > 0 { parts.append(String(localized: "\(installed) aplikasi terpasang")) }
            if failed > 0 { parts.append(String(localized: "\(failed) gagal")) }
            status[serial] = parts.joined(separator: " · ")
            try? await Task.sleep(for: .seconds(6))
            if status[serial] == parts.joined(separator: " · ") { status[serial] = nil }
        }
    }

    func pick(for serial: String, name: String) {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Pilih file untuk dikirim ke \(name)")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        send(panel.urls, to: serial)
    }
}

/// Makes a device card accept files dragged from Finder.
struct FileDropTarget: ViewModifier {
    let serial: String
    @ObservedObject private var sender = FileSender.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if sender.targeted == serial {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.android[1], style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                        .background(Theme.android[1].opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            Label("Lepas untuk mengirim ke HP", systemImage: "arrow.down.doc.fill")
                                .font(.headline).foregroundStyle(Theme.android[1])
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let s = sender.status[serial] {
                    Label(L(s), systemImage: "arrow.up.doc").font(.caption.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(14)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sender.status[serial])
            .onDrop(of: [.fileURL], isTargeted: Binding(get: { sender.targeted == serial }, set: { sender.targeted = $0 ? serial : (sender.targeted == serial ? nil : sender.targeted) })) { providers in
                var urls: [URL] = []
                let group = DispatchGroup()
                for p in providers {
                    group.enter()
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url { DispatchQueue.main.async { urls.append(url) } }
                        group.leave()
                    }
                }
                group.notify(queue: .main) { sender.send(urls, to: serial) }
                return true
            }
    }
}

extension View {
    func acceptsFiles(for serial: String) -> some View { modifier(FileDropTarget(serial: serial)) }
}
