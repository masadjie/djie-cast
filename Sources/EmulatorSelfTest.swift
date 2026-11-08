import Foundation

/// `DJIE_EMU_SELFTEST=<system-image path>` downloads that image (if missing), creates a
/// temporary AVD, boots it headless, waits for Android to finish booting, then cleans up.
@MainActor
enum EmulatorSelfTest {
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["DJIE_EMU_SELFTEST"] else { return }
        Task { await run(path); exit(0) }
    }

    private static func say(_ s: String) { print("[emu-test] " + s); fflush(stdout) }

    static func run(_ path: String) async {
        let m = EmulatorModel.shared
        await m.loadCatalog()
        say("catalog: emulator=\(m.emulatorPackage?.version ?? "-") images=\(m.images.count) installedEmulator=\(m.installedEmulator ?? "-")")
        guard let img = m.images.first(where: { $0.path == path }) else { say("image not in catalog: \(path)"); return }
        if !m.installedImages.contains(path) {
            say("downloading \(img.title) \(img.subtitle) \(img.archive.size / 1_000_000) MB")
            m.accept(img.license)
            m.installImage(img)
            var last = -1
            while m.download != nil {
                if let d = m.download, d.total > 0 {
                    let pct = Int(Double(d.received) * 100 / Double(d.total))
                    if pct / 10 != last / 10 { say("  \(d.phase) \(pct)%"); last = pct }
                }
                try? await Task.sleep(for: .seconds(2))
            }
            if let e = m.errorText { say("DOWNLOAD FAILED: \(e)"); return }
        }
        m.refresh()
        say("installed: \(m.installedImages.contains(path))")
        let name = "DjieCast_SelfTest"
        if let old = m.avds.first(where: { $0.name == name }) { m.delete(old) }
        do {
            try m.createAVD(name: "DjieCast SelfTest", profile: DeviceProfile.all[0], image: img, ramMB: 4096, cores: 4, storageGB: 8)
        } catch { say("CREATE FAILED: \(error.localizedDescription)"); return }
        guard let avd = m.avds.first(where: { $0.name == name }) else { say("avd missing after create"); return }
        UserDefaults.standard.set(false, forKey: "emuShowWindow")
        say("start: emulator " + m.command(for: avd).joined(separator: " "))
        let t0 = Date()
        m.start(avd)
        let adb = Tools.adb ?? "adb"
        var booted = false
        for _ in 0..<90 {
            try? await Task.sleep(for: .seconds(2))
            let devs = await Tools.run(adb, ["devices"])
            for line in devs.split(separator: "\n") where line.hasPrefix("emulator-") && line.hasSuffix("device") {
                let serial = String(line.split(separator: "\t")[0])
                let n = await Tools.run(adb, ["-s", serial, "emu", "avd", "name"])
                guard n.hasPrefix(name) else { continue }
                let b = await Tools.run(adb, ["-s", serial, "shell", "getprop", "sys.boot_completed"])
                if b.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                    let rel = await Tools.run(adb, ["-s", serial, "shell", "getprop", "ro.build.version.release"])
                    say("BOOTED \(serial) Android \(rel.trimmingCharacters(in: .whitespacesAndNewlines)) in \(Int(Date().timeIntervalSince(t0)))s")
                    booted = true
                }
            }
            if booted { break }
        }
        if !booted { say("NOT BOOTED within 180s. log tail:\n" + String(m.log.suffix(1500))) }
        m.stop(avd)
        try? await Task.sleep(for: .seconds(4))
        m.delete(avd)
        UserDefaults.standard.removeObject(forKey: "emuShowWindow")
        say("cleaned up, avd exists: \(m.avds.contains { $0.name == name })")
    }
}
