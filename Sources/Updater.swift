import SwiftUI
import AppKit
import CryptoKit

/// Update check without a server of our own: the app reads `update.json` from the project's
/// GitHub Pages site. `minimum` makes an update mandatory, `latest` only offers one.
///
///   { "latest": "1.1", "minimum": "1.1", "url": "https://github.com/masadjie/djie-cast/releases/latest",
///     "notes": "Apa yang baru…" }
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let feed = URL(string: "https://masadjie.github.io/djie-cast/update.json")!

    struct Info: Decodable {
        let latest: String
        let minimum: String?
        let url: String?
        let notes: String?
        /// Direct DMG link + its SHA-256, for in-app updating.
        let dmg: String?
        let sha256: String?
    }

    enum Install: Equatable { case idle, downloading(Double), installing, failed(String) }
    @Published var install: Install = .idle
    var installing: Bool { if case .downloading = install { return true }; return install == .installing }

    /// True when this copy can replace itself: a direct DMG is published and the app folder is writable
    /// (not running from the DMG or from a read-only/translocated location).
    var canSelfUpdate: Bool {
        guard info?.dmg != nil else { return false }
        let app = Bundle.main.bundleURL
        let path = app.path
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") { return false }
        return FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: path)
    }

    /// The download button: install in place when possible, otherwise open the release page.
    func update() {
        if canSelfUpdate { Task { await installUpdate() } } else { NSWorkspace.shared.open(downloadURL) }
    }

    /// Download → verify SHA-256 → mount → check it is Djie Cast → swap the app after we quit → relaunch.
    func installUpdate() async {
        guard let info, let dmgString = info.dmg, let dmgURL = URL(string: dmgString), !installing else { return }
        install = .downloading(0)
        do {
            let file = try await download(dmgURL)
            install = .installing
            if let want = info.sha256?.lowercased(), !want.isEmpty {
                let got = try await Task.detached { () -> String in
                    let data = try Data(contentsOf: file, options: .mappedIfSafe)
                    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                }.value
                guard got == want else { throw Fail(String(localized: "File unduhan tidak cocok (checksum berbeda). Coba lagi.")) }
            }
            let staged = try await stage(file)
            try relaunch(replacingWith: staged)
        } catch {
            install = .failed((error as? Fail)?.message ?? error.localizedDescription)
        }
    }

    struct Fail: Error { let message: String; init(_ m: String) { message = m } }

    private func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.downloadTask(with: url) { tmp, resp, err in
                if let err { cont.resume(throwing: err); return }
                guard let tmp, (resp as? HTTPURLResponse)?.statusCode ?? 200 == 200 else {
                    cont.resume(throwing: Fail(String(localized: "Unduhan gagal. Periksa koneksi internet."))); return
                }
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("DjieCast-update.dmg")
                try? FileManager.default.removeItem(at: dest)
                do { try FileManager.default.moveItem(at: tmp, to: dest); cont.resume(returning: dest) }
                catch { cont.resume(throwing: error) }
            }
            let progress = task.progress
            Task { @MainActor in
                while !progress.isFinished && !progress.isCancelled {
                    self.install = .downloading(progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            task.resume()
        }
    }

    /// Mounts the DMG and copies the new app next to the current one as a hidden staging bundle.
    private func stage(_ dmg: URL) async throws -> URL {
        let appDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let staged = appDir.appendingPathComponent(".Djie Cast.update.app")
        let bundleID = Bundle.main.bundleIdentifier ?? "local.djiecast.app"
        return try await Task.detached { () -> URL in
            func run(_ exe: String, _ args: [String]) -> (Int32, String) {
                let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
                guard (try? p.run()) != nil else { return (-1, "") }
                let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                p.waitUntilExit(); return (p.terminationStatus, out)
            }
            let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("djiecast-update-mnt")
            try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            let (rc, out) = run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint.path])
            guard rc == 0 else { throw Fail(String(localized: "Tidak bisa membuka file update: \(out)")) }
            defer { _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }
            let items = (try? FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)) ?? []
            guard let newApp = items.first(where: { $0.pathExtension == "app" }),
                  Bundle(url: newApp)?.bundleIdentifier == bundleID else {
                throw Fail(String(localized: "File update bukan Djie Cast."))
            }
            guard run("/usr/bin/codesign", ["--verify", "--deep", newApp.path]).0 == 0 else {
                throw Fail(String(localized: "Tanda tangan aplikasi di file update tidak valid."))
            }
            try? FileManager.default.removeItem(at: staged)
            guard run("/usr/bin/ditto", [newApp.path, staged.path]).0 == 0 else {
                throw Fail(String(localized: "Tidak bisa menyalin versi baru ke folder aplikasi."))
            }
            return staged
        }.value
    }

    /// A tiny helper script waits for Djie Cast to quit, swaps the bundles and opens the new version.
    private func relaunch(replacingWith staged: URL) throws {
        let app = Bundle.main.bundleURL.path
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
        rm -rf \(q(app)).old
        mv \(q(app)) \(q(app)).old && mv \(q(staged.path)) \(q(app)) && rm -rf \(q(app)).old || mv \(q(app)).old \(q(app))
        xattr -dr com.apple.quarantine \(q(app)) 2>/dev/null
        open \(q(app))
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try p.run()
        NSApp.terminate(nil)
    }

    enum State: Equatable { case idle, optional(String), required(String) }
    @Published var state: State = .idle
    @Published var info: Info?
    @Published var dismissedOptional = false

    /// The newer version on offer, if any (optional or required).
    var availableVersion: String? {
        switch state { case .optional(let v), .required(let v): return v; case .idle: return nil }
    }

    var downloadURL: URL {
        URL(string: info?.url ?? "") ?? URL(string: "https://github.com/masadjie/djie-cast/releases/latest")!
    }

    /// Compares dotted versions numerically: 1.10 > 1.9, 1.0 == 1.
    nonisolated static func isOlder(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    func check() {
        // DJIE_UPDATE_FEED points at a test feed (also file://); otherwise skip in demo/snapshot runs.
        let testFeed = Demo.env["DJIE_UPDATE_FEED"].flatMap(URL.init(string:))
        guard testFeed != nil || (!Demo.enabled && Demo.snapshotPath == nil) else { return }
        Task {
            var req = URLRequest(url: testFeed ?? Self.feed, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
            req.setValue("Djie Cast/\(Brand.version)", forHTTPHeaderField: "User-Agent")
            // Offline or the feed is unreachable: never lock anyone out because of the network.
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode ?? 200 == 200,
                  let info = try? JSONDecoder().decode(Info.self, from: data) else { return }
            self.info = info
            let current = Brand.version
            defer { if Demo.env["DJIE_AUTOUPDATE"] != nil, availableVersion != nil { update() } }   // test aid
            if let min = info.minimum, Self.isOlder(current, than: min) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { state = .required(info.latest) }
            } else if Self.isOlder(current, than: info.latest) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { state = .optional(info.latest) }
            }
        }
    }
}

