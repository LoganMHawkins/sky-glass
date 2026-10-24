import MapKit
import SwiftUI
import simd

/// One satellite's position over the Earth, for the globe.
struct GlobeSat: Sendable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let heightKm: Double
    let kind: ObjectKind
}

extension SatMath {
    /// The point on Earth directly below the satellite (geocentric latitude, plenty for a map).
    static func subpoint(for sat: Satellite, jd: Double, gmst: Double) -> (lat: Double, lon: Double, heightKm: Double)? {
        guard let (r, _) = try? sat.sgp4.propagate(minutes: (jd - sat.sgp4.epochJD) * 1440) else { return nil }
        let x = cos(gmst) * r.x + sin(gmst) * r.y
        let y = -sin(gmst) * r.x + cos(gmst) * r.y
        return (atan2(r.z, sqrt(x * x + y * y)) * Astro.rad, atan2(y, x) * Astro.rad, simd_length(r) - earthRadius)
    }

    static func subpoints(_ sats: [Satellite], date: Date) -> [GlobeSat] {
        let jd = Astro.julianDate(date)
        let gmst = SGP4.gstime(jd)
        return sats.compactMap { sat in
            subpoint(for: sat, jd: jd, gmst: gmst).map {
                GlobeSat(id: sat.id, coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon), heightKm: $0.heightKm, kind: sat.kind)
            }
        }
    }

    /// Ground track for the next orbit, split wherever it crosses the antimeridian.
    static func groundTrack(for sat: Satellite, from start: Date) -> [[CLLocationCoordinate2D]] {
        var segments: [[CLLocationCoordinate2D]] = [[]]
        let minutes = Int(min(sat.periodMinutes, 200))
        var lastLon: Double?
        for m in stride(from: 0, through: minutes, by: 1) {
            let date = start.addingTimeInterval(Double(m) * 60)
            let jd = Astro.julianDate(date)
            guard let p = subpoint(for: sat, jd: jd, gmst: SGP4.gstime(jd)) else { break }
            if let l = lastLon, abs(p.lon - l) > 180 { segments.append([]) }
            segments[segments.count - 1].append(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon))
            lastLon = p.lon
        }
        return segments.filter { $0.count > 1 }
    }
}

