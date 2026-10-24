import SwiftUI

/// Which drawing a spacecraft gets: a few landmark vehicles have their own, Starlink is drawn by
/// hardware generation, and everything else falls into a consistent family style.
enum SatDesign: CaseIterable {
    case generic, rocketBody, capsule
    case iss, tiangong, hubble
    case starlinkV09, starlinkV1, starlinkV15, starlinkV2Mini, starlinkDTC

    var title: String {
        switch self {
        case .generic: "Satellite"
        case .rocketBody: "Spent rocket stage"
        case .capsule: "Crew or cargo spacecraft"
        case .iss: "International Space Station"
        case .tiangong: "Tiangong space station"
        case .hubble: "Hubble Space Telescope"
        case .starlinkV09: "Starlink v0.9"
        case .starlinkV1: "Starlink v1.0"
        case .starlinkV15: "Starlink v1.5"
        case .starlinkV2Mini: "Starlink V2 Mini"
        case .starlinkDTC: "Starlink Direct to Cell"
        }
    }

    var isStarlink: Bool { [.starlinkV09, .starlinkV1, .starlinkV15, .starlinkV2Mini, .starlinkDTC].contains(self) }

    /// One line about the hardware, shown in the detail sheet.
    var note: String? {
        switch self {
        case .starlinkV09: "The 2019 test batch: a flat ~230 kg panel with a single solar array."
        case .starlinkV1: "Flat-packed ~260 kg satellite with one solar array, stacked 60 to a rocket."
        case .starlinkV15: "Like v1.0 but with laser links that pass data between satellites in orbit."
        case .starlinkV2Mini: "A larger ~800 kg satellite with two solar arrays and about four times the capacity."
        case .starlinkDTC: "Carries a large phased-array antenna that talks directly to ordinary phones."
        default: nil
        }
    }

    /// Half-width on the sky overlay, in points.
    var overlayHalfWidth: CGFloat {
        switch self {
        case .iss: 15
        case .tiangong: 12
        case .hubble: 9
        case .generic, .capsule: 7
        case .rocketBody: 6
        case .starlinkV2Mini, .starlinkDTC: 6
        default: 5.5
        }
    }

    /// Stations fly with their trusses across the direction of travel.
    var flightAngleOffset: CGFloat { self == .iss || self == .tiangong ? .pi / 2 : 0 }

    static func classify(norad: Int, name: String, isStarlinkGroup: Bool) -> SatDesign {
        switch norad {
        case 25544: return .iss
        case 48274: return .tiangong
        case 20580: return .hubble
        default: break
        }
        let n = name.uppercased()
        if isStarlinkGroup || n.hasPrefix("STARLINK") {
            // Generations are estimated from catalogue number, which tracks launch date.
            if n.contains("DTC") { return .starlinkDTC }
            if norad >= 55600 { return .starlinkV2Mini }   // Group 6 onward, Feb 2023
            if norad >= 49400 { return .starlinkV15 }      // Group 2-1 onward, Sep 2021
            if norad < 44700 { return .starlinkV09 }       // May 2019 test launch
            return .starlinkV1
        }
        if n.contains("R/B") { return .rocketBody }
        let vehicles = ["SOYUZ", "PROGRESS", "DRAGON", "CREW DRAGON", "CYGNUS", "SHENZHOU", "TIANZHOU", "HTV", "STARLINER"]
        if vehicles.contains(where: { n.hasPrefix($0) }) { return .capsule }
        return .generic
    }
}

extension Satellite {
    var design: SatDesign { SatelliteArt.design(for: self) }
}

/// Vector drawings for spacecraft, built once in unit coordinates (x and y in −1…1) and
/// transformed per frame, so hundreds of Starlinks stay cheap to draw.
enum SatelliteArt {
    struct Part {
        let path: Path
        let color: Color
    }

    private static var designCache: [Int: SatDesign] = [:]

    /// Cached per NORAD ID; only touched from the main thread.
    static func design(for sat: Satellite) -> SatDesign {
        if let d = designCache[sat.norad] { return d }
        let d = SatDesign.classify(norad: sat.norad, name: sat.name, isStarlinkGroup: sat.group == .starlink)
        designCache[sat.norad] = d
        return d
    }

    private static let artwork: [SatDesign: (parts: [Part], details: [Part])] = {
        var out: [SatDesign: (parts: [Part], details: [Part])] = [:]
        for d in SatDesign.allCases { out[d] = build(d) }
        return out
    }()

    /// Below `silhouetteBelow` points the craft is drawn as a single-colour silhouette so it reads on the sky.
    static let silhouetteBelow: CGFloat = 8

