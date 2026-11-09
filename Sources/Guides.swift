import SwiftUI

// MARK: - Setup guides: what each platform requires before casting over USB

struct GuideStep: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

enum SetupGuide: Identifiable {
    case android, ios, remoteHost
    var id: Self { self }

    var requirement: String {
        switch self {
        case .android: return "Wajib aktifkan USB Debugging"
        case .ios: return "Wajib ketuk “Percayai Komputer Ini”"
        case .remoteHost: return "Wajib beri izin Perekaman Layar & Aksesibilitas"
        }
    }

    var summary: String {
        switch self {
        case .android: return "Tanpa USB Debugging, Mac tidak bisa membaca layar HP Android. Cukup diatur sekali per HP."
        case .ios: return "iPhone/iPad hanya mau mengirim layarnya ke Mac yang sudah dipercaya. Cukup sekali per Mac."
        case .remoteHost: return "Di Mac yang akan dikontrol, macOS perlu mengizinkan Djie Cast merekam layar dan menggerakkan mouse/keyboard."
        }
    }

    var title: String {
        switch self {
        case .android: return "Cara mengaktifkan USB Debugging"
        case .ios: return "Cara mempercayai Mac ini di iPhone/iPad"
        case .remoteHost: return "Cara memberi izin Remote Desktop"
        }
    }

    var tint: Color { self == .android ? Theme.android[1] : self == .ios ? Theme.ios[1] : Theme.remote[1] }

    var eyebrow: String {
        switch self {
        case .android: return "ANDROID · USB"
        case .ios: return "IPHONE & IPAD · USB"
        case .remoteHost: return "REMOTE DESKTOP · MAC YANG DIKONTROL"
        }
    }

    var steps: [GuideStep] {
        switch self {
        case .android:
            return [
                GuideStep(icon: "gearshape", title: "Buka Pengaturan → Tentang ponsel",
                          detail: "Samsung: Tentang ponsel → Informasi perangkat lunak. Xiaomi: Tentang ponsel. Oppo/Realme/Vivo: Tentang ponsel → Versi."),
                GuideStep(icon: "hand.tap", title: "Ketuk “Nomor bentukan” 7 kali",
                          detail: "Di beberapa HP namanya Build number, Versi MIUI/HyperOS, atau Versi OS. Masukkan PIN bila diminta sampai muncul “Anda sekarang developer”."),
                GuideStep(icon: "hammer", title: "Buka Opsi pengembang",
                          detail: "Kembali ke Pengaturan → Sistem → Opsi pengembang (Developer options). Di Samsung letaknya di bagian paling bawah Pengaturan."),
                GuideStep(icon: "cable.connector", title: "Nyalakan “USB debugging”",
                          detail: "Khusus Xiaomi/Redmi/POCO: nyalakan juga “USB debugging (Setelan keamanan)” supaya klik dan ketik dari Mac berfungsi."),
                GuideStep(icon: "iphone.gen3.radiowaves.left.and.right", title: "Colok kabel data ke Mac",
                          detail: "Pakai kabel yang mendukung data, bukan kabel cas saja. Jika HP bertanya mode USB, pilih “Transfer file”."),
                GuideStep(icon: "checkmark.shield", title: "Ketuk “Izinkan” di HP",
                          detail: "Muncul dialog “Izinkan USB debugging?”. Centang “Selalu izinkan dari komputer ini”, lalu Izinkan. HP akan muncul di Djie Cast."),
            ]
        case .ios:
            return [
                GuideStep(icon: "cable.connector", title: "Colok iPhone/iPad ke Mac",
                          detail: "Pakai kabel Lightning atau USB-C yang mendukung data."),
                GuideStep(icon: "lock.open", title: "Buka kunci layar iPhone",
                          detail: "Dialog izin hanya muncul saat iPhone tidak terkunci."),
                GuideStep(icon: "hand.tap", title: "Ketuk “Percayai” (Trust)",
                          detail: "Pada pertanyaan “Percayai Komputer Ini?”, pilih Percayai lalu masukkan kode sandi iPhone."),
                GuideStep(icon: "desktopcomputer", title: "Izinkan aksesori di Mac",
                          detail: "macOS bisa bertanya “Izinkan aksesori tersambung?”. Klik Izinkan."),
                GuideStep(icon: "video", title: "Izinkan akses Kamera untuk Djie Cast",
                          detail: "Saat Mulai Cast pertama kali, macOS meminta izin Kamera karena layar iPhone dibaca sebagai sumber video. Klik OK."),
            ]
        case .remoteHost:
            return [
                GuideStep(icon: "rectangle.dashed.badge.record", title: "Izinkan Perekaman Layar",
                          detail: "Di halaman Remote Desktop klik “Beri izin” pada Perekaman Layar, atau buka Pengaturan Sistem → Privasi & Keamanan → Perekaman Layar & Audio Sistem, lalu nyalakan Djie Cast."),
                GuideStep(icon: "accessibility", title: "Izinkan Aksesibilitas",
                          detail: "Klik “Beri izin” pada Aksesibilitas, atau buka Pengaturan Sistem → Privasi & Keamanan → Aksesibilitas, lalu nyalakan Djie Cast. Ini yang membuat klik dan ketikan dari Mac lain berfungsi."),
                GuideStep(icon: "arrow.clockwise", title: "Buka ulang Djie Cast",
                          detail: "macOS biasanya meminta app dibuka ulang setelah izin Perekaman Layar diberikan."),
                GuideStep(icon: "network", title: "Izinkan Jaringan Lokal",
                          detail: "Bila macOS bertanya “Izinkan Djie Cast menemukan perangkat di jaringan lokal?”, pilih Izinkan agar Mac saling terdeteksi."),
                GuideStep(icon: "key", title: "Nyalakan “Izinkan Mac ini diakses”",
                          detail: "Bagikan kode 6 angka ke pengontrol. Kode bisa diganti kapan saja, dan sesi bisa diputus dari panel merah di atas layar."),
            ]
        }
    }

