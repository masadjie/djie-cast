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

    /// Saves the key window (incl. toolbar) to a PNG and quits.
    @MainActor static func snapshotIfRequested() {
        guard let path = snapshotPath else { return }
        if env["DJIE_APPEARANCE"] == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
        if env["DJIE_APPEARANCE"] == "dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
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
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.gradient(colors), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(.white.opacity(0.18)))
            .shadow(color: colors.first!.opacity(0.35), radius: 6, y: 3)
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
                Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
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
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(highlight?.opacity(0.7) ?? Color.primary.opacity(0.08), lineWidth: highlight == nil ? 1 : 1.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
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
            .background(Theme.gradient(colors), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}