    static func draw(_ design: SatDesign, in ctx: inout GraphicsContext, at c: CGPoint, halfWidth s: CGFloat,
                     angle: CGFloat, opacity: Double, detailed: Bool, silhouette: Color? = nil) {
        guard let art = artwork[design] else { return }
        let t = CGAffineTransform(scaleX: s, y: s)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
        if let silhouette, s < silhouetteBelow, !detailed {
            for part in art.parts { ctx.fill(part.path.applying(t), with: .color(silhouette.opacity(opacity))) }
            return
        }
        for part in art.parts { ctx.fill(part.path.applying(t), with: .color(part.color.opacity(opacity))) }
        if detailed || s >= 14 {
            for part in art.details { ctx.fill(part.path.applying(t), with: .color(part.color.opacity(opacity))) }
        }
    }

    // MARK: Building

    private static let foil = Color(red: 0.88, green: 0.7, blue: 0.34)
    private static let panel = Color(red: 0.2, green: 0.3, blue: 0.64)
    private static let panelLine = Color(red: 0.48, green: 0.62, blue: 1.0).opacity(0.55)
    private static let metal = Color(red: 0.78, green: 0.8, blue: 0.85)
    private static let white = Color(red: 0.94, green: 0.94, blue: 0.93)
    private static let dark = Color(red: 0.24, green: 0.25, blue: 0.3)
    private static let issArray = Color(red: 0.88, green: 0.62, blue: 0.3)
    private static let tiangongArray = Color(red: 0.34, green: 0.3, blue: 0.66)
    private static let laser = Color(red: 0.86, green: 0.9, blue: 1.0)

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, corner: CGFloat = 0) -> Path {
        corner > 0 ? Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: corner) : Path(CGRect(x: x, y: y, width: w, height: h))
    }

    private static func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
    }

    private static func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    /// Cell lines across a solar array, along its long side.
    private static func cells(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, count: Int = 4, color: Color = panelLine) -> [Part] {
        (1..<count).map { i in
            let f = CGFloat(i) / CGFloat(count)
            let line = w >= h ? rect(x + w * f - 0.008, y, 0.016, h) : rect(x, y + h * f - 0.008, w, 0.016)
            return Part(path: line, color: color)
        }
    }

    private static func build(_ d: SatDesign) -> (parts: [Part], details: [Part]) {
        switch d {
        case .generic:
            return ([Part(path: rect(-0.75, -0.025, 1.5, 0.05), color: metal),
                     Part(path: rect(-1, -0.2, 0.68, 0.4, corner: 0.03), color: panel),
                     Part(path: rect(0.32, -0.2, 0.68, 0.4, corner: 0.03), color: panel),
                     Part(path: rect(-0.25, -0.25, 0.5, 0.5, corner: 0.06), color: foil),
                     Part(path: oval(-0.12, -0.46, 0.24, 0.16), color: white)],
                    cells(-1, -0.2, 0.68, 0.4) + cells(0.32, -0.2, 0.68, 0.4)
                    + [Part(path: rect(-0.25, -0.02, 0.5, 0.04), color: Color(red: 0.7, green: 0.52, blue: 0.22))])

        case .rocketBody:
            return ([Part(path: rect(-0.88, -0.24, 1.5, 0.48, corner: 0.1), color: metal),
                     Part(path: poly([(0.62, -0.17), (0.98, -0.28), (0.98, 0.28), (0.62, 0.17)]), color: dark),
                     Part(path: rect(-0.42, -0.24, 0.08, 0.48), color: dark)],
                    [Part(path: rect(0.12, -0.24, 0.05, 0.48), color: Color(red: 0.6, green: 0.62, blue: 0.66)),
                     Part(path: rect(-0.8, -0.24, 0.05, 0.48), color: Color(red: 0.6, green: 0.62, blue: 0.66))])

        case .capsule:
            return ([Part(path: rect(-0.98, 0.14, 0.76, 0.24, corner: 0.02), color: panel),
                     Part(path: rect(0.22, 0.14, 0.76, 0.24, corner: 0.02), color: panel),
                     Part(path: rect(-0.22, 0.0, 0.44, 0.58, corner: 0.05), color: metal),
                     Part(path: poly([(-0.26, 0.02), (0.26, 0.02), (0.13, -0.5), (-0.13, -0.5)]), color: white)],
                    cells(-0.98, 0.14, 0.76, 0.24) + cells(0.22, 0.14, 0.76, 0.24)
                    + [Part(path: oval(-0.06, -0.3, 0.12, 0.12), color: dark)])

        case .iss:
            var parts: [Part] = []
            var details: [Part] = []
            for x in [-0.96, -0.72, 0.54, 0.78] as [CGFloat] {
                for y in [-0.9, 0.14] as [CGFloat] {
                    parts.append(Part(path: rect(x, y, 0.18, 0.76), color: issArray))
                    details += cells(x, y, 0.18, 0.76, count: 6, color: Color(red: 0.6, green: 0.38, blue: 0.16).opacity(0.7))
                }
            }
            parts += [Part(path: rect(-1, -0.065, 2, 0.13), color: metal),
                      Part(path: rect(-0.4, 0.1, 0.12, 0.4), color: white),
                      Part(path: rect(0.28, 0.1, 0.12, 0.4), color: white),
                      Part(path: rect(-0.1, -0.56, 0.2, 1.2, corner: 0.06), color: white),
                      Part(path: rect(-0.26, 0.24, 0.52, 0.13, corner: 0.05), color: white),
                      Part(path: rect(-0.06, 0.62, 0.12, 0.34, corner: 0.04), color: white)]
            details += [-0.8, -0.6, -0.4, 0.4, 0.6, 0.8].map { Part(path: rect($0, -0.065, 0.015, 0.13), color: dark.opacity(0.6)) }
            return (parts, details)

        case .tiangong:
            return ([Part(path: rect(-0.98, -0.95, 0.2, 1.15), color: tiangongArray),
                     Part(path: rect(0.78, -0.95, 0.2, 1.15), color: tiangongArray),
                     Part(path: rect(-0.8, -0.37, 1.6, 0.17, corner: 0.06), color: white),
                     Part(path: rect(-0.1, -0.3, 0.2, 1.0, corner: 0.07), color: white),
                     Part(path: rect(-0.58, 0.44, 0.46, 0.15), color: tiangongArray),
                     Part(path: rect(0.12, 0.44, 0.46, 0.15), color: tiangongArray)],
                    cells(-0.98, -0.95, 0.2, 1.15, count: 7) + cells(0.78, -0.95, 0.2, 1.15, count: 7)
                    + [Part(path: oval(-0.08, -0.36, 0.16, 0.16), color: metal)])

        case .hubble:
            return ([Part(path: rect(-0.04, -0.5, 0.05, 1.0), color: metal),
                     Part(path: rect(-0.58, -0.7, 1.1, 0.2, corner: 0.02), color: panel),
                     Part(path: rect(-0.58, 0.5, 1.1, 0.2, corner: 0.02), color: panel),
                     Part(path: rect(-0.82, -0.25, 1.62, 0.5, corner: 0.12), color: metal),
                     Part(path: rect(0.3, -0.25, 0.5, 0.5, corner: 0.1), color: white),
                     Part(path: oval(-0.88, -0.23, 0.14, 0.46), color: dark),
                     Part(path: rect(-0.99, -0.34, 0.05, 0.42, corner: 0.02), color: white),
                     Part(path: oval(0.02, -0.46, 0.16, 0.1), color: white),
                     Part(path: oval(0.02, 0.36, 0.16, 0.1), color: white)],
                    cells(-0.58, -0.7, 1.1, 0.2, count: 6) + cells(-0.58, 0.5, 1.1, 0.2, count: 6)
                    + [Part(path: rect(-0.1, -0.25, 0.03, 0.5), color: Color(red: 0.6, green: 0.62, blue: 0.68))])

        case .starlinkV09, .starlinkV1, .starlinkV15:
            var parts = [Part(path: rect(-0.05, -0.14, 1.05, 0.28, corner: 0.02), color: panel),
                         Part(path: rect(-0.62, -0.22, 0.62, 0.44, corner: 0.03), color: dark)]
            if d == .starlinkV15 {
                parts += [Part(path: oval(-0.52, -0.14, 0.12, 0.12), color: laser), Part(path: oval(-0.52, 0.02, 0.12, 0.12), color: laser)]
            }
            return (parts, cells(-0.05, -0.14, 1.05, 0.28, count: 6) + [Part(path: rect(-0.62, -0.01, 0.62, 0.02), color: metal.opacity(0.5))])

        case .starlinkV2Mini, .starlinkDTC:
            var parts = [Part(path: rect(-1, -0.15, 0.72, 0.3, corner: 0.02), color: panel),
                         Part(path: rect(0.28, -0.15, 0.72, 0.3, corner: 0.02), color: panel),
                         Part(path: rect(-0.3, -0.25, 0.6, 0.5, corner: 0.04), color: dark),
                         Part(path: oval(-0.2, -0.16, 0.12, 0.12), color: laser),
                         Part(path: oval(0.08, -0.16, 0.12, 0.12), color: laser)]
            var details = cells(-1, -0.15, 0.72, 0.3, count: 2, color: metal) + cells(0.28, -0.15, 0.72, 0.3, count: 2, color: metal)
                + cells(-1, -0.15, 0.72, 0.3, count: 6) + cells(0.28, -0.15, 0.72, 0.3, count: 6)
            if d == .starlinkDTC {
                parts.append(Part(path: rect(-0.28, 0.3, 0.56, 0.56, corner: 0.03), color: Color(red: 0.72, green: 0.74, blue: 0.8)))
                details += cells(-0.28, 0.3, 0.56, 0.56, count: 4, color: dark.opacity(0.5))
                details += [0.44, 0.58, 0.72].map { Part(path: rect(-0.28, $0, 0.56, 0.015), color: dark.opacity(0.5)) }
            }
            return (parts, details)
        }
    }
}
