import SwiftUI

enum Theme {
    static let void = Color(red: 0.027, green: 0.012, blue: 0.059)
    static let deep = Color(red: 0.086, green: 0.039, blue: 0.157)
    static let dusk = Color(red: 0.180, green: 0.043, blue: 0.137)
    static let purple = Color(red: 0.545, green: 0.302, blue: 0.957)
    static let magenta = Color(red: 0.902, green: 0.278, blue: 0.659)
    static let ember = Color(red: 1.0, green: 0.380, blue: 0.333)
    static let rose = Color(red: 1.0, green: 0.553, blue: 0.761)
    static let lavender = Color(red: 0.80, green: 0.74, blue: 1.0)
    static let satellite = Color(red: 0.62, green: 0.80, blue: 1.0)
    static let station = Color(red: 1.0, green: 0.80, blue: 0.48)
    static let starlink = Color(red: 1.0, green: 0.45, blue: 0.86)

    /// Text and hairlines on glass and sheets: white in dark mode, deep plum in light mode.
    /// The sky itself always stays dark, so the overlay keeps using fixed colours.
    static let ink = Color(UIColor { $0.userInterfaceStyle == .dark ? .white : UIColor(red: 0.17, green: 0.07, blue: 0.25, alpha: 1) })
    /// Small caps labels and section headers: soft rose in dark mode, deeper magenta on light panels.
    static let accentInk = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1.0, green: 0.553, blue: 0.761, alpha: 1)
        : UIColor(red: 0.76, green: 0.16, blue: 0.5, alpha: 1) })
    static let sheetBase = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.027, green: 0.012, blue: 0.059, alpha: 1)
        : UIColor(red: 0.97, green: 0.94, blue: 0.99, alpha: 1) })

    static let nebula = LinearGradient(colors: [ember, magenta, purple], startPoint: .leading, endPoint: .trailing)
    static let rim = LinearGradient(colors: [rose.opacity(0.7), purple.opacity(0.25), .clear, magenta.opacity(0.3)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 12) -> some View {
        shadow(color: color.opacity(0.7), radius: radius / 2)
            .shadow(color: color.opacity(0.35), radius: radius)
    }

    /// Liquid Glass panel with the app's nebula rim light.
    func spacePanel(cornerRadius: CGFloat = 28, tint: Color = Theme.purple) -> some View {
        self
            .glassEffect(.regular.tint(tint.opacity(0.16)), in: .rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.rim, lineWidth: 1))
    }
}

/// Deep-space gradient with nebula glows; used behind the virtual sky and in sheets.
/// `adaptive` backdrops (sheets) switch to a pale dawn version in light mode; the sky never does.
struct SpaceBackdrop: View {
    var dust: Double = 0.7
    var adaptive = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if adaptive && scheme == .light {
            ZStack {
                LinearGradient(colors: [Color(red: 0.98, green: 0.95, blue: 1.0), Color(red: 0.96, green: 0.91, blue: 0.99), Color(red: 1.0, green: 0.91, blue: 0.93)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.purple.opacity(0.2), .clear], center: UnitPoint(x: 0.15, y: 0.2), startRadius: 0, endRadius: 420)
                RadialGradient(colors: [Theme.magenta.opacity(0.14), .clear], center: UnitPoint(x: 0.9, y: 0.55), startRadius: 0, endRadius: 360)
                RadialGradient(colors: [Theme.ember.opacity(0.14), .clear], center: UnitPoint(x: 0.45, y: 1.05), startRadius: 0, endRadius: 460)
            }
        } else {
            darkBody
        }
    }

    private var darkBody: some View {
        ZStack {
            LinearGradient(colors: [Theme.void, Theme.deep, Theme.dusk], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.purple.opacity(0.38), .clear], center: UnitPoint(x: 0.15, y: 0.2), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Theme.magenta.opacity(0.26), .clear], center: UnitPoint(x: 0.9, y: 0.55), startRadius: 0, endRadius: 360)
            RadialGradient(colors: [Theme.ember.opacity(0.22), .clear], center: UnitPoint(x: 0.45, y: 1.05), startRadius: 0, endRadius: 460)
            StarDust().opacity(dust)
        }
    }
}

/// Seeded, static speckle of faint stars so backdrops never look flat.
struct StarDust: View {
    var count = 260

    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x5EED_CAFE
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53)
            }
            for _ in 0..<count {
                let p = CGPoint(x: next() * size.width, y: next() * size.height)
                let r = 0.3 + pow(next(), 3) * 1.4
                let a = 0.25 + next() * 0.6
                let tint: Color = next() > 0.8 ? Theme.rose : .white
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(tint.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Theme wash laid over the live camera feed.
struct CameraTint: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.magenta.opacity(0.18), .clear, Theme.purple.opacity(0.28)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.clear, Theme.void.opacity(0.65)], center: .center, startRadius: 180, endRadius: 560)
        }
        .allowsHitTesting(false)
    }
}
