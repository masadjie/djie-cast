import SwiftUI
import AppKit
import ImageCaptureCore
import UniformTypeIdentifiers

// MARK: - Model (ImageCaptureCore: the same public API Image Capture.app uses)
//
// Apple only exposes an iPhone's Photos library (camera roll) to Mac apps.
// App documents ("On My iPhone" in Files) are only reachable through Finder.

struct PhoneMedia: Identifiable, Hashable {
    let id: String
    let name: String
    let size: Int64
    let date: Date?
    let isVideo: Bool
    let duration: Double
    let file: ICCameraFile?
    var demoHue: Double = 0

    static func == (a: PhoneMedia, b: PhoneMedia) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
final class IOSFilesModel: NSObject, ObservableObject {
    static let shared = IOSFilesModel()

    enum State: Equatable { case searching, opening(String), locked(String), loading(String), ready(String), failed(String) }

    @Published var state: State = .searching
    @Published var devices: [ICCameraDevice] = []
    @Published var current: ICCameraDevice?
    @Published var items: [PhoneMedia] = []
    @Published var thumbs: [String: NSImage] = [:]
    @Published var transfer: String?
    @Published var progress: Double?

    var canDelete: Bool {
        Demo.enabled || (current?.capabilities.contains(ICDeviceCapability.cameraDeviceCanDeleteOneFile.rawValue) ?? false)
    }

    private let browser = ICDeviceBrowser()
    private var started = false
    private var thumbRequested = Set<String>()
    private var retry: Task<Void, Never>?

    static let downloadsDir: URL = {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Djie Cast/iPhone", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func start() {
        guard !started else { return }
        started = true
        if Demo.enabled { loadDemo(); return }
        browser.delegate = self
        let mask = ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mask)!
        browser.start()
    }

