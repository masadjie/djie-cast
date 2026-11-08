import Foundation

/// `DJIE_DEVICE_SELFTEST=1` boots a temporary Android 14 emulator, reads its specs and app list, then cleans up.
@MainActor
enum DeviceSelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["DJIE_DEVICE_SELFTEST"] != nil else { return }
        Task { await run(); exit(0) }
    }
    private static func say(_ s: String) { print("[dev-test] " + s); fflush(stdout) }

    static func run() async {
        let m = EmulatorModel.shared
        m.refresh()
        let path = "system-images;android-34;google_apis;arm64-v8a"
        guard m.installedImages.contains(path), let img = SystemImageOption.local(path) else { say("image missing"); return }
        let name = "DjieCast_DeviceTest"
        if let old = m.avds.first(where: { $0.name == name }) { m.delete(old) }
        try? m.createAVD(name: "DjieCast DeviceTest", profile: DeviceProfile.all[0], image: img, ramMB: 4096, cores: 4, storageGB: 8)
        guard let avd = m.avds.first(where: { $0.name == name }) else { say("create failed"); return }
        UserDefaults.standard.set(false, forKey: "emuShowWindow")
        m.start(avd)
        let adb = Tools.adb ?? "adb"
        var serial: String?
        for _ in 0..<90 {
            try? await Task.sleep(for: .seconds(2))
            for line in (await Tools.run(adb, ["devices"])).split(separator: "\n") where line.hasPrefix("emulator-") && line.hasSuffix("device") {
                let s = String(line.split(separator: "\t")[0])
                if (await Tools.run(adb, ["-s", s, "emu", "avd", "name"])).hasPrefix(name),
                   (await Tools.run(adb, ["-s", s, "shell", "getprop", "sys.boot_completed"])).trimmingCharacters(in: .whitespacesAndNewlines) == "1" { serial = s }
            }
            if serial != nil { break }
        }
        guard let serial else { say("boot timeout"); m.stop(avd); return }
        say("booted \(serial)")
        let d = await AndroidInspector.load(serial: serial)
        say("title=\(d.title) | subtitle=\(d.subtitle) | storage=\(d.storagePill)")
        for r in d.specs { say("  \(r.label): \(r.value)") }
        say("battery=\(d.batteryLevel.map(String.init) ?? "-")% health=\(d.batteryHealth ?? "-") state=\(d.batteryState ?? "-") extra=\(d.batteryExtra.map { "\($0.label) \($0.value)" })")
        say("storage used=\(d.storageUsed.map(Fmt.bytes) ?? "-") / \(d.storageTotal.map(Fmt.bytes) ?? "-") ram=\(d.ramTotal.map(Fmt.bytes) ?? "-")")
        let shot = await AndroidInspector.screenshot(serial: serial)
        say("screenshot: \(shot.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "nil")")
        let user = await AndroidInspector.apps(serial: serial, includeSystem: false)
        let all = await AndroidInspector.apps(serial: serial, includeSystem: true)
        say("apps user=\(user.count) all=\(all.count) sample=\(all.prefix(4).map { "\($0.name)(\($0.id)) v\($0.version) \($0.installed)" })")
        m.stop(avd)
        try? await Task.sleep(for: .seconds(4))
        m.delete(avd)
        UserDefaults.standard.removeObject(forKey: "emuShowWindow")
        say("cleaned up")
    }
}
