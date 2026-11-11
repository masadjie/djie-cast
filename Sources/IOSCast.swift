import SwiftUI
import AppKit
import AVFoundation
import CoreMediaIO

// MARK: - iPhone/iPad over USB (same source QuickTime uses)

@MainActor
final class IOSCastModel: ObservableObject {
    static let shared = IOSCastModel()

    @Published var devices: [AVCaptureDevice] = []
    @Published var mirroring: Set<String> = []
    /// iPhones offered by Continuity Camera (wireless, iOS 17+ / macOS 14+).
    @Published var cameras: [AVCaptureDevice] = []
    /// iPhones/iPads reachable over Wi-Fi via libimobiledevice.
    @Published var networkPhones: [NetPhone] = []
    struct NetPhone: Identifiable, Equatable { let udid: String; let name: String; var id: String { udid } }

    func scanNetwork() async {
        if Demo.enabled { networkPhones = [NetPhone(udid: "00008120-001A2B3C4D5E6F70", name: "iPhone Rina")]; return }
        guard IMD.available else { return }
        let list = await IMD.networkDevices().map { NetPhone(udid: $0.udid, name: $0.name) }
        if list != networkPhones { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { networkPhones = list } }
    }
    @Published var permissionDenied = false
    private var windows: [String: MirrorWindow] = [:]
    private var observers: [NSObjectProtocol] = []

    let mirroringAppURL = URL(fileURLWithPath: "/System/Applications/iPhone Mirroring.app")
    var hasMirroringApp: Bool { FileManager.default.fileExists(atPath: mirroringAppURL.path) }

    private init() {
        Self.allowScreenCaptureDevices()
        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    /// iOS screens only show up as capture devices after opting in via CoreMediaIO.
    nonisolated static func allowScreenCaptureDevices() {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil,
                                  UInt32(MemoryLayout<UInt32>.size), &allow)
    }

    func refresh() {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
        devices = session.devices
        let cams = AVCaptureDevice.DiscoverySession(deviceTypes: [.continuityCamera], mediaType: .video, position: .unspecified)
        cameras = cams.devices
    }

    func requestAccess() async -> Bool {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        permissionDenied = !video
        return video
    }

    func start(_ device: AVCaptureDevice) async {
        if let w = windows[device.uniqueID] { w.window.makeKeyAndOrderFront(nil); return }
        guard await requestAccess() else { return }
        guard let w = MirrorWindow(device: device, onClose: { [weak self] in
            self?.windows[device.uniqueID] = nil
            self?.mirroring.remove(device.uniqueID)
        }) else { return }
        windows[device.uniqueID] = w
        mirroring.insert(device.uniqueID)
    }

    func rotate(_ device: AVCaptureDevice, by degrees: Int) {
        windows[device.uniqueID]?.rotate(by: degrees)
    }

    func stop(_ device: AVCaptureDevice) {
        windows[device.uniqueID]?.window.close()
    }

    func openMirroringApp() {
        NSWorkspace.shared.openApplication(at: mirroringAppURL, configuration: .init())
    }

    func openAirPlaySettings() {
        let urls = ["x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension",
                    "x-apple.systempreferences:com.apple.preference.general"]
        for u in urls { if let url = URL(string: u), NSWorkspace.shared.open(url) { return } }
    }
}

/// Hosts the preview layer and rotates it in 90° steps.
final class RotatingPreviewView: NSView {
    let preview: AVCaptureVideoPreviewLayer
    var angle = 0 { didSet { needsLayout = true } }   // clockwise degrees: 0, 90, 180, 270

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspect
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let sideways = angle % 180 != 0
        preview.bounds = CGRect(x: 0, y: 0,
                                width: sideways ? bounds.height : bounds.width,
                                height: sideways ? bounds.width : bounds.height)
        preview.position = CGPoint(x: bounds.midX, y: bounds.midY)
        // Layer space is flipped vs. user expectation: negative = clockwise on screen.
        preview.setAffineTransform(CGAffineTransform(rotationAngle: -CGFloat(angle) * .pi / 180))
        CATransaction.commit()
    }
}

