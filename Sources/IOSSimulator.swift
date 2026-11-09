import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - iPhone / iPad simulators through Xcode's simctl
//
// Apple only ships the iOS Simulator inside Xcode (free on the App Store) and its license does not allow
// redistributing it, so Djie Cast drives the user's own Xcode: it lists runtimes and devices, creates and
// boots simulators, installs apps and takes screenshots. On Apple Silicon the simulator runs natively.

struct SimRuntime: Identifiable, Hashable {
    let id: String              // com.apple.CoreSimulator.SimRuntime.iOS-27-0
    let name: String            // iOS 27.0
    let version: String
    let types: [SimType]
}

struct SimType: Identifiable, Hashable {
    let id: String
    let name: String
    let family: String          // iPhone / iPad
}

struct SimDevice: Identifiable, Hashable {
    let id: String              // UDID
    let name: String
    let state: String           // Booted / Shutdown / Booting
    let runtime: String         // runtime identifier
    let typeID: String
    var booted: Bool { state == "Booted" }
}

@MainActor
final class SimulatorModel: ObservableObject {
    static let shared = SimulatorModel()

    enum XcodeState: Equatable { case checking, missing, commandLineOnly(String), ready(String) }
    @Published var xcode: XcodeState = .checking
    @Published var runtimes: [SimRuntime] = []
    @Published var devices: [SimDevice] = []
    @Published var busy: Set<String> = []
    @Published var shots: [String: NSImage] = [:]
    @Published var message: String?
    @Published var downloading = false
    @Published var downloadProgress: Double?
    @Published var downloadLine = ""
    /// True after the first successful read, so "download iOS" is not shown while still loading.
    @Published var loaded = false

    var bootedCount: Int { devices.filter(\.booted).count }
    private var downloadProcess: Process?

    // MARK: Discovery

