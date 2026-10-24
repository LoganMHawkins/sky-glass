import SwiftUI
import simd

/// Draws one frame of the sky overlay into a Canvas and records tap targets.
struct SkyRenderer {
    let model: SkyModel

    func draw(_ ctx: inout GraphicsContext, size: CGSize, date: Date) {
        let proj = model.projector(size: size)
        let now = date.timeIntervalSinceReferenceDate
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -30, dy: -30)
        var hits: [HitTarget] = []
        hits.reserveCapacity(512)

        drawHorizon(&ctx, proj)

        if model.layers.contains(.sky) {
            if model.showConstellations { drawConstellations(&ctx, proj) }
            let moon = model.bodies[.moon]
            for p in model.skyPoints {
                guard let pt = proj.project(p.vector), bounds.contains(pt) else { continue }
                drawSkyPoint(&ctx, p, at: pt, moon: moon)
                hits.append(HitTarget(id: p.id, point: pt, priority: p.priority))
            }
        }

        let hideDim = model.onlyVisibleSatellites
        for group in model.activeSatGroups {
            for p in model.satellites.points[group] ?? [] {
                if hideDim, p.dimmed, p.id != model.selectedID { continue }
                let v = p.vector(at: now)
                guard let pt = proj.project(v), bounds.contains(pt) else { continue }
                drawSatellite(&ctx, p, at: pt, time: now, proj: proj)
                hits.append(HitTarget(id: p.id, point: pt, priority: p.priority))
            }
        }

        drawFocus(&ctx, proj, size: size, time: now, hits: hits)

