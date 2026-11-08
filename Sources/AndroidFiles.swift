import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Model

struct RemoteFile: Identifiable, Hashable {
    let name: String
    let path: String
    let isDir: Bool
    let isLink: Bool
    let size: Int64
    let modified: String
    var id: String { path }

    var icon: String {
        if isDir { return "folder.fill" }
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "bmp": return "photo"
        case "mp4", "mov", "mkv", "3gp", "webm", "avi": return "film"
        case "mp3", "m4a", "wav", "ogg", "opus", "flac", "aac", "amr": return "music.note"
        case "pdf": return "doc.richtext"
        case "apk", "apks", "xapk": return "shippingbox"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "txt", "log", "md", "json", "xml", "csv": return "doc.text"
        case "doc", "docx", "xls", "xlsx", "ppt", "pptx": return "doc.richtext.fill"
        default: return "doc"
        }
    }

    var iconColor: Color {
        if isDir { return Color(red: 0.25, green: 0.55, blue: 1.0) }
        switch icon {
        case "photo": return .pink
        case "film": return .purple
        case "music.note": return .orange
        case "shippingbox": return .green
        default: return .secondary
        }
    }
}

@MainActor
final class AndroidFilesModel: ObservableObject {
    static let shared = AndroidFilesModel()
    static let root = "/storage/emulated/0"

    @Published var serial: String?
    @Published var path = AndroidFilesModel.root
    @Published var files: [RemoteFile] = []
    @Published var loading = false
    @Published var transfer: String?
    @Published var errorText: String?
    @Published var showHidden = false

    var visibleFiles: [RemoteFile] { showHidden ? files : files.filter { !$0.name.hasPrefix(".") } }

