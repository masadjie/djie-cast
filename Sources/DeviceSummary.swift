import SwiftUI
import AppKit

/// Caches device details + a screen snapshot per device so cards render instantly when revisited.
@MainActor
final class DeviceSummaryStore: ObservableObject {
    static let shared = DeviceSummaryStore()
    @Published var details: [String: DeviceDetail] = [:]
    @Published var shots: [String: NSImage] = [:]
    @Published var loading: Set<String> = []
    private var lastLoad: [String: Date] = [:]

    func load(_ b: DeviceBackend, force: Bool = false, withShot: Bool = true) {
        guard !loading.contains(b.id) else { return }
        if !force, let t = lastLoad[b.id], Date().timeIntervalSince(t) < 45 { return }
        loading.insert(b.id)
        Task {
            let d = await b.detail()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { details[b.id] = d }
            if withShot, let img = await b.screenshot() {
                withAnimation(.easeOut(duration: 0.35)) { shots[b.id] = img }
            }
            loading.remove(b.id)
            lastLoad[b.id] = Date()
        }
    }
}

/// A wide device card that shows the device's details right on the page.
struct DeviceSummaryCard<Actions: View>: View {
    let backend: DeviceBackend?
    let fallbackTitle: String
    let fallbackSubtitle: String
    let live: Bool
    let connection: String
    let showScreen: Bool
    let onDetails: () -> Void
    var titleOverride: String? = nil
    @ViewBuilder var actions: Actions
    @ObservedObject private var store = DeviceSummaryStore.shared

    private var id: String? { backend?.id }
    private var d: DeviceDetail? { id.flatMap { store.details[$0] } }
    private var accent: [Color] { backend?.accent ?? Theme.android }

    var body: some View {
        Panel(highlight: live ? Theme.live : nil, padding: 20) {
            HStack(alignment: .top, spacing: 24) {
                // Live screen in a phone bezel
                PhoneFrame(image: showScreen ? id.flatMap { store.shots[$0] } : nil, tint: accent[0])
                    .frame(width: 128, height: 264)
                    .overlay(alignment: .center) {
                        if !showScreen || (id.flatMap { store.shots[$0] } == nil && !(id.map { store.loading.contains($0) } ?? false)) {
                            Image(systemName: accent == Theme.ios ? "iphone" : "smartphone")
                                .font(.system(size: 34, weight: .light)).foregroundStyle(.white.opacity(0.5))
                        }
                    }

                // Name + key specs
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(titleOverride ?? d?.title ?? fallbackTitle).font(.title2.weight(.bold)).lineLimit(1)
                            Text(d?.subtitle ?? fallbackSubtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if let pill = d?.storagePill, !pill.isEmpty {
                            Text(pill).font(.caption.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        }
                        Spacer()
                        if live { LiveBadge() }
                        Pill(text: connection, icon: connection == "Wi-Fi" ? "wifi" : connection == "Emulator" ? "cpu" : "cable.connector", color: connection == "Wi-Fi" ? .blue : .secondary)
                    }
                    if let d {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                            ForEach(Array(stride(from: 0, to: min(8, d.specs.count), by: 2)), id: \.self) { i in
                                GridRow {
                                    specCell(d.specs[i])
                                    if i + 1 < min(8, d.specs.count) { specCell(d.specs[i + 1]) } else { Color.clear }
                                }
                            }
                        }
                        .transition(.opacity)
                    } else {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Membaca spesifikasi perangkat…").font(.callout).foregroundStyle(.secondary) }
                            .frame(minHeight: 120, alignment: .center)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        actions
                        Button(action: onDetails) { Label("Info & aplikasi", systemImage: "info.circle") }
                            .buttonStyle(SoftButtonStyle(tint: accent[1])).fixedSize()
                            .disabled(backend == nil)
                        if let backend {
                            Button { store.load(backend, force: true, withShot: showScreen) } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.borderless).help("Muat ulang info")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Battery + storage rings
                VStack(spacing: 18) {
                    ringBlock(progress: Double(d?.batteryLevel ?? 0) / 100,
                              label: d?.batteryLevel.map { "\($0)%" } ?? "–",
                              color: (d?.batteryLevel ?? 100) < 20 ? .red : Theme.live,
                              title: "Baterai",
                              lines: [d?.batteryState, d?.batteryHealth.map { "Kondisi \($0)" }, d?.batteryCycles.map { "\($0) siklus" }].compactMap { $0 })
                    ringBlock(progress: storageFraction, label: "\(Int(storageFraction * 100))%", color: accent[1],
                              title: "Penyimpanan",
                              lines: storageLines)
                }
                .frame(width: 230)
            }
        }
        .task(id: id) { if let backend { store.load(backend, withShot: showScreen) } }
    }

    private var storageFraction: Double {
        guard let t = d?.storageTotal, let u = d?.storageUsed, t > 0 else { return 0 }
        return Double(u) / Double(t)
    }
    private var storageLines: [String] {
        guard let t = d?.storageTotal, let u = d?.storageUsed else { return [] }
        return ["\(Fmt.bytes(max(0, t - u))) tersedia", "dari \(Fmt.bytes(t))"]
    }

    private func specCell(_ r: SpecRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(r.label.uppercased()).font(.system(size: 9.5, weight: .semibold)).kerning(0.6).foregroundStyle(.tertiary)
            Text(r.value).font(.callout).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ringBlock(progress: Double, label: String, color: Color, title: String, lines: [String]) -> some View {
        HStack(spacing: 12) {
            Ring(progress: progress, label: label, color: color).scaleEffect(0.85).frame(width: 68, height: 68)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                ForEach(lines, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
    }
}
