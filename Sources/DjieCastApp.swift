import SwiftUI
import AppKit

enum Brand {
    static let name = "Djie Cast"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0 Beta"
    }
    static let license = "MIT"
    static let author = "Adjie Kurniawan"
    static let donationPhoneDisplay = "0812-6949-4591"
    static let donationWhatsApp = URL(string: "https://wa.me/6281269494591")!
    /// Set this once the project is on GitHub; the Donasi page shows a button for it.
    static let repoURL: URL? = URL(string: "https://github.com/masadjie/djie-cast")
    static let start = Color(red: 0.31, green: 0.27, blue: 0.90)   // indigo
    static let end = Color(red: 0.02, green: 0.71, blue: 0.83)     // cyan
    static var colors: [Color] { [start, end] }
    static var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Page: String, Hashable { case home, android, ios, files, donate, about }

/// Shared navigation so any view can jump to another page.
@MainActor
final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var page: Page = Page(rawValue: Demo.startPage ?? "") ?? .home
}

// MARK: - Root

struct RootView: View {
    @State private var showSplash = Demo.startPage == nil

    var body: some View {
        ZStack {
            MainView()
            if showSplash {
                SplashView { withAnimation(.easeInOut(duration: 0.5)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .frame(minWidth: 1040, minHeight: 660)
        .tint(Brand.start)
        .onAppear { Demo.snapshotIfRequested() }
    }
}

// MARK: - Main window (sidebar + detail)

struct MainView: View {
    @ObservedObject private var nav = Nav.shared
    @ObservedObject private var android = LauncherModel.shared
    @ObservedObject private var ios = IOSCastModel.shared

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section {
                    sidebarRow(.home, "Beranda", "house.fill", Brand.colors)
                }
                Section("Cast") {
                    sidebarRow(.android, "Android", "smartphone", Theme.android, badge: android.readyCount)
                    sidebarRow(.ios, "iPhone & iPad", "iphone", Theme.ios, badge: ios.devices.count)
                }
                Section("Alat") {
                    sidebarRow(.files, "File Android", "folder.fill", Theme.files)
                }
                Section("Komunitas") {
                    sidebarRow(.donate, "Donasi", "heart.fill", Theme.donate)
                    sidebarRow(.about, "Tentang", "info.circle.fill", [Color(white: 0.55), Color(white: 0.35)])
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            Group {
                switch nav.page {
                case .home: HomeView(page: $nav.page)
                case .android: AndroidCastView()
                case .ios: IOSCastView()
                case .files: AndroidFilesView()
                case .donate: DonateView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(title)
        .task {
            // Keep both device lists fresh so sidebar badges are always right.
            ios.refresh()
            while !Task.isCancelled {
                await android.refresh()
                ios.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var title: String {
        switch nav.page {
        case .home: return Brand.name
        case .android: return "Android"
        case .ios: return "iPhone & iPad"
        case .files: return "File Android"
        case .donate: return "Donasi"
        case .about: return "Tentang"
        }
    }

    /// Sidebar selection must be optional for List; map it onto the shared page.
    private var sidebarSelection: Binding<Page?> {
        Binding(get: { nav.page }, set: { if let p = $0 { nav.page = p } })
    }

    private func sidebarRow(_ p: Page, _ label: String, _ icon: String, _ colors: [Color], badge: Int = 0) -> some View {
        HStack(spacing: 10) {
            IconBadge(icon: icon, colors: colors, size: 24)
            Text(label)
        }
        .padding(.vertical, 2)
        .badge(badge)
        // List selection is Page?, but tags must be plain Page — an Optional tag makes clicks select nil.
        .tag(p)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(Brand.name).font(.callout.weight(.semibold))
                Text("v\(Brand.version)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }
}

// MARK: - Splash

struct SplashView: View {
    let onFinish: () -> Void
    @State private var appear = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Brand.gradient.ignoresSafeArea()
            RadialGradient(colors: [.white.opacity(0.18), .clear], center: .center, startRadius: 10, endRadius: 420)
            ForEach(0..<3) { i in
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 2)
                    .frame(width: 180, height: 180)
                    .scaleEffect(pulse ? 2.8 : 1)
                    .opacity(pulse ? 0 : 0.8)
                    .animation(.easeOut(duration: 2).repeatForever(autoreverses: false).delay(Double(i) * 0.6), value: pulse)
            }
            VStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 150, height: 150)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .scaleEffect(appear ? 1 : 0.6)
                Text(Brand.name)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Cast Android & iOS ke Mac")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                Text("v\(Brand.version)".uppercased())
                    .font(.caption.weight(.bold))
                    .kerning(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.2), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.5)))
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .padding(.top, 10)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) { appear = true }
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { onFinish() }
        }
    }
}

// MARK: - Home dashboard

struct HomeView: View {
    @Binding var page: Page
    @ObservedObject private var android = LauncherModel.shared
    @ObservedObject private var ios = IOSCastModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Mulai cast")
                    HStack(spacing: 16) {
                        PlatformCard(icon: "smartphone", title: "Android", colors: Theme.android,
                                     description: "Mirror dan kontrol penuh HP Android dari Mac.",
                                     features: ["USB & Wi-Fi", "Kontrol mouse & keyboard", "Audio & rekam layar"],
                                     status: android.readyCount > 0 ? "\(android.readyCount) perangkat siap" : nil,
                                     live: !android.running.isEmpty) { page = .android }
                        PlatformCard(icon: "iphone", title: "iPhone & iPad", colors: Theme.ios,
                                     description: "Tampilkan layar iPhone/iPad lewat kabel atau wireless.",
                                     features: ["USB tanpa install", "iPhone Mirroring", "AirPlay"],
                                     status: ios.devices.isEmpty ? nil : "\(ios.devices.count) perangkat siap",
                                     live: !ios.mirroring.isEmpty) { page = .ios }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Tentang aplikasi")
                    HStack(spacing: 16) {
                        InfoTile(icon: "shippingbox.fill", title: "scrcpy \(Tools.scrcpyVersion)",
                                 detail: "Sudah dibundel, tanpa install")
                        InfoTile(icon: "cpu", title: "Universal",
                                 detail: "Apple Silicon & Intel")
                        InfoTile(icon: "lock.shield.fill", title: "100% lokal",
                                 detail: "Tidak ada data dikirim ke internet")
                        InfoTile(icon: "chevron.left.forwardslash.chevron.right", title: "Open source",
                                 detail: "Lisensi \(Brand.license), gratis selamanya")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            Brand.gradient
            // Decorative cast waves
            GeometryReader { geo in
                ForEach(1..<5) { i in
                    Circle()
                        .strokeBorder(.white.opacity(0.10), lineWidth: 18)
                        .frame(width: CGFloat(i) * 140, height: CGFloat(i) * 140)
                        .position(x: geo.size.width - 90, y: geo.size.height / 2)
                }
            }
            HStack(spacing: 22) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 92, height: 92)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selamat datang di \(Brand.name)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("Tampilkan & kendalikan layar HP kamu langsung di Mac — cepat, jernih, tanpa ribet.")
                        .font(.body)
                        .opacity(0.88)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("v\(Brand.version)".uppercased())
                        .font(.caption2.weight(.bold))
                        .kerning(1.2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.2), in: Capsule())
                        .padding(.top, 4)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 40)
            }
            .padding(28)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Brand.start.opacity(0.3), radius: 16, y: 8)
    }
}

