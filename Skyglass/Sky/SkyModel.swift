import SwiftUI
import QuartzCore
import simd

@Observable
final class SkyModel {
    let location = LocationProvider()
    let camera = CameraController()
    let satellites = SatelliteTracker()
    @ObservationIgnored let orientation = OrientationProvider()

    var layers: Set<SkyLayer> = [.sky, .satellites] {
        didSet {
            syncSatelliteLoads()
            Self.defaults.set(layers.map(\.rawValue), forKey: "layers")
        }
    }
    var selectedID: String?
    private(set) var centeredID: String?

    // Settings, remembered between launches
    var appearance: AppearanceMode = .system { didSet { Self.defaults.set(appearance.rawValue, forKey: "appearance") } }
    var showConstellations = true { didSet { Self.defaults.set(showConstellations, forKey: "showConstellations") } }
    var showLabels = true { didSet { Self.defaults.set(showLabels, forKey: "showLabels") } }
    var showBelowHorizon = true { didSet { Self.defaults.set(showBelowHorizon, forKey: "showBelowHorizon") } }
    var magnitudeLimit: Double = 5.0 {
        didSet {
            Self.defaults.set(magnitudeLimit, forKey: "magnitudeLimit")
            refresh()
        }
    }
    var allActiveSatellites = false {
        didSet {
            Self.defaults.set(allActiveSatellites, forKey: "allActiveSatellites")
            syncSatelliteLoads()
        }
    }
    var onlyVisibleSatellites = false { didSet { Self.defaults.set(onlyVisibleSatellites, forKey: "onlyVisibleSatellites") } }
    var keepScreenAwake = true {
        didSet {
            Self.defaults.set(keepScreenAwake, forKey: "keepScreenAwake")
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
    }
    var zoom: Double = 1
    private(set) var tick = 0
    private(set) var simulatedSky = false
    private(set) var compassNeedsCalibration = false
    private(set) var skyObjectsUp = 0

    @ObservationIgnored private(set) var skyPoints: [SkyPoint] = []
    /// Objects that already carry a permanent label on the overlay.
    @ObservationIgnored private(set) var labeledIDs: Set<String> = []
    @ObservationIgnored private(set) var constellationSegments: [(Vec3, Vec3)] = []
    @ObservationIgnored private(set) var constellationLabels: [(String, Vec3)] = []
    @ObservationIgnored private(set) var horizontals: [String: Horizontal] = [:]
    @ObservationIgnored private(set) var bodies: [Body: BodyState] = [:]
    @ObservationIgnored var hitTargets: [HitTarget] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastCenterCheck: CFTimeInterval = 0

    /// The object the glance card describes: whatever was tapped, else whatever sits under the reticle.
    var focusID: String? { selectedID ?? centeredID }

    var activeSatGroups: [SatGroup] { SkyLayer.allCases.filter { layers.contains($0) }.flatMap(satGroups(for:)) }

    /// Satellite groups behind a layer; the Satellites layer adds every active satellite when that setting is on.
    func satGroups(for layer: SkyLayer) -> [SatGroup] {
        layer == .satellites && allActiveSatellites ? layer.groups + [.active] : layer.groups
    }

    var lookDirection: Horizontal { Astro.horizontal(from: orientation.basis.forward) }

    /// Vertical field of view of the overlay, matched to the camera when it's live.
    var verticalFOV: Double {
        guard !simulatedSky, camera.isRunning else { return 70 / zoom }
        let f = camera.fieldOfView * Astro.deg
        return 2 * atan(tan(f / 2) / zoom) * Astro.rad
    }

    @ObservationIgnored private static let defaults = UserDefaults.standard

    init() {
        let d = Self.defaults
        if let raw = d.string(forKey: "appearance"), let mode = AppearanceMode(rawValue: raw) { appearance = mode }
        if let saved = d.stringArray(forKey: "layers") { layers = Set(saved.compactMap(SkyLayer.init(rawValue:))) }
        if d.object(forKey: "showConstellations") != nil { showConstellations = d.bool(forKey: "showConstellations") }
        if d.object(forKey: "showLabels") != nil { showLabels = d.bool(forKey: "showLabels") }
        if d.object(forKey: "showBelowHorizon") != nil { showBelowHorizon = d.bool(forKey: "showBelowHorizon") }
        if d.object(forKey: "magnitudeLimit") != nil { magnitudeLimit = d.double(forKey: "magnitudeLimit") }
        if d.object(forKey: "allActiveSatellites") != nil { allActiveSatellites = d.bool(forKey: "allActiveSatellites") }
        if d.object(forKey: "onlyVisibleSatellites") != nil { onlyVisibleSatellites = d.bool(forKey: "onlyVisibleSatellites") }
        if d.object(forKey: "keepScreenAwake") != nil { keepScreenAwake = d.bool(forKey: "keepScreenAwake") }
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        location.onAuthorized = { [weak self] in self?.orientation.start(trueNorth: true) }
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        location.start()
        orientation.start()
        simulatedSky = !orientation.isLive
        if !simulatedSky { camera.start() }
        syncSatelliteLoads()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func resume() {
        guard started else { return }
        camera.resume()
        if !simulatedSky { orientation.start(trueNorth: true) }
        satellites.retryFailed()
        refresh()
    }

    func pause() {
        camera.pause()
        orientation.stop()
    }

    func toggle(_ layer: SkyLayer) {
        if layers.contains(layer) { layers.remove(layer) } else { layers.insert(layer) }
        if let id = selectedID, let kind = kind(of: id), !layers.contains(kind.layer) { selectedID = nil }
    }

    func select(_ id: String?) {
        selectedID = id
        if let id, let kind = kind(of: id) { layers.insert(kind.layer) }
    }

    func setZoom(_ z: Double) {
        zoom = min(max(z, 1), simulatedSky ? 4 : 6)
        if !simulatedSky { camera.setZoom(zoom) }
    }

    private func syncSatelliteLoads() {
        for group in activeSatGroups { satellites.ensureLoaded(group) }
    }

    // MARK: Per-second refresh

    func refresh() {
        let now = Date()
        let jd = Astro.julianDate(now)
        let obs = location.observer
        let lst = Astro.lst(jd: jd, longitude: obs.longitude)
        var points: [SkyPoint] = []
        var horiz: [String: Horizontal] = [:]

        for star in StarCatalog.stars {
            let p = Astro.precess(raHours: star.ra, dec: star.dec, jd: jd)
            let h = Astro.horizontal(ra: p.ra, dec: p.dec, observer: obs, lst: lst)
            horiz[star.id] = h
            guard star.mag <= magnitudeLimit else { continue }
            points.append(SkyPoint(id: star.id, kind: .star, vector: h.vector, radius: Self.starRadius(star.mag),
                                   color: Self.starColor(star.spectral), label: star.mag < 1.6 ? star.name : nil,
                                   altitude: h.altitude, priority: star.mag < 1 ? 3 : 1))
        }
        for dso in DeepSkyCatalog.objects {
            let p = Astro.precess(raHours: dso.ra, dec: dso.dec, jd: jd)
            let h = Astro.horizontal(ra: p.ra, dec: p.dec, observer: obs, lst: lst)
            horiz[dso.id] = h
            points.append(SkyPoint(id: dso.id, kind: .deepSky, vector: h.vector, radius: 3.5, color: Theme.lavender,
                                   label: dso.mag < 4.5 ? dso.name : nil, altitude: h.altitude, priority: 2))
        }
        points.sort { $0.radius < $1.radius }

        bodies = SolarSystem.compute(jd: jd, observer: obs)
        for body in [Body.neptune, .uranus, .mercury, .mars, .saturn, .jupiter, .venus, .sun, .moon] {
            guard let b = bodies[body] else { continue }
            let h = Astro.horizontal(ra: b.ra, dec: b.dec, observer: obs, lst: lst)
            horiz[body.id] = h
            let kind: ObjectKind = body == .sun ? .sun : body == .moon ? .moon : .planet
            let radius = Self.bodyRadius(body)
            points.append(SkyPoint(id: body.id, kind: kind, vector: h.vector, radius: radius, color: Self.bodyColor(body),
                                   label: body.name, altitude: h.altitude, priority: 5))
        }

        var segments: [(Vec3, Vec3)] = []
        var labels: [(String, Vec3)] = []
        for c in StarCatalog.constellations {
            var sum = Vec3.zero
            for (a, b) in c.lines {
                guard let ha = StarCatalog.byName[a].flatMap({ horiz[$0.id] }),
                      let hb = StarCatalog.byName[b].flatMap({ horiz[$0.id] }) else { continue }
                segments.append((ha.vector, hb.vector))
                sum += ha.vector + hb.vector
            }
            if simd_length(sum) > 0 { labels.append((c.name, simd_normalize(sum))) }
        }

        skyPoints = points
        labeledIDs = Set(points.filter { $0.label != nil }.map(\.id))
        horizontals = horiz
        constellationSegments = segments
        constellationLabels = labels

        let up = points.filter { $0.altitude > 0 }.count
        if up != skyObjectsUp { skyObjectsUp = up }
        if orientation.needsCalibration != compassNeedsCalibration { compassNeedsCalibration = orientation.needsCalibration }

        let pinned = selectedID?.hasPrefix("sat:") == true ? selectedID : nil
        satellites.propagate(groups: Set(activeSatGroups), observer: obs, date: now, pinned: pinned,
                             sunAltitude: horiz[Body.sun.id]?.altitude ?? 0)
        tick &+= 1
    }

    // MARK: Projection & interaction

    func projector(size: CGSize) -> SkyProjector {
        let focal = Double(size.height / 2) / tan(verticalFOV * Astro.deg / 2)
        return SkyProjector(basis: orientation.basis, focal: focal, center: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    func handleTap(_ point: CGPoint) {
        var best: (HitTarget, CGFloat)?
        for h in hitTargets {
            let d = hypot(h.point.x - point.x, h.point.y - point.y) - CGFloat(h.priority) * 3
            if d < 36, d < (best?.1 ?? .infinity) { best = (h, d) }
        }
        withAnimation(.spring(duration: 0.35)) {
            selectedID = best?.0.id
        }
    }

    /// Called by the renderer each frame; picks the object closest to the reticle.
    func noteCenter(_ hits: [HitTarget], center: CGPoint) {
        let now = CACurrentMediaTime()
        guard now - lastCenterCheck > 0.15 else { return }
        lastCenterCheck = now
        func score(_ h: HitTarget) -> CGFloat { hypot(h.point.x - center.x, h.point.y - center.y) - CGFloat(h.priority) * 10 }
        var best: HitTarget?
        for h in hits where hypot(h.point.x - center.x, h.point.y - center.y) < 70 {
            if best == nil || score(h) < score(best!) { best = h }
        }
        // Hysteresis: hold on to the current object until something clearly better comes along.
        if let current = centeredID, let ch = hits.first(where: { $0.id == current }),
           hypot(ch.point.x - center.x, ch.point.y - center.y) < 95,
           best == nil || score(best!) > score(ch) - 18 {
            best = ch
        }
        let newID = best?.id
        if newID != centeredID {
            DispatchQueue.main.async { [weak self] in
                withAnimation(.spring(duration: 0.35)) { self?.centeredID = newID }
            }
        }
    }

    /// Current sky-frame direction of any object, satellites included.
    func vector(for id: String, at time: TimeInterval) -> Vec3? {
        if let h = horizontals[id] { return h.vector }
        for pts in satellites.points.values {
            if let p = pts.first(where: { $0.id == id }) { return p.vector(at: time) }
        }
        return satellites.states[id]?.vector
    }

    func kind(of id: String) -> ObjectKind? {
        if id.hasPrefix("star:") { return .star }
        if id.hasPrefix("dso:") { return .deepSky }
        if id.hasPrefix("body:") { return id == Body.sun.id ? .sun : id == Body.moon.id ? .moon : .planet }
        return satellites.byID[id]?.kind
    }

    func displayName(for id: String) -> String {
        if let s = StarCatalog.byID[id] { return s.name }
        if let d = DeepSkyCatalog.byID[id] { return d.name }
        if let b = Body(rawValue: String(id.dropFirst(5))), id.hasPrefix("body:") { return b.name }
        return satellites.byID[id]?.displayName ?? ""
    }

    // MARK: Styling

    static func starRadius(_ mag: Double) -> CGFloat { CGFloat(max(1.1, 4.8 - 0.85 * mag)) }

    static func starColor(_ spectral: String) -> Color { StarColor.color(spectral) }

    /// On-sky size of each body: big enough for its artwork to read, ordered roughly by brightness.
    static func bodyRadius(_ body: Body) -> CGFloat {
        switch body {
        case .sun: 16
        case .moon: 16
        case .jupiter: 11
        case .venus: 9
        case .saturn: 8
        case .mars: 8
        case .mercury: 6
        case .uranus, .neptune: 5.5
        }
    }

    static func bodyColor(_ body: Body) -> Color {
        switch body {
        case .sun: Color(red: 1.0, green: 0.78, blue: 0.45)
        case .moon: Color(red: 0.95, green: 0.93, blue: 0.98)
        case .mercury: Color(red: 0.82, green: 0.76, blue: 0.72)
        case .venus: Color(red: 1.0, green: 0.95, blue: 0.82)
        case .mars: Color(red: 1.0, green: 0.48, blue: 0.32)
        case .jupiter: Color(red: 0.96, green: 0.82, blue: 0.66)
        case .saturn: Color(red: 0.96, green: 0.87, blue: 0.6)
        case .uranus: Color(red: 0.62, green: 0.9, blue: 0.95)
        case .neptune: Color(red: 0.5, green: 0.62, blue: 1.0)
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