        model.hitTargets = hits
        model.noteCenter(hits, center: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    // MARK: Horizon & constellations

    private func drawHorizon(_ ctx: inout GraphicsContext, _ proj: SkyProjector) {
        var path = Path()
        var penDown = false
        for i in 0...120 {
            if let pt = proj.project(Astro.skyVector(altitude: 0, azimuth: Double(i) * 3), minZ: 0.08) {
                if penDown { path.addLine(to: pt) } else { path.move(to: pt); penDown = true }
            } else {
                penDown = false
            }
        }
        ctx.stroke(path, with: .color(Theme.magenta.opacity(0.22)), lineWidth: 8)
        ctx.stroke(path, with: .color(Theme.rose.opacity(0.85)), lineWidth: 1.2)

        for (i, name) in ["N", "NE", "E", "SE", "S", "SW", "W", "NW"].enumerated() {
            guard let pt = proj.project(Astro.skyVector(altitude: 2.2, azimuth: Double(i) * 45)) else { continue }
            let major = i % 2 == 0
            let text = Text(name)
                .font(.system(size: major ? 16 : 11, weight: .heavy, design: .rounded))
                .foregroundStyle(i == 0 ? Theme.ember : .white.opacity(major ? 0.9 : 0.6))
            ctx.draw(text, at: pt)
        }
    }

    private func drawConstellations(_ ctx: inout GraphicsContext, _ proj: SkyProjector) {
        var path = Path()
        for (a, b) in model.constellationSegments {
            guard let pa = proj.project(a), let pb = proj.project(b) else { continue }
            path.move(to: pa)
            path.addLine(to: pb)
        }
        ctx.stroke(path, with: .color(Theme.rose.opacity(0.28)), style: StrokeStyle(lineWidth: 1, lineCap: .round))

        guard model.showLabels else { return }
        for (name, v) in model.constellationLabels {
            guard let pt = proj.project(v) else { continue }
            let text = Text(name.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2.5)
                .foregroundStyle(Theme.rose.opacity(0.5))
            ctx.draw(text, at: pt)
        }
    }

    // MARK: Objects

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private func glow(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: Color, _ opacity: Double) {
        ctx.fill(circle(c, r), with: .radialGradient(Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
                                                      center: c, startRadius: 0, endRadius: r))
    }

    private func label(_ ctx: inout GraphicsContext, _ text: String, at pt: CGPoint, offset: CGFloat, color: Color, size: CGFloat = 12) {
        guard model.showLabels else { return }
        let t = Text(text).font(.system(size: size, weight: .semibold, design: .rounded)).foregroundStyle(color)
        ctx.draw(t, at: CGPoint(x: pt.x + offset + 5, y: pt.y), anchor: .leading)
    }

    private func drawSkyPoint(_ ctx: inout GraphicsContext, _ p: SkyPoint, at pt: CGPoint, moon: BodyState?) {
        let below = p.altitude < 0
        let alpha = below ? 0.35 : 1.0
        switch p.kind {
        case .star:
            if p.radius > 2.6 { glow(&ctx, pt, p.radius * 4, p.color, 0.35 * alpha) }
            ctx.fill(circle(pt, p.radius), with: .color(p.color.opacity(alpha)))
            if let l = p.label { label(&ctx, l, at: pt, offset: p.radius, color: .white.opacity(0.75 * alpha), size: 11) }

        case .deepSky:
            ctx.stroke(circle(pt, 7), with: .color(Theme.lavender.opacity(0.7 * alpha)), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
            ctx.fill(circle(pt, 1.6), with: .color(Theme.lavender.opacity(alpha)))
            if let l = p.label { label(&ctx, l, at: pt, offset: 7, color: Theme.lavender.opacity(0.8 * alpha), size: 11) }

        case .planet:
            glow(&ctx, pt, p.radius * 4.5, p.color, 0.45 * alpha)
            ctx.fill(circle(pt, p.radius), with: .radialGradient(Gradient(colors: [.white, p.color]), center: CGPoint(x: pt.x - p.radius * 0.3, y: pt.y - p.radius * 0.3), startRadius: 0, endRadius: p.radius * 1.4))
            if p.id == Body.saturn.id {
                var ring = Path(ellipseIn: CGRect(x: pt.x - p.radius * 2, y: pt.y - p.radius * 0.6, width: p.radius * 4, height: p.radius * 1.2))
                ring = ring.applying(CGAffineTransform(translationX: -pt.x, y: -pt.y).concatenating(CGAffineTransform(rotationAngle: -0.35)).concatenating(CGAffineTransform(translationX: pt.x, y: pt.y)))
                ctx.stroke(ring, with: .color(p.color.opacity(0.85 * alpha)), lineWidth: 1.2)
            }
            if let l = p.label { label(&ctx, l, at: pt, offset: p.radius + 2, color: p.color.opacity(alpha), size: 13) }

        case .moon:
            glow(&ctx, pt, p.radius * 3.5, Theme.lavender, 0.4 * alpha)
            ctx.fill(circle(pt, p.radius), with: .color(Theme.deep.opacity(0.9 * alpha)))
            if let m = moon {
                ctx.fill(moonPath(center: pt, r: p.radius, lit: m.illumination, waxing: m.waxing), with: .color(p.color.opacity(alpha)))
            }
            ctx.stroke(circle(pt, p.radius), with: .color(.white.opacity(0.25 * alpha)), lineWidth: 0.8)
            if let l = p.label { label(&ctx, l, at: pt, offset: p.radius + 2, color: .white.opacity(alpha), size: 13) }

        case .sun:
            glow(&ctx, pt, p.radius * 6, Theme.ember, 0.55 * alpha)
            glow(&ctx, pt, p.radius * 2.5, p.color, 0.9 * alpha)
            ctx.fill(circle(pt, p.radius), with: .color(Color(red: 1, green: 0.95, blue: 0.85).opacity(alpha)))
            if let l = p.label { label(&ctx, l, at: pt, offset: p.radius + 4, color: p.color.opacity(alpha), size: 13) }

        default:
            break
        }
    }

    /// Lit region of the Moon: between the limb and an elliptical terminator.
    private func moonPath(center c: CGPoint, r: CGFloat, lit k: Double, waxing: Bool) -> Path {
        var p = Path()
        let steps = 24
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

    private func drawSatellite(_ ctx: inout GraphicsContext, _ p: SkyPoint, at pt: CGPoint, time: TimeInterval, proj: SkyProjector) {
        let below = p.altitude < 0
        let alpha = below ? 0.3 : (p.dimmed ? 0.55 : 1.0)
        let color = p.color.opacity(alpha)

        if p.kind != .starlink, let tail = proj.project(p.vector(at: time - 20)) {
            var trail = Path()
            trail.move(to: tail)
            trail.addLine(to: pt)
            ctx.stroke(trail, with: .linearGradient(Gradient(colors: [p.color.opacity(0), p.color.opacity(0.55 * alpha)]), startPoint: tail, endPoint: pt),
                       style: StrokeStyle(lineWidth: p.kind == .station ? 2 : 1.2, lineCap: .round))
        }
        if p.kind == .station {
            glow(&ctx, pt, 18, Theme.station, 0.5 * alpha)
            let r = p.radius
            var body = Path(roundedRect: CGRect(x: pt.x - r * 0.6, y: pt.y - r * 0.6, width: r * 1.2, height: r * 1.2), cornerRadius: 1.5)
            body.addRect(CGRect(x: pt.x - r * 2.4, y: pt.y - 0.9, width: r * 4.8, height: 1.8))
            ctx.fill(body, with: .color(color))
            if let l = p.label { label(&ctx, l, at: pt, offset: r * 2.4, color: Theme.station.opacity(alpha), size: 13) }
        } else {
            if !p.dimmed { glow(&ctx, pt, p.radius * 3.5, p.color, 0.4 * alpha) }
            ctx.fill(circle(pt, p.radius), with: .color(color))
        }
    }

    // MARK: Selection, reticle target and off-screen guide

    private func hasPermanentLabel(_ id: String) -> Bool {
        model.showLabels && (model.labeledIDs.contains(id) || model.kind(of: id) == .station)
    }

    private func drawFocus(_ ctx: inout GraphicsContext, _ proj: SkyProjector, size: CGSize, time: TimeInterval, hits: [HitTarget]) {
        let pulse = 0.5 + 0.5 * sin(time * 3)

        if let centered = model.centeredID, centered != model.selectedID, let h = hits.first(where: { $0.id == centered }) {
            ctx.stroke(circle(h.point, 15), with: .color(.white.opacity(0.55)), lineWidth: 1)
            if !hasPermanentLabel(centered) {
                label(&ctx, model.displayName(for: centered), at: h.point, offset: 15, color: .white.opacity(0.85), size: 12)
            }
        }

        guard let id = model.selectedID else { return }
        let onScreen = CGRect(origin: .zero, size: size).insetBy(dx: 20, dy: 90)
        if let h = hits.first(where: { $0.id == id }), onScreen.contains(h.point) {
            let r = 19 + 4 * pulse
            ctx.stroke(circle(h.point, r), with: .linearGradient(Gradient(colors: [Theme.ember, Theme.magenta, Theme.purple]),
                                                                  startPoint: CGPoint(x: h.point.x - r, y: h.point.y - r),
                                                                  endPoint: CGPoint(x: h.point.x + r, y: h.point.y + r)), lineWidth: 2)
            glow(&ctx, h.point, r + 12, Theme.magenta, 0.25)
            if !hasPermanentLabel(id) {
                label(&ctx, model.displayName(for: id), at: h.point, offset: r, color: Theme.rose, size: 13)
            }
            return
        }

        // Off-screen: an arrow on the screen edge pointing the way to turn.
        guard let v = model.vector(for: id, at: time) else { return }
        let c = proj.camera(v)
        var dx = c.x, dy = -c.y
        if hypot(dx, dy) < 1e-4 { dy = 1 }
        if c.z < 0 && hypot(dx, dy) < 0.2 { dx = 1; dy = 0 }
        let ang = atan2(dy, dx)
        // Keep the guide clear of the top bar and the glance card at the bottom.
        let cx = size.width / 2, cy = size.height / 2
        let rx = cx - 36
        let ry = sin(ang) < 0 ? cy - 150 : size.height - 400 - cy
        let t = min(abs(cos(ang)) > 1e-6 ? rx / abs(cos(ang)) : .infinity, abs(sin(ang)) > 1e-6 ? max(40, ry) / abs(sin(ang)) : .infinity)
        let pos = CGPoint(x: cx + CGFloat(cos(ang) * t), y: cy + CGFloat(sin(ang) * t))

        glow(&ctx, pos, 30 + 6 * pulse, Theme.magenta, 0.45)
        var arrow = Path()
        arrow.move(to: CGPoint(x: 15, y: 0))
        arrow.addLine(to: CGPoint(x: -9, y: -10))
        arrow.addLine(to: CGPoint(x: -4, y: 0))
        arrow.addLine(to: CGPoint(x: -9, y: 10))
        arrow.closeSubpath()
        arrow = arrow.applying(CGAffineTransform(rotationAngle: ang).concatenating(CGAffineTransform(translationX: pos.x, y: pos.y)))
        ctx.fill(arrow, with: .linearGradient(Gradient(colors: [Theme.ember, Theme.magenta]),
                                              startPoint: CGPoint(x: pos.x - 12, y: pos.y), endPoint: CGPoint(x: pos.x + 12, y: pos.y)))

        let name = Text(model.displayName(for: id))
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.rose)
        let inward = CGPoint(x: pos.x - CGFloat(cos(ang)) * 34, y: pos.y - CGFloat(sin(ang)) * 26)
        ctx.draw(name, at: inward)
    }
}