struct GlobeView: View {
    @Environment(SkyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sats: [GlobeSat] = []
    @State private var selectedID: String?
    @State private var detail: ObjectRef?
    @State private var recenter = 0

    /// Satellite groups to plot: whatever the sky layers show, or the bright ones if those are off.
    private var groups: [SatGroup] {
        let g = model.activeSatGroups
        return g.isEmpty ? [.station, .visual] : g
    }

    var body: some View {
        ZStack {
            GlobeMapView(sats: sats, selectedID: selectedID, observer: model.location.observer,
                         recenterToken: recenter,
                         designFor: { id in model.satellites.byID[id]?.design ?? .generic },
                         track: selectedID.flatMap { model.satellites.byID[$0] }.map { SatMath.groundTrack(for: $0, from: Date()) } ?? [],
                         onSelect: { id in withAnimation(.spring(duration: 0.35)) { selectedID = id } })
                .ignoresSafeArea()

            VStack(spacing: 10) {
                topBar
                Spacer(minLength: 0)
                if let id = selectedID, let info = model.info(for: id) {
                    GlanceCard(info: info, locked: true,
                               onDetails: { detail = ObjectRef(id: id) },
                               onClose: { withAnimation(.spring(duration: 0.35)) { selectedID = nil } })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                layerChips
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)   // keeps Apple Maps' attribution visible beneath
        }
        .background(Theme.void)
        .boringMode()
        .task {
            for g in groups { model.satellites.ensureLoaded(g) }
            while !Task.isCancelled {
                let work = groups.flatMap { model.satellites.catalog[$0] ?? [] }
                let now = Date()
                sats = await Task.detached(priority: .userInitiated) { SatMath.subpoints(work, date: now) }.value
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sheet(item: $detail) { ref in
            DetailView(id: ref.id).environment(model)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "globe.americas.fill").foregroundStyle(Theme.blue)
                Text("\(Fmt.number(Double(sats.count))) satellites")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .glassEffect(.regular, in: .capsule)
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { recenter += 1 } label: {
                        Image(systemName: "location.fill").font(.system(size: 16, weight: .semibold)).frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .foregroundStyle(Theme.ink)
        }
    }

    private var layerChips: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach([SkyLayer.satellites, .starlink]) { layer in
                    let on = model.layers.contains(layer)
                    Button {
                        withAnimation(.spring(duration: 0.3)) { model.toggle(layer) }
                    } label: {
                        Label(layer.title, systemImage: layer.symbol)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(on ? (layer == .starlink ? .white : Theme.ink) : Theme.ink.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(on ? .regular.tint(layer.tint.opacity(layer == .starlink ? 0.85 : 0.75)).interactive() : .regular.interactive(), in: .capsule)
                }
            }
        }
    }
}

// MARK: - Map

/// Apple's satellite-imagery Earth, which becomes a 3D globe when zoomed out.
struct GlobeMapView: UIViewRepresentable {
    var sats: [GlobeSat]
    var selectedID: String?
    var observer: Observer
    var recenterToken: Int
    var designFor: (String) -> SatDesign
    var track: [[CLLocationCoordinate2D]]
    var onSelect: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 1_500_000, maxCenterCoordinateDistance: 45_000_000)
        map.showsUserLocation = true
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        map.delegate = context.coordinator
        map.addOverlay(context.coordinator.field, level: .aboveLabels)
        map.camera = MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: observer.latitude, longitude: observer.longitude),
                                 fromDistance: 22_000_000, pitch: 0, heading: 0)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.onSelect = onSelect
        c.designFor = designFor
        c.update(sats: sats, selectedID: selectedID, track: track)
        if c.recenterToken != recenterToken {
            c.recenterToken = recenterToken
            let camera = MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: observer.latitude, longitude: observer.longitude),
                                     fromDistance: max(map.camera.centerCoordinateDistance, 6_000_000), pitch: 0, heading: 0)
            map.setCamera(camera, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (String?) -> Void
        var designFor: (String) -> SatDesign = { _ in .generic }
        weak var map: MKMapView?
        var recenterToken = 0
        let field = SatelliteFieldOverlay()
        private var fieldRenderer: SatelliteFieldRenderer?
        private var stationPins: [String: SatellitePin] = [:]
        private var selectedPin: SatellitePin?
        private var trackLines: [MKPolyline] = []
        private var trackFor: String?
        private var sats: [GlobeSat] = []

        init(onSelect: @escaping (String?) -> Void) { self.onSelect = onSelect }

        func update(sats: [GlobeSat], selectedID: String?, track: [[CLLocationCoordinate2D]]) {
            guard let map else { return }
            self.sats = sats
            field.points = sats.filter { $0.kind != .station && $0.id != selectedID }
            fieldRenderer?.setNeedsDisplay()

            // Crewed stations and the selection get real icons; everything else is a dot.
            var wanted = Set(sats.filter { $0.kind == .station }.map(\.id))
            if let selectedID { wanted.insert(selectedID) }
            for (id, pin) in stationPins where !wanted.contains(id) {
                map.removeAnnotation(pin)
                stationPins[id] = nil
            }
            for s in sats where wanted.contains(s.id) {
                if let pin = stationPins[s.id] {
                    pin.coordinate = s.coordinate
                } else {
                    let pin = SatellitePin(id: s.id, coordinate: s.coordinate, kind: s.kind, design: designFor(s.id))
                    stationPins[s.id] = pin
                    map.addAnnotation(pin)
                }
            }
            for (id, pin) in stationPins {
                let selected = id == selectedID
                if pin.isSelected != selected {
                    pin.isSelected = selected
                    (map.view(for: pin) as? SatellitePinView)?.refresh()
                }
            }

            if trackFor != selectedID {
                map.removeOverlays(trackLines)
                trackLines = track.map { MKPolyline(coordinates: $0, count: $0.count) }
                map.addOverlays(trackLines, level: .aboveLabels)
                trackFor = selectedID
            }
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let map else { return }
            let p = g.location(in: map)
            let center = map.centerCoordinate
            var best: (String, CGFloat)?
            for s in sats {
                // Skip the far side of the globe, which can still convert to a screen point.
                guard angularDistance(s.coordinate, center) < 80 else { continue }
                let q = map.convert(s.coordinate, toPointTo: map)
                let d = hypot(q.x - p.x, q.y - p.y) - (s.kind == .station ? 8 : 0)
                if d < 26, d < (best?.1 ?? .infinity) { best = (s.id, d) }
            }
            onSelect(best?.0)
        }

        private func angularDistance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            let v1 = Astro.vector(ra: a.longitude, dec: a.latitude), v2 = Astro.vector(ra: b.longitude, dec: b.latitude)
            return acos(max(-1, min(1, simd_dot(v1, v2)))) * Astro.rad
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let field = overlay as? SatelliteFieldOverlay {
                let r = SatelliteFieldRenderer(overlay: field)
                fieldRenderer = r
                return r
            }
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor(Theme.rose).withAlphaComponent(0.85)
                r.lineWidth = 2
                r.lineDashPattern = [6, 5]
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? SatellitePin else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "sat") as? SatellitePinView
                ?? SatellitePinView(annotation: pin, reuseIdentifier: "sat")
            view.annotation = pin
            view.refresh()
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let pin = annotation as? SatellitePin { onSelect(pin.id) }
            mapView.deselectAnnotation(annotation, animated: false)
        }
    }
}

