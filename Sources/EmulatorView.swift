import SwiftUI
import AppKit

extension Theme {
    static let emulator = [Color(red: 0.25, green: 0.78, blue: 0.62), Color(red: 0.05, green: 0.52, blue: 0.47)]
}

extension SystemImageOption {
    /// Builds an option for an image that is already on disk (catalog may not list it).
    static func local(_ path: String) -> SystemImageOption? {
        let p = path.split(separator: ";").map(String.init)
        guard p.count == 4 else { return nil }
        return SystemImageOption(path: path, api: p[1].replacingOccurrences(of: "android-", with: ""), tag: p[2], abi: p[3],
                                 archive: SDKArchive(url: URL(string: "about:blank")!, size: 0, sha1: ""), license: "")
    }
}

struct EmulatorView: View {
    @ObservedObject var model = EmulatorModel.shared
    @AppStorage("emuNoBootAnim") private var noBootAnim = true
    @AppStorage("emuQuickBoot") private var quickBoot = true
    @AppStorage("emuShowWindow") private var showWindow = true

    @State private var name = "Pixel Djie"
    @State private var profile = DeviceProfile.all[0]
    @State private var imagePath = ""
    @State private var ramGB = 4
    @State private var cores = 4
    @State private var storageGB = 16
    @State private var showAllImages = false
    @State private var licenseFor: (id: String, action: () -> Void)?
    @State private var confirmDelete: AVD?
    @State private var createError: String?

    private var installedOptions: [SystemImageOption] {
        model.installedImages.sorted().reversed().compactMap { path in
            model.images.first { $0.path == path } ?? SystemImageOption.local(path)
        }
    }
    private var selectedImage: SystemImageOption? { installedOptions.first { $0.path == imagePath } ?? installedOptions.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(icon: "apps.iphone", colors: Theme.emulator, title: "Emulator Android",
                           subtitle: "Pilih bahan yang mau diunduh, buat emulator, jalankan dengan cepat") {
                    if !model.running.isEmpty {
                        HStack(spacing: 7) { PulseDot(); Text("\(model.running.count) berjalan").font(.callout.weight(.medium)) }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.live.opacity(0.1), in: Capsule())
                    }
                }
                .appearIn(0)

                if let d = model.download { downloadBar(d).transition(.move(edge: .top).combined(with: .opacity)) }
                if let e = model.errorText {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                }