    /// While the phone is locked/untrusted, try to open the session again every few seconds.
    private func scheduleRetry(_ device: ICDevice) {
        retry?.cancel()
        retry = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let cam = device as? ICCameraDevice, self.current === cam else { return }
            switch self.state {
            case .locked, .failed: DispatchQueue.main.async { cam.requestOpenSession() }
            default: break
            }
        }
    }

    func select(_ device: ICCameraDevice) {
        if let current, current !== device { current.requestCloseSession() }
        current = device
        items = []; thumbs = [:]; thumbRequested = []
        device.delegate = self
        state = .opening(device.name ?? "iPhone")
        device.requestOpenSession()
    }

    private func reloadItems() {
        guard let cam = current else { return }
        let files = (cam.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        items = files.map { f in
            let type = f.uti.flatMap { UTType($0) }
            return PhoneMedia(id: String(describing: ObjectIdentifier(f)), name: f.name ?? "Tanpa nama", size: Int64(f.fileSize),
                              date: f.creationDate ?? f.fileCreationDate, isVideo: type?.conforms(to: .movie) ?? false,
                              duration: f.duration, file: f)
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func thumbnail(for item: PhoneMedia) {
        guard thumbs[item.id] == nil, !thumbRequested.contains(item.id), let file = item.file else { return }
        thumbRequested.insert(item.id)
        file.requestThumbnailData(options: [.imageSourceThumbnailMaxPixelSize: 320]) { data, _ in
            guard let data, let img = NSImage(data: data) else { return }
            Task { @MainActor in self.thumbs[item.id] = img }
        }
    }

    // MARK: Actions

    func download(_ selection: [PhoneMedia]) {
        let files = selection.compactMap(\.file)
        guard !files.isEmpty else {
            if Demo.enabled { transfer = "Contoh: \(selection.count) file akan diunduh" }
            return
        }
        let dest = Self.downloadsDir
        var done = 0, saved: [URL] = []
        transfer = "Mengunduh 0/\(files.count)…"; progress = 0
        for f in files {
            f.requestDownload(options: [.downloadsDirectoryURL: dest as NSURL, .overwrite: true]) { name, _ in
                Task { @MainActor in
                    done += 1
                    if let name { saved.append(dest.appendingPathComponent(name)) }
                    self.transfer = "Mengunduh \(done)/\(files.count)…"
                    self.progress = Double(done) / Double(files.count)
                    if done == files.count {
                        self.transfer = nil; self.progress = nil
                        NSWorkspace.shared.activateFileViewerSelecting(saved.isEmpty ? [dest] : saved)
                    }
                }
            }
        }
    }

    func delete(_ selection: [PhoneMedia]) {
        guard let cam = current else {
            if Demo.enabled { items.removeAll { selection.contains($0) } }
            return
        }
        let files = selection.compactMap(\.file)
        transfer = "Menghapus \(files.count) item…"
        _ = cam.requestDeleteFiles(files, deleteFailed: { _ in }) { _, error in
            Task { @MainActor in
                self.transfer = error == nil ? nil : "Sebagian file tidak bisa dihapus dari iPhone."
                self.reloadItems()
            }
        }
    }

    func open(_ item: PhoneMedia) {
        guard let file = item.file else { return }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("DjieCast-iPhone", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        transfer = "Membuka \(item.name)…"
        file.requestDownload(options: [.downloadsDirectoryURL: tmp as NSURL, .overwrite: true]) { name, _ in
            Task { @MainActor in
                self.transfer = nil
                if let name { NSWorkspace.shared.open(tmp.appendingPathComponent(name)) }
            }
        }
    }

    private func loadDemo() {
        let names = ["IMG_4821.HEIC", "IMG_4820.HEIC", "IMG_4819.MOV", "IMG_4818.HEIC", "IMG_4817.JPG", "IMG_4816.HEIC",
                     "IMG_4815.MOV", "IMG_4814.HEIC", "IMG_4813.HEIC", "IMG_4812.PNG", "IMG_4811.HEIC", "IMG_4810.MOV",
                     "IMG_4809.HEIC", "IMG_4808.HEIC", "IMG_4807.JPG", "IMG_4806.HEIC", "IMG_4805.HEIC", "IMG_4804.MOV"]
        let base = Date(timeIntervalSince1970: 1_762_560_000)
        items = names.enumerated().map { i, n in
            let video = n.hasSuffix("MOV")
            return PhoneMedia(id: n, name: n, size: video ? 48_000_000 + Int64(i) * 1_300_000 : 2_400_000 + Int64(i) * 90_000,
                              date: base.addingTimeInterval(-Double(i) * 5400), isVideo: video, duration: video ? Double(8 + i * 3) : 0,
                              file: nil, demoHue: Double(i) / Double(names.count))
        }
        state = .ready("iPhone 16 Pro")
    }
}

extension IOSFilesModel: ICDeviceBrowserDelegate {
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let cam = device as? ICCameraDevice else { return }
        Task { @MainActor in
            if !self.devices.contains(where: { $0 === cam }) { self.devices.append(cam) }
            if self.current == nil { self.select(cam) }
        }
    }
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        Task { @MainActor in
            self.devices.removeAll { $0 === device }
            if self.current === device {
                self.current = nil; self.items = []; self.thumbs = [:]
                if let next = self.devices.first { self.select(next) } else { self.state = .searching }
            }
        }
    }
}

extension IOSFilesModel: ICCameraDeviceDelegate {
    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        Task { @MainActor in
            let name = device.name ?? "iPhone"
            if let error {
                let text = (error as NSError).localizedDescription.lowercased()
                if text.contains("unlock") || text.contains("lock") || text.contains("trust") {
                    self.state = .locked(name)
                } else {
                    self.state = .failed("Tidak bisa membuka \(name): \(error.localizedDescription)")
                }
                self.scheduleRetry(device)
            } else {
                self.retry?.cancel()
                self.state = .loading(name)
            }
        }
    }
    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
    nonisolated func didRemove(_ device: ICDevice) {}
    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        Task { @MainActor in self.reloadItems(); self.state = .ready(device.name ?? "iPhone") }
    }
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        Task { @MainActor in self.reloadItems() }
    }
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        Task { @MainActor in self.reloadItems() }
    }
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        Task { @MainActor in
            self.state = .loading(device.name ?? "iPhone")
            if let cam = device as? ICCameraDevice, cam.contentCatalogPercentCompleted >= 100 { self.reloadItems(); self.state = .ready(device.name ?? "iPhone") }
        }
    }
    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        Task { @MainActor in self.state = .locked(device.name ?? "iPhone"); self.items = [] }
    }
}

// MARK: - View

struct IOSFilesView: View {
    @ObservedObject var model = IOSFilesModel.shared
    @State private var filter = 0            // 0 semua, 1 foto, 2 video
    @State private var selection = Set<String>()
    @State private var confirmDelete = false
    @State private var showGuide = false

