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

/// App language: follows macOS, or forced to Indonesian / English (applied on next launch).
enum AppLanguage {
    static var current: String {
        guard let langs = UserDefaults.standard.object(forKey: "AppleLanguages") as? [String],
              UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] != nil,
              let first = langs.first else { return "system" }
        return first.hasPrefix("en") ? "en" : first.hasPrefix("id") ? "id" : "system"
    }
    static func set(_ lang: String) {
        if lang == "system" { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        else { UserDefaults.standard.set([lang], forKey: "AppleLanguages") }
    }
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"\(Bundle.main.bundlePath)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}

/// Light / dark / follow-system, stored per user and applied app-wide.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { ["system": "Ikuti sistem", "light": "Terang", "dark": "Gelap"][rawValue]! }
    var icon: String { ["system": "circle.lefthalf.filled", "light": "sun.max", "dark": "moon"][rawValue]! }

    @MainActor static func apply(_ raw: String) {
        switch Appearance(rawValue: raw) ?? .system {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum Page: String, Hashable { case home, android, ios, files, iosFiles, emulator, remote, donate, about }

/// Shared navigation so any view can jump to another page.
@MainActor
final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var page: Page = Page(rawValue: Demo.startPage ?? "") ?? .home
}

// MARK: - Root

struct RootView: View {
    @State private var showSplash = Demo.startPage == nil || Demo.env["DJIE_SPLASH"] != nil
    @AppStorage("appearance") private var appearance = Appearance.light.rawValue
    @ObservedObject private var updater = Updater.shared

    private var isRequired: Bool { if case .required = updater.state { return true } else { return false } }

    var body: some View {
        ZStack {
            MainView()
                .disabled(isRequired)
            if case .optional(let v) = updater.state, !updater.dismissedOptional, !showSplash {
                VStack { Spacer(); OptionalUpdateBanner(version: v) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
            if case .required(let v) = updater.state, !showSplash {
                RequiredUpdateView(version: v).transition(.opacity).zIndex(3)
            }
            if showSplash {
                SplashView { withAnimation(.easeInOut(duration: 0.5)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .frame(minWidth: 1040, minHeight: 660)
        .tint(Brand.start)
        .onAppear {
            updater.check()
            if let forced = Demo.env["DJIE_APPEARANCE"] {
                NSApp.appearance = NSAppearance(named: forced == "dark" ? .darkAqua : .aqua)
            } else { Appearance.apply(appearance) }
            Demo.snapshotIfRequested()
        }
        .onChange(of: appearance) { Appearance.apply(appearance) }
    }
}

// MARK: - Main window (sidebar + detail)

struct MainView: View {
    @ObservedObject private var nav = Nav.shared
    @ObservedObject private var android = LauncherModel.shared
    @ObservedObject private var ios = IOSCastModel.shared
    @ObservedObject private var emulator = EmulatorModel.shared
    @State private var askRelaunch = false

    var body: some View {
        Group {
            if Demo.env["DJIE_FLAT"] != nil {
                // Snapshot mode: a plain layout, because window snapshots cannot see the glass sidebar.
                HStack(spacing: 0) {
                    flatSidebar.safeAreaInset(edge: .bottom) { sidebarFooter }.frame(width: 220)
                    Divider()
                    NavigationStack { detailView }
                }
            } else {
                NavigationSplitView {
                    sidebarList
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
                        .safeAreaInset(edge: .bottom) { sidebarFooter }
                } detail: { detailView }
            }
        }
        .navigationTitle(L(title))
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

    private var detailView: some View {
            Group {
                switch nav.page {
                case .home: HomeView(page: $nav.page)
                case .android: AndroidCastView()
                case .ios: IOSCastView()
                case .files: AndroidFilesView()
                case .iosFiles: IOSFilesView()
                case .emulator: EmulatorView()
                case .remote: RemoteDesktopView()
                case .donate: DonateView()
                case .about: AboutView()
                }
            }
            .id(nav.page)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .animation(.spring(response: 0.38, dampingFraction: 0.9), value: nav.page)
    }

    private var title: String {
        switch nav.page {
        case .home: return Brand.name
        case .android: return "Android"
        case .ios: return "iPhone & iPad"
        case .files: return "File Android"
        case .iosFiles: return "File iPhone"
        case .emulator: return "Emulator Android"
        case .remote: return "Remote Desktop"
        case .donate: return "Donasi"
        case .about: return "Tentang"
        }
    }

    /// Sidebar selection must be optional for List; map it onto the shared page.
    private var sidebarSelection: Binding<Page?> {
        Binding(get: { nav.page }, set: { if let p = $0 { nav.page = p } })
    }

    private var sidebarList: some View {
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
                sidebarRow(.iosFiles, "File iPhone", "photo.on.rectangle.angled", Theme.ios)
                sidebarRow(.emulator, "Emulator Android", "apps.iphone", Theme.emulator, badge: emulator.running.count)
                sidebarRow(.remote, "Remote Desktop", "display.2", Theme.remote)
            }
            Section("Komunitas") {
                sidebarRow(.donate, "Donasi", "heart.fill", Theme.donate)
                sidebarRow(.about, "Tentang", "info.circle.fill", [Color(white: 0.55), Color(white: 0.35)])
            }
        }
        .listStyle(.sidebar)
    }

    private var flatSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                flatRow(.home, "Beranda", "house.fill", Brand.colors, 0)
                flatHeader("Cast")
                flatRow(.android, "Android", "smartphone", Theme.android, android.readyCount)
                flatRow(.ios, "iPhone & iPad", "iphone", Theme.ios, ios.devices.count)
                flatHeader("Alat")
                flatRow(.files, "File Android", "folder.fill", Theme.files, 0)
                flatRow(.iosFiles, "File iPhone", "photo.on.rectangle.angled", Theme.ios, 0)
                flatRow(.emulator, "Emulator Android", "apps.iphone", Theme.emulator, emulator.running.count)
                flatRow(.remote, "Remote Desktop", "display.2", Theme.remote, 0)
                flatHeader("Komunitas")
                flatRow(.donate, "Donasi", "heart.fill", Theme.donate, 0)
                flatRow(.about, "Tentang", "info.circle.fill", [Color(white: 0.55), Color(white: 0.35)], 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.55))
    }
    private func flatHeader(_ t: String) -> some View {
        Text(L(t)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 4)
    }
    private func flatRow(_ p: Page, _ label: String, _ icon: String, _ colors: [Color], _ badge: Int) -> some View {
        HStack(spacing: 10) {
            IconBadge(icon: icon, colors: colors, size: 24)
            Text(L(label)).font(.system(size: 13))
            Spacer()
            if badge > 0 { Text("\(badge)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(nav.page == p ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func sidebarRow(_ p: Page, _ label: String, _ icon: String, _ colors: [Color], badge: Int = 0) -> some View {
        HStack(spacing: 10) {
            IconBadge(icon: icon, colors: colors, size: 24)
            Text(L(label))
        }
        .padding(.vertical, 2)
        .badge(badge)
        // List selection is Page?, but tags must be plain Page — an Optional tag makes clicks select nil.
        .tag(p)
    }

    @AppStorage("appearance") private var appearance = Appearance.light.rawValue

    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(L(Brand.name)).font(.callout.weight(.semibold))
                Text("v\(Brand.version)").font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Picker("Tampilan", selection: $appearance) {
                    ForEach(Appearance.allCases) { a in Label(L(a.label), systemImage: a.icon).tag(a.rawValue) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: (Appearance(rawValue: appearance) ?? .system).icon)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Tampilan: terang, gelap, atau ikuti sistem")
            Menu {
                Picker("Bahasa", selection: Binding(get: { AppLanguage.current }, set: { AppLanguage.set($0); askRelaunch = true })) {
                    Text("Ikuti sistem").tag("system")
                    Text(verbatim: "Bahasa Indonesia").tag("id")
                    Text(verbatim: "English").tag("en")
                }
                .pickerStyle(.inline)
            } label: { Image(systemName: "globe") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Bahasa: Indonesia atau English")
        }
        .padding(12)
        .alert("Bahasa berubah setelah Djie Cast dibuka ulang.", isPresented: $askRelaunch) {
            Button("Buka ulang sekarang") { AppLanguage.relaunch() }
            Button("Nanti", role: .cancel) {}
        }
    }
}

// MARK: - Splash

struct SplashView: View {
    let onFinish: () -> Void
    @State private var start = Date()
    /// DJIE_SPLASH=<seconds> freezes the splash at that moment (for snapshots).
    private let frozen = Demo.env["DJIE_SPLASH"].flatMap(Double.init)
    private let duration = 2.4

    var body: some View {
        TimelineView(.animation(paused: frozen != nil)) { ctx in
            let t = frozen ?? ctx.date.timeIntervalSince(start)
            content(t)
        }
        .onAppear {
            start = Date()
            setToolbar(visible: false)
            if frozen == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { setToolbar(visible: true); onFinish() }
            }
        }
        .onDisappear { setToolbar(visible: true) }
    }

    // MARK: pieces, each a pure function of t (seconds since the splash appeared)

    private func content(_ t: Double) -> some View {
        let ink = Color(red: 0.043, green: 0.047, blue: 0.094)
        let iconIn = spring(t - 0.05, stiffness: 170, damping: 13)
        return ZStack {
            ink
            // two slow glows: indigo above, cyan below-right
            RadialGradient(colors: [Brand.start.opacity(0.55), .clear], center: UnitPoint(x: 0.5 + 0.03 * sin(t * 0.9), y: 0.28),
                           startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Brand.end.opacity(0.28), .clear], center: UnitPoint(x: 0.78, y: 0.92 - 0.02 * sin(t)),
                           startRadius: 0, endRadius: 460)
            dotGrid(t).opacity(0.5)

            VStack(spacing: 0) {
                ZStack {
                    castWaves(t)
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().interpolation(.high)
                        .frame(width: 128, height: 128)
                        .shadow(color: Brand.start.opacity(0.65), radius: 40, y: 14)
                        .scaleEffect(0.72 + 0.28 * iconIn)
                        .opacity(min(1, max(0, (t - 0.02) / 0.25)))
                        .blur(radius: 8 * max(0, 1 - iconIn))
                }
                .frame(height: 220)

                wordmark(t).padding(.top, 8)

                Text("Layar HP-mu, langsung di Mac.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.top, 12)
                    .opacity(ease((t - 0.9) / 0.4))
                    .offset(y: 8 * (1 - ease((t - 0.9) / 0.4)))
            }
            .offset(y: -18)

            VStack(spacing: 12) {
                Spacer()
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(Brand.gradient).frame(width: 180 * ease(t / (duration - 0.2)))
                }
                .frame(width: 180, height: 3)
                Text("VERSI \(Brand.version)  ·  OPEN SOURCE")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .kerning(1.6)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.bottom, 44)
            .opacity(ease((t - 0.5) / 0.4))
        }
        .ignoresSafeArea()
    }

    /// Wi-Fi style arcs leaving the icon's lower-left corner, like the cast symbol, one after another.
    private func castWaves(_ t: Double) -> some View {
        // signal arcs leave the icon toward the top-right, echoing the waves in the logo
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let t0 = 0.35 + Double(i) * 0.3
                let p = t > t0 ? ((t - t0) / 1.4).truncatingRemainder(dividingBy: 1) : 0
                let r = 96 + 150 * p
                Circle()
                    .trim(from: 0.79, to: 0.96)
                    .stroke(LinearGradient(colors: [Brand.end, Brand.start], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: r * 2, height: r * 2)
                    .opacity(t > t0 ? (1 - p) * (1 - p) * 0.9 : 0)
            }
        }
    }

    private func wordmark(_ t: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(Brand.name.enumerated()), id: \.offset) { i, ch in
                let k = spring(t - 0.45 - Double(i) * 0.035, stiffness: 260, damping: 20)
                Text(String(ch))
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(.white)
                    .offset(y: 26 * (1 - k))
                    .opacity(min(1, max(0, k * 1.4)))
            }
        }
        .kerning(-0.8)
        .mask(Rectangle().padding(.vertical, -4))
    }

    private func dotGrid(_ t: Double) -> some View {
        Canvas { c, size in
            let step: CGFloat = 26
            let cx = size.width / 2, cy = size.height * 0.42
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    let d = hypot(x - cx, y - cy) / max(size.width, size.height)
                    let a = max(0, 0.22 - d * 0.32) * min(1, t / 0.6)
                    c.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(.white.opacity(a)))
                    x += step
                }
                y += step
            }
        }
    }

    /// The window toolbar would sit on top of the splash; hide it only while the splash is up.
    private func setToolbar(visible: Bool) {
        DispatchQueue.main.async {
            for w in NSApp.windows where w.toolbar != nil { w.toolbar?.isVisible = visible; w.titleVisibility = visible ? .visible : .hidden }
        }
    }

    // closed-form damped spring 0 → 1 (time in seconds)
    private func spring(_ t: Double, stiffness: Double, damping: Double) -> Double {
        guard t > 0 else { return 0 }
        let w0 = stiffness.squareRoot(), z = damping / (2 * w0)
        if z < 1 {
            let wd = w0 * (1 - z * z).squareRoot()
            return 1 - exp(-z * w0 * t) * (cos(wd * t) + z * w0 / wd * sin(wd * t))
        }
        return 1 - exp(-w0 * t) * (1 + w0 * t)
    }
    private func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return 1 - pow(1 - c, 3) }
}