/// Window that forwards ⌘← / ⌘→ to rotate.
final class MirrorNSWindow: NSWindow {
    var onRotate: ((Int) -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 123: onRotate?(-90); return true   // ←
            case 124: onRotate?(90); return true    // →
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A window that shows the iPhone screen (and plays its audio), with rotation.
final class MirrorWindow: NSObject, NSWindowDelegate {
    let window: MirrorNSWindow
    private let session = AVCaptureSession()
    private let device: AVCaptureDevice
    private let previewView: RotatingPreviewView
    private let onClose: () -> Void
    private var formatObserver: NSObjectProtocol?

    init?(device: AVCaptureDevice, onClose: @escaping () -> Void) {
        self.device = device
        self.onClose = onClose
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return nil }
        session.addInput(input)
        let audio = AVCaptureAudioPreviewOutput()
        audio.volume = 1
        if session.canAddOutput(audio) { session.addOutput(audio) }

        previewView = RotatingPreviewView(session: session)
        window = MirrorNSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 800),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                backing: .buffered, defer: false)
        super.init()

        window.contentView = previewView
        window.title = "Djie Cast — \(device.localizedName)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.onRotate = { [weak self] d in self?.rotate(by: d) }
        window.backgroundColor = .black
        addRotateButtons()
        fitWindow(animated: false)
        window.center()
        window.makeKeyAndOrderFront(nil)

        // When the iPhone itself turns (portrait ↔ landscape) the stream size changes.
        formatObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureInputPortFormatDescriptionDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.fitWindow(animated: true)
        }
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    /// Source aspect ratio (width / height) after applying the manual rotation.
    private var aspect: CGFloat {
        let d = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        var w = CGFloat(d.width), h = CGFloat(d.height)
        if w <= 0 || h <= 0 { w = 9; h = 19.5 }
        if previewView.angle % 180 != 0 { swap(&w, &h) }
        return w / h
    }

    /// Resizes the window to the stream's shape, keeping it on screen.
    private func fitWindow(animated: Bool) {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxH = min(820, visible.height - 60), maxW = visible.width - 80
        var h = maxH, w = h * aspect
        if w > maxW { w = maxW; h = w / aspect }
        let content = NSSize(width: w.rounded(), height: h.rounded())
        window.contentAspectRatio = content
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        let old = window.frame
        frame.origin = NSPoint(x: old.midX - frame.width / 2, y: old.maxY - frame.height)
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animated)
    }

    func rotate(by degrees: Int) {
        previewView.angle = ((previewView.angle + degrees) % 360 + 360) % 360
        fitWindow(animated: true)
    }

    private func addRotateButtons() {
        func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
            b.bezelStyle = .texturedRounded
            b.isBordered = false
            b.toolTip = tip
            b.contentTintColor = .secondaryLabelColor
            return b
        }
        let stack = NSStackView(views: [
            button("rotate.left", "Putar kiri (⌘←)", #selector(rotateLeft)),
            button("rotate.right", "Putar kanan (⌘→)", #selector(rotateRight)),
        ])
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        stack.frame = NSRect(x: 0, y: 0, width: 64, height: 28)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = stack
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)
    }

    @objc private func rotateLeft() { rotate(by: -90) }
    @objc private func rotateRight() { rotate(by: 90) }

    func windowWillClose(_ notification: Notification) {
        if let formatObserver { NotificationCenter.default.removeObserver(formatObserver) }
        let s = session
        DispatchQueue.global().async { s.stopRunning() }
        onClose()
    }
}

// MARK: - View

struct IOSCastView: View {
    @ObservedObject var model = IOSCastModel.shared
    @State private var showGuide = false
    @State private var detailUDID: String?
    @State private var networkUDID: String?
    @State private var cleaner: IMDDevice?
    struct IMDDevice: Identifiable { let id: String; let name: String }
    @State private var infoError: String?

    /// Finds the libimobiledevice UDID for a device (by name), or the first connected one.
    private func openCleaner() {
        guard IMD.available else { infoError = "Info iPhone butuh komponen libimobiledevice (sudah termasuk di Djie Cast untuk Apple Silicon)."; return }
        Task {
            if let hit = await IMD.devices().first { cleaner = IMDDevice(id: hit.udid, name: hit.name); infoError = nil }
            else { infoError = "iPhone belum terbaca. Buka kunci iPhone dan pastikan sudah “Percayai Komputer Ini”." }
        }
    }

