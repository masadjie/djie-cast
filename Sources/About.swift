import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero

                HStack(alignment: .top, spacing: 16) {
                    Panel(padding: 20, fill: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                IconBadge(icon: "person.fill", colors: Brand.colors, size: 36)
                                Text("Pembuat").font(.headline)
                            }
                            Text(L(Brand.author)).font(.system(size: 22, weight: .bold))
                            Text("Djie Cast dibuat untuk memudahkan siapa saja menampilkan & mengendalikan HP dari Mac — tanpa terminal, tanpa ribet.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Panel(padding: 20, fill: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                IconBadge(icon: "chevron.left.forwardslash.chevron.right", colors: Theme.android, size: 36)
                                Text("Open Source").font(.headline)
                                Pill(text: String(localized: "Lisensi \(Brand.license)"), color: Theme.android[1])
                            }
                            Text("Aplikasi ini open source dan gratis selamanya. Bebas dipakai, dipelajari, diubah, dan dibagikan.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let url = Brand.repoURL {
                                Button { NSWorkspace.shared.open(url) } label: {
                                    Label("Kode sumber di GitHub", systemImage: "arrow.up.forward.square")
                                }
                                .buttonStyle(SoftButtonStyle(tint: Theme.android[1]))
                                .frame(maxWidth: 240)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                donateCard

                supportedMacs

                Panel(padding: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dibangun dengan").font(.headline)
                        credit("scrcpy \(Tools.scrcpyVersion)", "Genymobile · Apache License 2.0", "https://github.com/Genymobile/scrcpy")
                        credit("Android Debug Bridge (adb)", "Android Open Source Project · Apache License 2.0", "https://developer.android.com/tools/adb")
                        credit("SwiftUI & AVFoundation", "Apple", nil)
                    }
                }

                Text("© 2026 \(Brand.author) · \(Brand.name) v\(Brand.version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: Brand.start.opacity(0.35), radius: 16, y: 8)
            Text(L(Brand.name)).font(.system(size: 34, weight: .heavy))
            Text(verbatim: Brand.tagline).font(.title3).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Pill(text: "v\(Brand.version)", color: Brand.start)
                Pill(text: "Open Source", icon: "chevron.left.forwardslash.chevron.right", color: Theme.android[1])
                Pill(text: "Apple Silicon & Intel", icon: "cpu", color: .secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var donateCard: some View {
        Panel(highlight: Theme.donate[1].opacity(0.6), padding: 20) {
            HStack(spacing: 16) {
                IconBadge(icon: "heart.fill", colors: Theme.donate, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Suka dengan Djie Cast?").font(.headline)
                    Text("Dukung pengembangannya lewat donasi QRIS, lalu konfirmasi ke \(Brand.donationPhoneDisplay).")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button { Nav.shared.page = .donate } label: { Label("Donasi via QRIS", systemImage: "qrcode") }
                    .buttonStyle(GradientButtonStyle(colors: Theme.donate))
                    .fixedSize()
            }
        }
    }

    private func credit(_ name: String, _ detail: String, _ link: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(L(name)).font(.callout.weight(.medium))
                Text(L(detail)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let link, let url = URL(string: link) {
                Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.borderless)
                    .help(link)
            }
        }
    }
}

extension AboutView {
    /// Which Macs run Djie Cast (everything that runs macOS 14 Sonoma or later).
    var supportedMacs: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconBadge(icon: "laptopcomputer", colors: Brand.colors, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Mac yang didukung").font(.headline)
                        Text("Semua Mac yang bisa menjalankan macOS 14 Sonoma atau lebih baru").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    macRow("MacBook Air", "2018 ke atas (semua M1–M4)")
                    macRow("MacBook Pro", "2018 ke atas (semua M1–M5)")
                    macRow("iMac", "2019 ke atas")
                    macRow("iMac Pro", "2017")
                    macRow("Mac mini", "2018 ke atas")
                    macRow("Mac Studio", "Semua (2022 ke atas)")
                    macRow("Mac Pro", "2019 ke atas")
                }
                Text("Info & aplikasi iPhone butuh Mac Apple Silicon (M1 ke atas). iPhone Mirroring butuh macOS 15 Sequoia. Kamera iPhone butuh macOS 14 dan iOS 17. Fitur lain berjalan di Mac Intel maupun Apple Silicon.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func macRow(_ name: String, _ since: String) -> some View {
        GridRow {
            Text(verbatim: name).font(.callout.weight(.semibold))
            Text(L(since)).font(.callout).foregroundStyle(.secondary)
        }
    }
}