// MARK: - Home dashboard

struct HomeView: View {
    @Binding var page: Page
    @ObservedObject private var android = LauncherModel.shared
    @ObservedObject private var ios = IOSCastModel.shared
    @ObservedObject private var emu = EmulatorModel.shared

    private var connected: Int { android.readyCount + ios.devices.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                hero
                connections.appearIn(0.1)
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Mulai cast")
                    HStack(spacing: 16) {
                        PlatformCard(icon: "smartphone", title: "Android", colors: Theme.android,
                                     description: "Mirror dan kontrol penuh HP Android dari Mac.",
                                     features: ["USB & Wi-Fi", "Kontrol mouse & keyboard", "Audio, rekam & file manager"],
                                     status: android.readyCount > 0 ? String(localized: "\(android.readyCount) perangkat siap") : nil,
                                     live: !android.running.isEmpty) { page = .android }
                        PlatformCard(icon: "iphone", title: "iPhone & iPad", colors: Theme.ios,
                                     description: "Tampilkan layar iPhone/iPad lewat kabel atau wireless.",
                                     features: ["USB tanpa install", "iPhone Mirroring", "AirPlay"],
                                     status: ios.devices.isEmpty ? nil : String(localized: "\(ios.devices.count) perangkat siap"),
                                     live: !ios.mirroring.isEmpty) { page = .ios }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .appearIn(0.15)
                about.appearIn(0.22)
                readout.appearIn(0.28)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(maxWidth: 1060)
            .frame(maxWidth: .infinity)
        }
        .task {
            // emulators started anywhere (Djie Cast or Android Studio) count on the home page too
            while !Task.isCancelled {
                await emu.refreshSerials()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 6) {
                    PulseDot(active: connected > 0)
                    Text(connected > 0 ? "\(connected) PERANGKAT TERSAMBUNG" : "MENUNGGU PERANGKAT")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .kerning(1.2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.spring, value: connected)
                }
                (Text("Layar HP-mu,\n") + Text("langsung di Mac.").foregroundColor(Brand.start))
                    .font(.system(size: 40, weight: .heavy))
                    .kerning(-1.2)
                    .lineSpacing(-4)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Colok kabel atau sambungkan lewat Wi-Fi, lalu kendalikan HP dengan mouse dan keyboard Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420, alignment: .leading)
                HStack(spacing: 10) {
                    Button { page = .android } label: { Label("Cast Android", systemImage: "smartphone") }
                        .buttonStyle(InkButtonStyle())
                    Button { page = .ios } label: { Label("Cast iPhone", systemImage: "iphone") }
                        .buttonStyle(OutlineButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appearIn(0)

            CastIllustration(deviceName: android.devices.first(where: { $0.state == "device" })?.displayName ?? "Galaxy S24 Ultra")
                .frame(maxWidth: 420)
                .appearIn(0.08)
        }
    }

    // MARK: Connected right now

    private var connections: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Terhubung sekarang", detail: "· diperbarui otomatis")
            HStack(spacing: 14) {
                countTile(android.readyCount, "Android", "HP Android siap", "smartphone", Theme.android) { page = .android }
                countTile(ios.devices.count, "iPhone & iPad", "Lewat kabel USB", "iphone", Theme.ios) { page = .ios }
                countTile(emu.running.count, "Emulator", "Sedang berjalan", "apps.iphone", Theme.emulator) { page = .emulator }
                countTile(android.running.count + ios.mirroring.count, "Sedang cast", "Jendela mirror terbuka", "rectangle.on.rectangle", Theme.remote) { page = .android }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func countTile(_ n: Int, _ title: String, _ detail: String, _ icon: String, _ colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Panel(highlight: n > 0 ? colors[0].opacity(0.6) : nil, padding: 16, fill: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        IconBadge(icon: icon, colors: colors, size: 32)
                        Spacer()
                        if n > 0 { PulseDot(color: colors[0]) }
                    }
                    Text("\(n)")
                        .font(.system(size: 34, weight: .heavy).monospacedDigit())
                        .foregroundStyle(n > 0 ? Color.primary : Color.secondary.opacity(0.6))
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: n)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L(title)).font(.callout.weight(.semibold))
                        Text(L(detail)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: About & developer

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Tentang Djie Cast")
            Panel(padding: 24) {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Satu aplikasi untuk semua layar HP-mu.")
                            .font(.system(size: 20, weight: .bold))
                        Text("Djie Cast lahir dari kebiasaan menjalankan scrcpy lewat terminal. Sekarang semuanya cukup satu klik: mirror & kontrol Android, tampilkan iPhone, kelola file, jalankan emulator Android, sampai mengendalikan Mac lain dari jauh. Gratis, open source, dan semua berjalan di Mac-mu sendiri — tanpa akun, tanpa server, tanpa iklan.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 560, alignment: .leading)
                        HStack(spacing: 8) {
                            Pill(text: String(localized: "Versi \(Brand.version)"), color: Brand.start)
                            Pill(text: String(localized: "Lisensi \(Brand.license)"), color: .secondary)
                            Pill(text: "Buatan Indonesia", color: Theme.live)
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Developer card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text("AK")
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Brand.gradient, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DIKEMBANGKAN OLEH").font(.system(size: 9.5, weight: .semibold)).kerning(0.8).foregroundStyle(.tertiary)
                                Text(L(Brand.author)).font(.headline)
                                Text("Developer · Indonesia").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            if let repo = Brand.repoURL {
                                Button { NSWorkspace.shared.open(repo) } label: { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                                    .buttonStyle(SoftButtonStyle(tint: Brand.start)).fixedSize()
                            }
                            Button { page = .donate } label: { Label("Traktir kopi", systemImage: "cup.and.saucer.fill") }
                                .buttonStyle(SoftButtonStyle(tint: Theme.donate[1])).fixedSize()
                        }
                    }
                    .padding(16)
                    .frame(width: 290, alignment: .leading)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    /// Quiet one-line facts instead of a row of tiles.
    private var readout: some View {
        HStack(spacing: 0) {
            ForEach(Array([("Mesin", "scrcpy \(Tools.scrcpyVersion)"), ("Chip", "Apple Silicon & Intel"),
                           ("Privasi", "100% lokal"), ("Lisensi", "\(Brand.license) · open source")].enumerated()), id: \.offset) { i, item in
                if i > 0 { Divider().frame(height: 30) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L(item.0).uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(.tertiary)
                    Text(L(item.1)).font(.callout.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, i == 0 ? 0 : 18)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
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
            Panel(highlight: hover ? colors[0] : nil, padding: 20, fill: true) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        IconBadge(icon: icon, colors: colors, size: 52)
                        Spacer()
                        if live { LiveBadge() }
                        else if let status { Pill(text: status, icon: "circle.fill", color: Theme.live) }
                    }
                    .frame(height: 52, alignment: .top)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L(title)).font(.system(size: 20, weight: .bold))
                        Text(L(description)).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(features, id: \.self) { f in
                            Label {
                                Text(L(f)).font(.callout)
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
            .shadow(color: colors[1].opacity(hover ? 0.18 : 0), radius: 18, y: 10)
            .offset(y: hover ? -3 : 0)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { hover = h } }
    }
}

struct InfoTile: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        Panel(padding: 14, fill: true) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.start)
                    .frame(width: 34, height: 34)
                    .background(Brand.start.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L(title)).font(.callout.weight(.semibold))
                    Text(L(detail)).font(.caption).foregroundStyle(.secondary)
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
            CommandMenu("Tampilan") {
                AppearanceMenu()
            }
            CommandGroup(replacing: .help) {
                Button("Donasi untuk \(Brand.name)") { Nav.shared.page = .donate }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            RemoteSelfTest.runIfRequested(); EmulatorSelfTest.runIfRequested(); RemoteSelfTest.runTailnetIfRequested(); DeviceSelfTest.runIfRequested()
            let env = ProcessInfo.processInfo.environment
            if env["DJIE_REMOTE_SELFTEST"] == nil && env["DJIE_EMU_SELFTEST"] == nil && env["DJIE_TAILNET_SELFTEST"] == nil && env["DJIE_DEMO"] == nil && env["DJIE_DEVICE_SELFTEST"] == nil {
                TailnetModel.shared.autoStart()
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { LauncherModel.shared.stopAll(); TailnetModel.shared.shutdownForQuit() }
    }
}

/// Menu-bar version of the appearance picker (Tampilan menu, ⌘⇧L / ⌘⇧D / ⌘⇧S).
struct AppearanceMenu: View {
    @AppStorage("appearance") private var appearance = Appearance.light.rawValue
    var body: some View {
        Button("Mode Terang") { appearance = Appearance.light.rawValue }.keyboardShortcut("l", modifiers: [.command, .shift])
        Button("Mode Gelap") { appearance = Appearance.dark.rawValue }.keyboardShortcut("d", modifiers: [.command, .shift])
        Button("Ikuti Sistem") { appearance = Appearance.system.rawValue }.keyboardShortcut("s", modifiers: [.command, .shift])
    }
}