    var troubleshooting: [String] {
        switch self {
        case .android:
            return [
                "Dialog izin tidak muncul? Cabut lalu colok lagi kabelnya, atau buka Opsi pengembang → “Cabut otorisasi USB debugging” lalu ulangi.",
                "Status “unauthorized” di Djie Cast berarti HP belum menekan Izinkan.",
                "Untuk Wi-Fi: colok USB dulu, lalu pilih ••• → Aktifkan Wi-Fi di kartu perangkat.",
            ]
        case .ios:
            return [
                "Pernah menekan “Jangan Percayai”? Di iPhone buka Pengaturan → Umum → Transfer atau Atur Ulang iPhone → Atur Ulang → Atur Ulang Lokasi & Privasi, lalu colok lagi.",
                "Izin Kamera tertolak? Buka Pengaturan Sistem → Privasi & Keamanan → Kamera, lalu nyalakan Djie Cast.",
                "iPhone belum muncul? Tunggu beberapa detik, atau cabut-colok kabel sambil layar iPhone terbuka.",
            ]
        case .remoteHost:
            return [
                "Setelah memperbarui Djie Cast, izin kadang perlu dimatikan lalu dinyalakan lagi di Pengaturan Sistem karena app belum ditandatangani Apple.",
                "Mac tidak terdeteksi? Pastikan kedua Mac di Wi-Fi yang sama, atau ketik alamat IP-nya. Beda jaringan: pakai Tailscale.",
                "Firewall macOS menyala? Izinkan koneksi masuk untuk Djie Cast saat diminta.",
            ]
        }
    }
}

/// Compact "required" banner shown at the top of a platform page.
struct RequirementBanner: View {
    let guide: SetupGuide
    let onShow: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("WAJIB")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .foregroundStyle(.orange)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(L(guide.requirement)).font(.callout.weight(.semibold))
                Text(L(guide.summary)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Lihat langkah-langkah", action: onShow)
                .buttonStyle(SoftButtonStyle(tint: guide.tint))
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.28)))
    }
}

/// Numbered step list, used both inline (empty state) and in the sheet.
struct GuideStepsList: View {
    let guide: SetupGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(guide.steps.enumerated()), id: \.element.id) { i, step in
                HStack(alignment: .top, spacing: 14) {
                    Text(String(format: "%02d", i + 1))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(guide.tint)
                        .frame(width: 26, height: 26)
                        .background(guide.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 3) {
                        Label(L(step.title), systemImage: step.icon)
                            .font(.callout.weight(.semibold))
                            .labelStyle(TitleOnlyWithIconAfter())
                        Text(L(step.detail)).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 11)
                if i < guide.steps.count - 1 { Divider().padding(.leading, 40) }
            }
        }
    }
}

private struct TitleOnlyWithIconAfter: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.font(.caption).foregroundStyle(.tertiary)
        }
    }
}

struct SetupGuideSheet: View {
    let guide: SetupGuide
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(guide.eyebrow))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .kerning(1.2)
                        .foregroundStyle(.secondary)
                    Text(L(guide.title)).font(.title2.weight(.bold))
                    Text(L(guide.summary)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GuideStepsList(guide: guide)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kalau ada kendala").font(.callout.weight(.semibold))
                        ForEach(guide.troubleshooting, id: \.self) { t in
                            HStack(alignment: .top, spacing: 8) {
                                Text("—").foregroundStyle(.tertiary)
                                Text(L(t)).font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Selesai") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(16)
        }
        .frame(width: 560, height: 640)
    }
}
