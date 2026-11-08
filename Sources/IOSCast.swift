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

/// A plain window that shows the iPhone screen (and plays its audio).
final class MirrorWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let session = AVCaptureSession()
    private let onClose: () -> Void

    init?(device: AVCaptureDevice, onClose: @escaping () -> Void) {
        self.onClose = onClose
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return nil }
        session.addInput(input)
        let audio = AVCaptureAudioPreviewOutput()
        audio.volume = 1
        if session.canAddOutput(audio) { session.addOutput(audio) }

        // Size the window from the device's screen ratio, ~800pt tall.
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let ratio = dims.width > 0 && dims.height > 0 ? CGFloat(dims.width) / CGFloat(dims.height) : 9.0 / 19.5
        let h: CGFloat = min(800, (NSScreen.main?.visibleFrame.height ?? 900) - 60)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: h * ratio, height: h),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()

        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        window.contentView = view
        window.title = "Djie Cast — \(device.localizedName)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    func windowWillClose(_ notification: Notification) {
        let s = session
        DispatchQueue.global().async { s.stopRunning() }
        onClose()
    }
}

// MARK: - View

struct IOSCastView: View {
    @ObservedObject var model = IOSCastModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(icon: "iphone", colors: Theme.ios, title: "iPhone & iPad",
                           subtitle: "Tampilkan layar iOS lewat kabel USB atau wireless") {
                    StatusPill(count: model.devices.count, noun: "perangkat")
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
                        EmptyStateView(icon: "iphone.gen3.radiowaves.left.and.right", title: "Colok iPhone atau iPad kamu", steps: [
                            "Sambungkan iPhone/iPad ke Mac dengan kabel.",
                            "Buka kunci layar, lalu ketuk \"Percayai\" (Trust) bila diminta.",
                            "Perangkat akan muncul di sini dalam beberapa detik.",
                        ])
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                            ForEach(model.devices, id: \.uniqueID) { d in
                                IOSDeviceCard(name: d.localizedName,
                                              running: model.mirroring.contains(d.uniqueID),
                                              onStart: { Task { await model.start(d) } },
                                              onStop: { model.stop(d) })
                            }
                        }
                    }
                    if model.permissionDenied {
                        Label("Izin Kamera ditolak. Aktifkan Djie Cast di Pengaturan Sistem → Privasi & Keamanan → Kamera.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Wireless")
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
        .toolbar {
            ToolbarItem {
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Cari ulang perangkat")
            }
        }
    }
}

struct IOSDeviceCard: View {
    let name: String
    let running: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    private var isPad: Bool { name.lowercased().contains("ipad") }

    var body: some View {
        Panel(highlight: running ? Theme.live : nil) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    IconBadge(icon: isPad ? "ipad" : "iphone", colors: Theme.ios, size: 44)
                    Spacer()
                    if running { LiveBadge() }
                    Pill(text: "USB", icon: "cable.connector", color: .secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.headline).lineLimit(1)
                    Text(isPad ? "iPad" : "iPhone").font(.caption).foregroundStyle(.secondary)
                }
                if running {
                    Button(action: onStop) { Label("Hentikan", systemImage: "stop.fill") }
                        .buttonStyle(SoftButtonStyle(tint: .red))
                } else {
                    Button(action: onStart) { Label("Mulai Cast", systemImage: "play.fill") }
                        .buttonStyle(GradientButtonStyle(colors: Theme.ios))
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
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    IconBadge(icon: icon, colors: colors, size: 48)
                    Spacer()
                    Pill(text: tag, color: colors[0])
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(description).font(.callout).foregroundStyle(.secondary)
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
                            Text(s).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button(action: action) { Label(buttonTitle, systemImage: buttonIcon) }
                    .buttonStyle(GradientButtonStyle(colors: colors))
                    .disabled(!enabled)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
