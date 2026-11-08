import SwiftUI
import AppKit
import Network
import AVFoundation
import CoreMedia

// MARK: - Viewer model

@MainActor
final class RemoteViewerModel: ObservableObject {
    static let shared = RemoteViewerModel()

    struct Found: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    enum Status: Equatable { case idle, connecting(String), connected(String), failed(String) }

    @Published var found: [Found] = []
    @Published var status: Status = .idle
    @Published var stats = ""

    private var browser: NWBrowser?
    private var conn: FramedConnection?
    private var window: RemoteWindowController?
    private let netQueue = DispatchQueue(label: "djiecast.remote.viewer")
    private var connectTimeout: DispatchWorkItem?

    // Self-test hooks
    var onVideoConfig: ((Int, Int) -> Void)?
    var onFrameDecoded: ((Bool) -> Void)?
    var headless = false
    var testScreen: RemoteScreenView?

    func startBrowsing() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: Remote.serviceType, domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let list = results.compactMap { r -> Found? in
                if case let .service(name, _, _, _) = r.endpoint, name != NetInfo.macName { return Found(name: name, endpoint: r.endpoint) }
                return nil
            }.sorted { $0.name < $1.name }
            Task { @MainActor in self?.found = list }
        }
        b.start(queue: netQueue)
        browser = b
    }

    func stopBrowsing() { browser?.cancel(); browser = nil }

    func connect(to found: Found, code: String) { connect(endpoint: found.endpoint, label: found.name, code: code) }

    /// Connects to a Djie Cast Mac on the user's tailnet through the built-in Tailscale node.
    func connect(tailnetPeer peer: TailnetModel.Peer, code: String) {
        guard let port = TailnetModel.shared.openTunnel(to: peer.ip) else {
            status = .failed("Tailscale belum siap. Aktifkan dan masuk dulu di panel Remote lewat internet."); return
        }
        connect(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!), label: peer.name, code: code)
    }

    func connect(address: String, code: String) {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        let host = String(parts.first ?? "")
        let port = parts.count > 1 ? UInt16(parts[1]) ?? Remote.port.rawValue : Remote.port.rawValue
        guard !host.isEmpty else { status = .failed("Isi alamat IP Mac tujuan."); return }
        connect(endpoint: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!), label: host, code: code)
    }

    private func connect(endpoint: NWEndpoint, label: String, code: String) {
        let clean = code.filter(\.isNumber)
        guard clean.count == 6 else { status = .failed("Kode harus 6 angka."); return }
        disconnect()
        status = .connecting(label)
        let c = FramedConnection(NWConnection(to: endpoint, using: Remote.parameters(code: clean)), queue: netQueue)
        conn = c
        c.onState = { [weak self] state in
            Task { @MainActor in
                guard let self, self.conn === c else { return }
                switch state {
                case .ready:
                    self.connectTimeout?.cancel()
                    c.send(.hello, Data(NetInfo.macName.utf8))
                case .waiting(let e), .failed(let e):
                    self.fail(Self.explain(e))
                case .cancelled:
                    if case .connected = self.status { self.status = .idle; self.window?.close(); self.window = nil }
                default: break
                }
            }
        }
        c.onMessage = { [weak self] kind, payload in
            Task { @MainActor in self?.handle(kind, payload) }
        }
        let timeout = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                if case .connecting = self?.status { self?.fail("Mac tujuan tidak menjawab. Pastikan “Izinkan diakses” menyala dan kedua Mac di jaringan yang sama (atau Tailscale).") }
            }
        }
        connectTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
        c.start()
    }

    private static func explain(_ e: NWError) -> String {
        if case .tls = e { return "Kode salah, atau kode di Mac tujuan sudah diganti." }
        if case .posix(let code) = e, code == .ECONNREFUSED { return "Mac tujuan menolak koneksi. Pastikan “Izinkan diakses” menyala." }
        return "Gagal terhubung: \(e.localizedDescription)"
    }

    private func fail(_ message: String) {
        connectTimeout?.cancel()
        conn?.cancel(); conn = nil
        window?.close(); window = nil
        status = .failed(message)
    }

    func disconnect() {
        connectTimeout?.cancel()
        conn?.send(.bye)
        let c = conn
        conn = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { c?.cancel() }
        window?.close(); window = nil
        if case .failed = status {} else { status = .idle }
    }

    // MARK: Incoming

    private var format: CMVideoFormatDescription?
    private var frames = 0
    private var bytes = 0
    private var lastStats = Date()

    private func handle(_ kind: Remote.Kind, _ payload: Data) {
        var r = Reader(payload)
        switch kind {
        case .welcome:
            let host = String(decoding: payload, as: UTF8.self)
            status = .connected(host)
            if !headless {
                window = RemoteWindowController(title: host) { [weak self] in self?.disconnect() }
                window?.screen.sendHandler = { [weak self] kind, data in self?.conn?.send(kind, data) }
            }
        case .videoConfig:
            guard let w = r.u32(), let h = r.u32(), let sps = r.blob(), let pps = r.blob() else { return }
            var fmt: CMVideoFormatDescription?
            sps.withUnsafeBytes { s in
                pps.withUnsafeBytes { p in
                    let ptrs = [s.bindMemory(to: UInt8.self).baseAddress!, p.bindMemory(to: UInt8.self).baseAddress!]
                    let sizes = [sps.count, pps.count]
                    CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: 2, parameterSetPointers: ptrs,
                                                                        parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &fmt)
                }
            }
            format = fmt
            window?.setVideoSize(CGSize(width: Int(w), height: Int(h)))
            onVideoConfig?(Int(w), Int(h))
        case .videoFrame:
            guard let flag = r.u8(), let fmt = format else { conn?.send(.requestKeyframe); return }
            let nal = r.rest
            guard let sample = Self.sampleBuffer(nal, format: fmt) else { return }
            if let screen = window?.screen ?? testScreen {
                if screen.renderer.status == .failed { screen.renderer.flush(); conn?.send(.requestKeyframe) }
                screen.renderer.enqueue(sample)
            }
            onFrameDecoded?(flag == 1)
            frames += 1; bytes += payload.count
            let now = Date()
            if now.timeIntervalSince(lastStats) >= 1 {
                let secs = now.timeIntervalSince(lastStats)
                stats = String(format: "%.0f fps · %.1f Mbps", Double(frames) / secs, Double(bytes) * 8 / secs / 1_000_000)
                window?.setStats(stats)
                frames = 0; bytes = 0; lastStats = now
            }
        case .bye:
            disconnect()
            status = .failed("Sesi diakhiri oleh Mac tujuan.")
        default: break
        }
    }

    static func sampleBuffer(_ data: Data, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == noErr, let block else { return nil }
        data.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count) }
        var sample: CMSampleBuffer?
        var size = data.count
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1,
                                        sampleSizeArray: &size, sampleBufferOut: &sample) == noErr, let sample else { return nil }
        if let atts = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(atts) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(atts, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

// MARK: - Viewer window

@MainActor
final class RemoteWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let screen = RemoteScreenView()
    private let statsLabel = NSTextField(labelWithString: "")
    private let onClose: () -> Void
    private var closing = false

    init(title: String, onClose: @escaping () -> Void) {
        self.onClose = onClose
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Remote — \(title)"
        window.contentView = screen
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]

        statsLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        statsLabel.textColor = .secondaryLabelColor
        let disconnect = NSButton(title: "Putuskan", target: self, action: #selector(disconnectTapped))
        disconnect.bezelStyle = .rounded
        disconnect.controlSize = .small
        let stack = NSStackView(views: [statsLabel, disconnect])
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 10)
        stack.frame = NSRect(x: 0, y: 0, width: 220, height: 28)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = stack
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)

        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(screen)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setVideoSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        screen.videoSize = size
        let visible = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var w = min(size.width, visible.width - 60), h = w * size.height / size.width
        if h > visible.height - 80 { h = visible.height - 80; w = h * size.width / size.height }
        window.contentAspectRatio = size
        window.setContentSize(NSSize(width: w.rounded(), height: h.rounded()))
        window.center()
    }

    func setStats(_ s: String) { statsLabel.stringValue = s }

    @objc private func disconnectTapped() { onClose() }

    func close() {
        closing = true
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        if !closing { onClose() }
    }
}