struct PlatformCard: View {
    let icon: String
    let title: String
    let colors: [Color]
    let description: String
    let features: [String]
    let status: String?
    let live: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Panel(highlight: hover ? colors[0] : nil, padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        IconBadge(icon: icon, colors: colors, size: 52)
                        Spacer()
                        if live { LiveBadge() }
                        else if let status { Pill(text: status, icon: "circle.fill", color: Theme.live) }
                    }
                    .frame(height: 52, alignment: .top)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
                        Text(description).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(features, id: \.self) { f in
                            Label {
                                Text(f).font(.callout)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(colors[0])
                            }
                        }
                    }
                    HStack {
                        Text("Buka").font(.callout.weight(.semibold))
                        Image(systemName: "arrow.right").font(.callout.weight(.semibold))
                            .offset(x: hover ? 3 : 0)
                    }
                    .foregroundStyle(colors[1])
                    .padding(.top, 2)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity)
            .scaleEffect(hover ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

struct InfoTile: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        Panel(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.start)
                    .frame(width: 34, height: 34)
                    .background(Brand.start.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - App

@main
struct DjieCastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup(Brand.name) {
            RootView()
        }
        .defaultSize(width: 1200, height: 780)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Tentang \(Brand.name)") { Nav.shared.page = .about }
            }
            CommandGroup(replacing: .help) {
                Button("Donasi untuk \(Brand.name)") { Nav.shared.page = .donate }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { LauncherModel.shared.stopAll() }
    }
}
