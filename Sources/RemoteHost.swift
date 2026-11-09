import SwiftUI
import AppKit
import Network
import ScreenCaptureKit
import VideoToolbox
import CoreMedia
import ApplicationServices

// MARK: - H.264 encoder (hardware, low latency)

final class H264Encoder {
    private var session: VTCompressionSession?
    private(set) var width: Int32 = 0
    private(set) var height: Int32 = 0
    private var forceKey = true
    /// (AVCC frame data, isKeyframe, format description for keyframes)
    var onFrame: ((Data, Bool, CMFormatDescription?) -> Void)?

    func requestKeyframe() { forceKey = true }

    func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        let w = Int32(CVPixelBufferGetWidth(pixelBuffer)), h = Int32(CVPixelBufferGetHeight(pixelBuffer))
        if session == nil || w != width || h != height { makeSession(width: w, height: h) }
        guard let session else { return }
        var props: CFDictionary?
        if forceKey {
            props = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
            forceKey = false
        }
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer, presentationTimeStamp: pts,
                                        duration: .invalid, frameProperties: props, infoFlagsOut: nil) { [weak self] status, _, sample in
            guard status == noErr, let sample, let self else { return }
            self.emit(sample)
        }
    }

    private func makeSession(width w: Int32, height h: Int32) {
        if let session { VTCompressionSessionInvalidate(session) }
        width = w; height = h
        var s: VTCompressionSession?
        let spec = [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: kCFBooleanTrue] as CFDictionary
        VTCompressionSessionCreate(allocator: nil, width: w, height: h, codecType: kCMVideoCodecType_H264,
                                   encoderSpecification: spec, imageBufferAttributes: nil, compressedDataAllocator: nil,
                                   outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard let s else { return }
        let set: (CFString, CFTypeRef) -> Void = { VTSessionSetProperty(s, key: $0, value: $1) }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: 12_000_000))
        set(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: 60))
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: 4))
        VTCompressionSessionPrepareToEncodeFrames(s)
        session = s
        forceKey = true
    }

    private func emit(_ sample: CMSampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let isKey = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let len = CMBlockBufferGetDataLength(block)
        var data = Data(count: len)
        data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: len, destination: $0.baseAddress!) }
        onFrame?(data, isKey, isKey ? CMSampleBufferGetFormatDescription(sample) : nil)
    }

    func stop() {
        if let session { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid); VTCompressionSessionInvalidate(session) }
        session = nil
    }

    /// SPS + PPS from an H.264 format description.
    static func parameterSets(_ fmt: CMFormatDescription) -> (Data, Data)? {
        var sets: [Data] = []
        for i in 0..<2 {
            var ptr: UnsafePointer<UInt8>?, size = 0
            guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: i, parameterSetPointerOut: &ptr,
                                                                     parameterSetSizeOut: &size, parameterSetCountOut: nil,
                                                                     nalUnitHeaderLengthOut: nil) == noErr, let ptr else { return nil }
            sets.append(Data(bytes: ptr, count: size))
        }
        return (sets[0], sets[1])
    }
}

// MARK: - Screen source (ScreenCaptureKit), with a synthetic source for self-tests

protocol FrameSource: AnyObject {
    var onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)? { get set }
    var displayBounds: CGRect { get }
    func start() async throws
    func stop()
}

final class ScreenSource: NSObject, FrameSource, SCStreamOutput, SCStreamDelegate {
    var onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)?
    private(set) var displayBounds: CGRect = CGDisplayBounds(CGMainDisplayID())
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "djiecast.capture", qos: .userInteractive)
    private(set) var lastBuffer: CVPixelBuffer?

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw NSError(domain: "DjieCast", code: 1, userInfo: [NSLocalizedDescriptionKey: "Layar tidak ditemukan"])
        }
        displayBounds = CGDisplayBounds(display.displayID)
        // Keep the Djie Cast window itself out of the picture.
        let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        let maxW = 1920.0
        let scale = min(maxW / Double(display.width), 2.0)
        cfg.width = Int(Double(display.width) * scale) & ~1
        cfg.height = Int(Double(display.height) * scale) & ~1
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        cfg.showsCursor = true
        cfg.queueDepth = 5
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = atts.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        lastBuffer = pb
        onPixelBuffer?(pb, CMSampleBufferGetPresentationTimeStamp(sb))
    }
}