/// Covers the whole window when an update is mandatory; the app cannot be used until it is updated.
struct RequiredUpdateView: View {
    @ObservedObject var updater = Updater.shared
    let version: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture {}   // swallow clicks meant for the app behind
            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                    .shadow(color: Brand.start.opacity(0.5), radius: 24, y: 10)
                VStack(spacing: 6) {
                    Text("WAJIB UPDATE").font(.system(size: 11, weight: .semibold, design: .monospaced)).kerning(1.4)
                        .foregroundStyle(.orange)
                    Text("Djie Cast \(version) sudah tersedia").font(.system(size: 24, weight: .bold))
                    Text("Versi \(Brand.version) yang kamu pakai sudah tidak didukung. Unduh versi terbaru untuk lanjut memakai Djie Cast.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notes = updater.info?.notes, !notes.isEmpty {
                    Text(L(notes)).font(.callout).lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
                HStack(spacing: 10) {
                    Button { NSApp.terminate(nil) } label: { Text("Keluar") }
                        .buttonStyle(SoftButtonStyle(tint: .secondary)).fixedSize()
                    Button { updater.update() } label: {
                        Label(updater.canSelfUpdate ? "Update ke \(version)" : "Unduh versi \(version)", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(GradientButtonStyle(colors: Brand.colors)).fixedSize()
                    .keyboardShortcut(.defaultAction)
                }
                UpdateProgress()
                Text(updater.canSelfUpdate ? "Djie Cast mengunduh, memasang, dan membuka ulang dirinya sendiri." : "Setelah mengunduh: buka DMG, seret Djie Cast ke Applications dan ganti versi lama.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(32)
            .frame(width: 460)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
        }
    }
}

/// A slim banner for an optional update.
struct OptionalUpdateBanner: View {
    @ObservedObject var updater = Updater.shared
    let version: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").foregroundStyle(Brand.start)
            Text("Djie Cast \(version) sudah tersedia").font(.callout.weight(.semibold))
            if let notes = updater.info?.notes { Text(L(notes)).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            if updater.install != .idle {
                UpdateProgress(compact: true)
                if case .failed = updater.install {
                    Button("Coba lagi") { updater.update() }.buttonStyle(GradientButtonStyle(colors: Brand.colors)).fixedSize()
                }
            } else {
                Button("Nanti") { withAnimation { updater.dismissedOptional = true } }.buttonStyle(.borderless)
                Button { updater.update() } label: { Label(updater.canSelfUpdate ? "Update sekarang" : "Unduh", systemImage: "arrow.down.circle.fill") }
                    .buttonStyle(GradientButtonStyle(colors: Brand.colors)).fixedSize()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.start.opacity(0.3)))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .padding(16)
        .frame(maxWidth: 760)
    }
}


/// Download / install progress for the in-app updater.
struct UpdateProgress: View {
    @ObservedObject var updater = Updater.shared
    var compact = false

    var body: some View {
        switch updater.install {
        case .idle: EmptyView()
        case .downloading(let p):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: p).tint(Brand.start).frame(minWidth: compact ? 120 : 220)
                Text("Mengunduh… \(Int(p * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Memasang — Djie Cast akan dibuka ulang").font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let msg):
            HStack(spacing: 8) {
                Label(L(msg), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Button("Unduh manual") { NSWorkspace.shared.open(updater.downloadURL) }.buttonStyle(.borderless).font(.caption)
            }
        }
    }
}