/// Shows the remote video and forwards mouse, scroll and keyboard input.
final class RemoteScreenView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    var renderer: AVSampleBufferVideoRenderer { displayLayer.sampleBufferRenderer }
    var videoSize = CGSize(width: 16, height: 10)
    var sendHandler: ((Remote.Kind, Data) -> Void)?
    private var tracking: NSTrackingArea?
    private var lastMove = Date.distantPast

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        layer?.addSublayer(displayLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    /// Where the video actually sits inside the view (aspect-fit).
    private var videoRect: CGRect { AVMakeRect(aspectRatio: videoSize, insideRect: bounds) }

    private func normalized(_ event: NSEvent) -> (Float, Float)? {
        let p = convert(event.locationInWindow, from: nil)
        let r = videoRect
        guard r.width > 0, r.height > 0 else { return nil }
        let x = (p.x - r.minX) / r.width
        let y = 1 - (p.y - r.minY) / r.height      // AppKit is bottom-up, the remote screen is top-down
        return (Float(min(max(x, 0), 1)), Float(min(max(y, 0), 1)))
    }

    private func sendMouse(_ action: Remote.MouseAction, _ button: Remote.MouseButton, _ event: NSEvent) {
        guard let (x, y) = normalized(event) else { return }
        if action == .move || action == .drag {
            // ~120 updates/s is plenty and keeps the link quiet
            let now = Date(); guard now.timeIntervalSince(lastMove) > 0.008 else { return }; lastMove = now
        }
        var w = Writer()
        w.u8(action.rawValue); w.u8(button.rawValue); w.f32(x); w.f32(y)
        w.u8(UInt8(clamping: max(event.clickCount, 1))); w.u64(UInt64(Self.cgFlags(event.modifierFlags)))
        sendHandler?(.mouse, w.data)
    }

    override func mouseMoved(with e: NSEvent) { sendMouse(.move, .left, e) }
    override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(self); sendMouse(.down, .left, e) }
    override func mouseUp(with e: NSEvent) { sendMouse(.up, .left, e) }
    override func mouseDragged(with e: NSEvent) { sendMouse(.drag, .left, e) }
    override func rightMouseDown(with e: NSEvent) { sendMouse(.down, .right, e) }
    override func rightMouseUp(with e: NSEvent) { sendMouse(.up, .right, e) }
    override func rightMouseDragged(with e: NSEvent) { sendMouse(.drag, .right, e) }
    override func otherMouseDown(with e: NSEvent) { sendMouse(.down, .other, e) }
    override func otherMouseUp(with e: NSEvent) { sendMouse(.up, .other, e) }
    override func otherMouseDragged(with e: NSEvent) { sendMouse(.drag, .other, e) }

    override func scrollWheel(with e: NSEvent) {
        let k: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 10
        var w = Writer()
        w.i32(Int32(e.scrollingDeltaX * k)); w.i32(Int32(e.scrollingDeltaY * k))
        sendHandler?(.scroll, w.data)
    }

    private func sendKey(_ e: NSEvent, down: Bool) {
        var w = Writer()
        w.u16(e.keyCode); w.u8(down ? 1 : 0); w.u64(UInt64(Self.cgFlags(e.modifierFlags)))
        sendHandler?(.key, w.data)
    }

    override func keyDown(with e: NSEvent) { sendKey(e, down: true) }
    override func keyUp(with e: NSEvent) { sendKey(e, down: false) }

    /// Send ⌘-shortcuts to the remote Mac instead of this app (⌘Q, ⌘W, ⌘C …).
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        guard window?.firstResponder === self, e.type == .keyDown else { return super.performKeyEquivalent(with: e) }
        sendKey(e, down: true)
        var w = Writer(); w.u16(e.keyCode); w.u8(0); w.u64(UInt64(Self.cgFlags(e.modifierFlags)))
        sendHandler?(.key, w.data)
        return true
    }

    static func cgFlags(_ m: NSEvent.ModifierFlags) -> CGEventFlags.RawValue {
        var f: CGEventFlags = []
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.control) { f.insert(.maskControl) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.capsLock) { f.insert(.maskAlphaShift) }
        if m.contains(.function) { f.insert(.maskSecondaryFn) }
        return f.rawValue
    }
}
