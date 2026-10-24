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
            let hideBelow = !model.showBelowHorizon
            for p in model.skyPoints {
                if hideBelow, p.altitude < 0, p.id != model.selectedID { continue }
                guard let pt = proj.project(p.vector), bounds.contains(pt) else { continue }
                drawSkyPoint(&ctx, p, at: pt, moon: moon)
                hits.append(HitTarget(id: p.id, point: pt, priority: p.priority))
            }
        }

        let hideDim = model.onlyVisibleSatellites
        for group in model.activeSatGroups {
            for p in model.satellites.points[group] ?? [] {
                if hideDim, p.dimmed, p.id != model.selectedID { continue }
                if !model.showBelowHorizon, p.altitude < 0, p.id != model.selectedID { continue }
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
            BodyArt.drawStar(&ctx, pt, p.radius, color: p.color, opacity: alpha, spikes: p.radius > 4.2)
            if let l = p.label { label(&ctx, l, at: pt, offset: p.radius, color: .white.opacity(0.75 * alpha), size: 11) }

        case .deepSky:
            ctx.stroke(circle(pt, 7), with: .color(Theme.lavender.opacity(0.7 * alpha)), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
            ctx.fill(circle(pt, 1.6), with: .color(Theme.lavender.opacity(alpha)))
            if let l = p.label { label(&ctx, l, at: pt, offset: 7, color: Theme.lavender.opacity(0.8 * alpha), size: 11) }

        case .planet:
            guard let body = Body(rawValue: String(p.id.dropFirst(5))) else { return }
            glow(&ctx, pt, p.radius * 3.2, p.color, 0.4 * alpha)
            BodyArt.drawPlanet(&ctx, body, pt, p.radius, ringTilt: model.bodies[.saturn]?.ringTilt ?? 0, opacity: alpha)
            let labelOffset = body == .saturn ? p.radius * 2.2 : p.radius + 2
            if let l = p.label { label(&ctx, l, at: pt, offset: labelOffset, color: p.color.opacity(alpha), size: 13) }

        case .moon:
            glow(&ctx, pt, p.radius * 3.2, Theme.lavender, 0.35 * (moon?.illumination ?? 1) * alpha)
            if let m = moon {
                BodyArt.drawMoon(&ctx, pt, p.radius, illumination: m.illumination, waxing: m.waxing, opacity: alpha)
            }
            if let l = p.label { label(&ctx, l, at: pt, offset: p.radius + 2, color: .white.opacity(alpha), size: 13) }

        case .sun:
            glow(&ctx, pt, p.radius * 6, Theme.ember, 0.55 * alpha)
            glow(&ctx, pt, p.radius * 2.5, p.color, 0.9 * alpha)
            BodyArt.drawSun(&ctx, pt, p.radius, opacity: alpha)
            if let l = p.label { label(&ctx, l, at: pt, offset: p.radius + 4, color: p.color.opacity(alpha), size: 13) }

        default:
            break
        }
    }

    private func drawSatellite(_ ctx: inout GraphicsContext, _ p: SkyPoint, at pt: CGPoint, time: TimeInterval, proj: SkyProjector) {
        let below = p.altitude < 0
        let alpha = below ? 0.3 : (p.dimmed ? 0.5 : 1.0)
        let design = model.satellites.byID[p.id]?.design ?? .generic

        // Point the craft along its path across the screen.
        var heading: CGFloat = 0
        if let ahead = proj.project(p.vector(at: time + 10)) {
            heading = atan2(ahead.y - pt.y, ahead.x - pt.x)
        }
        if p.kind != .starlink, let tail = proj.project(p.vector(at: time - 20)) {
            var trail = Path()
            trail.move(to: tail)
            trail.addLine(to: pt)
            ctx.stroke(trail, with: .linearGradient(Gradient(colors: [p.color.opacity(0), p.color.opacity(0.55 * alpha)]), startPoint: tail, endPoint: pt),
                       style: StrokeStyle(lineWidth: p.kind == .station ? 2 : 1.2, lineCap: .round))
        }
        let size = design.overlayHalfWidth
        if !p.dimmed || p.kind == .station {
            glow(&ctx, pt, size * (p.kind == .starlink ? 1.8 : 2.2), p.color, (p.kind == .station ? 0.5 : 0.35) * alpha)
        }
        SatelliteArt.draw(design, in: &ctx, at: pt, halfWidth: size, angle: heading + design.flightAngleOffset, opacity: alpha, detailed: false, silhouette: p.color)
        if let l = p.label { label(&ctx, l, at: pt, offset: size + 2, color: Theme.station.opacity(alpha), size: 13) }
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
