import Foundation
import AppKit

// MARK: - Built-in Tailscale (libtailscale / tsnet)
//
// Djie Cast joins the user's tailnet as its own node ("djiecast-<mac>"), so no
// separate Tailscale app is needed. Remote Desktop traffic is bridged through it;
// the session itself stays end-to-end TLS-PSK encrypted with the access code.

@MainActor
final class TailnetModel: ObservableObject {
    static let shared = TailnetModel()

    struct Peer: Identifiable, Hashable {
        let id: String
        let name: String       // Mac name without the "djiecast-" prefix
        let ip: String
        let online: Bool
    }

    enum State: Equatable { case off, starting, needsLogin(URL), connected(String), failed(String) }

    @Published var state: State = .off
    @Published var peers: [Peer] = []
    @Published var account: String?

    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "tailnetEnabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "tailnetEnabled") }
    }

    private var sd: tailscale = -1
    private var hostListener: tailscale_listener = -1
    private var poll: Task<Void, Never>?
    private var openedLoginURL: URL?

    static let stateDir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Djie Cast/tailscale", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static var hostname: String {
        let base = NetInfo.macName.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let cleaned = String(base).split(separator: "-").joined(separator: "-")
        return "djiecast-" + (cleaned.isEmpty ? "mac" : String(cleaned.prefix(40)))
    }

    var ip: String? { if case .connected(let ip) = state { return ip }; return nil }

    /// True once a login has been saved in the state dir (tsnet writes tailscaled.state after login).
    static var hasSavedLogin: Bool {
        let f = stateDir.appendingPathComponent("tailscaled.state")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: f.path), let size = attrs[.size] as? Int else { return false }
        return size > 200 && UserDefaults.standard.bool(forKey: "tailnetLoggedIn")
    }

    /// On launch: reconnect silently with the saved login. Never opens a login page by itself.
    func autoStart() {
        if enabled && state == .off && Self.hasSavedLogin { start(userInitiated: false) }
    }

    /// Set while a login was requested by the user; only then may a browser page open.
    private var userInitiated = false

    func start(userInitiated: Bool = true) {
        guard sd < 0 else { return }
        self.userInitiated = userInitiated
        enabled = true
        signal(SIGPIPE, SIG_IGN)
        state = .starting
        let s = tailscale_new()
        sd = s
        tailscale_set_dir(s, Self.stateDir.path)
        tailscale_set_hostname(s, Self.hostname)
        // Quiet logs: send them to /dev/null (status comes from LocalAPI below).
        let devnull = open("/dev/null", O_WRONLY)
        tailscale_set_logfd(s, devnull)

        Thread.detachNewThread { [weak self] in
            let rc = tailscale_up(s)
            Task { @MainActor in
                guard let self, self.sd == s else { return }
                if rc != 0 { self.state = .failed(String(localized: "Gagal terhubung ke Tailscale: \(Self.errmsg(s))")) }
                else { self.onUp() }
            }
        }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatus()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Stops the node. With `forget`, the login is removed so another account can be used.
    func stop(forget: Bool = false, keepEnabled: Bool = false) {
        poll?.cancel(); poll = nil
        if sd >= 0 { tailscale_close(sd) }
        sd = -1; hostListener = -1
        peers = []; account = nil; openedLoginURL = nil
        state = .off
        if forget {
            try? FileManager.default.removeItem(at: Self.stateDir)
            try? FileManager.default.createDirectory(at: Self.stateDir, withIntermediateDirectories: true)
            UserDefaults.standard.set(false, forKey: "tailnetLoggedIn")
        }
        if !keepEnabled { enabled = false }
    }

    func shutdownForQuit() {
        poll?.cancel(); poll = nil
        if sd >= 0 { tailscale_close(sd) }
        sd = -1
    }

    private func onUp() {
        var buf = [CChar](repeating: 0, count: 256)
        tailscale_getips(sd, &buf, buf.count)
        let ips = String(cString: buf).split(separator: ",").map(String.init)
        state = .connected(ips.first { !$0.contains(":") } ?? ips.first ?? "?")
        startHostBridge()
        Task { await refreshStatus() }
    }

    private static func errmsg(_ s: tailscale) -> String {
        var buf = [CChar](repeating: 0, count: 512)
        tailscale_errmsg(s, &buf, buf.count)
        return String(cString: buf)
    }

    // MARK: Status / peers

    private func refreshStatus() async {
        guard sd >= 0 else { return }
        let s = sd
        let json: Data? = await Task.detached {
            var out: UnsafeMutablePointer<CChar>?
            guard tailscale_status_json(s, &out) == 0, let out else { return nil }
            defer { free(out) }
            return Data(bytes: out, count: strlen(out))
        }.value
        guard sd == s, let json, let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return }

        let backend = obj["BackendState"] as? String ?? ""
        if backend == "Running" { UserDefaults.standard.set(true, forKey: "tailnetLoggedIn") }
        if backend == "NeedsLogin" && !userInitiated {
            // Saved login expired: stop quietly and let the user press "Aktifkan & masuk".
            UserDefaults.standard.set(false, forKey: "tailnetLoggedIn")
            stop(keepEnabled: false)
            return
        }
        if backend == "NeedsLogin", let auth = obj["AuthURL"] as? String, !auth.isEmpty, let url = URL(string: auth) {
            if state != .needsLogin(url) {
                state = .needsLogin(url)
                if openedLoginURL != url {
                    openedLoginURL = url
                    if ProcessInfo.processInfo.environment["DJIE_TAILNET_SELFTEST"] == nil { NSWorkspace.shared.open(url) }
                }
            }
        }
        if let users = obj["User"] as? [String: Any], let selfNode = obj["Self"] as? [String: Any],
           let uid = selfNode["UserID"] as? Int, let u = users[String(uid)] as? [String: Any] {
            account = u["LoginName"] as? String
        }
        var list: [Peer] = []
        for (key, value) in obj["Peer"] as? [String: Any] ?? [:] {
            guard let p = value as? [String: Any], let host = p["HostName"] as? String, host.hasPrefix("djiecast-"),
                  let ip = (p["TailscaleIPs"] as? [String])?.first(where: { !$0.contains(":") }) else { continue }
            let dns = (p["DNSName"] as? String ?? "").split(separator: ".").first.map(String.init) ?? host
            let name = String(dns.dropFirst("djiecast-".count)).replacingOccurrences(of: "-", with: " ")
            list.append(Peer(id: key, name: name.isEmpty ? host : name.capitalized, ip: ip, online: p["Online"] as? Bool ?? false))
        }
        peers = list.sorted { ($0.online ? 0 : 1, $0.name) < ($1.online ? 0 : 1, $1.name) }
    }

    // MARK: Host side: tailnet :47800 → local Remote Desktop listener

    private func startHostBridge() {
        guard sd >= 0, hostListener < 0 else { return }
        var ln: tailscale_listener = -1
        guard tailscale_listen(sd, "tcp", ":\(Remote.port.rawValue)", &ln) == 0 else { return }
        hostListener = ln
        let s = sd
        Thread.detachNewThread {
            while true {
                var conn: tailscale_conn = -1
                guard tailscale_accept(ln, &conn) == 0 else { break }
                let port = DispatchQueue.main.sync { MainActor.assumeIsolated { RemoteHostModel.shared.enabled ? RemoteHostModel.shared.port : 0 } }
                guard port > 0, let local = Bridge.connectLocal(port: port) else { close(conn); continue }
                Bridge.pump(conn, local)
            }
            _ = s
        }
    }

    // MARK: Viewer side: local 127.0.0.1:<port> → tailnet peer

    /// Returns a local port; the first connection to it is forwarded to `ip:47800` over the tailnet.
    func openTunnel(to ip: String) -> UInt16? {
        guard sd >= 0 else { return nil }
        let s = sd
        guard let (server, port) = Bridge.listenLocal() else { return nil }
        Thread.detachNewThread {
            let client = accept(server, nil, nil)
            close(server)
            guard client >= 0 else { return }
            var conn: tailscale_conn = -1
            guard tailscale_dial(s, "tcp", "\(ip):\(Remote.port.rawValue)", &conn) == 0 else { close(client); return }
            Bridge.pump(conn, client)
        }
        return port
    }
}

