import SwiftUI
import AppKit

struct DonateView: View {
    private let qris: NSImage? = Bundle.main.image(forResource: "qris")
    private let merchant = "Ruang Kiitaa"
    private let nmid = "ID1026525837765"
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(icon: "heart.fill", colors: Theme.donate, title: "Dukung Djie Cast",
                           subtitle: "Gratis & open source — donasi membantu pengembangan terus berjalan")

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Panel(padding: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    IconBadge(icon: "chevron.left.forwardslash.chevron.right", colors: Brand.colors, size: 36)
                                    Text("Open Source").font(.title3.weight(.bold))
                                    Pill(text: "Lisensi \(Brand.license)", color: Brand.start)
                                }
                                Text("Djie Cast bebas dipakai, dipelajari, diubah, dan dibagikan. Kode sumbernya terbuka untuk siapa saja yang ingin ikut mengembangkan.")
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let url = Brand.repoURL {
                                    Button { NSWorkspace.shared.open(url) } label: {
                                        Label("Lihat kode di GitHub", systemImage: "arrow.up.forward.square")
                                    }
                                    .buttonStyle(GradientButtonStyle(colors: Brand.colors))
                                    .frame(maxWidth: 260)
                                }
                            }
                        }

                        Panel(padding: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Cara donasi").font(.headline)
                                ForEach(Array(["Buka aplikasi bank atau e-wallet berlogo QRIS (GoPay, OVO, DANA, ShopeePay, m-banking, dll).",
                                               "Scan kode QRIS di samping dengan kamera HP.",
                                               "Masukkan nominal seikhlasnya, cek nama \"\(merchant)\", lalu bayar."].enumerated()), id: \.offset) { i, s in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(i + 1)")
                                            .font(.caption.weight(.bold))
                                            .frame(width: 20, height: 20)
                                            .background(Theme.donate[0].opacity(0.15), in: Circle())
                                            .foregroundStyle(Theme.donate[1])
                                        Text(s).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Text("Terima kasih banyak atas dukunganmu! 🙏")
                                    .font(.callout.weight(.medium))
                                    .padding(.top, 4)
                            }
                        }

                        ConfirmDonationPanel()

                        Panel(padding: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Cara lain untuk mendukung").font(.headline)
                                Label("Bagikan Djie Cast ke teman", systemImage: "square.and.arrow.up")
                                Label("Laporkan bug atau usulkan fitur", systemImage: "ladybug")
                                Label("Kirim kontribusi kode (pull request)", systemImage: "arrow.triangle.pull")
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    qrisCard
                        .frame(width: 340)
                }
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    private var qrisCard: some View {
        VStack(spacing: 14) {
            if let qris {
                Image(nsImage: qris)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                    .shadow(color: Theme.donate[0].opacity(0.25), radius: 18, y: 8)
            }
            HStack(spacing: 10) {
                Button(action: saveQRIS) { Label("Simpan QRIS", systemImage: "square.and.arrow.down") }
                    .buttonStyle(GradientButtonStyle(colors: Theme.donate))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(nmid, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: { Label(copied ? "Tersalin" : "Salin NMID", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(SoftButtonStyle(tint: Theme.donate[1]))
            }
            Text("\(merchant) · NMID \(nmid)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func saveQRIS() {
        guard let qris, let tiff = qris.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("QRIS-Donasi-Djie-Cast.png")
        if (try? png.write(to: url)) != nil { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

/// Phone/WhatsApp confirmation after donating.
struct ConfirmDonationPanel: View {
    @State private var copied = false

    var body: some View {
        Panel(highlight: Theme.live.opacity(0.6), padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconBadge(icon: "checkmark.message.fill", colors: [Color(red: 0.15, green: 0.82, blue: 0.40), Color(red: 0.05, green: 0.60, blue: 0.35)], size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sudah donasi? Konfirmasi ya").font(.headline)
                        Text("Kirim bukti transfer ke \(Brand.author)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(Brand.donationPhoneDisplay)
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Button { NSWorkspace.shared.open(Brand.donationWhatsApp) } label: {
                        Label("Chat WhatsApp", systemImage: "message.fill")
                    }
                    .buttonStyle(GradientButtonStyle(colors: [Color(red: 0.15, green: 0.82, blue: 0.40), Color(red: 0.05, green: 0.60, blue: 0.35)]))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Brand.donationPhoneDisplay.replacingOccurrences(of: "-", with: ""), forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: { Label(copied ? "Tersalin" : "Salin nomor", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(SoftButtonStyle(tint: Theme.live))
                }
                .frame(maxWidth: 380)
            }
        }
    }
}
