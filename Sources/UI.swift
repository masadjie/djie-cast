import SwiftUI
import AppKit

// MARK: - Theme

enum Theme {
    static let android = [Color(red: 0.20, green: 0.80, blue: 0.50), Color(red: 0.04, green: 0.55, blue: 0.45)]
    static let ios = [Color(red: 0.30, green: 0.50, blue: 1.00), Color(red: 0.50, green: 0.30, blue: 0.95)]
    static let mirroring = [Color(red: 0.65, green: 0.35, blue: 0.95), Color(red: 0.90, green: 0.35, blue: 0.70)]
    static let airplay = [Color(red: 0.10, green: 0.70, blue: 0.85), Color(red: 0.20, green: 0.45, blue: 0.95)]
    static let files = [Color(red: 1.00, green: 0.66, blue: 0.20), Color(red: 0.93, green: 0.42, blue: 0.15)]
    static let donate = [Color(red: 1.00, green: 0.35, blue: 0.45), Color(red: 0.85, green: 0.20, blue: 0.55)]
    static let live = Color(red: 0.15, green: 0.78, blue: 0.40)

    static func gradient(_ c: [Color]) -> LinearGradient {
        LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Debug hooks (only via environment variables; used for UI snapshots)

enum Demo {
    static let env = ProcessInfo.processInfo.environment
    static var enabled: Bool { env["DJIE_DEMO"] != nil }
    static var startPage: String? { env["DJIE_PAGE"] }
    static var snapshotPath: String? { env["DJIE_SNAPSHOT"] }

    /// Sample specs for screenshots (demo devices are not real phones).
    static func androidDetail(_ serial: String) -> DeviceDetail {
        let pixel = serial.contains(":")
        var d = DeviceDetail()
        d.title = pixel ? "Pixel 8 Pro" : "Galaxy S24 Ultra"
        d.subtitle = pixel ? "Google · GC3VE" : "Samsung · SM-S928B"
        d.storagePill = pixel ? "128 GB" : "256 GB"
        d.specs = [
            SpecRow(label: "Versi Android", value: pixel ? "Android 16 (API 36)" : "Android 15 (API 35)"),
            SpecRow(label: "One UI / Build", value: pixel ? "BP2A.250605.031" : "One UI 7.0"),
            SpecRow(label: "Chipset", value: pixel ? "Google Tensor G3" : "Snapdragon 8 Gen 3"),
            SpecRow(label: "RAM", value: pixel ? "12 GB" : "12 GB"),
            SpecRow(label: "Layar", value: pixel ? "1344 × 2992 · 120 Hz" : "1440 × 3120 · 120 Hz"),
            SpecRow(label: "CPU", value: "8 core · arm64-v8a"),
            SpecRow(label: "Patch keamanan", value: "2026-10-01"),
            SpecRow(label: "Serial", value: serial),
        ]
        d.batteryLevel = pixel ? 64 : 82
        d.batteryState = pixel ? "Tidak mengisi" : "Mengisi daya (USB)"
        d.batteryHealth = "Baik"
        d.batteryCycles = pixel ? "214" : "318"
        d.storageTotal = pixel ? 128_000_000_000 : 256_000_000_000
        d.storageUsed = pixel ? 71_000_000_000 : 148_000_000_000
        return d
    }

    /// A drawn lock screen for demo phones.
    static func lockScreen(_ alt: Bool) -> NSImage {
        NSImage(size: NSSize(width: 540, height: 1170), flipped: true) { r in
            let g = NSGradient(colors: alt ? [NSColor(red: 0.05, green: 0.45, blue: 0.55, alpha: 1), NSColor(red: 0.12, green: 0.16, blue: 0.40, alpha: 1)]
                                           : [NSColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1), NSColor(red: 0.62, green: 0.30, blue: 0.85, alpha: 1)])!
            g.draw(in: r, angle: 90)
            let style = NSMutableParagraphStyle(); style.alignment = .center
            ("14:05" as NSString).draw(in: NSRect(x: 0, y: 190, width: 540, height: 170),
                withAttributes: [.font: NSFont.systemFont(ofSize: 132, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: style])
            ("Senin, 9 November" as NSString).draw(in: NSRect(x: 0, y: 370, width: 540, height: 50),
                withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.85), .paragraphStyle: style])
            let colors: [NSColor] = [.systemOrange, .systemRed, .systemGreen, .systemBlue, .systemPink, .systemTeal, .systemYellow, .systemIndigo]
            for i in 0..<8 {
                let x = 70 + CGFloat(i % 4) * 110, y = 820 + CGFloat(i / 4) * 120
                colors[i].withAlphaComponent(0.9).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 80, height: 80), xRadius: 22, yRadius: 22).fill()
            }
            NSColor.white.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: NSRect(x: 60, y: 1070, width: 420, height: 60), xRadius: 30, yRadius: 30).fill()
            return true
        }
    }

    /// Saves the key window (incl. toolbar) to a PNG and quits.
    @MainActor static func snapshotIfRequested() {
        guard let path = snapshotPath else { return }
        if env["DJIE_APPEARANCE"] == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
        if env["DJIE_APPEARANCE"] == "dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if let size = env["DJIE_WINDOW"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSApp.windows.first(where: { $0.isVisible })?.setContentSize(NSSize(width: size[0], height: size[1]))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard let win = NSApp.windows.first(where: { $0.isVisible }),
                  let view = win.contentView?.superview ?? win.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}