// MARK: - Socket plumbing

enum Bridge {
    static func connectLocal(port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if ok != 0 { close(fd); return nil }
        noSigPipe(fd)
        return fd
    }

    static func listenLocal() -> (Int32, UInt16)? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) == 0 && listen(fd, 1) == 0 && getsockname(fd, $0, &len) == 0 }
        }
        guard bound else { close(fd); return nil }
        return (fd, UInt16(bigEndian: addr.sin_port))
    }

    static func noSigPipe(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Copies bytes both ways until either side closes.
    static func pump(_ a: Int32, _ b: Int32) {
        noSigPipe(a); noSigPipe(b)
        let group = DispatchGroup()
        for (from, to) in [(a, b), (b, a)] {
            group.enter()
            Thread.detachNewThread {
                var buf = [UInt8](repeating: 0, count: 64 * 1024)
                while true {
                    let n = read(from, &buf, buf.count)
                    if n <= 0 { break }
                    var off = 0
                    while off < n {
                        let w = buf.withUnsafeBytes { write(to, $0.baseAddress! + off, n - off) }
                        if w <= 0 { off = -1; break }
                        off += w
                    }
                    if off < 0 { break }
                }
                shutdown(to, SHUT_WR)
                group.leave()
            }
        }
        group.notify(queue: .global()) { close(a); close(b) }
    }
}
