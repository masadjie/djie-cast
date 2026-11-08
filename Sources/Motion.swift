import SwiftUI
import AppKit

// MARK: - Canvas colour (cool paper in light, deep ink in dark) — cards sit on top of it

extension Theme {
    static let canvas = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.075, green: 0.078, blue: 0.11, alpha: 1)
            : NSColor(red: 0.953, green: 0.957, blue: 0.976, alpha: 1)
    })
}

// MARK: - Staggered entrance

private struct AppearIn: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                if Demo.snapshotPath != nil || reduceMotion { shown = true; return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Fades and lifts the view in shortly after it appears.
    func appearIn(_ delay: Double = 0) -> some View { modifier(AppearIn(delay: delay)) }
}

// MARK: - Live dot that breathes

struct PulseDot: View {
    var color: Color = Theme.live
    var active = true
    @State private var pulse = false

    var body: some View {
        ZStack {
            if active {
                Circle().fill(color.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 2.4 : 1)
                    .opacity(pulse ? 0 : 1)
            }
            Circle().fill(active ? color : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            guard active else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

// MARK: - Animated cast illustration (phone → Mac, cursor taps, both screens react)

/// One 7-second loop: cursor glides to an app, taps, the app opens on the Mac
/// mirror and on the phone at the same moment, then closes again.
struct CastIllustration: View {
    var deviceName = "Galaxy S24 Ultra"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || Demo.snapshotPath != nil)) { ctx in
            let t = (reduceMotion || Demo.snapshotPath != nil)
                ? 0.5 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7
            GeometryReader { geo in
                let W = geo.size.width, H = geo.size.height
                ZStack(alignment: .topLeading) {
                    macWindow(t: t, size: CGSize(width: W * 0.82, height: H * 0.86))
                        .offset(x: W * 0.18)
                    waves(t: t)
                        .frame(width: W * 0.13, height: W * 0.13)
                        .offset(x: W * 0.215, y: H * 0.36)
                    phone(t: t, width: W * 0.25)
                        .offset(x: 0, y: H - W * 0.25 * 19.2 / 9)
                }
            }
        }
        .aspectRatio(6 / 5, contentMode: .fit)
        .accessibilityLabel("Animasi: layar HP tampil di jendela Mac dan dikontrol dengan mouse")
    }

    // MARK: Pieces

    private func macWindow(t: Double, size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) {
                    Circle().fill($0).frame(width: 8, height: 8)
                }
                Text("\(deviceName) — Djie Cast")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(1)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Color(red: 0.15, green: 0.16, blue: 0.22))
            ZStack {
                RadialGradient(colors: [Color(red: 0.14, green: 0.15, blue: 0.25), Color(red: 0.07, green: 0.075, blue: 0.12)],
                               center: .init(x: 0.5, y: 0.4), startRadius: 10, endRadius: size.width * 0.7)
                MiniScreen(t: t, showsCursor: true)
                    .frame(height: (size.height - 24) * 0.88)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.25)))
        .shadow(color: Color(red: 0.07, green: 0.08, blue: 0.17).opacity(0.35), radius: 26, y: 18)
    }

    private func phone(t: Double, width: CGFloat) -> some View {
        MiniScreen(t: t, showsCursor: false)
            .padding(width * 0.035)
            .background(Color(red: 0.05, green: 0.055, blue: 0.09), in: RoundedRectangle(cornerRadius: width * 0.14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: width * 0.14, style: .continuous).strokeBorder(Color(white: 0.3), lineWidth: 1))
            .frame(width: width)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
    }

    private func waves(t: Double) -> some View {
        ZStack {
            ForEach(0..<3) { i in
                let phase = (t * 7 / 2.4 - Double(i) * 0.12).truncatingRemainder(dividingBy: 1)
                let p = phase < 0 ? phase + 1 : phase
                ArcShape(radius: 0.35 + Double(i) * 0.3)
                    .stroke(Color(red: 0.03, green: 0.6, blue: 0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .opacity(p < 0.3 ? p / 0.3 : max(0, 1 - (p - 0.3) / 0.7))
            }
        }
    }
}

/// Quarter arc anchored bottom-left, radius as a fraction of the frame.
private struct ArcShape: Shape {
    let radius: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: r.minX, y: r.maxY), radius: r.width * radius,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        return p
    }
}

/// A tiny Android home screen whose state is a pure function of `t` (0…1).
private struct MiniScreen: View {
    let t: Double
    let showsCursor: Bool

