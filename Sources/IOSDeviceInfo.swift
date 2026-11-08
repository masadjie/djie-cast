import SwiftUI
import AppKit
import AVFoundation
import CoreImage

// MARK: - iOS via libimobiledevice (bundled in Contents/MacOS/imd, or Homebrew)

enum IMD {
    static func tool(_ name: String) -> String? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/imd/\(name)").path
        for p in [bundled, "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"] where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }
    static var available: Bool { tool("ideviceinfo") != nil }

    static func run(_ name: String, _ args: [String]) async -> String {
        guard let t = tool(name) else { return "" }
        return await Tools.run(t, args)
    }

    static func plist(_ name: String, _ args: [String]) async -> Any? {
        let out = await run(name, args)
        guard let start = out.range(of: "<?xml") else { return nil }
        return try? PropertyListSerialization.propertyList(from: Data(out[start.lowerBound...].utf8), format: nil)
    }

    /// UDIDs of iPhones/iPads connected over USB, with their names.
    static func devices() async -> [(udid: String, name: String)] {
        let ids = (await run("idevice_id", ["-l"])).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var list: [(String, String)] = []
        for id in ids {
            let n = (await run("ideviceinfo", ["-u", id, "-k", "DeviceName"])).trimmingCharacters(in: .whitespacesAndNewlines)
            list.append((id, n.isEmpty ? "iPhone" : n))
        }
        return list
    }

    static let models: [String: String] = [
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2nd gen)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd gen)", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e",
        "iPhone18,3": "iPhone 17", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,4": "iPhone Air",
    ]
}

struct IOSBackend: DeviceBackend {
    let udid: String
    var id: String { udid }
    let supportsApps = true, supportsPower = true
    var accent: [Color] { Theme.ios }

