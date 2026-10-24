import SwiftUI

struct ObjectInfo {
    struct Stat: Identifiable {
        let label: String
        let value: String
        var id: String { label }
        init(_ label: String, _ value: String) { self.label = label; self.value = value }
    }

    struct Section: Identifiable {
        let title: String
        let symbol: String
        let rows: [Stat]
        var id: String { title }
    }

    let id: String
    let name: String
    let subtitle: String
    let kind: ObjectKind
    var symbol: String?          // nil → drawn as a planet sphere
    let tint: Color
    var art: ObjectArt?          // custom drawing; takes over from `symbol` in glyphs
    let glance: [Stat]
    let live: [Stat]
    let blurb: String
    var sections: [Section] = []
    var tags: [String] = []
    let isUp: Bool
    var warning: String?
}

enum Fmt {
    static func deg(_ x: Double, digits: Int = 1) -> String { String(format: "%.\(digits)f°", x).replacingOccurrences(of: "-", with: "−") }
    static func az(_ x: Double) -> String { "\(Int(x.rounded()) % 360)° \(Astro.compassPoint(x))" }
    static func number(_ x: Double, digits: Int = 0) -> String { x.formatted(.number.precision(.fractionLength(digits))) }
    static func km(_ x: Double) -> String { "\(number(x)) km" }
    static func mag(_ m: Double) -> String { String(format: "%.1f", m).replacingOccurrences(of: "-", with: "−") }
    static func time(_ d: Date?) -> String { d.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—" }
    static func dayTime(_ d: Date?) -> String {
        guard let d else { return "—" }
        return Calendar.current.isDateInToday(d) ? time(d) : d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func ra(_ degrees: Double) -> String {
        let h = Astro.norm360(degrees) / 15
        let hh = Int(h), m = (h - Double(hh)) * 60, mm = Int(m)
        let ss = min(59, Int(((m - Double(mm)) * 60).rounded()))
        return String(format: "%02dh %02dm %02ds", hh, mm, ss)
    }

    static func dec(_ d: Double) -> String {
        let a = abs(d), dd = Int(a), m = min(59, Int(((a - Double(dd)) * 60).rounded()))
        return "\(d < 0 ? "−" : "+")\(dd)° \(String(format: "%02d", m))′"
    }

    static func lightTime(seconds s: Double) -> String {
        if s < 120 { return "\(number(s, digits: 2)) s" }
        if s < 7200 { return "\(number(s / 60, digits: 1)) min" }
        return "\(number(s / 3600, digits: 1)) h"
    }

    static func ly(_ ly: Double) -> String {
        ly >= 1_000_000 ? "\(number(ly / 1_000_000, digits: 1)) million ly" : "\(number(ly, digits: ly < 20 ? 1 : 0)) ly"
    }
}

extension SkyModel {
    func info(for id: String, detailed: Bool = false) -> ObjectInfo? {
        _ = tick   // re-evaluate every refresh
        if let star = StarCatalog.byID[id] { return starInfo(star, detailed) }
        if let dso = DeepSkyCatalog.byID[id] { return deepSkyInfo(dso, detailed) }
        if id.hasPrefix("body:"), let body = Body(rawValue: String(id.dropFirst(5))), let state = bodies[body] {
            return bodyInfo(body, state, detailed)
        }
        if let sat = satellites.byID[id] { return satelliteInfo(sat) }
        return nil
    }

    // MARK: Shared helpers

    private func positionRows(_ h: Horizontal, ra: Double, dec: Double) -> [ObjectInfo.Stat] {
        [.init("Altitude", Fmt.deg(h.altitude)), .init("Azimuth", Fmt.az(h.azimuth)),
         .init("Right ascension", Fmt.ra(ra)), .init("Declination", Fmt.dec(dec))]
    }

    private func upTag(_ h: Horizontal) -> String { h.altitude > 0 ? "Above horizon" : "Below horizon" }

    private func timing(_ altitudeAt: (Date) -> Double, threshold: Double = 0, rise: String = "Rises", set: String = "Sets", peak: String = "Highest") -> ObjectInfo.Section {
        let rs = Astro.riseTransitSet(from: Date(), threshold: threshold, altitudeAt: altitudeAt)
        var rows: [ObjectInfo.Stat]
        if rs.alwaysUp {
            rows = [.init("Visibility", "Never sets from here"), .init(peak, "\(Fmt.dayTime(rs.transit)) · \(Fmt.deg(rs.transitAltitude ?? 0, digits: 0))")]
        } else if rs.neverUp {
            rows = [.init("Visibility", "Doesn't rise from your latitude today")]
        } else {
            rows = [.init(rise, Fmt.dayTime(rs.rise)), .init(peak, "\(Fmt.dayTime(rs.transit)) · \(Fmt.deg(rs.transitAltitude ?? 0, digits: 0))"), .init(set, Fmt.dayTime(rs.set))]
        }
        return .init(title: "Next 24 hours", symbol: "clock", rows: rows)
    }

    private func fixedAltitude(ra raHours: Double, dec: Double) -> (Date) -> Double {
        let obs = location.observer
        return { date in
            let jd = Astro.julianDate(date)
            let p = Astro.precess(raHours: raHours, dec: dec, jd: jd)
            return Astro.horizontal(ra: p.ra, dec: p.dec, observer: obs, lst: Astro.lst(jd: jd, longitude: obs.longitude)).altitude
        }
    }

    // MARK: Stars

    private func spectralDescription(_ sp: String) -> String {
        let colour: String
        switch sp.first {
        case "O": colour = "Blue"
        case "B": colour = "Blue-white"
        case "A": colour = "White"
        case "F": colour = "Yellow-white"
        case "G": colour = "Yellow"
        case "K": colour = "Orange"
        case "M": colour = "Red"
        default: colour = "White"
        }
        let classes: [(String, String)] = [("Iab", "supergiant"), ("Ia", "supergiant"), ("Ib", "supergiant"), ("III", "giant"),
                                           ("IV", "subgiant"), ("II", "bright giant"), ("V", "main-sequence star"), ("I", "supergiant")]
        let size = classes.first { sp.contains($0.0) }?.1 ?? "star"
        return "\(colour) \(size)"
    }

    private func starInfo(_ s: Star, _ detailed: Bool) -> ObjectInfo {
        let h = horizontals[s.id] ?? Horizontal(altitude: 0, azimuth: 0)
        let p = Astro.precess(raHours: s.ra, dec: s.dec, jd: Astro.julianDate(Date()))
        let type = spectralDescription(s.spectral)
        let year = Calendar.current.component(.year, from: Date())
        let left = year - Int(s.distanceLy.rounded())
        let leftText = left > 0 ? "around \(left) CE" : "around \(-left + 1) BCE"
        let blurb = StarCatalog.blurbs[s.name]
            ?? "\(s.name) is a \(type.lowercased()) in \(s.constellation), about \(Fmt.ly(s.distanceLy)) away."

        var info = ObjectInfo(id: s.id, name: s.name, subtitle: "Star · \(s.constellation)", kind: .star, symbol: "star.fill",
                              tint: Self.starColor(s.spectral),
                              glance: [.init("Altitude", Fmt.deg(h.altitude, digits: 0)), .init("Direction", Fmt.az(h.azimuth)), .init("Brightness", "mag \(Fmt.mag(s.mag))")],
                              live: [.init("Altitude", Fmt.deg(h.altitude)), .init("Azimuth", Fmt.az(h.azimuth)),
                                     .init("Distance", Fmt.ly(s.distanceLy)), .init("Magnitude", Fmt.mag(s.mag))],
                              blurb: blurb, tags: [type, s.bayer, upTag(h)], isUp: h.altitude > 0)
        info.art = .star(Self.starColor(s.spectral))
        guard detailed else { return info }
        info.sections = [
            .init(title: "The star", symbol: "sparkle", rows: [
                .init("Designation", s.bayer), .init("Constellation", s.constellation), .init("Type", type),
                .init("Spectral class", s.spectral),
                .init("Colour", "\(StarColor.name(s.spectral)) · ≈ \(Fmt.number((StarColor.temperature(s.spectral) / 100).rounded() * 100)) K surface"),
                .init("Apparent magnitude", Fmt.mag(s.mag)),
                .init("Distance", Fmt.ly(s.distanceLy)), .init("Light you see left", leftText),
            ]),
            .init(title: "Position now", symbol: "scope", rows: positionRows(h, ra: p.ra, dec: p.dec)),
            timing(fixedAltitude(ra: s.ra, dec: s.dec)),
        ]
        return info
    }

    // MARK: Deep sky

    private func deepSkyInfo(_ d: DeepSkyObject, _ detailed: Bool) -> ObjectInfo {
        let h = horizontals[d.id] ?? Horizontal(altitude: 0, azimuth: 0)
        let p = Astro.precess(raHours: d.ra, dec: d.dec, jd: Astro.julianDate(Date()))
        let invisible = d.mag > 50
        let howTo = invisible ? "Not visible — hidden behind dust" : d.mag < 4.5 ? "Naked eye from a dark site" : d.mag < 7.5 ? "Binoculars" : "Small telescope"
        let symbol = d.type.contains("galaxy") ? "hurricane" : d.type.contains("black hole") ? "circle.dotted" : "sparkles"
        var info = ObjectInfo(id: d.id, name: d.name, subtitle: "\(d.type) · \(d.constellation)", kind: .deepSky, symbol: symbol, tint: Theme.lavender,
                              glance: [.init("Altitude", Fmt.deg(h.altitude, digits: 0)), .init("Direction", Fmt.az(h.azimuth)),
                                       .init("Brightness", invisible ? "—" : "mag \(Fmt.mag(d.mag))")],
                              live: [.init("Altitude", Fmt.deg(h.altitude)), .init("Azimuth", Fmt.az(h.azimuth)),
                                     .init("Distance", d.distance), .init("See it with", howTo)],
                              blurb: d.blurb, tags: [d.catalog, d.type, upTag(h)], isUp: h.altitude > 0)
        guard detailed else { return info }
        info.sections = [
            .init(title: "The object", symbol: "sparkles", rows: [
                .init("Catalogue", d.catalog), .init("Type", d.type), .init("Constellation", d.constellation),
                .init("Distance", d.distance), .init("Magnitude", invisible ? "—" : Fmt.mag(d.mag)), .init("Best seen with", howTo),
            ]),
            .init(title: "Position now", symbol: "scope", rows: positionRows(h, ra: p.ra, dec: p.dec)),
            timing(fixedAltitude(ra: d.ra, dec: d.dec)),
        ]
        return info
    }

    // MARK: Sun, Moon, planets

    private func moonPhaseName(_ age: Double) -> (String, String) {
        switch age {
        case ..<1.85: ("New Moon", "moonphase.new.moon")
        case ..<5.54: ("Waxing Crescent", "moonphase.waxing.crescent")
        case ..<9.23: ("First Quarter", "moonphase.first.quarter")
        case ..<12.92: ("Waxing Gibbous", "moonphase.waxing.gibbous")
        case ..<16.61: ("Full Moon", "moonphase.full.moon")
        case ..<20.30: ("Waning Gibbous", "moonphase.waning.gibbous")
        case ..<23.99: ("Last Quarter", "moonphase.last.quarter")
        case ..<27.68: ("Waning Crescent", "moonphase.waning.crescent")
        default: ("New Moon", "moonphase.new.moon")
        }
    }

    private func bodyAltitude(_ body: Body) -> (Date) -> Double {
        let obs = location.observer
        return { date in
            let jd = Astro.julianDate(date)
            guard let b = SolarSystem.compute(jd: jd, observer: obs)[body] else { return -90 }
            return Astro.horizontal(ra: b.ra, dec: b.dec, observer: obs, lst: Astro.lst(jd: jd, longitude: obs.longitude)).altitude
        }
    }

    private func bodyInfo(_ body: Body, _ b: BodyState, _ detailed: Bool) -> ObjectInfo {
        let h = horizontals[body.id] ?? Horizontal(altitude: 0, azimuth: 0)
        let tint = Self.bodyColor(body)
        let lightSeconds = b.distanceKm / 299_792.458
        let position = ObjectInfo.Section(title: "Position now", symbol: "scope", rows: positionRows(h, ra: b.ra, dec: b.dec))

        switch body {
        case .sun:
            var info = ObjectInfo(id: body.id, name: "Sun", subtitle: "Our star · G2V yellow dwarf", kind: .sun, symbol: "sun.max.fill", tint: Theme.station,
                                  glance: [.init("Altitude", Fmt.deg(h.altitude, digits: 0)), .init("Direction", Fmt.az(h.azimuth)), .init("Light time", Fmt.lightTime(seconds: lightSeconds))],
                                  live: [.init("Altitude", Fmt.deg(h.altitude)), .init("Azimuth", Fmt.az(h.azimuth)),
                                         .init("Distance", "\(Fmt.number(b.distanceKm / 1e6, digits: 1)) million km"), .init("Light travel", Fmt.lightTime(seconds: lightSeconds))],
                                  blurb: "A 4.6-billion-year-old ball of hydrogen and helium holding 99.8% of the Solar System's mass. Its light takes about eight minutes to reach you.",
                                  tags: ["Star", "G2V", upTag(h)], isUp: h.altitude > 0,
                                  warning: "Never look at the Sun directly or through binoculars or a telescope without a certified solar filter.")
            info.art = .sun
            guard detailed else { return info }
            info.sections = [
                timing(bodyAltitude(.sun), threshold: -0.27, rise: "Sunrise", set: "Sunset", peak: "Solar noon"),
                .init(title: "The Sun", symbol: "sun.max", rows: [
                    .init("Diameter", "1.39 million km"), .init("Surface", "≈ 5,500 °C"), .init("Core", "≈ 15 million °C"),
                    .init("Distance", "\(Fmt.number(b.distanceAU, digits: 4)) AU"), .init("Magnitude", Fmt.mag(b.magnitude)),
                ]),
                position,
            ]
            return info

        case .moon:
            let (phase, symbol) = moonPhaseName(b.moonAge)
            let synodic = 29.530588
            let toFull = (14.765 - b.moonAge + synodic).truncatingRemainder(dividingBy: synodic)
            let toNew = synodic - b.moonAge
            var info = ObjectInfo(id: body.id, name: "Moon", subtitle: "\(phase) · \(Int((b.illumination * 100).rounded()))% lit", kind: .moon, symbol: symbol, tint: Theme.lavender,
                                  glance: [.init("Altitude", Fmt.deg(h.altitude, digits: 0)), .init("Direction", Fmt.az(h.azimuth)), .init("Lit", "\(Int((b.illumination * 100).rounded()))%")],
                                  live: [.init("Altitude", Fmt.deg(h.altitude)), .init("Azimuth", Fmt.az(h.azimuth)),
                                         .init("Distance", Fmt.km(b.distanceKm)), .init("Phase", phase)],
                                  blurb: "Earth's only natural satellite, probably formed when a Mars-sized body slammed into the young Earth. It always shows us the same face.",
                                  tags: [phase, "Day \(Fmt.number(b.moonAge, digits: 1)) of 29.5", upTag(h)], isUp: h.altitude > 0)
            info.art = .moon(illumination: b.illumination, waxing: b.waxing)
            guard detailed else { return info }
            info.sections = [
                .init(title: "Phase", symbol: symbol, rows: [
                    .init("Phase", phase), .init("Illuminated", "\(Fmt.number(b.illumination * 100, digits: 1))%"),
                    .init("Age", "\(Fmt.number(b.moonAge, digits: 1)) days"),
                    .init("Next full moon", Date().addingTimeInterval(toFull * 86400).formatted(.dateTime.weekday(.wide).month().day())),
                    .init("Next new moon", Date().addingTimeInterval(toNew * 86400).formatted(.dateTime.weekday(.wide).month().day())),
                ]),
                timing(bodyAltitude(.moon), threshold: -0.25, rise: "Moonrise", set: "Moonset"),
                .init(title: "The Moon", symbol: "moon", rows: [
                    .init("Distance", Fmt.km(b.distanceKm)), .init("Light travel", Fmt.lightTime(seconds: lightSeconds)),
                    .init("Diameter", "3,474 km"), .init("Orbit", "27.3 days"), .init("Magnitude", Fmt.mag(b.magnitude)),
                ]),
                position,
            ]
            return info

        default:
            let facts = PlanetFacts.all[body]
            var info = ObjectInfo(id: body.id, name: body.name, subtitle: "Planet · \(facts?.type ?? "")", kind: .planet, symbol: nil, tint: tint,
                                  glance: [.init("Altitude", Fmt.deg(h.altitude, digits: 0)), .init("Direction", Fmt.az(h.azimuth)), .init("Brightness", "mag \(Fmt.mag(b.magnitude))")],
                                  live: [.init("Altitude", Fmt.deg(h.altitude)), .init("Azimuth", Fmt.az(h.azimuth)),
                                         .init("From Earth", "\(Fmt.number(b.distanceKm / 1e6, digits: 0)) M km"), .init("Light travel", Fmt.lightTime(seconds: lightSeconds))],
                                  blurb: facts?.blurb ?? "", tags: [facts?.type ?? "Planet", "mag \(Fmt.mag(b.magnitude))", upTag(h)], isUp: h.altitude > 0)
            info.art = .planet(body, ringTilt: b.ringTilt)
            guard detailed else { return info }
            var sections: [ObjectInfo.Section] = [
                .init(title: "Right now", symbol: "dot.scope", rows: [
                    .init("Distance from Earth", "\(Fmt.number(b.distanceAU, digits: 3)) AU · \(Fmt.number(b.distanceKm / 1e6, digits: 1)) million km"),
                    .init("Light travel time", Fmt.lightTime(seconds: lightSeconds)),
                    .init("Distance from Sun", "\(Fmt.number(b.heliocentricAU, digits: 3)) AU"),
                    .init("Magnitude", Fmt.mag(b.magnitude)),
                    .init("Disc lit", "\(Fmt.number(b.illumination * 100, digits: 0))%"),
                    .init("Angle from Sun", Fmt.deg(b.elongation)),
                ] + (body == .saturn ? [ObjectInfo.Stat("Ring tilt", "\(Fmt.deg(abs(b.ringTilt)))\(abs(b.ringTilt) < 7 ? " · nearly edge-on" : "")")] : [])),
                timing(bodyAltitude(body)),
            ]
            if let f = facts {
                sections.append(.init(title: "The planet", symbol: "globe", rows: [
                    .init("Type", f.type), .init("Diameter", f.diameter), .init("Moons", f.moons),
                    .init("Day length", f.day), .init("Year length", f.year), .init("Temperature", f.temperature),
                ]))
            }
            sections.append(position)
            info.sections = sections
            return info
        }
    }

    // MARK: Satellites

    func lightingText(_ s: SatState) -> String {
        let sunAlt = horizontals[Body.sun.id]?.altitude ?? 0
        if s.altitude <= 0 { return "Below horizon" }
        if !s.sunlit { return "In Earth's shadow" }
        return sunAlt < -6 ? "Sunlit · visible" : "Sunlit · daytime"
    }

    private func satelliteInfo(_ sat: Satellite) -> ObjectInfo? {
        guard let s = satellites.state(for: sat.id, observer: location.observer) else { return nil }
        let blurb: String
        let subtitle: String
        let symbol: String
        switch sat.norad {
        case 25544:
            subtitle = "Space station · crewed"
            symbol = "person.2.fill"
            blurb = "The International Space Station: a laboratory the size of a football field, crewed continuously since November 2000. It laps Earth every 92 minutes and is often the brightest thing in the sky after the Moon and Venus."
        case 48274:
            subtitle = "Space station · crewed"
            symbol = "person.2.fill"
            blurb = "China's Tiangong space station, home to rotating crews of three. Its T-shaped core and two lab modules make it easy to spot on a good pass."
        case 20580:
            subtitle = "Space telescope"
            symbol = "camera.aperture"
            blurb = "The Hubble Space Telescope, launched in 1990. It has made over 1.5 million observations and helped pin down the age of the universe."
        default:
            switch sat.group {
            case .starlink:
                subtitle = "Starlink · \(Int(sat.omm.INCLINATION.rounded()))° shell"
                symbol = "wifi"
                blurb = "Part of SpaceX's Starlink broadband constellation, thousands of flat-panel satellites in low orbit. Freshly launched batches fly in a line called a “train” before spreading out."
            case .station:
                subtitle = "Near the space stations"
                symbol = "antenna.radiowaves.left.and.right"
                blurb = "Tracked in CelesTrak's space-station group — a module, visiting spacecraft or small satellite flying close to a station."
            case .active:
                subtitle = "Active satellite\(sat.launchYear.map { " · launched \($0)" } ?? "")"
                symbol = "antenna.radiowaves.left.and.right"
                blurb = "One of thousands of working satellites in low orbit: Earth observation, communications, science and technology demos. Most are too faint to see without binoculars."
            case .visual:
                subtitle = "Bright satellite\(sat.launchYear.map { " · launched \($0)" } ?? "")"
                symbol = "antenna.radiowaves.left.and.right"
                blurb = "One of the brightest satellites in the sky — often a large spacecraft or spent rocket stage that catches sunlight after dusk or before dawn."
            }
        }
        let tleAge = (Astro.julianDate(Date()) - sat.sgp4.epochJD)
        let design = sat.design
        var info = ObjectInfo(id: sat.id, name: sat.displayName, subtitle: subtitle, kind: sat.kind, symbol: symbol, tint: sat.kind.color,
                              glance: [.init("Height", Fmt.km(s.heightKm)), .init("Speed", "\(Fmt.number(s.speedKmS, digits: 2)) km/s"),
                                       .init(s.altitude > 0 ? "Altitude" : "Status", s.altitude > 0 ? Fmt.deg(s.altitude, digits: 0) : "Below")],
                              live: [.init("Altitude", Fmt.deg(s.altitude)), .init("Azimuth", Fmt.az(s.azimuth)),
                                     .init("Range", Fmt.km(s.rangeKm)), .init("Lighting", lightingText(s))],
                              blurb: design.note.map { blurb + " " + $0 } ?? blurb, tags: [lightingText(s), design.isStarlink ? design.title : "NORAD \(sat.norad)"], isUp: s.altitude > 0)
        info.art = .satellite(design)
        info.sections = [
            .init(title: "Right now", symbol: "dot.scope", rows: [
                .init("Height above Earth", Fmt.km(s.heightKm)),
                .init("Speed", "\(Fmt.number(s.speedKmS, digits: 2)) km/s · \(Fmt.number(s.speedKmS * 3600)) km/h"),
                .init("Distance from you", Fmt.km(s.rangeKm)),
                .init("Over", "\(Fmt.number(abs(s.latitude), digits: 1))°\(s.latitude >= 0 ? "N" : "S"), \(Fmt.number(abs(s.longitude), digits: 1))°\(s.longitude >= 0 ? "E" : "W")"),
                .init("Lighting", lightingText(s)),
            ]),
            .init(title: "Orbit", symbol: "circle.dashed", rows: [
                .init("Period", "\(Fmt.number(sat.periodMinutes, digits: 1)) min"),
                .init("Orbits per day", Fmt.number(sat.omm.MEAN_MOTION, digits: 2)),
                .init("Inclination", Fmt.deg(sat.omm.INCLINATION, digits: 2)),
                .init("Perigee · apogee", "\(Fmt.number(sat.perigeeKm)) · \(Fmt.number(sat.apogeeKm)) km"),
                .init("Eccentricity", Fmt.number(sat.omm.ECCENTRICITY, digits: 5)),
            ]),
            .init(title: "Identity", symbol: "number", rows: [
                .init("Catalogue name", sat.name),
                .init("Hardware", design.title + (design.isStarlink ? " (est. from launch date)" : "")),
                .init("NORAD ID", "\(sat.norad)"),
                .init("International ID", sat.omm.OBJECT_ID ?? "—"), .init("Launched", sat.launchYear ?? "—"),
                .init("Element set age", "\(Fmt.number(tleAge, digits: 1)) days"),
            ]),
        ]
        return info
    }

    func passes(for id: String) async -> [SatPass] {
        guard let sat = satellites.byID[id] else { return [] }
        let obs = location.observer
        return await Task.detached(priority: .userInitiated) {
            SatMath.passes(for: sat, observer: obs, from: Date())
        }.value
    }

    // MARK: Search

    struct SearchItem: Identifiable {
        let id: String
        let name: String
        let detail: String
        let symbol: String
        let tint: Color
        let altitude: Double?
        let rank: Int
        var art: ObjectArt? = nil
    }

    func searchItems(for layer: SkyLayer?) -> [SearchItem] {
        var items: [SearchItem] = []
        if layer == nil || layer == .sky {
            for body in Body.allCases {
                items.append(SearchItem(id: body.id, name: body.name, detail: body == .sun ? "Star" : body == .moon ? "Moon" : "Planet",
                                        symbol: body == .sun ? "sun.max.fill" : body == .moon ? "moon.fill" : "circle.fill",
                                        tint: Self.bodyColor(body), altitude: horizontals[body.id]?.altitude, rank: 0,
                                        art: bodies[body].map { b in body == .sun ? .sun : body == .moon ? .moon(illumination: b.illumination, waxing: b.waxing) : .planet(body, ringTilt: b.ringTilt) }))
            }
            for d in DeepSkyCatalog.objects {
                items.append(SearchItem(id: d.id, name: d.name, detail: "\(d.catalog) · \(d.type)", symbol: "sparkles", tint: Theme.lavender,
                                        altitude: horizontals[d.id]?.altitude, rank: 1))
            }
            for s in StarCatalog.stars {
                items.append(SearchItem(id: s.id, name: s.name, detail: "\(s.bayer) · \(s.constellation)", symbol: "star.fill",
                                        tint: Self.starColor(s.spectral), altitude: horizontals[s.id]?.altitude, rank: 2,
                                        art: .star(Self.starColor(s.spectral))))
            }
        }
        for group in SatGroup.allCases {
            let layerForGroup: SkyLayer = group == .starlink ? .starlink : .satellites
            guard layer == nil || layer == layerForGroup else { continue }
            for sat in satellites.catalog[group] ?? [] {
                items.append(SearchItem(id: sat.id, name: sat.displayName, detail: "NORAD \(sat.norad)",
                                        symbol: sat.kind == .station ? "person.2.fill" : sat.kind == .starlink ? "wifi" : "antenna.radiowaves.left.and.right",
                                        tint: sat.kind.color, altitude: satellites.states[sat.id]?.altitude ?? -90,
                                        rank: sat.kind == .station ? 0 : (group == .active ? 4 : 3), art: .satellite(sat.design)))
            }
        }
        return items.sorted {
            let up0 = ($0.altitude ?? -90) > 0, up1 = ($1.altitude ?? -90) > 0
            if up0 != up1 { return up0 }
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            return $0.name < $1.name
        }
    }
}
