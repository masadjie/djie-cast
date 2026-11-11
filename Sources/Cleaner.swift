import SwiftUI
import AppKit

// MARK: - Junk cleaner
//
// Android (adb, no root): system cache of every app, per-app cache folders in shared storage, leftover APK
// installers, thumbnail caches, temp/log files, empty folders, plus a review list of large files.
// iPhone: Apple does not let a Mac clear app caches, so we offer what is allowed: crash/diagnostic logs
// (moved off the phone) and the apps that take the most space, with uninstall.

struct JunkGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    var bytes: Int64          // -1 = unknown until cleaned
    var count: Int
    var paths: [String] = []  // files/folders this group removes
    var selected = true
    var review = false        // large files: listed for the user to pick, not selected by default
}

struct BigFile: Identifiable, Hashable { var id: String { path }; let path: String; let bytes: Int64 }

@MainActor
final class AndroidCleaner: ObservableObject {
    enum Phase: Equatable { case idle, scanning, ready, cleaning, done(Int64) }
    let serial: String
    @Published var phase: Phase = .idle
    @Published var groups: [JunkGroup] = []
    @Published var bigFiles: [BigFile] = []
    @Published var pickedBig: Set<String> = []
    @Published var status = ""

    init(serial: String) { self.serial = serial }

    /// Android's own top-level folders: apps expect them, so they stay even when empty.
    static let standardFolders: Set<String> = ["Alarms", "Audiobooks", "DCIM", "Documents", "Download", "Movies", "Music",
                                               "Notifications", "Pictures", "Podcasts", "Recordings", "Ringtones"]

    private func sh(_ cmd: String) async -> String {
        guard let adb = Tools.adb else { return "" }
        return await Tools.run(adb, ["-s", serial, "shell", cmd])
    }

    /// Free space on /data in KB, from `df`.
    private func freeKB() async -> Int64 {
        let out = await sh("df -k /data | tail -1")
        let cols = out.split(whereSeparator: { $0 == " " || $0 == "\t" })
        return cols.count >= 4 ? Int64(cols[3]) ?? 0 : 0
    }