    static let downloadsDir: URL = {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Djie Cast", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Single-quotes a path for the remote Android shell.
    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private func adb(_ args: [String]) async -> String {
        guard let adb = Tools.adb, let serial else { return "adb tidak tersedia" }
        return await Tools.run(adb, ["-s", serial] + args)
    }

    func select(serial: String?) {
        guard serial != self.serial else { return }
        self.serial = serial
        path = Self.root
        files = []
        Task { await load() }
    }

    func load() async {
        guard serial != nil else { files = []; return }
        loading = true
        errorText = nil
        defer { loading = false }
        if Demo.enabled { files = Self.demoFiles(in: path); return }

        let out = await adb(["shell", "ls -lA \(q(path + "/"))"])
        // toybox: perms links owner group size YYYY-MM-DD HH:MM name
        let re = try! NSRegularExpression(pattern: #"^([\-dlcbps][rwxsStT\-]{9}\S*)\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s(.+)$"#)
        var list: [RemoteFile] = []
        for raw in out.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let perms = ns.substring(with: m.range(at: 1))
            var name = ns.substring(with: m.range(at: 4))
            let isLink = perms.hasPrefix("l")
            if isLink, let r = name.range(of: " -> ") { name = String(name[..<r.lowerBound]) }
            let full = (path == "/" ? "" : path) + "/" + name
            list.append(RemoteFile(name: name, path: full, isDir: perms.hasPrefix("d") || isLink, isLink: isLink,
                                   size: Int64(ns.substring(with: m.range(at: 2))) ?? 0,
                                   modified: ns.substring(with: m.range(at: 3))))
        }
        if list.isEmpty, out.localizedCaseInsensitiveContains("denied") || out.contains("No such") || out.contains("error") {
            errorText = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        files = list.sorted {
            $0.isDir != $1.isDir ? $0.isDir : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func go(_ newPath: String) {
        path = newPath.count > 1 && newPath.hasSuffix("/") ? String(newPath.dropLast()) : newPath
        Task { await load() }
    }

    func up() {
        guard path != "/" else { return }
        let parent = (path as NSString).deletingLastPathComponent
        go(parent.isEmpty ? "/" : parent)
    }

    var breadcrumbs: [(name: String, path: String)] {
        if path.hasPrefix(Self.root) {
            var crumbs = [("Penyimpanan internal", Self.root)]
            var acc = Self.root
            for part in path.dropFirst(Self.root.count).split(separator: "/") {
                acc += "/" + part
                crumbs.append((String(part), acc))
            }
            return crumbs
        }
        var crumbs = [("/", "/")]
        var acc = ""
        for part in path.split(separator: "/") {
            acc += "/" + part
            crumbs.append((String(part), acc))
        }
        return crumbs
    }

    // MARK: Actions

    func download(_ items: [RemoteFile]) async {
        guard !items.isEmpty else { return }
        let dest = Self.downloadsDir
        for (i, f) in items.enumerated() {
            transfer = "Mengunduh \(f.name) (\(i + 1)/\(items.count))…"
            _ = await adb(["pull", f.path, dest.path])
        }
        transfer = nil
        let urls = items.map { dest.appendingPathComponent($0.name) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func upload(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        for (i, u) in urls.enumerated() {
            transfer = "Mengunggah \(u.lastPathComponent) (\(i + 1)/\(urls.count))…"
            _ = await adb(["push", u.path, path + "/"])
        }
        transfer = nil
        await load()
    }

    func delete(_ items: [RemoteFile]) async {
        guard !items.isEmpty else { return }
        transfer = "Menghapus \(items.count) item…"
        _ = await adb(["shell", "rm -rf " + items.map { q($0.path) }.joined(separator: " ")])
        transfer = nil
        await load()
    }

    func makeFolder(_ name: String) async {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !clean.contains("/") else { return }
        _ = await adb(["shell", "mkdir -p \(q(path + "/" + clean))"])
        await load()
    }

    func rename(_ item: RemoteFile, to name: String) async {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !clean.contains("/"), clean != item.name else { return }
        let target = (item.path as NSString).deletingLastPathComponent + "/" + clean
        _ = await adb(["shell", "mv \(q(item.path)) \(q(target))"])
        await load()
    }

    /// Pulls to a temp folder and opens with the default Mac app.
    func open(_ item: RemoteFile) async {
        if item.isDir { go(item.path); return }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("DjieCast-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        transfer = "Membuka \(item.name)…"
        _ = await adb(["pull", item.path, tmp.path])
        transfer = nil
        NSWorkspace.shared.open(tmp.appendingPathComponent(item.name))
    }

    private static func demoFiles(in path: String) -> [RemoteFile] {
        let dirs = ["Alarms", "Android", "DCIM", "Documents", "Download", "Movies", "Music", "Pictures"]
        let files: [(String, Int64)] = [("Laporan-Q3.pdf", 2_481_220), ("IMG_20261105_141522.jpg", 4_120_331),
                                        ("VID_20261102_190011.mp4", 182_331_002), ("Catatan rapat.txt", 3_201),
                                        ("app-release.apk", 28_442_118), ("Lagu favorit.mp3", 6_120_004)]
        return dirs.map { RemoteFile(name: $0, path: path + "/" + $0, isDir: true, isLink: false, size: 3488, modified: "2026-11-07 09:12") }
            + files.map { RemoteFile(name: $0.0, path: path + "/" + $0.0, isDir: false, isLink: false, size: $0.1, modified: "2026-11-05 14:15") }
    }
}

// MARK: - View

struct AndroidFilesView: View {
    @ObservedObject var model = AndroidFilesModel.shared
    @ObservedObject var devices = LauncherModel.shared
    @State private var selection = Set<RemoteFile.ID>()
    @State private var confirmDelete = false
    @State private var newFolderName = ""
    @State private var showNewFolder = false
    @State private var renaming: RemoteFile?
    @State private var renameText = ""
    @State private var dropTargeted = false

    private var readyDevices: [Device] { devices.devices.filter { $0.state == "device" } }
    private var selectedFiles: [RemoteFile] { model.visibleFiles.filter { selection.contains($0.id) } }

    private let places: [(String, String, String)] = [
        ("Penyimpanan internal", "internaldrive", ""),
        ("Kamera", "camera", "/DCIM/Camera"),
        ("Download", "arrow.down.circle", "/Download"),
        ("Gambar", "photo.on.rectangle", "/Pictures"),
        ("Video", "film", "/Movies"),
        ("Musik", "music.note", "/Music"),
        ("Dokumen", "doc.text", "/Documents"),
        ("WhatsApp", "message", "/Android/media/com.whatsapp/WhatsApp/Media"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(icon: "folder.fill", colors: Theme.files, title: "File Android",
                       subtitle: "Lihat, unduh, unggah & kelola file di HP Android") {
                if !readyDevices.isEmpty {
                    Picker("Perangkat", selection: Binding(get: { model.serial ?? "" },
                                                          set: { model.select(serial: $0) })) {
                        ForEach(readyDevices) { d in
                            Label(d.displayName, systemImage: d.isWireless ? "wifi" : "cable.connector").tag(d.serial)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }

            if readyDevices.isEmpty {
                ScrollView {
                    Panel(padding: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Belum ada HP Android tersambung").font(.headline)
                            Text("Sambungkan HP lewat USB dengan USB Debugging aktif. Setelah itu isi HP langsung tampil di sini.")
                                .font(.callout).foregroundStyle(.secondary)
                            GuideStepsList(guide: .android).padding(.top, 6)
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    placesPanel
                    browser
                }
            }
        }
        .padding(28)
        .onAppear(perform: syncDevice)
        .onChange(of: readyDevices.map(\.serial)) { syncDevice() }
        .alert("Hapus \(selectedFiles.count) item?", isPresented: $confirmDelete) {
            Button("Hapus", role: .destructive) {
                let items = selectedFiles
                selection.removeAll()
                Task { await model.delete(items) }
            }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("File akan dihapus permanen dari HP dan tidak bisa dikembalikan.")
        }
        .alert("Folder baru", isPresented: $showNewFolder) {
            TextField("Nama folder", text: $newFolderName)
            Button("Buat") { let n = newFolderName; Task { await model.makeFolder(n) } }
            Button("Batal", role: .cancel) {}
        }
        .alert("Ganti nama", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nama baru", text: $renameText)
            Button("Simpan") { if let r = renaming { let t = renameText; Task { await model.rename(r, to: t) } } }
            Button("Batal", role: .cancel) {}
        }
    }

    private func syncDevice() {
        if model.serial == nil || !readyDevices.contains(where: { $0.serial == model.serial }) {
            model.select(serial: readyDevices.first?.serial)
        }
    }

    // MARK: Places

    private var placesPanel: some View {
        Panel(padding: 8, fill: true) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOKASI").font(.caption2.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                ForEach(places, id: \.0) { p in
                    let target = AndroidFilesModel.root + p.2
                    let active = model.path == target
                    Button { model.go(target) } label: {
                        Label(p.0, systemImage: p.1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(active ? Theme.files[0].opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(active ? Theme.files[1] : .primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider().padding(.vertical, 6)
                Toggle("File tersembunyi", isOn: $model.showHidden)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .padding(.horizontal, 8)
                Spacer(minLength: 0)
            }
        }
        .frame(width: 210)
    }

    // MARK: Browser

    private var browser: some View {
        Panel(highlight: dropTargeted ? Theme.files[0] : nil, padding: 0, fill: true) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                ZStack {
                    table
                    if model.loading && model.files.isEmpty {
                        ProgressView()
                    } else if let err = model.errorText {
                        Label(err, systemImage: "lock.fill").foregroundStyle(.secondary).padding()
                    } else if model.visibleFiles.isEmpty && !model.loading {
                        VStack(spacing: 6) {
                            Image(systemName: "folder").font(.largeTitle).foregroundStyle(.tertiary)
                            Text("Folder kosong").foregroundStyle(.secondary)
                            Text("Seret file dari Finder ke sini untuk mengunggah").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                Divider()
                statusBar
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.upload(urls) }
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button { model.up() } label: { Image(systemName: "chevron.left") }
                .help("Folder sebelumnya")
                .disabled(model.path == "/")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { i, c in
                        if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        Button(c.name) { model.go(c.path) }
                            .buttonStyle(.plain)
                            .font(.callout.weight(i == model.breadcrumbs.count - 1 ? .semibold : .regular))
                            .foregroundStyle(i == model.breadcrumbs.count - 1 ? .primary : .secondary)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                    }
                }
            }
            Spacer(minLength: 8)
            Group {
                Button { newFolderName = ""; showNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
                    .help("Folder baru")
                Button(action: pickUpload) { Image(systemName: "square.and.arrow.up") }
                    .help("Unggah file dari Mac")
                Button { Task { await model.download(selectedFiles) } } label: { Image(systemName: "square.and.arrow.down") }
                    .help("Unduh ke Mac (Downloads/Djie Cast)")
                    .disabled(selectedFiles.isEmpty)
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .help("Hapus")
                    .disabled(selectedFiles.isEmpty)
                Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Muat ulang")
            }
            .buttonStyle(.borderless)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var table: some View {
        Table(model.visibleFiles, selection: $selection) {
            TableColumn("Nama") { f in
                HStack(spacing: 8) {
                    Image(systemName: f.icon).foregroundStyle(f.iconColor).frame(width: 18)
                    Text(f.name).lineLimit(1)
                    if f.isLink { Image(systemName: "arrow.turn.up.right").font(.caption2).foregroundStyle(.tertiary) }
                }
            }
            .width(min: 220, ideal: 360)
            TableColumn("Ukuran") { f in
                Text(f.isDir ? "—" : ByteCountFormatter.string(fromByteCount: f.size, countStyle: .file))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            TableColumn("Diubah") { f in
                Text(f.modified).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 110, ideal: 140)
        }
        .contextMenu(forSelectionType: RemoteFile.ID.self) { ids in
            let items = model.visibleFiles.filter { ids.contains($0.id) }
            if items.count == 1, let f = items.first {
                Button(f.isDir ? "Buka folder" : "Buka di Mac", systemImage: "arrow.up.forward.app") { Task { await model.open(f) } }
                Button("Ganti nama…", systemImage: "pencil") { renameText = f.name; renaming = f }
            }
            if !items.isEmpty {
                Button("Unduh ke Mac", systemImage: "square.and.arrow.down") { Task { await model.download(items) } }
                Divider()
                Button("Hapus…", systemImage: "trash", role: .destructive) { selection = ids; confirmDelete = true }
            } else {
                Button("Folder baru…", systemImage: "folder.badge.plus") { newFolderName = ""; showNewFolder = true }
                Button("Unggah file…", systemImage: "square.and.arrow.up", action: pickUpload)
            }
        } primaryAction: { ids in
            if let f = model.visibleFiles.first(where: { ids.contains($0.id) }) { Task { await model.open(f) } }
        }
        .scrollContentBackground(.hidden)
        .onChange(of: model.path) { selection.removeAll() }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let t = model.transfer {
                ProgressView().controlSize(.small)
                Text(t)
            } else {
                Text("\(model.visibleFiles.count) item")
                if !selection.isEmpty { Text("· \(selection.count) dipilih") }
            }
            Spacer()
            Text("Klik 2× untuk membuka · seret file ke sini untuk mengunggah").foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func pickUpload() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Unggah"
        panel.message = "Pilih file untuk dikirim ke \(model.path)"
        if panel.runModal() == .OK { Task { await model.upload(panel.urls) } }
    }
}
