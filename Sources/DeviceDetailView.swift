import SwiftUI
import AppKit

/// What a device-detail sheet can do; Android (adb) and iOS (libimobiledevice) both provide this.
protocol DeviceBackend {
    var id: String { get }
    var supportsApps: Bool { get }
    var supportsPower: Bool { get }
    var accent: [Color] { get }
    func detail() async -> DeviceDetail
    func screenshot() async -> NSImage?
    func apps(includeSystem: Bool) async -> [InstalledApp]
    func uninstall(_ id: String) async -> String
    func install(_ file: URL) async -> String
    func power(off: Bool) async
}

struct AndroidBackend: DeviceBackend {
    let serial: String
    var id: String { serial }
    let supportsApps = true, supportsPower = true
    var accent: [Color] { Theme.android }
    func detail() async -> DeviceDetail { await AndroidInspector.load(serial: serial) }
    func screenshot() async -> NSImage? { await AndroidInspector.screenshot(serial: serial) }
    func apps(includeSystem: Bool) async -> [InstalledApp] { await AndroidInspector.apps(serial: serial, includeSystem: includeSystem) }
    func uninstall(_ id: String) async -> String { await AndroidInspector.uninstall(serial: serial, package: id) }
    func install(_ file: URL) async -> String { await AndroidInspector.install(serial: serial, apk: file) }
    func power(off: Bool) async { await AndroidInspector.reboot(serial: serial, powerOff: off) }
}

// MARK: - Sheet

struct DeviceDetailSheet: View {
    let backend: DeviceBackend
    @Environment(\.dismiss) private var dismiss

