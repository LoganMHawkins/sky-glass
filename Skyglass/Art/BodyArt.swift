import SwiftUI

/// What an object looks like, shared by the sky overlay and the glance/detail glyphs.
enum ObjectArt {
    case planet(Body, ringTilt: Double)
    case moon(illumination: Double, waxing: Bool)
    case sun
    case star(Color)
    case satellite(SatDesign)
}

/// Hand-drawn vector artwork for the Sun, Moon, planets and stars. Everything is drawn in a
/// GraphicsContext so the same code serves a 10 pt dot on the sky and a 90 pt hero image.
enum BodyArt {
    // MARK: Helpers

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// Ellipse centred at (x, y) in units of the radius from `c`, optionally rotated (radians).
    private static func blob(_ c: CGPoint, _ r: CGFloat, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, rotation: CGFloat = 0) -> Path {
        let center = CGPoint(x: c.x + x * r, y: c.y + y * r)
        let p = Path(ellipseIn: CGRect(x: center.x - w * r / 2, y: center.y - h * r / 2, width: w * r, height: h * r))
        guard rotation != 0 else { return p }
        return p.applying(CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: rotation))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
    }

    /// A horizontal latitude band between two heights (in units of the radius, −1 = top) with soft edges.
    private static func band(_ g: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ from: CGFloat, _ to: CGFloat, _ color: Color) {
        let top = c.y + from * r, bottom = c.y + to * r
        g.fill(Path(CGRect(x: c.x - r, y: top, width: r * 2, height: bottom - top)),
               with: .linearGradient(Gradient(stops: [.init(color: color.opacity(0), location: 0), .init(color: color, location: 0.3),
                                                      .init(color: color, location: 0.7), .init(color: color.opacity(0), location: 1)]),
                                     startPoint: CGPoint(x: c.x, y: top), endPoint: CGPoint(x: c.x, y: bottom)))
    }

    /// Limb darkening and a soft highlight, lit from the upper left.
    private static func shade(_ g: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, strength: Double = 1) {
        let light = CGPoint(x: c.x - r * 0.32, y: c.y - r * 0.32)
        g.fill(circle(c, r), with: .radialGradient(Gradient(stops: [.init(color: .clear, location: 0),
                                                                    .init(color: .black.opacity(0.12 * strength), location: 0.5),
                                                                    .init(color: .black.opacity(0.62 * strength), location: 1)]),
                                                   center: light, startRadius: 0, endRadius: r * 1.5))
        g.fill(circle(c, r), with: .radialGradient(Gradient(colors: [.white.opacity(0.28 * strength), .white.opacity(0)]),
                                                   center: CGPoint(x: c.x - r * 0.4, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 0.65))
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color { Color(red: r, green: g, blue: b).opacity(a) }

    // MARK: Entry point

    /// Draws `art` centred on `c`. `r` is the globe radius for bodies, the core radius for stars,
    /// and the half-width for spacecraft.
    static func draw(_ art: ObjectArt, in ctx: inout GraphicsContext, at c: CGPoint, radius r: CGFloat,
                     opacity: Double = 1, angle: CGFloat = 0, detailed: Bool = false) {
        switch art {
        case .planet(let body, let tilt): drawPlanet(&ctx, body, c, r, ringTilt: tilt, opacity: opacity)
        case .moon(let k, let waxing): drawMoon(&ctx, c, r, illumination: k, waxing: waxing, opacity: opacity)
        case .sun: drawSun(&ctx, c, r, opacity: opacity)
        case .star(let color): drawStar(&ctx, c, r, color: color, opacity: opacity, spikes: detailed || r > 4.2, hero: detailed)
        case .satellite(let design): SatelliteArt.draw(design, in: &ctx, at: c, halfWidth: r, angle: angle, opacity: opacity, detailed: detailed)
        }
    }

    // MARK: Planets

    static func drawPlanet(_ ctx: inout GraphicsContext, _ body: Body, _ c: CGPoint, _ r: CGFloat, ringTilt: Double = 0, opacity: Double = 1) {
        ctx.drawLayer { l in
            l.opacity = opacity
            switch body {
            case .saturn: drawSaturn(&l, c, r, tilt: ringTilt)
            case .venus:
                l.fill(circle(c, r * 1.18), with: .radialGradient(Gradient(colors: [rgb(1, 0.93, 0.75, 0.55), .clear]),
                                                                    center: c, startRadius: r * 0.9, endRadius: r * 1.18))
                globe(&l, body, c, r)
            case .uranus, .neptune:
                l.fill(circle(c, r * 1.12), with: .radialGradient(Gradient(colors: [rgb(0.6, 0.85, 1, 0.4), .clear]),
                                                                    center: c, startRadius: r * 0.95, endRadius: r * 1.12))
                globe(&l, body, c, r)
            default:
                globe(&l, body, c, r)
            }
        }
    }

    private static func globe(_ l: inout GraphicsContext, _ body: Body, _ c: CGPoint, _ r: CGFloat) {
        l.drawLayer { g in
            g.clip(to: circle(c, r))
            switch body {
            case .mercury:
                g.fill(circle(c, r), with: .color(rgb(0.62, 0.59, 0.56)))
                g.fill(blob(c, r, -0.2, 0.25, 1.1, 0.7, rotation: 0.4), with: .color(rgb(0.5, 0.48, 0.46, 0.5)))
                let craters: [(CGFloat, CGFloat, CGFloat)] = [(-0.45, -0.35, 0.22), (0.3, -0.5, 0.16), (0.5, 0.2, 0.26), (-0.1, 0.55, 0.18),
                                                              (0.05, -0.05, 0.12), (-0.62, 0.25, 0.14), (0.25, 0.6, 0.1), (0.7, -0.25, 0.1),
                                                              (-0.25, -0.7, 0.1), (0.0, 0.3, 0.08)]
                for (x, y, s) in craters {
                    g.fill(blob(c, r, x, y, s, s), with: .color(rgb(0.4, 0.38, 0.36, 0.55)))
                    g.stroke(blob(c, r, x + 0.02, y + 0.02, s, s), with: .color(rgb(0.85, 0.83, 0.8, 0.45)), lineWidth: max(0.4, r * 0.025))
                }
            case .venus:
                g.fill(circle(c, r), with: .color(rgb(0.96, 0.9, 0.72)))
                for (y, a) in [(-0.55, 0.3), (-0.15, 0.4), (0.25, 0.35), (0.6, 0.3)] as [(CGFloat, Double)] {
                    g.fill(blob(c, r, 0.1, y, 2.2, 0.28, rotation: -0.18), with: .color(rgb(0.86, 0.74, 0.5, a)))
                }
                g.fill(blob(c, r, -0.3, 0.05, 0.9, 0.5, rotation: 0.6), with: .color(rgb(1, 0.97, 0.88, 0.45)))
            case .mars:
                g.fill(circle(c, r), with: .color(rgb(0.8, 0.4, 0.24)))
                g.fill(blob(c, r, 0.25, -0.2, 0.9, 0.6, rotation: 0.3), with: .color(rgb(0.9, 0.55, 0.36, 0.5)))
                g.fill(blob(c, r, -0.25, 0.12, 0.62, 0.3, rotation: -0.3), with: .color(rgb(0.48, 0.22, 0.14, 0.7)))
                g.fill(blob(c, r, 0.32, 0.05, 0.28, 0.42, rotation: 0.2), with: .color(rgb(0.5, 0.24, 0.15, 0.65)))
                g.fill(blob(c, r, 0.0, 0.48, 0.9, 0.18), with: .color(rgb(0.52, 0.25, 0.16, 0.55)))
                g.fill(blob(c, r, 0.05, -0.92, 0.8, 0.32), with: .color(rgb(0.98, 0.97, 0.98)))
                g.fill(blob(c, r, -0.05, 0.95, 0.4, 0.14), with: .color(rgb(0.95, 0.93, 0.95, 0.85)))
            case .jupiter:
                g.fill(circle(c, r), with: .color(rgb(0.93, 0.86, 0.74)))
                band(&g, c, r, -1.05, -0.72, rgb(0.62, 0.55, 0.48))
                band(&g, c, r, -0.62, -0.46, rgb(0.8, 0.66, 0.52, 0.8))
                band(&g, c, r, -0.36, -0.1, rgb(0.66, 0.43, 0.29))
                band(&g, c, r, 0.1, 0.34, rgb(0.7, 0.46, 0.31))
                band(&g, c, r, 0.46, 0.6, rgb(0.8, 0.66, 0.52, 0.8))
                band(&g, c, r, 0.72, 1.05, rgb(0.62, 0.55, 0.48))
                g.fill(blob(c, r, 0.3, 0.37, 0.44, 0.26), with: .color(rgb(0.97, 0.9, 0.82, 0.8)))
                g.fill(blob(c, r, 0.3, 0.37, 0.34, 0.19), with: .color(rgb(0.82, 0.4, 0.27)))
                g.fill(blob(c, r, -0.35, 0.52, 0.12, 0.07), with: .color(rgb(1, 0.98, 0.94, 0.8)))
            case .uranus:
                g.fill(circle(c, r), with: .color(rgb(0.64, 0.87, 0.91)))
                g.fill(circle(c, r), with: .radialGradient(Gradient(colors: [rgb(0.82, 0.96, 0.97, 0.7), .clear]),
                                                           center: CGPoint(x: c.x + r * 0.55, y: c.y - r * 0.1), startRadius: 0, endRadius: r * 0.9))
                band(&g, c, r, -0.35, -0.2, rgb(0.55, 0.8, 0.86, 0.5))
            case .neptune:
                g.fill(circle(c, r), with: .color(rgb(0.27, 0.45, 0.92)))
                band(&g, c, r, -0.5, -0.3, rgb(0.45, 0.62, 1, 0.45))
                band(&g, c, r, 0.05, 0.35, rgb(0.18, 0.32, 0.78, 0.8))
                g.fill(blob(c, r, -0.25, 0.18, 0.3, 0.17), with: .color(rgb(0.1, 0.17, 0.5)))
                g.fill(blob(c, r, -0.18, 0.36, 0.24, 0.05), with: .color(rgb(0.96, 0.98, 1, 0.85)))
                g.fill(blob(c, r, 0.35, -0.42, 0.2, 0.04), with: .color(rgb(0.96, 0.98, 1, 0.6)))
            default:
                g.fill(circle(c, r), with: .color(.gray))
            }
            shade(&g, c, r)
        }
    }

    private static func drawSaturn(_ l: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, tilt: Double) {
        // The rings' real opening angle, never quite edge-on so they stay visible.
        let ratio = CGFloat(max(0.09, abs(sin(tilt * Astro.deg))))
        let rot = CGAffineTransform(translationX: -c.x, y: -c.y)
            .concatenating(CGAffineTransform(rotationAngle: -0.2))
            .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
        func ring(_ inner: CGFloat, _ outer: CGFloat) -> Path {
            var p = Path(ellipseIn: CGRect(x: c.x - outer * r, y: c.y - outer * r * ratio, width: 2 * outer * r, height: 2 * outer * r * ratio))
            p.addPath(Path(ellipseIn: CGRect(x: c.x - inner * r, y: c.y - inner * r * ratio, width: 2 * inner * r, height: 2 * inner * r * ratio)))
            return p.applying(rot)
        }
        let rings: [(CGFloat, CGFloat, Color)] = [(1.24, 1.52, rgb(0.72, 0.64, 0.52, 0.4)),
                                                  (1.53, 1.95, rgb(0.94, 0.86, 0.68)),
                                                  (2.02, 2.27, rgb(0.84, 0.76, 0.6, 0.9))]
        func drawRings(_ g: inout GraphicsContext) {
            for (i, o, color) in rings { g.fill(ring(i, o), with: .color(color), style: FillStyle(eoFill: true)) }
        }

        drawRings(&l)
        l.drawLayer { g in
            g.clip(to: circle(c, r))
            g.fill(circle(c, r), with: .color(rgb(0.93, 0.83, 0.6)))
            band(&g, c, r, -1.05, -0.7, rgb(0.74, 0.68, 0.56))
            band(&g, c, r, -0.45, -0.25, rgb(0.86, 0.72, 0.5, 0.7))
            band(&g, c, r, -0.1, 0.08, rgb(0.84, 0.68, 0.46, 0.6))
            band(&g, c, r, 0.25, 0.42, rgb(0.86, 0.74, 0.54, 0.6))
            shade(&g, c, r)
        }
        // Near side of the rings passes in front of the globe.
        let nearSide = tilt >= 0 ? CGRect(x: c.x - 3 * r, y: c.y, width: 6 * r, height: 3 * r)
                                 : CGRect(x: c.x - 3 * r, y: c.y - 3 * r, width: 6 * r, height: 3 * r)
        l.drawLayer { f in
            f.clip(to: Path(nearSide).applying(rot))
            drawRings(&f)
        }
    }

    // MARK: Moon & Sun

    /// Lit region of the Moon: between the limb and an elliptical terminator.
    static func moonLitPath(center c: CGPoint, r: CGFloat, lit k: Double, waxing: Bool) -> Path {
        var p = Path()
        let steps = 28
        let side: CGFloat = waxing ? 1 : -1
        for i in 0...steps {
            let th = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            let pt = CGPoint(x: c.x + side * r * CGFloat(cos(th)), y: c.y + r * CGFloat(sin(th)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let th = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            p.addLine(to: CGPoint(x: c.x + side * r * CGFloat(cos(th) * (1 - 2 * k)), y: c.y + r * CGFloat(sin(th))))
        }
        p.closeSubpath()
        return p
    }

    static func drawMoon(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, illumination k: Double, waxing: Bool, opacity: Double = 1) {
        ctx.drawLayer { l in
            l.opacity = opacity
            l.drawLayer { g in
                g.clip(to: circle(c, r))
                g.fill(circle(c, r), with: .color(rgb(0.8, 0.79, 0.77)))
                // Maria, roughly where they sit on the near side (north up).
                let maria: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (-0.5, 0.0, 0.62, 0.95, 0.2),    // Oceanus Procellarum
                    (-0.25, -0.42, 0.55, 0.42, 0),   // Imbrium
                    (0.2, -0.36, 0.3, 0.28, 0),      // Serenitatis
                    (0.3, -0.05, 0.38, 0.32, 0.3),   // Tranquillitatis
                    (0.64, -0.22, 0.2, 0.18, 0),     // Crisium
                    (0.55, 0.18, 0.2, 0.3, 0),       // Fecunditatis
                    (0.33, 0.35, 0.18, 0.16, 0),     // Nectaris
                    (-0.17, 0.38, 0.3, 0.22, 0),     // Nubium
                    (-0.05, -0.72, 0.9, 0.12, 0),    // Frigoris
                ]
                for (x, y, w, h, rot) in maria {
                    g.fill(blob(c, r, x, y, w, h, rotation: rot), with: .color(rgb(0.55, 0.55, 0.56, 0.55)))
                }
                g.fill(blob(c, r, -0.12, 0.72, 0.09, 0.09), with: .color(.white.opacity(0.9)))           // Tycho
                g.fill(blob(c, r, -0.3, -0.12, 0.07, 0.07), with: .color(.white.opacity(0.7)))           // Copernicus
                for a in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 5) {
                    var ray = Path()
                    let t = CGPoint(x: c.x - 0.12 * r, y: c.y + 0.72 * r)
                    ray.move(to: t)
                    ray.addLine(to: CGPoint(x: t.x + CGFloat(cos(a)) * r * 0.45, y: t.y + CGFloat(sin(a)) * r * 0.45))
                    g.stroke(ray, with: .color(.white.opacity(0.18)), lineWidth: max(0.3, r * 0.025))
                }
                shade(&g, c, r, strength: 0.6)
                // Night side, with a faint earthshine
                let dark = moonLitPath(center: c, r: r * 1.01, lit: 1 - k, waxing: !waxing)
                g.fill(dark, with: .color(rgb(0.05, 0.03, 0.1, 0.86)))
            }
            l.stroke(circle(c, r), with: .color(.white.opacity(0.2)), lineWidth: max(0.5, r * 0.03))
        }
    }

    static func drawSun(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, opacity: Double = 1) {
        ctx.drawLayer { l in
            l.opacity = opacity
            l.fill(circle(c, r), with: .radialGradient(Gradient(stops: [.init(color: .white, location: 0),
                                                                        .init(color: rgb(1, 0.94, 0.7), location: 0.45),
                                                                        .init(color: rgb(1, 0.72, 0.32), location: 0.85),
                                                                        .init(color: rgb(0.95, 0.45, 0.2), location: 1)]),
                                                       center: c, startRadius: 0, endRadius: r))
            l.fill(blob(c, r, 0.3, 0.15, 0.12, 0.09), with: .color(rgb(0.55, 0.25, 0.1, 0.7)))
            l.fill(blob(c, r, 0.4, 0.22, 0.07, 0.06), with: .color(rgb(0.55, 0.25, 0.1, 0.6)))
            l.fill(blob(c, r, -0.35, -0.3, 0.08, 0.06), with: .color(rgb(0.6, 0.3, 0.12, 0.55)))
        }
    }

    // MARK: Stars

    static func drawStar(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, color: Color, opacity: Double = 1, spikes: Bool, hero: Bool = false) {
        ctx.drawLayer { l in
            l.opacity = opacity
            if r > 2.6 || hero {
                l.fill(circle(c, r * (hero ? 2.6 : 4)), with: .radialGradient(Gradient(colors: [color.opacity(hero ? 0.6 : 0.4), color.opacity(0)]),
                                                                              center: c, startRadius: 0, endRadius: r * (hero ? 2.6 : 4)))
            }
            if spikes {
                let length = r * (hero ? 2.4 : 4.5)
                for angle in [0.0, Double.pi / 2, hero ? Double.pi / 4 : -1, hero ? -Double.pi / 4 : -1] where angle >= -Double.pi / 2 {
                    let thick = max(0.8, r * (hero ? (abs(angle).truncatingRemainder(dividingBy: Double.pi / 2) == 0 ? 0.09 : 0.05) : 0.18))
                    let spike = Path(roundedRect: CGRect(x: c.x - length, y: c.y - thick / 2, width: length * 2, height: thick), cornerRadius: thick / 2)
                        .applying(CGAffineTransform(translationX: -c.x, y: -c.y)
                            .concatenating(CGAffineTransform(rotationAngle: angle))
                            .concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
                    l.fill(spike, with: .linearGradient(Gradient(stops: [.init(color: color.opacity(0), location: 0), .init(color: color.opacity(0.9), location: 0.45),
                                                                         .init(color: .white, location: 0.5), .init(color: color.opacity(0.9), location: 0.55),
                                                                         .init(color: color.opacity(0), location: 1)]),
                                                        startPoint: CGPoint(x: c.x - CGFloat(cos(angle)) * length, y: c.y - CGFloat(sin(angle)) * length),
                                                        endPoint: CGPoint(x: c.x + CGFloat(cos(angle)) * length, y: c.y + CGFloat(sin(angle)) * length)))
                }
            }
            l.fill(circle(c, r), with: .radialGradient(Gradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: hero ? 0.08 : 0.2),
                                                                        .init(color: color, location: hero ? 0.55 : 0.75), .init(color: color, location: 1)]),
                                                       center: c, startRadius: 0, endRadius: r))
        }
    }
}