                myEmulators.appearIn(0.05)
                createPanel.appearIn(0.1)
                ingredients.appearIn(0.15)
                launchSettings.appearIn(0.2)
            }
            .padding(28)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.download?.title)
        }
        .task {
            model.refresh()
            if model.images.isEmpty { await model.loadCatalog() }
        }
        .sheet(item: Binding(get: { licenseFor.map { LicenseItem(id: $0.id) } }, set: { if $0 == nil { licenseFor = nil } })) { item in
            LicenseSheet(id: item.id, text: model.licenses[item.id] ?? "") {
                model.accept(item.id)
                let action = licenseFor?.action
                licenseFor = nil
                action?()
            } onCancel: { licenseFor = nil }
        }
        .alert("Hapus emulator “\(confirmDelete?.displayName ?? "")”?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Hapus", role: .destructive) { if let a = confirmDelete { withAnimation { model.delete(a) } }; confirmDelete = nil }
            Button("Batal", role: .cancel) { confirmDelete = nil }
        } message: { Text("Data dan aplikasi di dalam emulator ini ikut terhapus. Bahan (system image) tetap tersimpan.") }
    }

    private func requireLicense(_ id: String, then action: @escaping () -> Void) {
        if id.isEmpty || model.accepted(id) { action() } else { licenseFor = (id, action) }
    }

    // MARK: Download progress

    private func downloadBar(_ d: (title: String, received: Int64, total: Int64, phase: String)) -> some View {
        Panel(highlight: Theme.emulator[0]) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.emulator[1])
                    Text("\(d.phase): \(d.title)").font(.callout.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text("\(ByteCountFormatter.string(fromByteCount: d.received, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: d.total, countStyle: .file))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if d.phase == "Mengunduh" {
                        Button("Batal") { model.cancelDownload() }.buttonStyle(.borderless)
                    }
                }
                ProgressView(value: d.total > 0 ? Double(d.received) / Double(d.total) : 0)
                    .tint(Theme.emulator[1])
            }
        }
    }

    // MARK: My emulators

    private var myEmulators: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Emulator saya", detail: model.avds.isEmpty ? nil : "· \(model.avds.count)")
            if model.avds.isEmpty {
                Panel(padding: 18) {
                    Text("Belum ada emulator. Unduh bahan di bawah, lalu buat emulator pertamamu.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(model.avds) { avd in avdCard(avd).transition(.scale(scale: 0.94).combined(with: .opacity)) }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.avds.map(\.name))
            }
        }
    }

    private func avdCard(_ avd: AVD) -> some View {
        let isRunning = model.running.contains(avd.name)
        return Panel(highlight: isRunning ? Theme.live : nil, fill: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    IconBadge(icon: "apps.iphone", colors: Theme.emulator, size: 40)
                    Spacer()
                    if isRunning { LiveBadge() }
                    if avd.playStore { Pill(text: "Google Play", color: Theme.emulator[1]) }
                    Menu {
                        Button("Cold boot (mulai bersih)", systemImage: "snowflake") { model.start(avd, coldBoot: true) }.disabled(isRunning)
                        Button("Cast di Djie Cast", systemImage: "rectangle.on.rectangle") { Nav.shared.page = .android }.disabled(!isRunning)
                        Button("Tampilkan di Finder", systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([AndroidSDK.avdHome.appendingPathComponent("\(avd.name).avd")])
                        }
                        Divider()
                        Button("Hapus…", systemImage: "trash", role: .destructive) { confirmDelete = avd }
                    } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(avd.displayName).font(.headline).lineLimit(1)
                    Text("\(AndroidSDK.androidName(api: avd.api)) · \(avd.ramMB / 1024) GB RAM · \(avd.cores) core")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if isRunning {
                    Button { model.stop(avd) } label: { Label("Hentikan", systemImage: "stop.fill") }
                        .buttonStyle(SoftButtonStyle(tint: .red))
                } else {
                    Button { model.start(avd) } label: { Label("Jalankan", systemImage: "play.fill") }
                        .buttonStyle(GradientButtonStyle(colors: Theme.emulator))
                        .disabled(model.installedEmulator == nil)
                }
            }
        }
    }

    // MARK: Create

    private var createPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Buat emulator baru")
            Panel(padding: 20) {
                if !model.ready {
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox").font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bahan belum lengkap").font(.headline)
                            Text("Unduh **Android Emulator** dan minimal **satu system image** di bagian Bahan. Kamu yang pilih versi Android-nya.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            GridRow {
                                Text("Nama").foregroundStyle(.secondary)
                                TextField("Nama emulator", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                            }
                            GridRow {
                                Text("Perangkat").foregroundStyle(.secondary)
                                Picker("", selection: $profile) {
                                    ForEach(DeviceProfile.all) { p in Label(p.title, systemImage: p.icon).tag(p) }
                                }
                                .pickerStyle(.segmented).labelsHidden().fixedSize()
                            }
                            GridRow {
                                Text("Android").foregroundStyle(.secondary)
                                Picker("", selection: Binding(get: { selectedImage?.path ?? "" }, set: { imagePath = $0 })) {
                                    ForEach(installedOptions) { o in Text("\(o.title) · \(o.subtitle)").tag(o.path) }
                                }
                                .labelsHidden().frame(maxWidth: 380)
                            }
                            GridRow {
                                Text("Performa").foregroundStyle(.secondary)
                                HStack(spacing: 10) {
                                    Picker("RAM", selection: $ramGB) { ForEach([2, 3, 4, 6, 8], id: \.self) { Text("\($0) GB RAM").tag($0) } }.fixedSize()
                                    Picker("CPU", selection: $cores) { ForEach([2, 4, 6, 8], id: \.self) { Text("\($0) core").tag($0) } }.fixedSize()
                                    Picker("Penyimpanan", selection: $storageGB) { ForEach([8, 16, 32, 64], id: \.self) { Text("\($0) GB").tag($0) } }.fixedSize()
                                }
                                .labelsHidden()
                            }
                        }
                        HStack(spacing: 12) {
                            Button {
                                guard let img = selectedImage else { return }
                                do {
                                    try model.createAVD(name: name, profile: profile, image: img, ramMB: ramGB * 1024, cores: cores, storageGB: storageGB)
                                    createError = nil
                                } catch { createError = error.localizedDescription }
                            } label: { Label("Buat emulator", systemImage: "plus") }
                            .buttonStyle(GradientButtonStyle(colors: Theme.emulator)).fixedSize()
                            if let createError { Text(createError).font(.callout).foregroundStyle(.orange) }
                        }
                        Text(previewCommand)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var previewCommand: String {
        let n = name.replacingOccurrences(of: " ", with: "_")
        var parts = ["emulator -avd \(n) -gpu host -accel on -cores \(cores)"]
        if noBootAnim { parts.append("-no-boot-anim") }
        if !quickBoot { parts.append("-no-snapshot-load") }
        if !showWindow { parts.append("-no-window") }
        parts.append("-qemu -m \(ramGB * 1024)")
        return "$ " + parts.joined(separator: " ")
    }

    // MARK: Ingredients (user picks what to download)

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Bahan", detail: "· unduh sesuai kebutuhan, dari server resmi Google")
            Panel(padding: 0) {
                VStack(spacing: 0) {
                    if let state = model.catalogState {
                        HStack(spacing: 10) {
                            if state.hasPrefix("Memuat") { ProgressView().controlSize(.small) }
                            Text(state).font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            if !state.hasPrefix("Memuat") { Button("Coba lagi") { Task { await model.loadCatalog() } } }
                        }
                        .padding(16)
                        Divider()
                    }
                    emulatorRow
                    ForEach(visibleImages) { img in
                        Divider().padding(.leading, 16)
                        imageRow(img)
                    }
                    if model.images.count > 6 {
                        Divider()
                        Button(showAllImages ? "Tampilkan lebih sedikit" : "Tampilkan semua versi (\(model.images.count))") {
                            withAnimation { showAllImages.toggle() }
                        }
                        .buttonStyle(.borderless).padding(12)
                    }
                }
            }
            Text("Lokasi: \(AndroidSDK.root.path) — sama dengan Android Studio, jadi bahan bisa dipakai bersama.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var visibleImages: [SystemImageOption] {
        let installedFirst = model.images.filter { model.installedImages.contains($0.path) } + model.images.filter { !model.installedImages.contains($0.path) }
        return showAllImages ? installedFirst : Array(installedFirst.prefix(6))
    }

    private var emulatorRow: some View {
        HStack(spacing: 14) {
            IconBadge(icon: "cpu", colors: Theme.emulator, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Android Emulator").font(.callout.weight(.semibold))
                Group {
                    if let v = model.installedEmulator { Text("Terpasang \(v)") } else { Text("Wajib · mesin emulatornya") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let pkg = model.emulatorPackage {
                let newer = model.installedEmulator.map { pkg.version.compare($0, options: .numeric) == .orderedDescending } ?? true
                if newer {
                    sizeLabel(pkg.archive.size)
                    Button(model.installedEmulator == nil ? "Unduh" : "Perbarui ke \(pkg.version)") {
                        requireLicense(pkg.license) { model.installEmulator() }
                    }
                    .buttonStyle(SoftButtonStyle(tint: Theme.emulator[1])).fixedSize()
                    .disabled(model.download != nil)
                } else { installedMark }
            } else if model.installedEmulator != nil { installedMark }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func imageRow(_ img: SystemImageOption) -> some View {
        let installed = model.installedImages.contains(img.path)
        return HStack(spacing: 14) {
            IconBadge(icon: img.playStore ? "bag" : "square.stack.3d.up", colors: Theme.android, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(img.title).font(.callout.weight(.semibold))
                Text("\(img.subtitle) · \(img.abi)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if installed { installedMark }
            else {
                sizeLabel(img.archive.size)
                Button("Unduh") { requireLicense(img.license) { model.installImage(img) } }
                    .buttonStyle(SoftButtonStyle(tint: Theme.emulator[1])).fixedSize()
                    .disabled(model.download != nil)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func sizeLabel(_ bytes: Int64) -> some View {
        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
    }

    private var installedMark: some View {
        Label("Terpasang", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Theme.live)
    }

    // MARK: Launch settings

    private var launchSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Cara menjalankan")
            Panel(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Lewati animasi boot (-no-boot-anim)", isOn: $noBootAnim)
                    Toggle("Boot cepat dari snapshot (Quick Boot)", isOn: $quickBoot)
                    Toggle("Tampilkan jendela emulator", isOn: $showWindow)
                    Text("Selalu memakai GPU Mac (-gpu host) dan akselerasi hardware (-accel on). RAM dan jumlah core mengikuti setelan tiap emulator.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
            }
        }
    }
}

private struct LicenseItem: Identifiable { let id: String }

private struct LicenseSheet: View {
    let id: String
    let text: String
    let onAccept: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LISENSI GOOGLE · \(id)").font(.system(size: 10.5, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(.secondary)
                Text("Perjanjian Lisensi Android SDK").font(.title2.weight(.bold))
                Text("Komponen ini disediakan Google. Baca dan setujui lisensinya untuk mengunduh.").foregroundStyle(.secondary)
            }
            .padding(24)
            Divider()
            ScrollView {
                Text(text.isEmpty ? "Teks lisensi tidak tersedia." : text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button("Batal", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Setuju & unduh", action: onAccept).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 620, height: 600)
    }
}