    @State private var detail: DeviceDetail?
    @State private var screen: NSImage?
    @State private var tab = 0
    @State private var apps: [InstalledApp] = []
    @State private var appsLoaded = false
    @State private var loadingApps = false
    @State private var showSystem = false
    @State private var query = ""
    @State private var confirmUninstall: InstalledApp?
    @State private var confirmPower: Bool?          // true = shutdown, false = restart
    @State private var toast: String?
    @State private var busy: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack {
                Picker("", selection: $tab) {
                    Text("Info perangkat").tag(0)
                    if backend.supportsApps { Text("Aplikasi\(appsLoaded ? " · \(apps.filter { !$0.system }.count)" : "")").tag(1) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                if let toast { Text(toast).font(.callout).foregroundStyle(.secondary).transition(.opacity) }
                Button("Selesai") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            Group {
                if tab == 0 { infoTab } else { appsTab }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 1080, height: 720)
        .background(Theme.canvas)
        .task { await reload() }
        .onChange(of: tab) { if tab == 1 && !appsLoaded { Task { await loadApps() } } }
        .alert("Uninstall \(confirmUninstall?.name ?? "")?", isPresented: Binding(get: { confirmUninstall != nil }, set: { if !$0 { confirmUninstall = nil } })) {
            Button("Uninstall", role: .destructive) { if let a = confirmUninstall { Task { await uninstall(a) } }; confirmUninstall = nil }
            Button("Batal", role: .cancel) { confirmUninstall = nil }
        } message: { Text("Aplikasi \(confirmUninstall?.id ?? "") beserta datanya akan dihapus dari perangkat.") }
        .alert(confirmPower == true ? "Matikan perangkat?" : "Restart perangkat?", isPresented: Binding(get: { confirmPower != nil }, set: { if !$0 { confirmPower = nil } })) {
            Button(confirmPower == true ? "Matikan" : "Restart", role: .destructive) {
                let off = confirmPower == true
                confirmPower = nil
                Task { await backend.power(off: off); flash(off ? "Perintah matikan dikirim" : "Perangkat sedang restart") }
            }
            Button("Batal", role: .cancel) { confirmPower = nil }
        } message: { Text(confirmPower == true ? "Sambungan akan terputus sampai perangkat dinyalakan lagi." : "Sambungan akan terputus sebentar selama perangkat restart.") }
    }

    private func reload() async {
        async let d = backend.detail()
        async let s = backend.screenshot()
        let (dd, ss) = await (d, s)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { detail = dd; screen = ss }
    }

    private func loadApps() async {
        loadingApps = true
        let list = await backend.apps(includeSystem: showSystem)
        withAnimation { apps = list; appsLoaded = true; loadingApps = false }
    }

    private func uninstall(_ a: InstalledApp) async {
        busy.insert(a.id)
        let out = await backend.uninstall(a.id)
        busy.remove(a.id)
        if out.localizedCaseInsensitiveContains("success") || out.isEmpty {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { apps.removeAll { $0.id == a.id } }
            flash("\(a.name) dihapus")
        } else {
            flash("Gagal: \(out.prefix(80))")
        }
    }

    private func flash(_ s: String) {
        withAnimation { toast = s }
        Task { try? await Task.sleep(for: .seconds(3)); withAnimation { if toast == s { toast = nil } } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 18) {
            IconBadge(icon: backend.accent == Theme.ios ? "iphone" : "smartphone", colors: backend.accent, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(detail?.title ?? "Membaca perangkat…").font(.title2.weight(.bold))
                Text(detail?.subtitle ?? " ").font(.callout).foregroundStyle(.secondary)
            }
            if let pill = detail?.storagePill, !pill.isEmpty {
                Text(pill).font(.callout.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
            Spacer()
            if let d = detail, let level = d.batteryLevel {
                HStack(spacing: 8) {
                    if let s = d.batteryState { Text(s).font(.callout).foregroundStyle(.secondary) }
                    if d.batteryState?.hasPrefix("Mengisi") == true { Image(systemName: "bolt.fill").foregroundStyle(Theme.live) }
                    BatteryGlyph(level: level)
                }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    // MARK: Info tab

    private var infoTab: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 16) {
                PhoneFrame(image: screen, tint: backend.accent[0])
                    .frame(width: 230, height: 460)
                HStack(spacing: 18) {
                    if backend.supportsPower {
                        Button { confirmPower = false } label: { Label("Restart", systemImage: "arrow.clockwise.circle") }
                        Button { confirmPower = true } label: { Label("Matikan", systemImage: "power") }
                    }
                    Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.triangle.2.circlepath") }
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }
            .frame(width: 270)

            Panel(padding: 18) {
                if let d = detail {
                    VStack(spacing: 0) {
                        ForEach(Array(d.specs.enumerated()), id: \.offset) { i, row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.label).foregroundStyle(.primary)
                                Spacer(minLength: 16)
                                Text(row.value).foregroundStyle(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled)
                                    .lineLimit(2)
                            }
                            .font(.callout)
                            .padding(.vertical, 8.5)
                            if i < d.specs.count - 1 { Divider() }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 14) {
                Panel(padding: 16) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Baterai").font(.headline)
                            if let h = detail?.batteryHealth { Text("Kondisi \(h)").font(.callout) }
                            if let c = detail?.batteryCycles { Text("Siklus isi ulang \(c)").font(.callout).foregroundStyle(.secondary) }
                            ForEach(detail?.batteryExtra ?? []) { r in Text("\(r.label) \(r.value)").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Ring(progress: Double(detail?.batteryLevel ?? 0) / 100, label: detail?.batteryLevel.map { "\($0)%" } ?? "–",
                             color: (detail?.batteryLevel ?? 100) < 20 ? .red : Theme.live)
                    }
                }
                Panel(padding: 16) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Penyimpanan").font(.headline)
                            if let t = detail?.storageTotal, let u = detail?.storageUsed {
                                Text("\(Fmt.bytes(u)) dipakai").font(.callout)
                                Text("\(Fmt.bytes(max(0, t - u))) tersedia").font(.callout).foregroundStyle(.secondary)
                            } else { Text("Membaca…").font(.callout).foregroundStyle(.secondary) }
                            if let r = detail?.ramTotal, let a = detail?.ramAvailable {
                                Text("RAM \(Fmt.bytes(r - a)) / \(Fmt.bytes(r))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        let frac = { () -> Double in
                            guard let t = detail?.storageTotal, let u = detail?.storageUsed, t > 0 else { return 0 }
                            return Double(u) / Double(t)
                        }()
                        Ring(progress: frac, label: "\(Int(frac * 100))%", color: backend.accent[1])
                    }
                }
                Panel(padding: 16) {
                    VStack(spacing: 0) {
                        ForEach(Array((detail?.status ?? []).enumerated()), id: \.offset) { i, row in
                            HStack { Text(row.label); Spacer(); Text(row.value).foregroundStyle(.secondary).lineLimit(1) }
                                .font(.callout).padding(.vertical, 7)
                            if i < (detail?.status.count ?? 0) - 1 { Divider() }
                        }
                    }
                }
            }
            .frame(width: 330)
        }
        .padding(.horizontal, 22).padding(.bottom, 20)
    }

    // MARK: Apps tab

    private var filtered: [InstalledApp] {
        let q = query.lowercased()
        return apps.filter { (showSystem || !$0.system) && (q.isEmpty || $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q)) }
    }

    private var appsTab: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Cari aplikasi", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                .frame(maxWidth: 320)
                Toggle("Tampilkan aplikasi sistem", isOn: $showSystem)
                    .toggleStyle(.checkbox)
                    .onChange(of: showSystem) { Task { await loadApps() } }
                Spacer()
                if loadingApps { ProgressView().controlSize(.small) }
                Button { Task { await loadApps() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                if backend.accent == Theme.android {
                    Button {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.init(filenameExtension: "apk")!]
                        panel.prompt = "Pasang"
                        if panel.runModal() == .OK, let url = panel.url {
                            Task {
                                flash("Memasang \(url.lastPathComponent)…")
                                let out = await backend.install(url)
                                flash(out.contains("Success") ? "\(url.lastPathComponent) terpasang" : "Gagal: \(out.suffix(80))")
                                await loadApps()
                            }
                        }
                    } label: { Label("Pasang APK…", systemImage: "plus.app") }
                    .buttonStyle(SoftButtonStyle(tint: backend.accent[1])).fixedSize()
                }
            }
            Panel(padding: 0) {
                if !appsLoaded {
                    VStack(spacing: 10) { ProgressView(); Text("Membaca daftar aplikasi…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    Text(query.isEmpty ? "Tidak ada aplikasi." : "Tidak ada yang cocok dengan “\(query)”.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { app in
                                AppRow(app: app, tint: backend.accent, busy: busy.contains(app.id)) { confirmUninstall = app }
                                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 22).padding(.bottom, 20)
    }
}

// MARK: - Pieces

private struct AppRow: View {
    let app: InstalledApp
    let tint: [Color]
    let busy: Bool
    let onUninstall: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            let hue = Double(abs(app.id.hashValue % 360)) / 360
            Text(String(app.name.prefix(1)).uppercased())
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(hue: hue, saturation: 0.5, brightness: 0.75), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.callout.weight(.semibold))
                    if app.system { Pill(text: "Sistem", color: .secondary) }
                }
                Text(app.id).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !app.version.isEmpty { Text("v\(app.version)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 160, alignment: .trailing) }
            if !app.installed.isEmpty { Text(app.installed).font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 84, alignment: .trailing) }
            if busy { ProgressView().controlSize(.small).frame(width: 96) }
            else if !app.system {
                Button("Uninstall", action: onUninstall)
                    .buttonStyle(SoftButtonStyle(tint: .red))
                    .frame(width: 96)
                    .opacity(hover ? 1 : 0.75)
            } else { Color.clear.frame(width: 96, height: 1) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(hover ? Color.primary.opacity(0.03) : .clear)
        .onHover { hover = $0 }
    }
}

struct Ring: View {
    let progress: Double
    let label: String
    let color: Color
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 7)
            Circle().trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label).font(.system(size: 17, weight: .bold).monospacedDigit())
        }
        .frame(width: 78, height: 78)
        .onAppear { withAnimation(.spring(response: 1.0, dampingFraction: 0.85).delay(0.15)) { shown = progress } }
        .onChange(of: progress) { withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) { shown = progress } }
    }
}