    private func openInfo(name: String?) {
        guard IMD.available else { infoError = "Info iPhone butuh komponen libimobiledevice (sudah termasuk di Djie Cast untuk Apple Silicon)."; return }
        Task {
            let list = await IMD.devices()
            if let hit = list.first(where: { $0.name == name }) ?? list.first { detailUDID = hit.udid; infoError = nil }
            else { infoError = "iPhone belum terbaca. Buka kunci iPhone dan pastikan sudah “Percayai Komputer Ini”." }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if Demo.env["DJIE_FOCUS"] == "wireless" { networkPanel; cameraSection }   // snapshot aid
                PageHeader(icon: "iphone", colors: Theme.ios, title: "iPhone & iPad",
                           subtitle: "Tampilkan layar iOS lewat kabel USB atau wireless") {
                    StatusPill(count: model.devices.count, noun: "perangkat")
                }

                if !model.devices.isEmpty {
                    RequirementBanner(guide: .ios) { showGuide = true }
                }
                if let infoError {
                    Label(L(infoError), systemImage: "info.circle").font(.callout).foregroundStyle(.orange)
                }

                Panel {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill").font(.title3).foregroundStyle(Theme.ios[0])
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Mau mengontrol iPhone dari Mac?").font(.headline)
                            Text("Apple tidak mengizinkan aplikasi lain mengendalikan iPhone lewat USB atau AirPlay — keduanya hanya bisa menampilkan layar. Untuk klik, ketik & swipe dari Mac, pakai **iPhone Mirroring** di bawah (fitur resmi Apple).")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Lewat kabel USB", detail: "· hanya lihat + audio")
                    if model.devices.isEmpty {
                        Panel(padding: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Belum ada iPhone/iPad tersambung").font(.headline)
                                Text("Ikuti langkah ini sekali saja, lalu perangkat akan muncul di sini dalam beberapa detik.")
                                    .font(.callout).foregroundStyle(.secondary)
                                GuideStepsList(guide: .ios).padding(.top, 6)
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            ForEach(model.devices, id: \.uniqueID) { d in
                                IOSRichCard(name: d.localizedName, running: model.mirroring.contains(d.uniqueID),
                                            onStart: { Task { await model.start(d) } }, onStop: { model.stop(d) },
                                            onRotate: { model.rotate(d, by: $0) },
                                            onDetails: { detailUDID = $0 })
                                .transition(.scale(scale: 0.96).combined(with: .opacity))
                            }
                        }
                    }
                    if model.permissionDenied {
                        Label("Izin Kamera ditolak. Aktifkan Djie Cast di Pengaturan Sistem → Privasi & Keamanan → Kamera.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }

                cameraSection

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Wireless")
                    networkPanel
                    HStack(alignment: .top, spacing: 16) {
                        WirelessCard(icon: "hand.tap.fill", colors: Theme.mirroring, title: "iPhone Mirroring",
                                     tag: "Kontrol penuh",
                                     description: "Pakai iPhone langsung dari Mac — klik, ketik, dan swipe.",
                                     steps: ["macOS Sequoia & iOS 18 atau lebih baru",
                                             "Apple ID yang sama di Mac & iPhone",
                                             "iPhone terkunci & berada di dekat Mac"],
                                     buttonTitle: model.hasMirroringApp ? "Buka iPhone Mirroring" : "Tidak tersedia di Mac ini",
                                     buttonIcon: "arrow.up.forward.app",
                                     enabled: model.hasMirroringApp,
                                     action: model.openMirroringApp)
                        WirelessCard(icon: "airplayvideo", colors: Theme.airplay, title: "AirPlay",
                                     tag: "Hanya lihat",
                                     description: "Pantulkan layar iPhone/iPad ke Mac lewat Wi-Fi.",
                                     steps: ["Nyalakan \"AirPlay Receiver\" di Mac",
                                             "Di iPhone: Control Center → Screen Mirroring",
                                             "Pilih nama Mac ini"],
                                     buttonTitle: "Buka Pengaturan AirPlay",
                                     buttonIcon: "gearshape.fill",
                                     enabled: true,
                                     action: model.openAirPlaySettings)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.devices.map(\.uniqueID))
        .sheet(isPresented: $showGuide) { SetupGuideSheet(guide: .ios) }
        .sheet(item: $cleaner) { d in IOSCleanerSheet(udid: d.id, name: d.name) }
        .sheet(item: Binding(get: { networkUDID.map { SerialItem(id: $0) } }, set: { networkUDID = $0?.id })) { item in
            DeviceDetailSheet(backend: IOSBackend(udid: item.id, network: true))
        }
        .task {
            while !Task.isCancelled {
                await model.scanNetwork()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .sheet(item: Binding(get: { detailUDID.map { SerialItem(id: $0) } }, set: { detailUDID = $0?.id })) { item in
            DeviceDetailSheet(backend: IOSBackend(udid: item.id))
        }
        .toolbar {
            ToolbarItem {
                Button { openCleaner() } label: { Label("Bersihkan iPhone", systemImage: "sparkles") }
                    .help("Bersihkan log crash dan lihat aplikasi yang paling makan ruang")
            }
            ToolbarItem {
                Button { openInfo(name: nil) } label: { Label("Info & aplikasi iPhone", systemImage: "info.circle") }
                    .help("Spesifikasi, baterai & aplikasi iPhone yang tersambung")
            }
            ToolbarItem {
                Button { showGuide = true } label: { Label("Panduan Trust", systemImage: "questionmark.circle") }
                    .help("Cara mempercayai Mac ini di iPhone/iPad")
            }
            ToolbarItem {
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Cari ulang perangkat")
            }
        }
    }
}

extension IOSCastView {
    /// iPhones found on this Wi-Fi network, with what can be done wirelessly.
    var networkPanel: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        IconBadge(icon: "wifi", colors: Theme.ios, size: 44)
                        RadarRings(color: Theme.ios[1]).frame(width: 44, height: 44).allowsHitTesting(false)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("iPhone di jaringan ini").font(.headline)
                        Text("iPhone yang pernah dicolok ke Mac ini dan menyalakan sinkron Wi-Fi muncul otomatis — info dan aplikasinya bisa dibuka tanpa kabel.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.networkPhones.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mencari iPhone di jaringan…").font(.callout).foregroundStyle(.secondary)
                            Text("Belum muncul? Colok iPhone sekali, buka Finder → pilih iPhone → centang “Tampilkan iPhone ini saat tersambung ke Wi-Fi”. Mac dan iPhone harus di Wi-Fi yang sama.")
                                .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ForEach(model.networkPhones) { p in
                        HStack(spacing: 12) {
                            Image(systemName: "iphone")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ios[1])
                                .frame(width: 34, height: 34)
                                .background(Theme.ios[1].opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L(p.name)).font(.callout.weight(.semibold))
                                Label("Wi-Fi", systemImage: "wifi").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.hasMirroringApp {
                                Button { model.openMirroringApp() } label: { Label("Kontrol", systemImage: "hand.tap.fill") }
                                    .buttonStyle(SoftButtonStyle(tint: Theme.ios[1])).fixedSize()
                                    .help("Buka iPhone Mirroring")
                            }
                            Button { networkUDID = p.udid } label: { Label("Info & aplikasi", systemImage: "info.circle") }
                                .buttonStyle(GradientButtonStyle(colors: Theme.ios)).fixedSize()
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    /// Uses the iPhone's own camera as a live view on the Mac (Continuity Camera).
    @ViewBuilder var cameraSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Kamera iPhone", detail: "· Continuity Camera, tanpa kabel")
            Panel(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        IconBadge(icon: "camera.fill", colors: Theme.ios, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Pakai kamera iPhone dari Mac").font(.headline)
                            Text("Kamera belakang iPhone tampil di jendela Mac — cocok untuk dokumen, produk, atau sumber video di OBS & aplikasi live.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).help("Cari kamera iPhone")
                    }
                    if model.cameras.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(["iPhone dengan iOS 17+ dan Mac dengan macOS 14+, Apple ID yang sama",
                                           "Wi-Fi & Bluetooth menyala di keduanya, iPhone di dekat Mac",
                                           "Di iPhone: Pengaturan → Umum → AirPlay & Kontinuitas → Kamera Kontinuitas",
                                           "Letakkan iPhone dalam posisi diam, layar terkunci"].enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(String(format: "%02d", i + 1)).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.ios[1])
                                    Text(L(step)).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        ForEach(model.cameras, id: \.uniqueID) { cam in
                            HStack(spacing: 12) {
                                Image(systemName: "iphone.rear.camera").foregroundStyle(Theme.ios[1])
                                Text(L(cam.localizedName)).font(.callout.weight(.medium))
                                if model.mirroring.contains(cam.uniqueID) { LiveBadge() }
                                Spacer()
                                if model.mirroring.contains(cam.uniqueID) {
                                    Button { model.stop(cam) } label: { Label("Tutup", systemImage: "stop.fill") }
                                        .buttonStyle(SoftButtonStyle(tint: .red)).fixedSize()
                                } else {
                                    Button { Task { await model.start(cam) } } label: { Label("Buka kamera", systemImage: "camera.fill") }
                                        .buttonStyle(GradientButtonStyle(colors: Theme.ios)).fixedSize()
                                }
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }
}

struct IOSDeviceCard: View {
    let name: String
    let running: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onRotate: (Int) -> Void
    let onInfo: () -> Void
    private var isPad: Bool { name.lowercased().contains("ipad") }

    var body: some View {
        Panel(highlight: running ? Theme.live : nil) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    IconBadge(icon: isPad ? "ipad" : "iphone", colors: Theme.ios, size: 44)
                    Spacer()
                    if running { LiveBadge() }
                    Pill(text: "USB", icon: "cable.connector", color: .secondary)
                    Button(action: onInfo) { Image(systemName: "info.circle").font(.system(size: 15)) }
                        .buttonStyle(.borderless).help("Info perangkat & aplikasi")
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L(name)).font(.headline).lineLimit(1)
                    Text(isPad ? "iPad" : "iPhone").font(.caption).foregroundStyle(.secondary)
                }
                if running {
                    HStack(spacing: 8) {
                        Button { onRotate(-90) } label: { Label("Putar kiri", systemImage: "rotate.left") }
                            .buttonStyle(SoftButtonStyle(tint: Theme.ios[0]))
                        Button { onRotate(90) } label: { Label("Putar kanan", systemImage: "rotate.right") }
                            .buttonStyle(SoftButtonStyle(tint: Theme.ios[0]))
                    }
                    Button(action: onStop) { Label("Hentikan", systemImage: "stop.fill") }
                        .buttonStyle(SoftButtonStyle(tint: .red))
                } else {
                    Button(action: onStart) { Label("Mulai Cast", systemImage: "play.fill") }
                        .buttonStyle(GradientButtonStyle(colors: Theme.ios))
                    Text("Jendela cast mengikuti rotasi iPhone otomatis · ⌘← / ⌘→ untuk memutar manual")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct WirelessCard: View {
    let icon: String
    let colors: [Color]
    let title: String
    let tag: String
    let description: String
    let steps: [String]
    let buttonTitle: String
    let buttonIcon: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Panel(padding: 20, fill: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    IconBadge(icon: icon, colors: colors, size: 48)
                    Spacer()
                    Pill(text: tag, color: colors[0])
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(title)).font(.system(size: 18, weight: .bold))
                    Text(L(description)).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)")
                                .font(.caption2.weight(.bold))
                                .frame(width: 18, height: 18)
                                .background(colors[0].opacity(0.15), in: Circle())
                                .foregroundStyle(colors[0])
                            Text(L(s)).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button(action: action) { Label(L(buttonTitle), systemImage: buttonIcon) }
                    .buttonStyle(GradientButtonStyle(colors: colors))
                    .disabled(!enabled)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// iPhone/iPad card with its details shown inline (libimobiledevice when available).
struct IOSRichCard: View {
    let name: String
    let running: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onRotate: (Int) -> Void
    let onDetails: (String) -> Void
    @State private var udid: String?
    @State private var resolved = false

    var body: some View {
        DeviceSummaryCard(backend: udid.map { IOSBackend(udid: $0) }, fallbackTitle: name,
                          fallbackSubtitle: resolved && udid == nil ? "Buka kunci iPhone & ketuk “Percayai” untuk melihat detail" : "iPhone",
                          live: running, connection: "USB", showScreen: !running,
                          onDetails: { if let udid { onDetails(udid) } }) {
            if running {
                Button { onRotate(-90) } label: { Image(systemName: "rotate.left") }.buttonStyle(SoftButtonStyle(tint: Theme.ios[0])).fixedSize()
                Button { onRotate(90) } label: { Image(systemName: "rotate.right") }.buttonStyle(SoftButtonStyle(tint: Theme.ios[0])).fixedSize()
                Button(action: onStop) { Label("Hentikan", systemImage: "stop.fill") }.buttonStyle(SoftButtonStyle(tint: .red)).fixedSize()
            } else {
                Button(action: onStart) { Label("Mulai Cast", systemImage: "play.fill") }
                    .buttonStyle(GradientButtonStyle(colors: Theme.ios)).fixedSize()
            }
        }
        .task(id: name) {
            guard IMD.available else { resolved = true; return }
            for _ in 0..<5 {
                let list = await IMD.devices()
                if let hit = list.first(where: { $0.name == name }) ?? (list.count == 1 ? list.first : nil) { udid = hit.udid; break }
                try? await Task.sleep(for: .seconds(2))
            }
            resolved = true
        }
    }
}