/// Star colours from spectral class: class → effective temperature → blackbody colour.
enum StarColor {
    private static let anchors: [(Double, Double)] = [
        (5, 42000), (9.5, 31900), (10, 30000), (15, 15200), (20, 9790), (25, 8180), (30, 7300), (35, 6650),
        (40, 5940), (45, 5560), (50, 5150), (55, 4410), (60, 3840), (65, 3170), (69, 2600),
    ]

    /// Approximate surface temperature in kelvin for a spectral type like "K1.5III".
    static func temperature(_ spectral: String) -> Double {
        let classes: [Character: Double] = ["O": 0, "B": 1, "A": 2, "F": 3, "G": 4, "K": 5, "M": 6]
        guard let first = spectral.first, let base = classes[first] else { return 9000 }
        let digits = spectral.dropFirst().prefix { $0.isNumber || $0 == "." }
        let code = base * 10 + (Double(digits) ?? 0)
        if code <= anchors[0].0 { return anchors[0].1 }
        for i in 1..<anchors.count where code <= anchors[i].0 {
            let (c0, t0) = anchors[i - 1], (c1, t1) = anchors[i]
            let f = (code - c0) / (c1 - c0)
            return exp(log(t0) + f * (log(t1) - log(t0)))
        }
        return anchors.last!.1
    }

    /// Blackbody colour (Tanner Helland's fit).
    static func color(kelvin: Double) -> Color {
        let t = kelvin / 100
        let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        // Exaggerated a little (gamma 1.7): true blackbody colours look nearly white on screen.
        func ch(_ v: Double) -> Double { pow(min(255, max(0, v)) / 255, 1.7) * 0.94 + 0.06 }
        return Color(red: ch(r), green: ch(g), blue: ch(b))
    }

    static func color(_ spectral: String) -> Color { color(kelvin: temperature(spectral)) }

    static func name(_ spectral: String) -> String {
        switch temperature(spectral) {
        case 25000...: "Blue"
        case 10000..<25000: "Blue-white"
        case 7500..<10000: "White"
        case 6000..<7500: "Yellow-white"
        case 5200..<6000: "Yellow"
        case 3700..<5200: "Orange"
        default: "Red-orange"
        }
    }
}
