import SwiftUI
import AppKit

extension Theme {
    static let remote = [Color(red: 0.36, green: 0.42, blue: 0.98), Color(red: 0.24, green: 0.28, blue: 0.80)]
}

struct RemoteDesktopView: View {
    @ObservedObject var host = RemoteHostModel.shared
    @ObservedObject var viewer = RemoteViewerModel.shared
    @AppStorage("remoteLastAddress") private var address = ""
    @State private var code = ""
    @State private var selected: RemoteViewerModel.Found?
    @State private var showGuide = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(icon: "display.2", colors: Theme.remote, title: "Remote Desktop",
                           subtitle: "Lihat dan kendalikan Mac lain lewat jaringan, terenkripsi") {
                    sessionPill
                }
                .appearIn(0)

                HStack(alignment: .top, spacing: 18) {
                    hostPanel
                    connectPanel
                }
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(0.08)

                tips.appearIn(0.16)
            }
            .padding(28)
        }
        .onAppear {
            host.refreshPermissions()
            viewer.startBrowsing()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            host.refreshPermissions()
        }
        .sheet(isPresented: $showGuide) { SetupGuideSheet(guide: .remoteHost) }
        .toolbar {
            ToolbarItem {
                Button { showGuide = true } label: { Label("Panduan izin", systemImage: "questionmark.circle") }
                    .help("Izin macOS yang dibutuhkan Remote Desktop")
            }
        }
    }

    @ViewBuilder private var sessionPill: some View {
        switch (host.status, viewer.status) {
        case (.connected(let who), _):
            HStack(spacing: 7) { PulseDot(color: .red); Text("Dikontrol oleh \(who)").font(.callout.weight(.medium)) }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.red.opacity(0.1), in: Capsule())
        case (_, .connected(let to)):
            HStack(spacing: 7) { PulseDot(); Text("Mengontrol \(to)").font(.callout.weight(.medium)) }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.live.opacity(0.1), in: Capsule())
        default:
            EmptyView()
        }
    }

    // MARK: Host side

    private var hostPanel: some View {
        Panel(padding: 20, fill: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Izinkan Mac ini diakses").font(.headline)
                        Text("Bagikan kode ke orang yang ingin mengontrol Mac ini.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { host.enabled }, set: { host.setEnabled($0) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if host.enabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("KODE AKSES").font(.system(size: 10.5, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(.secondary)
                        HStack(alignment: .center, spacing: 12) {
                            Text(host.code.prefix(3) + " " + host.code.suffix(3))
                                .font(.system(size: 34, weight: .bold, design: .monospaced))
                                .textSelection(.enabled)
                                .contentTransition(.numericText())
                            Button { withAnimation { host.regenerateCode() } } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.borderless)
                                .help("Buat kode baru (sesi yang sedang berjalan akan terputus)")
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(host.code, forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.borderless)
                                .help("Salin kode")
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ALAMAT MAC INI").font(.system(size: 10.5, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(.secondary)
                        LabeledContent("Nama", value: NetInfo.macName).font(.callout)
                        ForEach(host.addresses, id: \.self) { a in
                            LabeledContent(a.label) {
                                Text(host.port == Remote.port.rawValue ? a.ip : "\(a.ip):\(host.port)")
                                    .font(.callout.monospaced()).textSelection(.enabled)
                            }
                            .font(.callout)
                        }
                        if host.addresses.isEmpty {
                            Text("Belum tersambung ke jaringan.").font(.callout).foregroundStyle(.orange)
                        }
                    }
                    hostStatus
                }

                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("IZIN MACOS").font(.system(size: 10.5, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(.secondary)
                    permissionRow("Perekaman Layar", detail: "Agar layar Mac ini bisa dikirim", ok: host.screenAllowed,
                                  action: host.requestScreenPermission)
                    permissionRow("Aksesibilitas", detail: "Agar mouse & keyboard dari jauh bisa dipakai", ok: host.inputAllowed,
                                  action: host.requestInputPermission)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: host.enabled)
    }

    @ViewBuilder private var hostStatus: some View {
        switch host.status {
        case .waiting:
            HStack(spacing: 8) { PulseDot(color: Theme.remote[0]); Text("Menunggu koneksi…").font(.callout).foregroundStyle(.secondary) }
        case .connected(let who):
            HStack(spacing: 10) {
                PulseDot(color: .red)
                Text("Dikontrol oleh \(who)").font(.callout.weight(.semibold))
                Spacer()
                Button("Putuskan") { host.disconnectViewer() }
                    .buttonStyle(SoftButtonStyle(tint: .red)).fixedSize()
            }
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
        case .off:
            EmptyView()
        }
    }

    private func permissionRow(_ title: String, detail: String, ok: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Theme.live : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok {
                Button("Beri izin", action: action).buttonStyle(SoftButtonStyle(tint: Theme.remote[1])).fixedSize()
            }
        }
    }

    // MARK: Viewer side

    private var connectPanel: some View {
        Panel(padding: 20, fill: true) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hubungkan ke Mac lain").font(.headline)
                    Text("Pilih Mac di jaringan yang sama, atau ketik alamatnya.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("DI JARINGAN INI").font(.system(size: 10.5, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(.secondary)
                    if viewer.found.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Mencari Mac yang menyalakan “Izinkan diakses”…").font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(viewer.found) { f in
                            Button {
                                selected = f; address = ""
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "desktopcomputer").foregroundStyle(Theme.remote[1])
                                    Text(f.name).font(.callout.weight(.medium))
                                    Spacer()
                                    if selected == f { Image(systemName: "checkmark").foregroundStyle(Theme.remote[1]) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(selected == f ? Theme.remote[0].opacity(0.1) : Color.primary.opacity(0.03),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewer.found)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ATAU KETIK ALAMAT").font(.system(size: 10.5, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(.secondary)
                    field("network", "192.168.1.20 atau 100.x.x.x", text: Binding(get: { address }, set: { address = $0; if !$0.isEmpty { selected = nil } }))
                    field("key", "Kode 6 angka dari Mac tujuan", text: $code)
                }

                Button(action: connect) {
                    if case .connecting = viewer.status {
                        HStack(spacing: 8) { ProgressView().controlSize(.small).tint(.white); Text("Menghubungkan…") }
                    } else {
                        Label("Hubungkan", systemImage: "arrow.right.circle.fill")
                    }
                }
                .buttonStyle(GradientButtonStyle(colors: Theme.remote))
                .disabled((selected == nil && address.isEmpty) || code.filter(\.isNumber).count != 6)
                .keyboardShortcut(.defaultAction)

                switch viewer.status {
                case .failed(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                case .connected(let to):
                    HStack {
                        Label("Terhubung ke \(to)", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Theme.live)
                        Spacer()
                        Button("Putuskan") { viewer.disconnect() }.buttonStyle(SoftButtonStyle(tint: .red)).fixedSize()
                    }
                default: EmptyView()
                }
            }
        }
    }

    private func field(_ icon: String, _ prompt: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
            TextField(prompt, text: text).textFieldStyle(.plain).onSubmit(connect)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func connect() {
        if let selected { viewer.connect(to: selected, code: code) }
        else { viewer.connect(address: address, code: code) }
    }

    // MARK: Tips

    private var tips: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Beda jaringan? Pakai Tailscale (gratis)").font(.headline)
                Text("Pasang Tailscale di kedua Mac dan masuk dengan akun yang sama. Mac tujuan akan punya alamat 100.x.x.x yang bisa diketik di kolom alamat, dari mana pun.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    Label("Koneksi terenkripsi TLS dengan kode akses", systemImage: "lock.fill")
                    Label("Satu pengontrol dalam satu waktu", systemImage: "person.fill")
                    Label("Bisa diputus kapan saja dari Mac tujuan", systemImage: "xmark.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Button { NSWorkspace.shared.open(URL(string: "https://tailscale.com/download/mac")!) } label: {
                    Label("Unduh Tailscale", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(SoftButtonStyle(tint: Theme.remote[1]))
                .fixedSize()
            }
        }
    }
}