// MARK: - Building blocks

struct IconBadge: View {
    let icon: String
    let colors: [Color]
    var size: CGFloat = 40

    var body: some View {
        // Small (sidebar) badges follow macOS Settings: solid tile, white glyph.
        // Larger badges are tinted so content, not chrome, carries the colour.
        let solid = size <= 28
        let tone = colors.count > 1 ? colors[1] : colors[0]
        Image(systemName: icon)
            .font(.system(size: size * (solid ? 0.5 : 0.44), weight: .semibold))
            .foregroundStyle(solid ? Color.white : tone)
            .frame(width: size, height: size)
            .background(solid ? AnyShapeStyle(tone) : AnyShapeStyle(tone.opacity(0.13)),
                        in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct PageHeader<Trailing: View>: View {
    let icon: String
    let colors: [Color]
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconBadge(icon: icon, colors: colors, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 26, weight: .bold)).kerning(-0.3)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(icon: String, colors: [Color], title: String, subtitle: String) {
        self.init(icon: icon, colors: colors, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }
}

/// Card surface used everywhere.
struct Panel<Content: View>: View {
    var highlight: Color? = nil
    var padding: CGFloat = 16
    /// Stretch to the row's height. Only for cards side by side in an HStack/grid —
    /// in a non-scrolling stack this would ask for infinite height and blank the window.
    var fill = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(highlight?.opacity(0.7) ?? Color.primary.opacity(0.09), lineWidth: highlight == nil ? 1 : 1.5)
            )
    }
}

struct Pill: View {
    let text: String
    var icon: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.13), in: Capsule())
    }
}

struct LiveBadge: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.live)
                .frame(width: 7, height: 7)
                .shadow(color: Theme.live, radius: on ? 4 : 0)
                .opacity(on ? 1 : 0.45)
            Text("LIVE").font(.caption2.weight(.heavy)).kerning(1)
        }
        .foregroundStyle(Theme.live)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.live.opacity(0.13), in: Capsule())
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { on = true } }
    }
}

/// Counter shown in page headers, e.g. "2 perangkat terhubung".
struct StatusPill: View {
    let count: Int
    let noun: String
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(count > 0 ? Theme.live : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
            Text(count > 0 ? "\(count) \(noun) terhubung" : "Belum ada \(noun)")
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let steps: [String]

    var body: some View {
        Panel(padding: 28) {
            HStack(alignment: .center, spacing: 28) {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.04)).frame(width: 110, height: 110)
                    Circle().strokeBorder(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: 140, height: 140)
                    Image(systemName: icon).font(.system(size: 42, weight: .light)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.title3.weight(.semibold))
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)")
                                .font(.caption.weight(.bold))
                                .frame(width: 20, height: 20)
                                .background(Color.accentColor.opacity(0.15), in: Circle())
                                .foregroundStyle(Color.accentColor)
                            Text(s).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Primary call-to-action button with a gradient fill.
struct GradientButtonStyle: ButtonStyle {
    var colors: [Color]
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(colors.count > 1 ? colors[1] : colors[0], in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Secondary button: subtle tinted surface.
struct SoftButtonStyle: ButtonStyle {
    var tint: Color = .primary
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

/// Primary action: solid ink (black in light, white in dark) — calm and confident.
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .padding(.vertical, 10).padding(.horizontal, 16)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.vertical, 10).padding(.horizontal, 16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.3 : 0.14)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}


/// Lays children out left to right and wraps to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { y += line + lineSpacing; x = 0; line = 0 }
            x += sz.width + spacing; line = max(line, sz.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        // vertically centre items within their line
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        var rowW: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if rowW > 0 && rowW + sz.width > bounds.width { rows.append([]); rowW = 0 }
            rows[rows.count - 1].append((v, sz)); rowW += sz.width + spacing
        }
        for row in rows {
            line = row.map(\.1.height).max() ?? 0
            x = bounds.minX
            for (v, sz) in row {
                v.place(at: CGPoint(x: x, y: y + (line - sz.height) / 2), proposal: ProposedViewSize(sz))
                x += sz.width + spacing
            }
            y += line + lineSpacing
        }
    }
}

/// Reports a view's width so a layout can switch between wide and compact arrangements.
struct WidthReader: ViewModifier {
    @Binding var width: CGFloat
    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear
                .onAppear { width = g.size.width }
                .onChange(of: g.size.width) { _, w in width = w }
        })
    }
}
extension View { func readWidth(_ w: Binding<CGFloat>) -> some View { modifier(WidthReader(width: w)) } }
