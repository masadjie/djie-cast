import SwiftUI
import AppKit
import CryptoKit

// MARK: - SDK locations

enum AndroidSDK {
    /// Standard location shared with Android Studio.
    static let root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Android/sdk")
    static let avdHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".android/avd")
    static var emulatorBinary: URL { root.appendingPathComponent("emulator/emulator") }
    static var hostArch: String {
        var sys = utsname(); uname(&sys)
        let m = withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        return m == "arm64" ? "aarch64" : "x64"
    }
    static var abi: String { hostArch == "aarch64" ? "arm64-v8a" : "x86_64" }

    static func properties(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var d: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { d[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        return d
    }

    static func androidName(api: String) -> String {
        let major = Int(api.split(separator: ".").first ?? "") ?? 0
        let names = [29: "10", 30: "11", 31: "12", 32: "12L", 33: "13", 34: "14", 35: "15", 36: "16", 37: "17"]
        return names[major].map { "Android \($0)" } ?? "Android API \(api)"
    }
}

// MARK: - Catalog (Google's public SDK repository XML)

struct SDKArchive: Hashable {
    let url: URL
    let size: Int64
    let sha1: String
}

struct SystemImageOption: Identifiable, Hashable {
    let path: String          // system-images;android-36.1;google_apis_playstore;arm64-v8a
    let api: String
    let tag: String
    let abi: String
    let archive: SDKArchive
    let license: String
    var id: String { path }
    var relDir: String { path.split(separator: ";").joined(separator: "/") }
    var playStore: Bool { tag.contains("playstore") }
    var title: String { "\(AndroidSDK.androidName(api: api)) · API \(api)" }
    var subtitle: String { (playStore ? "Google Play" : "Google APIs") + (tag.contains("ps16k") ? " · halaman 16 KB" : "") }
}

struct EmulatorPackage: Hashable {
    let version: String
    let archive: SDKArchive
    let license: String
}

enum SDKCatalog {
    static let base = URL(string: "https://dl.google.com/android/repository/")!

    static func fetch() async throws -> (EmulatorPackage?, [SystemImageOption], [String: String]) {
        async let repoData = URLSession.shared.data(from: base.appendingPathComponent("repository2-3.xml")).0
        async let playData = URLSession.shared.data(from: base.appendingPathComponent("sys-img/google_apis_playstore/sys-img2-3.xml")).0
        async let apisData = URLSession.shared.data(from: base.appendingPathComponent("sys-img/google_apis/sys-img2-3.xml")).0
        let repo = try XMLDocument(data: try await repoData)
        var licenses = Self.licenses(repo)

        // Emulator: newest stable (channel-0) build for this Mac's CPU
        var emulator: EmulatorPackage?
        for pkg in try repo.nodes(forXPath: "//*[local-name()='remotePackage'][@path='emulator']") {
            guard let el = pkg as? XMLElement, Self.text(el, "channelRef/@ref") == "channel-0",
                  let archive = Self.archive(el, base: base, hostArch: AndroidSDK.hostArch) else { continue }
            let version = ["major", "minor", "micro"].compactMap { Self.text(el, "revision/\($0)") }.joined(separator: ".")
            if emulator == nil || version.compare(emulator!.version, options: .numeric) == .orderedDescending {
                emulator = EmulatorPackage(version: version, archive: archive, license: Self.text(el, "uses-license/@ref") ?? "android-sdk-license")
            }
        }

        var images: [SystemImageOption] = []
        for (data, dir) in [(try await playData, "google_apis_playstore"), (try await apisData, "google_apis")] {
            let doc = try XMLDocument(data: data)
            licenses.merge(Self.licenses(doc)) { a, _ in a }
            for pkg in try doc.nodes(forXPath: "//*[local-name()='remotePackage']") {
                guard let el = pkg as? XMLElement, let path = el.attribute(forName: "path")?.stringValue,
                      Self.text(el, "channelRef/@ref") == "channel-0" else { continue }
                let parts = path.split(separator: ";").map(String.init)
                guard parts.count == 4, parts[3] == AndroidSDK.abi else { continue }
                let api = parts[1].replacingOccurrences(of: "android-", with: "")
                // Stable numbered releases only (no beta / canary / preview letters)
                guard api.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil,
                      (Int(api.split(separator: ".")[0]) ?? 0) >= 33,
                      let archive = Self.archive(el, base: base.appendingPathComponent("sys-img/\(dir)/"), hostArch: nil) else { continue }
                images.append(SystemImageOption(path: path, api: api, tag: parts[2], abi: parts[3], archive: archive,
                                                license: Self.text(el, "uses-license/@ref") ?? "android-sdk-license"))
            }
        }
        images.sort {
            if $0.api != $1.api { return $0.api.compare($1.api, options: .numeric) == .orderedDescending }
            if $0.playStore != $1.playStore { return $0.playStore }
            return $0.tag < $1.tag
        }
        return (emulator, images, licenses)
    }

    private static func text(_ el: XMLElement, _ xpath: String) -> String? {
        let xp = xpath.split(separator: "/").map { $0.hasPrefix("@") ? String($0) : "*[local-name()='\($0)']" }.joined(separator: "/")
        return (try? el.nodes(forXPath: xp))?.first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func archive(_ el: XMLElement, base: URL, hostArch: String?) -> SDKArchive? {
        guard let archives = try? el.nodes(forXPath: "*[local-name()='archives']/*[local-name()='archive']") else { return nil }
        for case let a as XMLElement in archives {
            let os = text(a, "host-os"), arch = text(a, "host-arch")
            if let hostArch {
                guard os == "macosx", arch == nil || arch == hostArch else { continue }
            } else if let os, os != "macosx" { continue }
            guard let urlText = text(a, "complete/url"), let size = Int64(text(a, "complete/size") ?? ""),
                  let sha = text(a, "complete/checksum") else { continue }
            return SDKArchive(url: URL(string: urlText, relativeTo: base)!.absoluteURL, size: size, sha1: sha)
        }
        return nil
    }

    private static func licenses(_ doc: XMLDocument) -> [String: String] {
        var d: [String: String] = [:]
        for case let el as XMLElement in (try? doc.nodes(forXPath: "//*[local-name()='license']")) ?? [] {
            if let id = el.attribute(forName: "id")?.stringValue { d[id] = el.stringValue ?? "" }
        }
        return d
    }
}

// MARK: - AVDs

struct AVD: Identifiable, Hashable {
    let name: String
    let displayName: String
    let api: String
    let ramMB: Int
    let cores: Int
    let playStore: Bool
    let sysdir: String
    var id: String { name }
}

struct DeviceProfile: Identifiable, Hashable {
    let id: String, title: String, width: Int, height: Int, density: Int, icon: String
    static let all = [
        DeviceProfile(id: "phone", title: "Ponsel", width: 1080, height: 2400, density: 420, icon: "iphone.gen3"),
        DeviceProfile(id: "small", title: "Ponsel kecil", width: 720, height: 1600, density: 320, icon: "iphone.gen1"),
        DeviceProfile(id: "tablet", title: "Tablet", width: 2560, height: 1600, density: 320, icon: "ipad.landscape"),
    ]
}

// MARK: - Model

@MainActor
final class EmulatorModel: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = EmulatorModel()

    @Published var catalogState: String? = "Memuat katalog Google…"
    @Published var emulatorPackage: EmulatorPackage?
    @Published var images: [SystemImageOption] = []
    @Published var licenses: [String: String] = [:]
    @Published var installedEmulator: String?
    @Published var installedImages: Set<String> = []
    @Published var avds: [AVD] = []
    @Published var running: Set<String> = []
    @Published var download: (title: String, received: Int64, total: Int64, phase: String)?
    @Published var errorText: String?
    @Published var log = ""

    private var acceptedRaw: String {
        get { UserDefaults.standard.string(forKey: "acceptedSDKLicenses") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "acceptedSDKLicenses"); objectWillChange.send() }
    }
    // Launch preferences (bound with @AppStorage in the view using the same keys)
    private func pref(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    var noBootAnim: Bool { pref("emuNoBootAnim") }
    var quickBoot: Bool { pref("emuQuickBoot") }
    var showWindow: Bool { pref("emuShowWindow") }

    private var processes: [String: Process] = [:]
    private var task: URLSessionDownloadTask?
    private var pending: (option: Any, archive: SDKArchive, finish: @Sendable (URL) throws -> Void)?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    var ready: Bool { installedEmulator != nil && !installedImages.isEmpty }
    func accepted(_ license: String) -> Bool { acceptedRaw.split(separator: ",").contains(Substring(license)) }
    func accept(_ license: String) { if !accepted(license) { acceptedRaw += (acceptedRaw.isEmpty ? "" : ",") + license } }

    // MARK: Scan

    func refresh() {
        let props = AndroidSDK.properties(AndroidSDK.root.appendingPathComponent("emulator/source.properties"))
        installedEmulator = FileManager.default.isExecutableFile(atPath: AndroidSDK.emulatorBinary.path) ? (props["Pkg.Revision"] ?? "?") : nil

        var found = Set<String>()
        let sys = AndroidSDK.root.appendingPathComponent("system-images")
        for api in (try? FileManager.default.contentsOfDirectory(atPath: sys.path)) ?? [] {
            for tag in (try? FileManager.default.contentsOfDirectory(atPath: sys.appendingPathComponent(api).path)) ?? [] {
                for abi in (try? FileManager.default.contentsOfDirectory(atPath: sys.appendingPathComponent("\(api)/\(tag)").path)) ?? [] {
                    if FileManager.default.fileExists(atPath: sys.appendingPathComponent("\(api)/\(tag)/\(abi)/system.img").path) {
                        found.insert("system-images;\(api);\(tag);\(abi)")
                    }
                }
            }
        }
        installedImages = found

        var list: [AVD] = []
        for file in (try? FileManager.default.contentsOfDirectory(atPath: AndroidSDK.avdHome.path)) ?? [] where file.hasSuffix(".ini") {
            let name = String(file.dropLast(4))
            let ini = AndroidSDK.properties(AndroidSDK.avdHome.appendingPathComponent(file))
            let path = ini["path"].map { URL(fileURLWithPath: $0) } ?? AndroidSDK.avdHome.appendingPathComponent("\(name).avd")
            let cfg = AndroidSDK.properties(path.appendingPathComponent("config.ini"))
            list.append(AVD(name: name, displayName: cfg["avd.ini.displayname"] ?? name.replacingOccurrences(of: "_", with: " "),
                            api: (cfg["target"] ?? ini["target"] ?? "").replacingOccurrences(of: "android-", with: ""),
                            ramMB: Int(cfg["hw.ramSize"] ?? "") ?? 2048, cores: Int(cfg["hw.cpu.ncore"] ?? "") ?? 4,
                            playStore: cfg["PlayStore.enabled"] == "true", sysdir: cfg["image.sysdir.1"] ?? ""))
        }
        avds = list.sorted { $0.displayName < $1.displayName }
        detectRunning()
    }

    /// Emulators started outside Djie Cast count as running too.
    /// Runs `ps` off the main thread and reads its output *before* waiting — a full pipe would otherwise deadlock.
    private func detectRunning() {
        let names = avds.map(\.name)
        let ours = Set(processes.keys)
        Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/ps")
            p.arguments = ["-axo", "command"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            var r = ours
            for line in out.split(separator: "\n") where line.contains("qemu-system") || line.contains("/emulator") {
                for n in names where line.contains("-avd \(n) ") || line.hasSuffix("-avd \(n)") { r.insert(n) }
            }
            let result = r
            await MainActor.run { self.running = result }
        }
    }

    func loadCatalog() async {
        catalogState = "Memuat katalog Google…"
        do {
            let (emu, imgs, lic) = try await SDKCatalog.fetch()
            emulatorPackage = emu; images = imgs; licenses = lic
            catalogState = nil
        } catch {
            catalogState = "Tidak bisa memuat katalog. Periksa koneksi internet."
        }
        refresh()
    }

    // MARK: Downloads

    func installEmulator() {
        guard let pkg = emulatorPackage else { return }
        start(title: "Android Emulator \(pkg.version)", archive: pkg.archive) { zip in
            try EmulatorModel.unpack(zip, topFolder: "emulator", into: AndroidSDK.root.appendingPathComponent("emulator"))
        }
    }

    func installImage(_ img: SystemImageOption) {
        let abi = img.abi, dest = AndroidSDK.root.appendingPathComponent(img.relDir)
        start(title: "\(img.title) (\(img.subtitle))", archive: img.archive) { zip in
            try EmulatorModel.unpack(zip, topFolder: abi, into: dest)
        }
    }

    /// Finished downloads are kept here until installed, so a failed install never re-downloads GBs.
    nonisolated static let cacheDir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Djie Cast/android-sdk", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    nonisolated static func cached(_ a: SDKArchive) -> URL { cacheDir.appendingPathComponent("\(a.sha1).zip") }

    private func start(title: String, archive: SDKArchive, finish: @escaping @Sendable (URL) throws -> Void) {
        guard task == nil else { return }
        errorText = nil
        let cache = Self.cached(archive)
        if FileManager.default.fileExists(atPath: cache.path) {
            download = (title, archive.size, archive.size, "Memeriksa & memasang")
            install(zip: cache, archive: archive, finish: finish)
            return
        }
        download = (title, 0, archive.size, "Mengunduh")
        pending = (title, archive, finish)
        let t = session.downloadTask(with: archive.url)
        task = t
        t.resume()
    }

    private func install(zip: URL, archive: SDKArchive, finish: @escaping @Sendable (URL) throws -> Void) {
        Task.detached(priority: .userInitiated) {
            do {
                guard try Self.sha1(of: zip) == archive.sha1.lowercased() else {
                    try? FileManager.default.removeItem(at: zip)
                    throw NSError(domain: "DjieCast", code: 2, userInfo: [NSLocalizedDescriptionKey: "Checksum tidak cocok, file rusak saat diunduh. Coba lagi."])
                }
                try finish(zip)
                try? FileManager.default.removeItem(at: zip)      // installed: free the space
                await MainActor.run { self.download = nil; self.refresh() }
            } catch {
                await MainActor.run { self.download = nil; self.errorText = error.localizedDescription }
            }
        }
    }

    func cancelDownload() {
        task?.cancel(); task = nil; pending = nil; download = nil
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated {
            if let d = download { download = (d.title, totalBytesWritten, max(totalBytesExpectedToWrite, d.total), "Mengunduh") }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move out of the temporary location before this method returns.
        let staged = Self.cacheDir.appendingPathComponent("incoming-\(UUID().uuidString).zip")
        try? FileManager.default.moveItem(at: location, to: staged)
        MainActor.assumeIsolated {
            guard let job = pending else { return }
            task = nil; pending = nil
            let keep = Self.cached(job.archive)
            try? FileManager.default.removeItem(at: keep)
            try? FileManager.default.moveItem(at: staged, to: keep)
            if let d = download { download = (d.title, d.total, d.total, "Memeriksa & memasang") }
            install(zip: keep, archive: job.archive, finish: job.finish)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        MainActor.assumeIsolated {
            self.task = nil; pending = nil; download = nil
            errorText = "Unduhan gagal: \(error.localizedDescription)"
        }
    }

    nonisolated static func sha1(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = Insecure.SHA1()
        while let chunk = try h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Extracts with `unzip` (zip64-safe), falling back to `ditto`, then moves the archive's top folder into place.
    nonisolated static func unpack(_ zip: URL, topFolder: String, into dest: URL) throws {
        let fm = FileManager.default
        let staging = AndroidSDK.root.appendingPathComponent(".djiecast-temp-\(UUID().uuidString.prefix(6))")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        func run(_ tool: String, _ args: [String]) -> (Int32, String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            let err = Pipe(); p.standardError = err; p.standardOutput = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return (-1, "tidak bisa menjalankan \(tool)") }
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            return (p.terminationStatus, msg)
        }
        var (code, msg) = run("/usr/bin/unzip", ["-q", "-o", zip.path, "-d", staging.path])
        if code > 1 {   // unzip: 1 = warnings only
            try? fm.removeItem(at: staging); try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            (code, msg) = run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
        }
        guard code <= 1 else {
            throw NSError(domain: "DjieCast", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "Gagal mengekstrak arsip (\(code)): \(msg.trimmingCharacters(in: .whitespacesAndNewlines).suffix(200)). File tersimpan, klik Unduh lagi untuk mencoba memasang ulang tanpa mengunduh."])
        }
        let contents = try fm.contentsOfDirectory(atPath: staging.path).filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }
        let src = staging.appendingPathComponent(contents.contains(topFolder) ? topFolder : (contents.first ?? topFolder))
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) {
            let old = dest.deletingLastPathComponent().appendingPathComponent(".old-\(dest.lastPathComponent)-\(UUID().uuidString.prefix(4))")
            try fm.moveItem(at: dest, to: old)
            try? fm.removeItem(at: old)
        }
        try fm.moveItem(at: src, to: dest)
    }

    // MARK: Create / delete

    func createAVD(name rawName: String, profile: DeviceProfile, image: SystemImageOption, ramMB: Int, cores: Int, storageGB: Int) throws {
        let name = rawName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || "_-.".contains($0) }
        guard !name.isEmpty else { throw NSError(domain: "DjieCast", code: 4, userInfo: [NSLocalizedDescriptionKey: "Isi nama emulator."]) }
        let fm = FileManager.default
        let dir = AndroidSDK.avdHome.appendingPathComponent("\(name).avd")
        guard !fm.fileExists(atPath: dir.path) else { throw NSError(domain: "DjieCast", code: 5, userInfo: [NSLocalizedDescriptionKey: "Nama “\(name)” sudah dipakai."]) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ini = """
        avd.ini.encoding=UTF-8
        path=\(dir.path)
        path.rel=avd/\(name).avd
        target=android-\(image.api)

        """
        try ini.write(to: AndroidSDK.avdHome.appendingPathComponent("\(name).ini"), atomically: true, encoding: .utf8)
        let config: [(String, String)] = [
            ("AvdId", name), ("PlayStore.enabled", image.playStore ? "true" : "false"), ("abi.type", image.abi),
            ("avd.ini.displayname", rawName.trimmingCharacters(in: .whitespaces)), ("avd.ini.encoding", "UTF-8"),
            ("disk.dataPartition.size", "\(storageGB)G"), ("fastboot.forceColdBoot", "no"), ("fastboot.forceFastBoot", "yes"),
            ("hw.accelerometer", "yes"), ("hw.audioInput", "yes"), ("hw.battery", "yes"),
            ("hw.camera.back", "virtualscene"), ("hw.camera.front", "emulated"),
            ("hw.cpu.arch", image.abi == "arm64-v8a" ? "arm64" : "x86_64"), ("hw.cpu.ncore", "\(cores)"),
            ("hw.dPad", "no"), ("hw.device.manufacturer", "Generic"), ("hw.device.name", "djiecast_\(profile.id)"),
            ("hw.gps", "yes"), ("hw.gpu.enabled", "yes"), ("hw.gpu.mode", "host"), ("hw.gyroscope", "yes"),
            ("hw.initialOrientation", profile.width > profile.height ? "landscape" : "portrait"), ("hw.keyboard", "yes"),
            ("hw.lcd.density", "\(profile.density)"), ("hw.lcd.height", "\(profile.height)"), ("hw.lcd.width", "\(profile.width)"),
            ("hw.mainKeys", "no"), ("hw.ramSize", "\(ramMB)"), ("hw.sdCard", "yes"), ("hw.sensors.orientation", "yes"),
            ("hw.sensors.proximity", "yes"), ("hw.trackBall", "no"), ("image.sysdir.1", image.relDir + "/"),
            ("runtime.network.latency", "none"), ("runtime.network.speed", "full"), ("sdcard.size", "512M"),
            ("showDeviceFrame", "no"), ("skin.dynamic", "yes"), ("tag.id", image.tag),
            ("tag.display", image.playStore ? "Google Play" : "Google APIs"), ("target", "android-\(image.api)"),
            ("vm.heapSize", "256"),
        ]
        try config.map { "\($0.0)=\($0.1)" }.joined(separator: "\n").appending("\n")
            .write(to: dir.appendingPathComponent("config.ini"), atomically: true, encoding: .utf8)
        refresh()
    }

    func delete(_ avd: AVD) {
        stop(avd)
        try? FileManager.default.removeItem(at: AndroidSDK.avdHome.appendingPathComponent("\(avd.name).avd"))
        try? FileManager.default.removeItem(at: AndroidSDK.avdHome.appendingPathComponent("\(avd.name).ini"))
        refresh()
    }

    // MARK: Run

    func command(for avd: AVD, coldBoot: Bool = false) -> [String] {
        var a = ["-avd", avd.name, "-gpu", "host", "-accel", "on", "-cores", "\(avd.cores)"]
        if noBootAnim { a.append("-no-boot-anim") }
        if !quickBoot || coldBoot { a.append("-no-snapshot-load") }
        if !showWindow { a.append("-no-window") }
        a += ["-qemu", "-m", "\(avd.ramMB)"]   // must stay last: everything after -qemu goes to QEMU
        return a
    }

    func start(_ avd: AVD, coldBoot: Bool = false) {
        guard processes[avd.name] == nil else { return }
        let p = Process()
        p.executableURL = AndroidSDK.emulatorBinary
        p.arguments = command(for: avd, coldBoot: coldBoot)
        var env = Tools.environment
        env["ANDROID_SDK_ROOT"] = AndroidSDK.root.path
        env["ANDROID_HOME"] = AndroidSDK.root.path
        env["ANDROID_AVD_HOME"] = AndroidSDK.avdHome.path
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }
            let s = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.appendLog(s) }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.processes[avd.name] = nil; self?.detectRunning() }
        }
        do {
            appendLog("▶ emulator " + (p.arguments ?? []).joined(separator: " ") + "\n")
            try p.run()
            processes[avd.name] = p
            running.insert(avd.name)
        } catch {
            errorText = "Gagal menjalankan emulator: \(error.localizedDescription)"
        }
    }

    func stop(_ avd: AVD) {
        if let p = processes[avd.name] { p.terminate(); return }
        // Started elsewhere: ask it to quit via the emulator console through adb.
        guard let adb = Tools.adb else { return }
        Task {
            let devices = await Tools.run(adb, ["devices"])
            for line in devices.split(separator: "\n") where line.hasPrefix("emulator-") {
                let serial = String(line.split(separator: "\t").first ?? "")
                let name = await Tools.run(adb, ["-s", serial, "emu", "avd", "name"])
                if name.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces) == avd.name {
                    _ = await Tools.run(adb, ["-s", serial, "emu", "kill"])
                }
            }
            try? await Task.sleep(for: .seconds(2))
            detectRunning()
        }
    }

    func stopAll() { processes.values.forEach { $0.terminate() } }

    private func appendLog(_ s: String) {
        log += s
        if log.count > 40_000 { log = String(log.suffix(30_000)) }
    }
}