    func refresh(shots withShots: Bool = true) async {
        if Demo.enabled { demo(); return }
        let path = (await run("/usr/bin/xcode-select", ["-p"])).trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty || path.hasPrefix("Error") {
            xcode = Self.xcodeApps().isEmpty ? .missing : .commandLineOnly(Self.xcodeApps()[0])
            return
        }
        if path.contains("CommandLineTools") {
            xcode = Self.xcodeApps().isEmpty ? .missing : .commandLineOnly(Self.xcodeApps()[0])
            return
        }
        xcode = .ready(path)
        let out = await run("/usr/bin/xcrun", ["simctl", "list", "-j", "runtimes", "devices"], stdoutOnly: true)
        let json = out.firstIndex(of: "{").map { String(out[$0...]) } ?? out
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            message = String(localized: "Tidak bisa membaca daftar simulator dari Xcode.")
            return
        }
        defer { loaded = true }
        let rts = (root["runtimes"] as? [[String: Any]] ?? []).compactMap { r -> SimRuntime? in
            guard let id = r["identifier"] as? String, id.contains(".iOS-"), (r["isAvailable"] as? Bool) == true else { return nil }
            let types = (r["supportedDeviceTypes"] as? [[String: Any]] ?? []).compactMap { t -> SimType? in
                guard let tid = t["identifier"] as? String, let n = t["name"] as? String,
                      let fam = t["productFamily"] as? String, fam == "iPhone" || fam == "iPad" else { return nil }
                return SimType(id: tid, name: n, family: fam)
            }
            return SimRuntime(id: id, name: (r["name"] as? String) ?? id, version: (r["version"] as? String) ?? "", types: types)
        }
        runtimes = rts.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
        var list: [SimDevice] = []
        for (rt, arr) in root["devices"] as? [String: [[String: Any]]] ?? [:] where rt.contains(".iOS-") {
            for d in arr where (d["isAvailable"] as? Bool) == true {
                guard let udid = d["udid"] as? String, let name = d["name"] as? String else { continue }
                list.append(SimDevice(id: udid, name: name, state: (d["state"] as? String) ?? "Shutdown",
                                      runtime: rt, typeID: (d["deviceTypeIdentifier"] as? String) ?? ""))
            }
        }
        list.sort { ($0.booted ? 0 : 1, $0.name) < ($1.booted ? 0 : 1, $1.name) }
        if list != devices { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { devices = list } }
        if withShots { for d in list where d.booted { await snapshot(d) } }
    }

    static func xcodeApps() -> [String] {
        let apps = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
        return apps.filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }.map { "/Applications/" + $0 }.sorted()
    }

    func runtimeName(_ id: String) -> String {
        runtimes.first { $0.id == id }?.name ?? id.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "iOS ", with: "iOS ")
    }

    func typeName(_ id: String) -> String {
        for r in runtimes { if let t = r.types.first(where: { $0.id == id }) { return t.name } }
        return id.replacingOccurrences(of: "com.apple.CoreSimulator.SimDeviceType.", with: "").replacingOccurrences(of: "-", with: " ")
    }

    // MARK: Actions

    func create(name: String, type: SimType, runtime: SimRuntime) async {
        let n = name.trimmingCharacters(in: .whitespaces).isEmpty ? type.name : name
        busy.insert("create")
        let out = await run("/usr/bin/xcrun", ["simctl", "create", n, type.id, runtime.id])
        busy.remove("create")
        if out.contains("Error") || out.contains("Invalid") { message = out.trimmingCharacters(in: .whitespacesAndNewlines) }
        else { message = nil }
        await refresh()
    }

    /// Boots the device first (fast, no window) and then brings up Simulator.app on exactly that device.
    func boot(_ d: SimDevice) async {
        busy.insert(d.id)
        _ = await run("/usr/bin/xcrun", ["simctl", "boot", d.id])
        _ = await run("/usr/bin/open", ["-a", "Simulator", "--args", "-CurrentDeviceUDID", d.id])
        _ = await run("/usr/bin/xcrun", ["simctl", "bootstatus", d.id, "-b"])
        busy.remove(d.id)
        await refresh()
    }

    func shutdown(_ d: SimDevice) async {
        busy.insert(d.id)
        _ = await run("/usr/bin/xcrun", ["simctl", "shutdown", d.id])
        busy.remove(d.id)
        shots[d.id] = nil
        await refresh()
    }

    func erase(_ d: SimDevice) async {
        busy.insert(d.id)
        if d.booted { _ = await run("/usr/bin/xcrun", ["simctl", "shutdown", d.id]) }
        _ = await run("/usr/bin/xcrun", ["simctl", "erase", d.id])
        busy.remove(d.id)
        await refresh()
    }

    func delete(_ d: SimDevice) async {
        busy.insert(d.id)
        if d.booted { _ = await run("/usr/bin/xcrun", ["simctl", "shutdown", d.id]) }
        _ = await run("/usr/bin/xcrun", ["simctl", "delete", d.id])
        busy.remove(d.id)
        await refresh()
    }

    func showWindow(_ d: SimDevice) {
        Task { _ = await run("/usr/bin/open", ["-a", "Simulator", "--args", "-CurrentDeviceUDID", d.id]) }
    }

    /// Installs a simulator build (.app) — device builds (.ipa for real iPhones) do not run on the simulator.
    func install(_ d: SimDevice, url: URL) async {
        busy.insert(d.id)
        let out = await run("/usr/bin/xcrun", ["simctl", "install", d.id, url.path])
        busy.remove(d.id)
        message = out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "\(url.deletingPathExtension().lastPathComponent) terpasang di \(d.name).")
            : out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func openURL(_ d: SimDevice, _ link: String) {
        Task { _ = await run("/usr/bin/xcrun", ["simctl", "openurl", d.id, link]) }
    }

    func saveScreenshot(_ d: SimDevice) {
        Task {
            let desk = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let url = desk.appendingPathComponent("\(d.name) \(f.string(from: Date())).png")
            _ = await run("/usr/bin/xcrun", ["simctl", "io", d.id, "screenshot", url.path])
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func snapshot(_ d: SimDevice) async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("djiecast-sim-\(d.id).png")
        _ = await run("/usr/bin/xcrun", ["simctl", "io", d.id, "screenshot", "--type=png", tmp.path])
        if let img = NSImage(contentsOf: tmp) { shots[d.id] = img }
    }

    // MARK: Runtime download (xcodebuild -downloadPlatform iOS)

    func downloadRuntime() {
        guard !downloading else { return }
        downloading = true; downloadProgress = nil; downloadLine = String(localized: "Menyiapkan unduhan…")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["xcodebuild", "-downloadPlatform", "iOS"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                guard let self else { return }
                if let line = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).last.map(String.init) {
                    self.downloadLine = line.trimmingCharacters(in: .whitespaces)
                }
                if let m = text.range(of: #"(\d+(\.\d+)?)%"#, options: [.regularExpression, .backwards]),
                   let v = Double(text[m].dropLast()) { self.downloadProgress = v / 100 }
            }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                self.downloading = false
                self.downloadProcess = nil
                self.downloadLine = proc.terminationStatus == 0 ? String(localized: "Runtime iOS terpasang.") : String(localized: "Unduhan berhenti (kode \(proc.terminationStatus)).")
                await self.refresh()
            }
        }
        do { try p.run(); downloadProcess = p } catch { downloading = false; downloadLine = error.localizedDescription }
    }

    func cancelDownload() { downloadProcess?.terminate() }

    // MARK: Helpers

    private func run(_ exe: String, _ args: [String], stdoutOnly: Bool = false) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                let pipe = Pipe(); p.standardOutput = pipe
                p.standardError = stdoutOnly ? FileHandle.nullDevice : pipe   // JSON must not mix with warnings
                do {
                    try p.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    cont.resume(returning: String(decoding: data, as: UTF8.self))
                } catch { cont.resume(returning: "Error: \(error.localizedDescription)") }
            }
        }
    }

    private func demo() {
        loaded = true
        xcode = .ready("/Applications/Xcode.app/Contents/Developer")
        let types = [SimType(id: "t17p", name: "iPhone 17 Pro", family: "iPhone"), SimType(id: "t17", name: "iPhone 17", family: "iPhone"),
                     SimType(id: "tair", name: "iPhone Air", family: "iPhone"), SimType(id: "tipad", name: "iPad Pro 13-inch (M5)", family: "iPad")]
        runtimes = [SimRuntime(id: "rt27", name: "iOS 27.0", version: "27.0", types: types)]
        devices = [SimDevice(id: "D1", name: "iPhone 17 Pro", state: "Booted", runtime: "rt27", typeID: "t17p"),
                   SimDevice(id: "D2", name: "iPhone Air", state: "Shutdown", runtime: "rt27", typeID: "tair"),
                   SimDevice(id: "D3", name: "iPad Pro 13-inch (M5)", state: "Shutdown", runtime: "rt27", typeID: "tipad")]
        shots["D1"] = Demo.lockScreen(false)
    }
}