    private var visible: [PhoneMedia] {
        model.items.filter { filter == 0 || (filter == 1 ? !$0.isVideo : $0.isVideo) }
    }
    private var selectedItems: [PhoneMedia] { model.items.filter { selection.contains($0.id) } }
    private var photoCount: Int { model.items.filter { !$0.isVideo }.count }
    private var videoCount: Int { model.items.count - photoCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(icon: "photo.on.rectangle.angled", colors: Theme.ios, title: "File iPhone",
                       subtitle: "Lihat, unduh & hapus foto dan video di iPhone/iPad") {
                if model.devices.count > 1 {
                    Picker("Perangkat", selection: Binding(get: { model.current.map(ObjectIdentifier.init) },
                                                          set: { id in if let d = model.devices.first(where: { ObjectIdentifier($0) == id }) { model.select(d) } })) {
                        ForEach(model.devices, id: \.self) { d in Text(d.name ?? "iPhone").tag(Optional(ObjectIdentifier(d))) }
                    }
                    .labelsHidden().frame(width: 200)
                }
            }
            .padding(.horizontal, 28).padding(.top, 28)

            content
        }
        .onAppear { model.start() }
        .sheet(isPresented: $showGuide) { SetupGuideSheet(guide: .ios) }
        .alert("Hapus \(selection.count) item dari iPhone?", isPresented: $confirmDelete) {
            Button("Hapus", role: .destructive) {
                let items = selectedItems
                selection.removeAll()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { model.delete(items) }
            }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Foto dan video akan dipindahkan ke “Baru Dihapus” di iPhone atau dihapus permanen, tergantung pengaturan iPhone.")
        }
        .toolbar {
            ToolbarItem {
                Button { showGuide = true } label: { Label("Panduan Trust", systemImage: "questionmark.circle") }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .ready(let name):
            gallery(name)
        case .searching:
            ScrollView {
                Panel(padding: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Belum ada iPhone/iPad tersambung").font(.headline)
                        Text("Colok lewat kabel dan percayai Mac ini. Foto & video akan muncul di sini.")
                            .font(.callout).foregroundStyle(.secondary)
                        GuideStepsList(guide: .ios).padding(.top, 6)
                    }
                }
                limitsNote.padding(.top, 14)
            }
            .padding(.horizontal, 28)
        case .opening(let name), .loading(let name):
            centered {
                ProgressView().controlSize(.large)
                Text("Membaca galeri \(name)…").font(.headline)
                Text("Pertama kali bisa butuh beberapa detik, tergantung jumlah foto.").font(.callout).foregroundStyle(.secondary)
            }
        case .locked(let name):
            centered {
                Image(systemName: "lock.iphone").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.ios[1])
                Text("\(name) terkunci").font(.headline)
                Text("Buka kunci iPhone dan ketuk “Percayai” bila diminta. Galeri akan muncul otomatis.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
        case .failed(let msg):
            centered {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 40, weight: .light)).foregroundStyle(.orange)
                Text(msg).font(.callout).multilineTextAlignment(.center).frame(maxWidth: 420)
                Button("Lihat panduan") { showGuide = true }.buttonStyle(SoftButtonStyle(tint: Theme.ios[1])).fixedSize()
            }
        }
    }

    private func centered<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 12) { c() }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 60)
    }

    // MARK: Gallery

    private func gallery(_ name: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("", selection: $filter) {
                    Text("Semua · \(model.items.count)").tag(0)
                    Text("Foto · \(photoCount)").tag(1)
                    Text("Video · \(videoCount)").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                if !selection.isEmpty {
                    Text("\(selection.count) dipilih").font(.callout).foregroundStyle(.secondary)
                    Button("Batal pilih") { selection.removeAll() }.buttonStyle(.borderless)
                } else {
                    Button("Pilih semua") { selection = Set(visible.map(\.id)) }.buttonStyle(.borderless)
                }
                Button { model.download(selection.isEmpty ? visible : selectedItems) } label: {
                    Label(selection.isEmpty ? "Unduh semua" : "Unduh", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(GradientButtonStyle(colors: Theme.ios)).fixedSize()
                if model.canDelete {
                    Button { confirmDelete = true } label: { Label("Hapus", systemImage: "trash") }
                        .buttonStyle(SoftButtonStyle(tint: .red)).fixedSize()
                        .disabled(selection.isEmpty)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 14)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 10)], spacing: 10) {
                    ForEach(visible) { item in
                        MediaTile(item: item, image: model.thumbs[item.id], selected: selection.contains(item.id))
                            .onAppear { model.thumbnail(for: item) }
                            .onTapGesture(count: 2) { model.open(item) }
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                                }
                            }
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 16)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: visible.map(\.id))
            }

            HStack(spacing: 8) {
                if let t = model.transfer {
                    if let p = model.progress { ProgressView(value: p).frame(width: 120) } else { ProgressView().controlSize(.small) }
                    Text(t)
                } else {
                    Image(systemName: "iphone").foregroundStyle(.secondary)
                    Text("\(name) · \(model.items.count) item")
                }
                Spacer()
                Text("Klik untuk memilih · klik 2× untuk membuka di Mac · disimpan ke Downloads/Djie Cast/iPhone")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 28).padding(.vertical, 9)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var limitsNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Theme.ios[1])
            Text("Apple hanya mengizinkan aplikasi Mac membuka **Foto & Video** iPhone. Untuk dokumen di app Files (“Di iPhone Saya”), buka **Finder → pilih iPhone di sidebar → tab File**.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ios[0].opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MediaTile: View {
    let item: PhoneMedia
    let image: NSImage?
    let selected: Bool
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if item.file == nil {
                    LinearGradient(colors: [Color(hue: item.demoHue, saturation: 0.45, brightness: 0.95),
                                            Color(hue: (item.demoHue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.75)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    Rectangle().fill(Color.primary.opacity(0.06)).overlay(ProgressView().controlSize(.small))
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .clipped()

            if item.isVideo {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 8))
                    if item.duration >= 1 {
                        Text(String(format: "%d:%02d", Int(item.duration) / 60, Int(item.duration) % 60))
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(selected ? Theme.ios[0] : Color.primary.opacity(hover ? 0.2 : 0.06), lineWidth: selected ? 3 : 1))
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, Theme.ios[0])
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(selected ? 0.95 : (hover ? 1.02 : 1))
        .help("\(item.name) · \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .contentShape(Rectangle())
    }
}