final class SatellitePin: NSObject, MKAnnotation {
    let id: String
    let kind: ObjectKind
    let design: SatDesign
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var isSelected = false

    init(id: String, coordinate: CLLocationCoordinate2D, kind: ObjectKind, design: SatDesign) {
        self.id = id
        self.coordinate = coordinate
        self.kind = kind
        self.design = design
    }
}

final class SatellitePinView: MKAnnotationView {
    @MainActor func refresh() {
        guard let pin = annotation as? SatellitePin else { return }
        let design = pin.design
        let size: CGFloat = pin.kind == .station ? 44 : 34
        let renderer = ImageRenderer(content:
            ZStack {
                if pin.isSelected {
                    Circle().stroke(LinearGradient(colors: [Theme.ember, Theme.magenta, Theme.purple], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                        .frame(width: size, height: size)
                }
                Canvas { ctx, s in
                    SatelliteArt.draw(design, in: &ctx, at: CGPoint(x: s.width / 2, y: s.height / 2), halfWidth: size * 0.36,
                                      angle: -0.35, opacity: 1, detailed: true)
                }
                .frame(width: size, height: size)
            }
            .frame(width: size + 4, height: size + 4)
        )
        renderer.scale = UIScreen.main.scale
        image = renderer.uiImage
        layer.shadowColor = UIColor(pin.kind.color).cgColor
        layer.shadowRadius = 6
        layer.shadowOpacity = 0.8
        layer.shadowOffset = .zero
        zPriority = pin.isSelected ? .max : .defaultSelected
    }
}

/// Every plotted satellite as one overlay, so thousands of moving points stay cheap.
final class SatelliteFieldOverlay: NSObject, MKOverlay {
    var points: [GlobeSat] = []
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 0, longitude: 0) }
    var boundingMapRect: MKMapRect { .world }
}

final class SatelliteFieldRenderer: MKOverlayRenderer {
    private static let colors: [ObjectKind: CGColor] = [
        .satellite: UIColor(Theme.satellite).cgColor,
        .starlink: UIColor(Theme.starlink).cgColor,
        .station: UIColor(Theme.station).cgColor,
    ]

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let field = overlay as? SatelliteFieldOverlay else { return }
        let radius = 3.0 / zoomScale
        let padded = mapRect.insetBy(dx: -radius * 2, dy: -radius * 2)
        for kind in [ObjectKind.starlink, .satellite] {
            context.setFillColor(Self.colors[kind] ?? UIColor.white.cgColor)
            for s in field.points where s.kind == kind {
                let mp = MKMapPoint(s.coordinate)
                guard padded.contains(mp) else { continue }
                let p = point(for: mp)
                let r = radius * (kind == .starlink ? 0.7 : 1.15)
                context.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        }
    }
}