// MARK: - Page

struct IOSSimulatorView: View {
    @ObservedObject private var model = SimulatorModel.shared
    @State private var name = ""
    @State private var runtimeID = ""
    @State private var typeID = ""
    @State private var confirmDelete: SimDevice?
    @State private var urlFor: SimDevice?
    @State private var link = "https://"

    private var runtime: SimRuntime? { model.runtimes.first { $0.id == runtimeID } ?? model.runtimes.first }
    private var type: SimType? {
        guard let r = runtime else { return nil }
        return r.types.first { $0.id == typeID } ?? r.types.first { $0.family == "iPhone" } ?? r.types.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(icon: "iphone", colors: Theme.ios, title: "Simulator iPhone",
                           subtitle: "iPhone & iPad virtual dari Xcode, berjalan native dan cepat di Mac") {
                    if model.bootedCount > 0 {
                        HStack(spacing: 7) { PulseDot(); Text("\(model.bootedCount) berjalan").font(.callout.weight(.medium)) }
                    }
                }

                switch model.xcode {
                case .checking:
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Memeriksa Xcode…").foregroundStyle(.secondary) }
                case .missing:
                    xcodeMissing
                case .commandLineOnly(let app):
                    xcodeSelect(app)
                case .ready:
                    if let msg = model.message {
                        Label(L(msg), systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !model.loaded {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Membaca simulator…").foregroundStyle(.secondary) }
                    } else if model.runtimes.isEmpty { runtimeMissing } else {
                        myDevices
                        createPanel
                    }
                    speedNote
                }
            }
            .padding(28)
        }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .alert("Hapus simulator “\(confirmDelete?.name ?? "")”?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Hapus", role: .destructive) { if let d = confirmDelete { Task { await model.delete(d) } }; confirmDelete = nil }
            Button("Batal", role: .cancel) { confirmDelete = nil }
        } message: { Text("Aplikasi dan data di dalam simulator ini ikut terhapus.") }
        .alert("Buka link di simulator", isPresented: Binding(get: { urlFor != nil }, set: { if !$0 { urlFor = nil } })) {
            TextField("https://…", text: $link)
            Button("Buka") { if let d = urlFor { model.openURL(d, link) }; urlFor = nil }
            Button("Batal", role: .cancel) { urlFor = nil }
        }
        .toolbar {
            ToolbarItem {
                Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Muat ulang daftar simulator")
            }
        }
    }

    // MARK: States without Xcode

    private var xcodeMissing: some View {
        Panel(padding: 22) {
            HStack(alignment: .top, spacing: 16) {
                IconBadge(icon: "hammer.fill", colors: Theme.ios, size: 48)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Butuh Xcode dari Apple (gratis)").font(.title3.weight(.bold))
                    Text("Simulator iPhone hanya disediakan Apple di dalam Xcode dan tidak boleh dibundel ke aplikasi lain. Pasang Xcode sekali dari App Store, lalu Djie Cast mengurus sisanya: membuat, menjalankan, dan mengelola simulator.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 6) {
                        step(1, "Pasang Xcode dari App Store (sekitar 3 GB)")
                        step(2, "Buka Xcode sekali dan setujui lisensinya")
                        step(3, "Kembali ke sini — runtime iOS bisa diunduh langsung dari Djie Cast")
                    }
                    HStack(spacing: 10) {
                        Button { NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/xcode/id497799835")!) } label: {
                            Label("Buka Xcode di App Store", systemImage: "arrow.down.app.fill")
                        }
                        .buttonStyle(GradientButtonStyle(colors: Theme.ios)).fixedSize()
                        Button("Periksa lagi") { Task { await model.refresh() } }.buttonStyle(SoftButtonStyle(tint: Theme.ios[1])).fixedSize()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func xcodeSelect(_ app: String) -> some View {
        Panel(padding: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Xcode ada, tapi belum dipilih sebagai alat developer", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.orange)
                Text("Jalankan perintah ini sekali di Terminal (minta kata sandi Mac), lalu tekan Periksa lagi:")
                    .foregroundStyle(.secondary)
                Text(verbatim: "sudo xcode-select -s \"\(app)\"").font(.callout.monospaced()).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("Salin perintah") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("sudo xcode-select -s \"\(app)\"", forType: .string)
                    }.buttonStyle(SoftButtonStyle(tint: Theme.ios[1])).fixedSize()
                    Button("Periksa lagi") { Task { await model.refresh() } }.buttonStyle(.borderless)
                }
            }
        }
    }

    private var runtimeMissing: some View {
        Panel(padding: 22) {
            HStack(alignment: .top, spacing: 16) {
                IconBadge(icon: "square.and.arrow.down.fill", colors: Theme.ios, size: 48)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Unduh runtime iOS").font(.title3.weight(.bold))
                    Text("Xcode sudah siap, tinggal sistem iOS untuk simulatornya (sekitar 8 GB, langsung dari Apple).")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.downloading {
                        if let p = model.downloadProgress { ProgressView(value: p).tint(Theme.ios[1]) } else { ProgressView().progressViewStyle(.linear) }
                        HStack {
                            Text(model.downloadLine).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Button("Batal") { model.cancelDownload() }.buttonStyle(.borderless)
                        }
                    } else {
                        if !model.downloadLine.isEmpty { Text(L(model.downloadLine)).font(.caption).foregroundStyle(.secondary) }
                        Button { model.downloadRuntime() } label: { Label("Unduh iOS", systemImage: "arrow.down.circle.fill") }
                            .buttonStyle(GradientButtonStyle(colors: Theme.ios)).fixedSize()
                    }
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(format: "%02d", n)).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.ios[1])
            Text(L(text)).font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: Devices

    private var myDevices: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Simulator saya", detail: model.devices.isEmpty ? nil : "· \(model.devices.count)")
            if model.devices.isEmpty {
                Panel(padding: 18) {
                    Text("Belum ada simulator. Buat satu di bawah.").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.devices.filter(\.booted)) { d in runningCard(d) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(model.devices.filter { !$0.booted }) { d in smallCard(d) }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.devices)
    }

    private func runningCard(_ d: SimDevice) -> some View {
        Panel(highlight: Theme.live, padding: 20) {
            HStack(alignment: .top, spacing: 24) {
                PhoneFrame(image: model.shots[d.id], tint: Theme.ios[0]).frame(width: 128, height: 264)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L(d.name)).font(.title2.weight(.bold)).lineLimit(1)
                            Text(verbatim: "\(model.typeName(d.typeID)) · \(model.runtimeName(d.runtime))").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        LiveBadge()
                        Pill(text: "Simulator", icon: "hammer", color: .secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                        spec("Sistem", model.runtimeName(d.runtime))
                        spec("Perangkat", model.typeName(d.typeID))
                        spec("Arsitektur", "arm64 · native")
                        spec("UDID", d.id)
                    }
                    FlowLayout(spacing: 10) {
                        Button { model.showWindow(d) } label: { Label("Tampilkan jendela", systemImage: "macwindow") }
                            .buttonStyle(GradientButtonStyle(colors: Theme.ios)).fixedSize()
                        Button { pickApp(for: d) } label: { Label("Pasang app (.app)", systemImage: "square.and.arrow.down") }
                            .buttonStyle(SoftButtonStyle(tint: Theme.ios[1])).fixedSize()
                        Button { model.saveScreenshot(d) } label: { Label("Screenshot", systemImage: "camera") }
                            .buttonStyle(SoftButtonStyle(tint: Theme.ios[1])).fixedSize()
                        Button { urlFor = d } label: { Label("Buka link", systemImage: "link") }
                            .buttonStyle(SoftButtonStyle(tint: Theme.ios[1])).fixedSize()
                        Button { Task { await model.shutdown(d) } } label: {
                            if model.busy.contains(d.id) { ProgressView().controlSize(.small) } else { Label("Matikan", systemImage: "stop.fill") }
                        }
                        .buttonStyle(SoftButtonStyle(tint: .red)).fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func smallCard(_ d: SimDevice) -> some View {
        Panel(fill: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    IconBadge(icon: model.typeName(d.typeID).hasPrefix("iPad") ? "ipad" : "iphone", colors: Theme.ios, size: 40)
                    Spacer()
                    Menu {
                        Button("Reset isi (hapus semua data)", systemImage: "arrow.counterclockwise") { Task { await model.erase(d) } }
                        Divider()
                        Button("Hapus…", systemImage: "trash", role: .destructive) { confirmDelete = d }
                    } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L(d.name)).font(.headline).lineLimit(1)
                    Text(verbatim: model.runtimeName(d.runtime)).font(.caption).foregroundStyle(.secondary)
                }
                Button { Task { await model.boot(d) } } label: {
                    if model.busy.contains(d.id) {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Menyalakan…") }
                    } else { Label("Jalankan", systemImage: "play.fill") }
                }
                .buttonStyle(GradientButtonStyle(colors: Theme.ios))
                .disabled(model.busy.contains(d.id))
            }
        }
    }

    private func spec(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L(label).uppercased()).font(.system(size: 9.5, weight: .semibold)).kerning(0.6).foregroundStyle(.tertiary)
            Text(verbatim: value).font(.callout).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
    }

    private func pickApp(for d: SimDevice) {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Pilih build simulator (.app) untuk dipasang di \(d.name)")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.install(d, url: url) }
    }

    // MARK: Create

    private var createPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Buat simulator baru")
            Panel(padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Nama").foregroundStyle(.secondary)
                            TextField(type?.name ?? "iPhone", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                        }
                        GridRow {
                            Text("Sistem").foregroundStyle(.secondary)
                            Picker("", selection: Binding(get: { runtime?.id ?? "" }, set: { runtimeID = $0; typeID = "" })) {
                                ForEach(model.runtimes) { r in Text(verbatim: r.name).tag(r.id) }
                            }
                            .labelsHidden().fixedSize()
                        }
                        GridRow {
                            Text("Perangkat").foregroundStyle(.secondary)
                            Picker("", selection: Binding(get: { type?.id ?? "" }, set: { typeID = $0 })) {
                                Section("iPhone") { ForEach(runtime?.types.filter { $0.family == "iPhone" } ?? []) { t in Text(verbatim: t.name).tag(t.id) } }
                                Section("iPad") { ForEach(runtime?.types.filter { $0.family == "iPad" } ?? []) { t in Text(verbatim: t.name).tag(t.id) } }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                    Button {
                        guard let t = type, let r = runtime else { return }
                        Task { await model.create(name: name, type: t, runtime: r); name = "" }
                    } label: {
                        if model.busy.contains("create") { ProgressView().controlSize(.small) } else { Label("Buat simulator", systemImage: "plus") }
                    }
                    .buttonStyle(GradientButtonStyle(colors: Theme.ios)).fixedSize()
                    .disabled(type == nil || model.busy.contains("create"))
                }
            }
        }
    }

    private var speedNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.fill").foregroundStyle(Theme.ios[1])
            Text("Kenapa cepat: di Mac Apple Silicon, simulator menjalankan iOS versi arm64 langsung di chip Mac, memakai GPU lewat Metal — tanpa emulasi. Djie Cast menyalakan perangkat dulu di latar belakang, baru membuka jendelanya. Di Mac Intel simulator tetap berjalan, tapi lebih berat.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}