/// Generates moving test frames (used by the self-test; no permissions needed).
final class SyntheticSource: FrameSource {
    var onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)?
    let displayBounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
    private var timer: DispatchSourceTimer?
    private var n: Int64 = 0

    func start() async throws {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "djiecast.synthetic"))
        t.schedule(deadline: .now(), repeating: .milliseconds(33))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }
    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1280, 800, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        guard let pb else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let shift = Int(n * 8 % 1280)
        for y in 0..<800 {
            let row = base + y * stride
            for x in 0..<1280 {
                let v = UInt8(((x + shift) / 40 + y / 40) % 2 == 0 ? 230 : 40)
                row[x * 4] = v; row[x * 4 + 1] = UInt8(y % 256); row[x * 4 + 2] = 120; row[x * 4 + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        onPixelBuffer?(pb, CMTime(value: n, timescale: 30))
        n += 1
    }
}

// MARK: - Input injection on the host

enum InputInjector {
    static var trusted: Bool { AXIsProcessTrusted() }
    private static var buttonsDown = Set<UInt8>()

    static func mouse(action: Remote.MouseAction, button: Remote.MouseButton, x: Float, y: Float, clicks: Int, flags: UInt64, in bounds: CGRect) {
        let p = CGPoint(x: bounds.minX + CGFloat(x) * bounds.width, y: bounds.minY + CGFloat(y) * bounds.height)
        let cgButton: CGMouseButton = button == .left ? .left : button == .right ? .right : .center
        let type: CGEventType
        switch (action, button) {
        case (.down, .left): type = .leftMouseDown; buttonsDown.insert(0)
        case (.down, .right): type = .rightMouseDown; buttonsDown.insert(1)
        case (.down, _): type = .otherMouseDown; buttonsDown.insert(2)
        case (.up, .left): type = .leftMouseUp; buttonsDown.remove(0)
        case (.up, .right): type = .rightMouseUp; buttonsDown.remove(1)
        case (.up, _): type = .otherMouseUp; buttonsDown.remove(2)
        case (.drag, .left): type = .leftMouseDragged
        case (.drag, .right): type = .rightMouseDragged
        case (.drag, _): type = .otherMouseDragged
        case (.move, _): type = .mouseMoved
        }
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: cgButton) else { return }
        if clicks > 1 { e.setIntegerValueField(.mouseEventClickState, value: Int64(clicks)) }
        e.flags = CGEventFlags(rawValue: flags)
        e.post(tap: .cghidEventTap)
    }

    static func scroll(dx: Int32, dy: Int32) {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    static func key(code: UInt16, down: Bool, flags: UInt64) {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return }
        e.flags = CGEventFlags(rawValue: flags)
        e.post(tap: .cghidEventTap)
    }
}

// MARK: - Host model

@MainActor
final class RemoteHostModel: ObservableObject {
    static let shared = RemoteHostModel()

    enum Status: Equatable { case off, waiting, connected(String), failed(String) }

    @Published var status: Status = .off
    @Published var code = Remote.newCode()
    @Published var addresses: [NetInfo.Address] = []
    @Published var screenAllowed = CGPreflightScreenCaptureAccess()
    @Published var inputAllowed = InputInjector.trusted
    @Published var port: UInt16 = Remote.port.rawValue

    var enabled: Bool { status != .off }
    var useSyntheticSource = false

    private var listener: NWListener?
    private var client: FramedConnection?
    private var source: FrameSource?
    private let encoder = H264Encoder()
    private let netQueue = DispatchQueue(label: "djiecast.remote.host")
    private var lastConfig: Data?
    private var hud: ControlledHUD?

