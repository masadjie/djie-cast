import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero

                HStack(alignment: .top, spacing: 16) {
                    Panel(padding: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                IconBadge(icon: "person.fill", colors: Brand.colors, size: 36)
                                Text("Pembuat").font(.headline)
                            }
                            Text(Brand.author).font(.system(size: 22, weight: .bold))
                            Text("Djie Cast dibuat untuk memudahkan siapa saja menampilkan & mengendalikan HP dari Mac — tanpa terminal, tanpa ribet.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Panel(padding: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                IconBadge(icon: "chevron.left.forwardslash.chevron.right", colors: Theme.android, size: 36)
                                Text("Open Source").font(.headline)
                                Pill(text: "Lisensi \(Brand.license)", color: Theme.android[1])
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
            Text(Brand.name).font(.system(size: 34, weight: .heavy))
            Text("Cast Android & iOS ke Mac").font(.title3).foregroundStyle(.secondary)
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
                Text(name).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
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