    /// Parses `size path` lines (from `du -k` or `stat`), returning total bytes and the paths.
    private func sizes(_ out: String, kb: Bool) -> (Int64, [String]) {
        var total: Int64 = 0; var paths: [String] = []
        for line in out.split(whereSeparator: \.isNewline) {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == "\t" || $0 == " " })
            guard parts.count == 2, let n = Int64(parts[0]) else { continue }
            total += kb ? n * 1024 : n; paths.append(String(parts[1]).trimmingCharacters(in: .whitespaces))
        }
        return (total, paths)
    }

    func scan() async {
        phase = .scanning; groups = []; bigFiles = []; pickedBig = []
        // /sdcard is a symlink and find does not follow it, so walk the real path.
        let root = "/storage/emulated/0"
        let skip = "-path \(root)/Android -prune -o"
        status = String(localized: "Memeriksa cache aplikasi…")
        let (extBytes, extPaths) = sizes(await sh("du -sk /sdcard/Android/data/*/cache 2>/dev/null | awk '$1>0'"), kb: true)
        status = String(localized: "Mencari file APK sisa instalasi…")
        let (apkBytes, apkPaths) = sizes(await sh("find \(root) \(skip) -type f -iname '*.apk' -exec stat -c '%s %n' {} + 2>/dev/null"), kb: false)
        status = String(localized: "Memeriksa cache thumbnail…")
        let (thumbBytes, thumbPaths) = sizes(await sh("find \(root) \(skip) -type d -name .thumbnails -exec du -sk {} + 2>/dev/null"), kb: true)
        status = String(localized: "Mencari file sementara & log…")
        let (tmpBytes, tmpPaths) = sizes(await sh("find \(root) \(skip) -type f \\( -iname '*.tmp' -o -iname '*.temp' -o -iname '*.log' -o -iname '*.bak' \\) -exec stat -c '%s %n' {} + 2>/dev/null"), kb: false)
        let emptyDirs = (await sh("find \(root) \(skip) -mindepth 1 -type d -empty -print 2>/dev/null"))
            .split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.contains("/.") && !Self.standardFolders.contains($0.replacingOccurrences(of: root + "/", with: "")) }
        status = String(localized: "Mencari file besar…")
        let big = await sh("find \(root) \(skip) -type f -size +50M -exec stat -c '%s %n' {} + 2>/dev/null | sort -rn | head -20")
        bigFiles = big.split(whereSeparator: \.isNewline).compactMap { l in
            let p = l.split(separator: " ", maxSplits: 1); guard p.count == 2, let n = Int64(p[0]) else { return nil }
            return BigFile(path: String(p[1]), bytes: n)
        }.filter { !$0.path.lowercased().hasSuffix(".apk") }

        groups = [
            JunkGroup(id: "sys", title: String(localized: "Cache semua aplikasi"), detail: String(localized: "Data sementara yang disimpan aplikasi. Aman dihapus; aplikasi membuatnya lagi bila perlu."),
                      icon: "app.badge.checkmark", bytes: -1, count: 0),
            JunkGroup(id: "ext", title: String(localized: "Cache aplikasi di penyimpanan"), detail: String(localized: "Folder cache aplikasi di penyimpanan internal (gambar, video sementara)."),
                      icon: "folder.badge.minus", bytes: extBytes, count: extPaths.count, paths: extPaths),
            JunkGroup(id: "apk", title: String(localized: "File APK sisa instalasi"),
                      detail: apkPaths.isEmpty ? "" : apkPaths.prefix(3).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ") + (apkPaths.count > 3 ? " …" : ""),
                      icon: "shippingbox", bytes: apkBytes, count: apkPaths.count, paths: apkPaths),
            JunkGroup(id: "thumb", title: String(localized: "Cache thumbnail"), detail: String(localized: "Gambar kecil pratinjau galeri. Dibuat ulang otomatis."),
                      icon: "photo.stack", bytes: thumbBytes, count: thumbPaths.count, paths: thumbPaths),
            JunkGroup(id: "tmp", title: String(localized: "File sementara & log"), detail: String(localized: "File .tmp, .log, dan .bak yang tertinggal."),
                      icon: "doc.badge.ellipsis", bytes: tmpBytes, count: tmpPaths.count, paths: tmpPaths),
            JunkGroup(id: "empty", title: String(localized: "Folder kosong"), detail: String(localized: "Folder tanpa isi yang tertinggal dari aplikasi yang sudah dihapus."),
                      icon: "folder", bytes: 0, count: emptyDirs.count, paths: emptyDirs),
        ].filter { $0.id == "sys" || $0.count > 0 }
        status = ""
        phase = .ready
    }

    var selectedBytes: Int64 {
        groups.filter { $0.selected && $0.bytes > 0 }.reduce(0) { $0 + $1.bytes }
            + bigFiles.filter { pickedBig.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }

    func clean() async {
        phase = .cleaning
        let before = await freeKB()
        func quote(_ p: String) -> String { "'" + p.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        for g in groups where g.selected {
            status = String(localized: "Membersihkan \(g.title)…")
            switch g.id {
            case "sys": _ = await sh("pm trim-caches 9999G")
            case "ext", "thumb":
                for chunk in g.paths.chunked(30) { _ = await sh(chunk.map { "rm -rf \(quote($0))/* \(quote($0))/.[!.]* 2>/dev/null" }.joined(separator: "; ")) }
            case "empty":
                for chunk in g.paths.chunked(40) { _ = await sh("rmdir " + chunk.map(quote).joined(separator: " ") + " 2>/dev/null") }
            default:
                for chunk in g.paths.chunked(40) { _ = await sh("rm -f " + chunk.map(quote).joined(separator: " ")) }
            }
        }
        let big = bigFiles.filter { pickedBig.contains($0.path) }.map(\.path)
        if !big.isEmpty {
            status = String(localized: "Menghapus file besar yang dipilih…")
            for chunk in big.chunked(20) { _ = await sh("rm -f " + chunk.map(quote).joined(separator: " ")) }
        }
        // let the media index forget removed files
        _ = await sh("am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard >/dev/null 2>&1")
        let after = await freeKB()
        status = ""
        phase = .done(max(0, (after - before) * 1024))
    }
}

extension Array {
    func chunked(_ n: Int) -> [[Element]] { stride(from: 0, to: count, by: n).map { Array(self[$0..<Swift.min($0 + n, count)]) } }
}

struct AndroidCleanerSheet: View {
    @StateObject private var c: AndroidCleaner
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false

    init(serial: String, name: String) { _c = StateObject(wrappedValue: AndroidCleaner(serial: serial)); self.name = name }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(eyebrow: name.uppercased(), title: "Bersihkan sampah", subtitle: "Pindai lalu pilih yang mau dibersihkan. Foto, video, dan dokumenmu tidak disentuh kecuali kamu memilihnya sendiri di daftar file besar.")
            switch c.phase {
            case .idle, .scanning:
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(c.status.isEmpty ? String(localized: "Memindai…") : c.status).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            case .cleaning:
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(c.status.isEmpty ? String(localized: "Membersihkan…") : c.status).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            case .done(let freed):
                VStack(spacing: 14) {
                    Image(systemName: "sparkles").font(.system(size: 46)).foregroundStyle(Theme.android[1])
                    Text(freed > 0 ? String(localized: "\(Fmt.bytes(freed)) berhasil dikosongkan") : String(localized: "Sudah bersih")).font(.title2.weight(.bold))
                    Text("Ruang kosong dihitung dari penyimpanan HP sebelum dan sesudah dibersihkan.").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Pindai lagi") { Task { await c.scan() } }.buttonStyle(SoftButtonStyle(tint: Theme.android[1])).fixedSize()
                        Button("Selesai") { dismiss() }.buttonStyle(GradientButtonStyle(colors: Theme.android)).fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            case .ready:
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($c.groups) { $g in groupRow($g) }
                        if !c.bigFiles.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("FILE BESAR · PILIH SENDIRI").font(.system(size: 10.5, weight: .semibold, design: .monospaced)).kerning(1).foregroundStyle(.secondary).padding(.top, 10)
                                ForEach(c.bigFiles) { f in bigRow(f) }
                            }
                        }
                    }
                }
                .frame(height: 360)
                HStack {
                    Text(c.selectedBytes > 0 ? String(localized: "± \(Fmt.bytes(c.selectedBytes)) akan dikosongkan, ditambah cache aplikasi") : String(localized: "Cache aplikasi akan dibersihkan"))
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Pindai ulang") { Task { await c.scan() } }.buttonStyle(.borderless)
                    Button { confirm = true } label: { Label("Bersihkan", systemImage: "sparkles") }
                        .buttonStyle(GradientButtonStyle(colors: Theme.android)).fixedSize()
                        .disabled(!c.groups.contains { $0.selected } && c.pickedBig.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 640)
        .task { await c.scan() }
        .alert("Bersihkan sekarang?", isPresented: $confirm) {
            Button("Bersihkan", role: .destructive) { Task { await c.clean() } }
            Button("Batal", role: .cancel) {}
        } message: {
            Text(c.pickedBig.isEmpty ? "File yang dibersihkan tidak bisa dikembalikan." : "File besar yang kamu pilih juga ikut dihapus dan tidak bisa dikembalikan.")
        }
    }

    private func header(eyebrow: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: eyebrow).font(.system(size: 10.5, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(Theme.android[1])
                Text(L(title)).font(.title2.weight(.bold))
                Text(L(subtitle)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Tutup") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private func groupRow(_ g: Binding<JunkGroup>) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: g.selected).toggleStyle(.checkbox).labelsHidden()
            Image(systemName: g.wrappedValue.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.android[1])
                .frame(width: 32, height: 32).background(Theme.android[1].opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(g.wrappedValue.title).font(.callout.weight(.semibold))
                Text(g.wrappedValue.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(g.wrappedValue.bytes < 0 ? "—" : Fmt.bytes(g.wrappedValue.bytes)).font(.callout.weight(.semibold).monospacedDigit())
                if g.wrappedValue.count > 0 { Text("\(g.wrappedValue.count) item").font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func bigRow(_ f: BigFile) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { c.pickedBig.contains(f.path) }, set: { if $0 { c.pickedBig.insert(f.path) } else { c.pickedBig.remove(f.path) } }))
                .toggleStyle(.checkbox).labelsHidden()
            Image(systemName: "doc.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: (f.path as NSString).lastPathComponent).font(.callout).lineLimit(1)
                Text(verbatim: (f.path as NSString).deletingLastPathComponent.replacingOccurrences(of: "/storage/emulated/0", with: "")).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Text(Fmt.bytes(f.bytes)).font(.callout.monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }
}

// MARK: - iPhone

@MainActor
final class IOSCleaner: ObservableObject {
    struct AppUse: Identifiable, Hashable { let id: String; let name: String; let app: Int64; let data: Int64 }
    let udid: String
    @Published var loading = true
    @Published var apps: [AppUse] = []
    @Published var logCount = 0
    @Published var logBytes: Int64 = 0
    @Published var status = ""
    @Published var busy: Set<String> = []

    init(udid: String) { self.udid = udid }

    func scan() async {
        loading = true
        status = String(localized: "Membaca ukuran aplikasi…")
        if let arr = await IMD.plist("ideviceinstaller", ["-u", udid, "list", "--user", "-a", "CFBundleIdentifier", "-a", "CFBundleDisplayName",
                                                             "-a", "CFBundleName", "-a", "StaticDiskUsage", "-a", "DynamicDiskUsage", "--xml"]) as? [[String: Any]] {
            apps = arr.compactMap { a in
                guard let id = a["CFBundleIdentifier"] as? String else { return nil }
                let name = (a["CFBundleDisplayName"] as? String) ?? (a["CFBundleName"] as? String) ?? id
                return AppUse(id: id, name: name, app: (a["StaticDiskUsage"] as? NSNumber)?.int64Value ?? 0, data: (a["DynamicDiskUsage"] as? NSNumber)?.int64Value ?? 0)
            }
            .sorted { $0.app + $0.data > $1.app + $1.data }
        }
        status = String(localized: "Memeriksa log crash…")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("djiecast-crash-\(udid)")
        try? FileManager.default.removeItem(at: tmp)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        _ = await IMD.run("idevicecrashreport", ["-u", udid, "-k", tmp.path])     // -k: copy only, nothing removed yet
        let files = (FileManager.default.enumerator(at: tmp, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        logCount = files.count
        logBytes = files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        try? FileManager.default.removeItem(at: tmp)
        status = ""
        loading = false
    }

    /// Without -k idevicecrashreport moves the reports off the phone; we discard the copies.
    func clearLogs() async {
        busy.insert("logs")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("djiecast-crash-clear")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        _ = await IMD.run("idevicecrashreport", ["-u", udid, tmp.path])
        try? FileManager.default.removeItem(at: tmp)
        busy.remove("logs")
        logCount = 0; logBytes = 0
    }

    func uninstall(_ a: AppUse) async {
        busy.insert(a.id)
        _ = await IOSBackend(udid: udid).uninstall(a.id)
        busy.remove(a.id)
        apps.removeAll { $0.id == a.id }
    }
}

struct IOSCleanerSheet: View {
    @StateObject private var c: IOSCleaner
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmApp: IOSCleaner.AppUse?

    init(udid: String, name: String) { _c = StateObject(wrappedValue: IOSCleaner(udid: udid)); self.name = name }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: name.uppercased()).font(.system(size: 10.5, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(Theme.ios[1])
                    Text("Bersihkan iPhone").font(.title2.weight(.bold))
                    Text("Apple tidak mengizinkan Mac menghapus cache aplikasi di iPhone. Yang bisa dibersihkan dari sini: log crash, dan aplikasi yang paling banyak makan ruang.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Tutup") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if c.loading {
                VStack(spacing: 12) { ProgressView().controlSize(.large); Text(c.status).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "ladybug").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ios[1])
                        .frame(width: 32, height: 32).background(Theme.ios[1].opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log crash & diagnostik").font(.callout.weight(.semibold))
                        Text(c.logCount > 0 ? String(localized: "\(c.logCount) file · \(Fmt.bytes(c.logBytes))") : String(localized: "Tidak ada log yang tertinggal"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await c.clearLogs() } } label: {
                        if c.busy.contains("logs") { ProgressView().controlSize(.small) } else { Label("Bersihkan", systemImage: "sparkles") }
                    }
                    .buttonStyle(GradientButtonStyle(colors: Theme.ios)).fixedSize().disabled(c.logCount == 0)
                }
                .padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))

                Text("APLIKASI TERBESAR").font(.system(size: 10.5, weight: .semibold, design: .monospaced)).kerning(1).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(c.apps.prefix(30)) { a in
                            HStack(spacing: 10) {
                                Text(String(a.name.prefix(1)).uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 28, height: 28).background(Theme.ios[0].opacity(0.75), in: RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: a.name).font(.callout.weight(.medium)).lineLimit(1)
                                    Text("Aplikasi \(Fmt.bytes(a.app)) · Data \(Fmt.bytes(a.data))").font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(Fmt.bytes(a.app + a.data)).font(.callout.weight(.semibold).monospacedDigit())
                                Button { confirmApp = a } label: {
                                    if c.busy.contains(a.id) { ProgressView().controlSize(.small) } else { Image(systemName: "trash") }
                                }
                                .buttonStyle(.borderless).foregroundStyle(.red).help("Uninstall")
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                        }
                    }
                }
                .frame(height: 300)
                Text("Untuk mengosongkan “Data” sebuah aplikasi di iPhone: hapus lalu pasang ulang dari App Store. Foto & video besar bisa dihapus dari halaman File iPhone.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 640)
        .task { await c.scan() }
        .alert("Uninstall \(confirmApp?.name ?? "")?", isPresented: Binding(get: { confirmApp != nil }, set: { if !$0 { confirmApp = nil } })) {
            Button("Uninstall", role: .destructive) { if let a = confirmApp { Task { await c.uninstall(a) } }; confirmApp = nil }
            Button("Batal", role: .cancel) { confirmApp = nil }
        } message: { Text("Aplikasi beserta datanya akan dihapus dari iPhone.") }
    }
}