    /// Set after the user asks for Screen Recording; macOS only applies it after a relaunch.
    @Published var screenRequested = false

    /// Cheap check, safe to poll. Never touches ScreenCaptureKit: asking it while access is missing
    /// makes macOS show its permission alert again, which is what kept nagging users.
    func refreshPermissions() {
        inputAllowed = InputInjector.trusted
        addresses = NetInfo.ipv4Addresses()
        if CGPreflightScreenCaptureAccess() { screenAllowed = true }
    }

    /// Live Screen Recording check (the preflight value is cached per launch). Only on explicit user action.
    func verifyScreenAccess() {
        Task {
            let ok = (try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)) != nil
            await MainActor.run { self.screenAllowed = ok || CGPreflightScreenCaptureAccess() }
        }
    }

    /// macOS keeps a grant per app signature; an older Djie Cast build can stay ticked in System Settings
    /// while this build is not trusted. Clear Djie Cast's entries so the next request starts clean.
    func resetPermissions() {
        let id = Bundle.main.bundleIdentifier ?? "local.djiecast.app"
        for service in ["ScreenCapture", "Accessibility"] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", service, id]
            try? p.run(); p.waitUntilExit()
        }
        screenRequested = false
        screenAllowed = false
        inputAllowed = InputInjector.trusted
        requestInputPermission()
        requestScreenPermission()
    }

    /// Relaunch so a freshly granted Screen Recording permission takes effect.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    func requestScreenPermission() {
        screenRequested = true
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        refreshPermissions()
    }

    func requestInputPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        refreshPermissions()
    }

    func setEnabled(_ on: Bool) { on ? start() : stop() }

    func regenerateCode() {
        code = Remote.newCode()
        if enabled { stop(); start() }
    }

    func start(port wanted: UInt16? = nil) {
        refreshPermissions()
        do {
            let params = Remote.parameters(code: code)
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: wanted ?? Remote.port.rawValue) ?? Remote.port)
            l.service = NWListener.Service(name: NetInfo.macName, type: Remote.serviceType)
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.port = l.port?.rawValue ?? Remote.port.rawValue
                        if case .off = self.status { self.status = .waiting }
                        if case .failed = self.status { self.status = .waiting }
                    case .failed(let e):
                        self.status = .failed(String(localized: "Tidak bisa membuka koneksi: \(e.localizedDescription)"))
                    default: break
                    }
                }
            }
            l.start(queue: netQueue)
            listener = l
            status = .waiting
        } catch {
            status = .failed(String(localized: "Tidak bisa membuka koneksi: \(error.localizedDescription)"))
        }
    }

    func stop() {
        endSession()
        listener?.cancel()
        listener = nil
        status = .off
    }

    func disconnectViewer() {
        client?.send(.bye)
        endSession()
        if listener != nil { status = .waiting }
    }

    // MARK: Session

    private func accept(_ conn: NWConnection) {
        guard client == nil else { conn.cancel(); return }   // one viewer at a time
        let c = FramedConnection(conn, queue: netQueue)
        client = c
        c.onState = { [weak self] state in
            Task { @MainActor in
                guard let self, self.client === c else { return }
                switch state {
                case .failed, .cancelled: self.endSession(); if self.listener != nil { self.status = .waiting }
                default: break
                }
            }
        }
        c.onMessage = { [weak self] kind, payload in self?.handle(kind, payload, from: c) }
        c.start()
    }

    /// Runs on the network queue.
    nonisolated private func handle(_ kind: Remote.Kind, _ payload: Data, from c: FramedConnection) {
        var r = Reader(payload)
        switch kind {
        case .hello:
            let name = String(decoding: payload, as: UTF8.self)
            c.send(.welcome, Data(NetInfo.macName.utf8))
            Task { @MainActor in self.beginStreaming(viewer: name.isEmpty ? "Mac lain" : name) }
        case .requestKeyframe:
            Task { @MainActor in self.encoder.requestKeyframe() }
        case .mouse:
            guard let a = r.u8(), let b = r.u8(), let x = r.f32(), let y = r.f32(), let clicks = r.u8(), let flags = r.u64(),
                  let action = Remote.MouseAction(rawValue: a), let button = Remote.MouseButton(rawValue: b) else { return }
            Task { @MainActor in
                InputInjector.mouse(action: action, button: button, x: x, y: y, clicks: Int(clicks), flags: flags,
                                    in: self.source?.displayBounds ?? CGDisplayBounds(CGMainDisplayID()))
            }
        case .scroll:
            guard let dx = r.i32(), let dy = r.i32() else { return }
            DispatchQueue.main.async { InputInjector.scroll(dx: dx, dy: dy) }
        case .key:
            guard let code = r.u16(), let down = r.u8(), let flags = r.u64() else { return }
            DispatchQueue.main.async { InputInjector.key(code: code, down: down == 1, flags: flags) }
        case .bye:
            Task { @MainActor in self.disconnectViewer() }
        default: break
        }
    }

    private func beginStreaming(viewer: String) {
        status = .connected(viewer)
        hud = ControlledHUD(viewer: viewer) { [weak self] in self?.disconnectViewer() }
        let src: FrameSource = useSyntheticSource ? SyntheticSource() : ScreenSource()
        source = src
        encoder.requestKeyframe()
        encoder.onFrame = { [weak self] data, isKey, fmt in self?.sendFrame(data, isKey: isKey, fmt: fmt) }
        src.onPixelBuffer = { [weak self] pb, pts in
            guard let self else { return }
            self.encoder.encode(pb, pts: pts)
        }
        Task {
            do { try await src.start() }
            catch {
                await MainActor.run {
                    self.status = .failed("Gagal merekam layar. Pastikan izin Perekaman Layar untuk Djie Cast sudah aktif.")
                    self.disconnectViewer()
                }
            }
        }
    }

    nonisolated private func sendFrame(_ data: Data, isKey: Bool, fmt: CMFormatDescription?) {
        Task { @MainActor in
            guard let c = self.client else { return }
            if isKey, let fmt, let (sps, pps) = H264Encoder.parameterSets(fmt) {
                let dims = CMVideoFormatDescriptionGetDimensions(fmt)
                var w = Writer()
                w.u32(UInt32(dims.width)); w.u32(UInt32(dims.height)); w.blob(sps); w.blob(pps)
                if w.data != self.lastConfig { self.lastConfig = w.data }
                c.send(.videoConfig, w.data)
            }
            // Back-pressure: if the network is behind, drop delta frames and ask for a fresh keyframe.
            if !isKey && c.pending > 6 { self.encoder.requestKeyframe(); return }
            var w = Writer()
            w.u8(isKey ? 1 : 0)
            w.data.append(data)
            c.send(.videoFrame, w.data)
        }
    }

    private func endSession() {
        source?.stop(); source = nil
        encoder.onFrame = nil
        encoder.stop()
        client?.cancel(); client = nil
        lastConfig = nil
        hud?.close(); hud = nil
    }
}

// MARK: - "This Mac is being controlled" floating panel

final class ControlledHUD {
    private let panel: NSPanel

    init(viewer: String, onDisconnect: @escaping () -> Void) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 56),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentView = NSHostingView(rootView: HUDView(viewer: viewer, onDisconnect: onDisconnect))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 180, y: f.maxY - 72))
        }
        panel.orderFrontRegardless()
    }

    func close() { panel.orderOut(nil) }

    private struct HUDView: View {
        let viewer: String
        let onDisconnect: () -> Void
        var body: some View {
            HStack(spacing: 10) {
                PulseDot(color: .red)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mac ini sedang dikontrol").font(.system(size: 12, weight: .semibold))
                    Text(L(viewer)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Putuskan", action: onDisconnect)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .frame(width: 360, height: 56)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        }
    }
}