private struct BatteryGlyph: View {
    let level: Int
    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5).frame(width: 40, height: 20)
                RoundedRectangle(cornerRadius: 2.5).fill(level < 20 ? Color.red : Theme.live)
                    .frame(width: max(3, 34 * CGFloat(level) / 100), height: 14).padding(.leading, 3)
                Text("\(level)").font(.system(size: 11, weight: .bold).monospacedDigit()).frame(width: 40)
                    .foregroundStyle(level > 45 ? .white : .primary)
            }
            RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.35)).frame(width: 2.5, height: 7)
        }
    }
}

/// A phone bezel showing the device's current screen.
struct PhoneFrame: View {
    let image: NSImage?
    let tint: Color

    var body: some View {
        GeometryReader { g in
            let ratio: CGFloat = image.map { $0.size.width / max($0.size.height, 1) } ?? 9 / 19.5
            let h = g.size.height, w = min(g.size.width, h * ratio + 18)
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .fill(Color(white: 0.08))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 12)
                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .strokeBorder(tint.opacity(0.55), lineWidth: 2)
                Group {
                    if let image {
                        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    } else {
                        ZStack { Color(white: 0.14); ProgressView().controlSize(.small).tint(.white) }
                    }
                }
                .frame(width: w - 16, height: h - 16)
                .clipShape(RoundedRectangle(cornerRadius: w * 0.13, style: .continuous))
            }
            .frame(width: w, height: h)
            .frame(maxWidth: .infinity)
        }
    }
}