    func detail() async -> DeviceDetail {
        async let basicP = IMD.plist("ideviceinfo", ["-u", udid, "-x"])
        async let batP = IMD.plist("ideviceinfo", ["-u", udid, "-q", "com.apple.mobile.battery", "-x"])
        async let diskP = IMD.plist("ideviceinfo", ["-u", udid, "-q", "com.apple.disk_usage", "-x"])
        async let gaugeP = IMD.plist("idevicediagnostics", ["-u", udid, "ioregentry", "AppleSmartBattery"])
        let basic = (await basicP as? [String: Any]) ?? [:]
        let bat = (await batP as? [String: Any]) ?? [:]
        let disk = (await diskP as? [String: Any]) ?? [:]
        let gaugeRoot = (await gaugeP as? [String: Any]) ?? [:]
        let gauge = (gaugeRoot["IORegistry"] as? [String: Any]) ?? gaugeRoot
        // Battery keys sit at different depths depending on the iOS version; search the whole tree.
        func num(_ key: String, _ node: Any? = nil) -> Double? {
            let n = node ?? gauge
            if let d = n as? [String: Any] {
                if let v = d[key] as? NSNumber { return v.doubleValue }
                for v in d.values { if let r = num(key, v) { return r } }
            } else if let a = n as? [Any] {
                for v in a { if let r = num(key, v) { return r } }
            }
            return nil
        }

        func s(_ k: String) -> String? { (basic[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        var d = DeviceDetail()
        let type = s("ProductType") ?? "-"
        let marketing = IMD.models[type] ?? s("ProductType") ?? "iPhone"
        d.title = s("DeviceName") ?? marketing
        d.subtitle = "\(marketing) · iOS \(s("ProductVersion") ?? "?")"
        if let total = (disk["TotalDiskCapacity"] as? NSNumber)?.int64Value {
            d.storagePill = AndroidInspector.marketingSize(total)
            d.storageTotal = (disk["TotalDataCapacity"] as? NSNumber)?.int64Value ?? total
            if let avail = (disk["TotalDataAvailable"] as? NSNumber)?.int64Value { d.storageUsed = max(0, (d.storageTotal ?? total) - avail) }
        }
        let model = [s("ModelNumber"), s("RegionInfo")].compactMap { $0 }.joined(separator: " ")
        d.specs = [
            SpecRow(label: "Versi iOS", value: "\(s("ProductVersion") ?? "?") (\(s("BuildVersion") ?? "?"))"),
            SpecRow(label: "Serial", value: s("SerialNumber") ?? "-"),
            SpecRow(label: "IMEI 1", value: s("InternationalMobileEquipmentIdentity") ?? "-"),
            SpecRow(label: "IMEI 2", value: s("InternationalMobileEquipmentIdentity2") ?? "-"),
            SpecRow(label: "Identifier", value: "\(type) (\(s("HardwareModel") ?? "-"))"),
            SpecRow(label: "Nomor model", value: model.isEmpty ? "-" : model),
            SpecRow(label: "Wilayah", value: s("RegionInfo") ?? "-"),
            SpecRow(label: "Aktivasi", value: s("ActivationState") == "Activated" ? "Ya" : (s("ActivationState") ?? "-")),
            SpecRow(label: "CPU", value: s("CPUArchitecture") ?? "-"),
            SpecRow(label: "Wi-Fi MAC", value: s("WiFiAddress") ?? "-"),
            SpecRow(label: "Bluetooth", value: s("BluetoothAddress") ?? "-"),
            SpecRow(label: "UDID", value: udid),
        ]
        d.batteryLevel = (bat["BatteryCurrentCapacity"] as? NSNumber)?.intValue
        let charging = (bat["BatteryIsCharging"] as? Bool) ?? false, ext = (bat["ExternalConnected"] as? Bool) ?? false
        d.batteryState = (bat["FullyCharged"] as? Bool) == true ? "Penuh" : charging ? "Mengisi daya" : ext ? "Tersambung, tidak mengisi" : "Tidak mengisi"
        let design = num("DesignCapacity")
        let maxCap = num("NominalChargeCapacity") ?? num("AppleRawMaxCapacity")
        if let design, let maxCap, design > 0 { d.batteryHealth = "\(min(100, Int((maxCap / design * 100).rounded())))%" }
        if let c = num("CycleCount") { d.batteryCycles = "\(Int(c))" }
        if let t = num("Temperature") { d.batteryExtra.append(SpecRow(label: "Suhu", value: String(format: "%.1f °C", t / 100))) }
        if let v = num("Voltage") { d.batteryExtra.append(SpecRow(label: "Tegangan", value: String(format: "%.2f V", v / 1000))) }
        d.status = [
            SpecRow(label: "Warna", value: s("DeviceColor").map { $0 == "1" ? "Hitam" : $0 == "2" ? "Putih" : $0 } ?? "-"),
            SpecRow(label: "Kode wilayah", value: s("RegionInfo") ?? "-"),
            SpecRow(label: "Zona waktu", value: s("TimeZone") ?? "-"),
            SpecRow(label: "Koneksi", value: "USB"),
        ]
        return d
    }

    /// iOS has no public screenshot API over USB; grab one frame from the screen-capture device instead.
    func screenshot() async -> NSImage? {
        let name = (await IMD.run("ideviceinfo", ["-u", udid, "-k", "DeviceName"])).trimmingCharacters(in: .whitespacesAndNewlines)
        let dev = await MainActor.run { IOSCastModel.shared.devices.first { $0.uniqueID == udid || $0.localizedName == name } }
        guard let dev else { return nil }
        return await FrameGrabber.grab(dev)
    }

    func apps(includeSystem: Bool) async -> [InstalledApp] {
        guard let arr = await IMD.plist("ideviceinstaller", ["-u", udid, "list", includeSystem ? "--all" : "--user", "--xml"]) as? [[String: Any]] else { return [] }
        return arr.compactMap { a in
            guard let id = a["CFBundleIdentifier"] as? String else { return nil }
            let name = (a["CFBundleDisplayName"] as? String) ?? (a["CFBundleName"] as? String) ?? id
            return InstalledApp(id: id, name: name, version: (a["CFBundleShortVersionString"] as? String) ?? "",
                                installed: "", system: (a["ApplicationType"] as? String) == "System")
        }
        .sorted { ($0.system ? 1 : 0, $0.name.lowercased()) < ($1.system ? 1 : 0, $1.name.lowercased()) }
    }

    func uninstall(_ id: String) async -> String {
        let out = await IMD.run("ideviceinstaller", ["-u", udid, "uninstall", id])
        return out.localizedCaseInsensitiveContains("complete") ? "Success" : out
    }

    func install(_ file: URL) async -> String { "Tidak didukung" }

    func power(off: Bool) async { _ = await IMD.run("idevicediagnostics", ["-u", udid, off ? "shutdown" : "restart"]) }
}

/// Captures a single frame from an iOS screen-capture AVCaptureDevice.
final class FrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private var continuation: CheckedContinuation<NSImage?, Never>?
    private let queue = DispatchQueue(label: "djiecast.grab")

    static func grab(_ device: AVCaptureDevice) async -> NSImage? {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return nil }
        let g = FrameGrabber()
        return await withCheckedContinuation { c in
            g.continuation = c
            guard let input = try? AVCaptureDeviceInput(device: device), g.session.canAddInput(input) else { c.resume(returning: nil); return }
            g.session.addInput(input)
            let out = AVCaptureVideoDataOutput()
            out.setSampleBufferDelegate(g, queue: g.queue)
            if g.session.canAddOutput(out) { g.session.addOutput(out) }
            g.queue.async { g.session.startRunning() }
            g.queue.asyncAfter(deadline: .now() + 4) { g.finish(nil) }   // no frame (locked / static screen)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent) else { return }
        finish(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
    }

    private func finish(_ img: NSImage?) {
        guard let c = continuation else { return }
        continuation = nil
        session.stopRunning()
        c.resume(returning: img)
    }
}
