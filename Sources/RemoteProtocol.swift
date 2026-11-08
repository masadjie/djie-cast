import Foundation
import Network
import CryptoKit

// MARK: - Wire protocol
//
// Every message: [type: UInt8][length: UInt32 big-endian][payload].
// The TCP stream is wrapped in TLS 1.2 with a pre-shared key derived from the
// 6-digit session code, so a wrong code fails the handshake before any data flows.

enum Remote {
    static let serviceType = "_djiecast._tcp"
    static let port: NWEndpoint.Port = 47800
    static let pskIdentity = "DjieCast-Remote-v1"

    enum Kind: UInt8 {
        case hello = 1        // viewer → host: UTF-8 viewer name
        case welcome = 2      // host → viewer: UTF-8 host name
        case videoConfig = 3  // host → viewer: width, height, SPS, PPS
        case videoFrame = 4   // host → viewer: keyframe flag + AVCC NAL units
        case mouse = 10       // viewer → host
        case scroll = 11      // viewer → host
        case key = 12         // viewer → host
        case requestKeyframe = 13
        case bye = 20
    }

    enum MouseAction: UInt8 { case move = 0, down = 1, up = 2, drag = 3 }
    enum MouseButton: UInt8 { case left = 0, right = 1, other = 2 }

    /// Network parameters (TCP + TLS-PSK from the session code).
    static func parameters(code: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = SymmetricKey(data: Data(code.utf8))
        let psk = HMAC<SHA256>.authenticationCode(for: Data(pskIdentity.utf8), using: key)
        let pskData = Data(psk).withUnsafeBytes { DispatchData(bytes: $0) }
        let idData = Data(pskIdentity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, pskData as __DispatchData, idData as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,
                                                    tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        let params = NWParameters(tls: tls, tcp: tcp)
        params.includePeerToPeer = true
        return params
    }

    static func newCode() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }
}

// MARK: - Binary helpers

struct Writer {
    var data = Data()
    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    mutating func f32(_ v: Float) { u32(v.bitPattern) }
    mutating func u64(_ v: UInt64) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    mutating func blob(_ d: Data) { u32(UInt32(d.count)); data.append(d) }
}

struct Reader {
    let data: Data
    var i: Int
    init(_ d: Data) { data = d; i = d.startIndex }
    mutating func bytes(_ n: Int) -> Data? {
        guard i + n <= data.endIndex else { return nil }
        defer { i += n }
        return data.subdata(in: i..<(i + n))
    }
    mutating func u8() -> UInt8? { bytes(1)?.first }
    mutating func u16() -> UInt16? { bytes(2).map { $0.reduce(0) { $0 << 8 | UInt16($1) } } }
    mutating func u32() -> UInt32? { bytes(4).map { $0.reduce(0) { $0 << 8 | UInt32($1) } } }
    mutating func i32() -> Int32? { u32().map { Int32(bitPattern: $0) } }
    mutating func f32() -> Float? { u32().map { Float(bitPattern: $0) } }
    mutating func u64() -> UInt64? { bytes(8).map { $0.reduce(0) { $0 << 8 | UInt64($1) } } }
    mutating func blob() -> Data? { guard let n = u32() else { return nil }; return bytes(Int(n)) }
    var rest: Data { data.subdata(in: i..<data.endIndex) }
}

// MARK: - Framed connection

/// Wraps an NWConnection with length-prefixed messages and simple back-pressure.
final class FramedConnection {
    let connection: NWConnection
    private let queue: DispatchQueue
    var onMessage: ((Remote.Kind, Data) -> Void)?
    var onState: ((NWConnection.State) -> Void)?
    private(set) var inFlight = 0          // sends not yet handed to the network
    private let lock = NSLock()

    init(_ connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.onState?(state)
            if case .ready = state { self?.receiveHeader() }
        }
        connection.start(queue: queue)
    }

    func cancel() { connection.cancel() }

    var pending: Int { lock.lock(); defer { lock.unlock() }; return inFlight }

    func send(_ kind: Remote.Kind, _ payload: Data = Data()) {
        var w = Writer()
        w.u8(kind.rawValue)
        w.u32(UInt32(payload.count))
        w.data.append(payload)
        lock.lock(); inFlight += 1; lock.unlock()
        connection.send(content: w.data, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.inFlight -= 1; self.lock.unlock()
        })
    }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] data, _, done, error in
            guard let self else { return }
            guard error == nil, let data, data.count == 5 else {
                if done || error != nil { self.connection.cancel() }
                return
            }
            var r = Reader(data)
            let kindRaw = r.u8()!, len = Int(r.u32()!)
            guard len <= 64 << 20 else { self.connection.cancel(); return }
            if len == 0 {
                if let kind = Remote.Kind(rawValue: kindRaw) { self.onMessage?(kind, Data()) }
                self.receiveHeader()
            } else {
                self.receiveBody(kindRaw, len)
            }
        }
    }

    private func receiveBody(_ kindRaw: UInt8, _ len: Int) {
        connection.receive(minimumIncompleteLength: len, maximumLength: len) { [weak self] data, _, done, error in
            guard let self else { return }
            guard error == nil, let data, data.count == len else {
                if done || error != nil { self.connection.cancel() }
                return
            }
            if let kind = Remote.Kind(rawValue: kindRaw) { self.onMessage?(kind, data) }
            self.receiveHeader()
        }
    }
}

// MARK: - Local addresses (to show the host's IP, incl. Tailscale 100.x)

enum NetInfo {
    struct Address: Hashable { let ip: String; let label: String }

    static func ipv4Addresses() -> [Address] {
        var result: [Address] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            let name = String(cString: ptr.pointee.ifa_name)
            let label: String
            if ip.hasPrefix("100.") { label = "Tailscale" }
            else if name.hasPrefix("utun") || name.hasPrefix("zt") { label = "VPN" }
            else if ["bridge", "vnic", "vmnet", "vboxnet"].contains(where: name.hasPrefix) { label = "Virtual" }
            else if ip.hasPrefix("169.254.") { continue }
            else { label = "Jaringan lokal" }
            result.append(Address(ip: ip, label: label))
        }
        let rank = ["Jaringan lokal": 0, "Tailscale": 1, "VPN": 2, "Virtual": 3]
        return Array(Set(result)).sorted { (rank[$0.label] ?? 9, $0.ip) < (rank[$1.label] ?? 9, $1.ip) }
    }

    static var macName: String { Host.current().localizedName ?? "Mac" }
}
