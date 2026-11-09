import SwiftUI
import AppKit

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
    }

    enum State: Equatable { case idle, optional(String), required(String) }
    @Published var state: State = .idle
    @Published var info: Info?
    @Published var dismissedOptional = false

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
                    Text(notes).font(.callout).lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
                HStack(spacing: 10) {
                    Button { NSApp.terminate(nil) } label: { Text("Keluar") }
                        .buttonStyle(SoftButtonStyle(tint: .secondary)).fixedSize()
                    Button { NSWorkspace.shared.open(updater.downloadURL) } label: {
                        Label("Unduh versi \(version)", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(GradientButtonStyle(colors: Brand.colors)).fixedSize()
                    .keyboardShortcut(.defaultAction)
                }
                Text("Setelah mengunduh: buka DMG, seret Djie Cast ke Applications dan ganti versi lama.")
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
            if let notes = updater.info?.notes { Text(notes).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            Button("Nanti") { withAnimation { updater.dismissedOptional = true } }.buttonStyle(.borderless)
            Button { NSWorkspace.shared.open(updater.downloadURL) } label: { Label("Unduh", systemImage: "arrow.down.circle.fill") }
                .buttonStyle(GradientButtonStyle(colors: Brand.colors)).fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.start.opacity(0.3)))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .padding(16)
        .frame(maxWidth: 760)
    }
}