    private func ease(_ x: Double) -> Double { x < 0 ? 0 : x > 1 ? 1 : x * x * (3 - 2 * x) }
    private func seg(_ a: Double, _ b: Double) -> Double { ease((t - a) / (b - a)) }

    /// 0 = closed, 1 = open
    private var appOpen: Double { t < 0.6 ? seg(0.34, 0.44) : 1 - seg(0.82, 0.92) }
    /// Tap ripple 0…1
    private var tap: Double { t >= 0.30 && t <= 0.42 ? (t - 0.30) / 0.12 : 0 }

    private var cursor: CGPoint {
        let start = CGPoint(x: 0.95, y: 1.02), icon = CGPoint(x: 0.385, y: 0.80), wander = CGPoint(x: 0.7, y: 0.38)
        func lerp(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k) }
        if t < 0.26 { return lerp(start, icon, seg(0.0, 0.26)) }
        if t < 0.38 { return icon }
        if t < 0.62 { return lerp(icon, wander, seg(0.38, 0.62)) }
        return lerp(wander, start, seg(0.62, 1.0))
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let s = w * 0.17, gap = w * 0.06
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.23, green: 0.18, blue: 0.82), Color(red: 0.43, green: 0.23, blue: 0.85), Color(red: 0.05, green: 0.62, blue: 0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: h * 0.012) {
                    HStack {
                        Text("14:05"); Spacer(); Text("5G")
                    }
                    .font(.system(size: h * 0.032, weight: .semibold))
                    .padding(.bottom, h * 0.05)
                    Text("14:05").font(.system(size: h * 0.12, weight: .bold)).kerning(-1)
                    Text("Sabtu, 8 November").font(.system(size: h * 0.034)).opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, w * 0.07)
                .padding(.top, h * 0.04)

                // App grid (2 × 4)
                let colors: [Color] = [.yellow, .pink, .green, .white, .orange, .cyan, .purple, Color(white: 0.95)]
                ForEach(0..<8, id: \.self) { i in
                    let col = Double(i % 4), row = Double(i / 4)
                    RoundedRectangle(cornerRadius: s * 0.3, style: .continuous)
                        .fill(colors[i].opacity(0.92))
                        .overlay {
                            if i == 5 && tap > 0 {
                                RoundedRectangle(cornerRadius: s * 0.3, style: .continuous)
                                    .fill(.white.opacity(0.6 * (1 - tap)))
                                    .scaleEffect(1 + tap * 0.35)
                            }
                        }
                        .frame(width: s, height: s)
                        .offset(x: w * 0.07 + col * (s + gap), y: h * 0.84 - (2 - row) * s - (1 - row) * gap)
                }
                // Dock
                Capsule().fill(.white.opacity(0.2))
                    .frame(width: w * 0.86, height: h * 0.075)
                    .offset(x: w * 0.07, y: h * 0.885)

                // Opened "Galeri" app slides up
                VStack(alignment: .leading, spacing: h * 0.025) {
                    Text("Galeri").font(.system(size: h * 0.055, weight: .bold)).foregroundStyle(Color(red: 0.07, green: 0.08, blue: 0.17))
                        .padding(.top, h * 0.07)
                    let thumbs: [Color] = [Color(red: 1, green: 0.7, blue: 0.64), Color(red: 0.65, green: 0.71, blue: 0.99), Color(red: 0.53, green: 0.94, blue: 0.67),
                                           Color(red: 0.99, green: 0.9, blue: 0.54), Color(red: 0.58, green: 0.77, blue: 0.99), Color(red: 0.94, green: 0.67, blue: 0.99)]
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: w * 0.016), count: 3), spacing: w * 0.016) {
                        ForEach(0..<15, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(thumbs[i % 6]).aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                .padding(.horizontal, w * 0.06)
                .frame(width: w, height: h, alignment: .topLeading)
                .background(Color(red: 0.965, green: 0.965, blue: 0.985))
                .offset(y: h * (1 - appOpen) * 1.02)

                if showsCursor {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: max(12, w * 0.12), weight: .regular))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
                        .scaleEffect(t > 0.3 && t < 0.34 ? 0.85 : 1)
                        .offset(x: w * cursor.x - 3, y: h * cursor.y - 3)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: w * 0.09, style: .continuous))
        }
        .aspectRatio(9 / 19.5, contentMode: .fit)
    }
}
