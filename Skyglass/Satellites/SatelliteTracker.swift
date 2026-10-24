import Foundation
import SwiftUI
import simd

enum SatGroup: String, CaseIterable, Sendable {
    case station, visual, starlink, active   // active = every other working satellite (opt-in)

    var celestrakGroup: String {
        switch self {
        case .station: "stations"
        case .visual: "visual"
        case .starlink: "starlink"
        case .active: "active"
        }
    }

    var title: String {
        switch self {
        case .station: "space stations"
        case .visual: "bright satellites"
        case .starlink: "Starlink"
        case .active: "other active satellites"
        }
    }
}

/// CelesTrak General Perturbations record (OMM JSON).
struct OMM: Codable, Sendable {
    let OBJECT_NAME: String
    let OBJECT_ID: String?
    let EPOCH: String
    let MEAN_MOTION: Double
    let ECCENTRICITY: Double
    let INCLINATION: Double
    let RA_OF_ASC_NODE: Double
    let ARG_OF_PERICENTER: Double
    let MEAN_ANOMALY: Double
    let NORAD_CAT_ID: Int
    let BSTAR: Double
}

struct Satellite: Identifiable, Sendable {
    static let crewedStations: [Int: String] = [25544: "ISS", 48274: "Tiangong"]

    let id: String
    let norad: Int
    let name: String
    let displayName: String
    let group: SatGroup
    let kind: ObjectKind
    let omm: OMM
    let sgp4: SGP4

    init?(omm: OMM, group: SatGroup) {
        guard let jd = Astro.julianDate(iso: omm.EPOCH),
              let model = try? SGP4(epochJD: jd, meanMotion: omm.MEAN_MOTION, eccentricity: omm.ECCENTRICITY,
                                    inclination: omm.INCLINATION, raan: omm.RA_OF_ASC_NODE,
                                    argPerigee: omm.ARG_OF_PERICENTER, meanAnomaly: omm.MEAN_ANOMALY, bstar: omm.BSTAR)
        else { return nil }
        if group != .starlink, omm.OBJECT_NAME.uppercased().hasPrefix("STARLINK") { return nil }
        self.id = "sat:\(omm.NORAD_CAT_ID)"
        self.norad = omm.NORAD_CAT_ID
        self.name = omm.OBJECT_NAME
        self.group = group
        self.omm = omm
        self.sgp4 = model
        if let station = Self.crewedStations[omm.NORAD_CAT_ID] {
            displayName = station
            kind = .station
        } else {
            displayName = omm.OBJECT_NAME.capitalized(with: nil)
            kind = group == .starlink ? .starlink : .satellite
        }
    }

    var launchYear: String? {
        guard let id = omm.OBJECT_ID, id.count >= 4 else { return nil }
        return String(id.prefix(4))
    }
    var periodMinutes: Double { 1440 / omm.MEAN_MOTION }
    var semiMajorAxisKm: Double {
        let n = omm.MEAN_MOTION * 2 * .pi / 86400
        return pow(398600.4418 / (n * n), 1.0 / 3.0)
    }
    var perigeeKm: Double { semiMajorAxisKm * (1 - omm.ECCENTRICITY) - SatMath.earthRadius }
    var apogeeKm: Double { semiMajorAxisKm * (1 + omm.ECCENTRICITY) - SatMath.earthRadius }
}

struct SatState: Sendable {
    let date: Date
    let vector: Vec3       // sky frame unit vector
    let velocity: Vec3     // change of that vector per second
    let altitude: Double
    let azimuth: Double
    let rangeKm: Double
    let heightKm: Double
    let speedKmS: Double
    let sunlit: Bool
    let latitude: Double
    let longitude: Double
}

struct SatPass: Identifiable, Sendable {
    let id = UUID()
    let rise: Date
    let riseAzimuth: Double
    let peak: Date
    let peakAltitude: Double
    let set: Date
    let setAzimuth: Double
    let visible: Bool
}

enum SatMath {
    static let earthRadius = 6378.137
    static let omegaEarth = 7.292115e-5

    static func observerECEF(_ o: Observer) -> Vec3 {
        let a = earthRadius, f = 1 / 298.257223563, e2 = f * (2 - f)
        let lat = o.latitude * Astro.deg, lon = o.longitude * Astro.deg, h = o.elevation / 1000
        let n = a / sqrt(1 - e2 * sin(lat) * sin(lat))
        return Vec3((n + h) * cos(lat) * cos(lon), (n + h) * cos(lat) * sin(lon), (n * (1 - e2) + h) * sin(lat))
    }

    static func sunDirection(jd: Double) -> Vec3 {
        let s = SolarSystem.sun(jd: jd)
        return Astro.vector(ra: s.ra, dec: s.dec)
    }

    static func state(for sat: Satellite, date: Date, observer o: Observer, obsECEF: Vec3, gmst: Double, sunDir: Vec3) -> SatState? {
        let jd = Astro.julianDate(date)
        guard let (r, v) = try? sat.sgp4.propagate(minutes: (jd - sat.sgp4.epochJD) * 1440) else { return nil }
        let cg = cos(gmst), sg = sin(gmst)
        let rE = Vec3(cg * r.x + sg * r.y, -sg * r.x + cg * r.y, r.z)
        let vE = Vec3(cg * v.x + sg * v.y, -sg * v.x + cg * v.y, v.z) - simd_cross(Vec3(0, 0, omegaEarth), rE)
        let lat = o.latitude * Astro.deg, lon = o.longitude * Astro.deg
        func enu(_ p: Vec3) -> Vec3 {
            Vec3(-sin(lon) * p.x + cos(lon) * p.y,
                 -sin(lat) * cos(lon) * p.x - sin(lat) * sin(lon) * p.y + cos(lat) * p.z,
                 cos(lat) * cos(lon) * p.x + cos(lat) * sin(lon) * p.y + sin(lat) * p.z)
        }
        let t = enu(rE - obsECEF)
        let range = simd_length(t)
        let unit = t / range
        let tv = enu(vE)
        let dUnit = (tv - simd_dot(tv, unit) * unit) / range
        // ENU → sky frame (north, west, up)
        let sky = Vec3(unit.y, -unit.x, unit.z)
        let skyVel = Vec3(dUnit.y, -dUnit.x, dUnit.z)
        let along = simd_dot(r, sunDir)
        let sunlit = along > 0 || simd_length(r - along * sunDir) > earthRadius
        return SatState(date: date, vector: sky, velocity: skyVel,
                        altitude: asin(max(-1, min(1, unit.z))) * Astro.rad,
                        azimuth: Astro.norm360(atan2(unit.x, unit.y) * Astro.rad),
                        rangeKm: range, heightKm: simd_length(r) - earthRadius, speedKmS: simd_length(v), sunlit: sunlit,
                        latitude: atan2(rE.z, sqrt(rE.x * rE.x + rE.y * rE.y)) * Astro.rad,
                        longitude: atan2(rE.y, rE.x) * Astro.rad)
    }

    static func state(for sat: Satellite, date: Date, observer: Observer) -> SatState? {
        let jd = Astro.julianDate(date)
        return state(for: sat, date: date, observer: observer, obsECEF: observerECEF(observer),
                     gmst: SGP4.gstime(jd), sunDir: sunDirection(jd: jd))
    }

    static func sunAltitude(jd: Double, observer: Observer) -> Double {
        let s = SolarSystem.sun(jd: jd)
        return Astro.horizontal(ra: s.ra, dec: s.dec, observer: observer, lst: Astro.lst(jd: jd, longitude: observer.longitude)).altitude
    }

    /// Steps forward 20 s at a time to find upcoming passes peaking above 10°.
    static func passes(for sat: Satellite, observer: Observer, from start: Date, hours: Double = 48, limit: Int = 6) -> [SatPass] {
        let obsECEF = observerECEF(observer)
        let step: TimeInterval = 20
        var result: [SatPass] = []
        var prev: SatState?
        var rise: (Date, Double)?
        var peak: SatState?
        var visible = false
        var t = start
        while t < start.addingTimeInterval(hours * 3600) && result.count < limit {
            let jd = Astro.julianDate(t)
            guard let s = state(for: sat, date: t, observer: observer, obsECEF: obsECEF, gmst: SGP4.gstime(jd), sunDir: sunDirection(jd: jd)) else { break }
            if rise == nil, s.altitude > 0 {
                var at = t
                if let p = prev, p.altitude < 0 { at = t.addingTimeInterval(-step * s.altitude / (s.altitude - p.altitude)) }
                rise = (at, s.azimuth)
                peak = s
                visible = false
            }
            if let r = rise {
                if s.altitude > (peak?.altitude ?? -90) { peak = s }
                if !visible, s.sunlit, sunAltitude(jd: jd, observer: observer) < -6 { visible = true }
                if s.altitude <= 0, let pk = peak {
                    if pk.altitude >= 10 {
                        result.append(SatPass(rise: r.0, riseAzimuth: r.1, peak: pk.date, peakAltitude: pk.altitude,
                                              set: t, setAzimuth: s.azimuth, visible: visible))
                    }
                    rise = nil
                    peak = nil
                }
            }
            prev = s
            t = t.addingTimeInterval(step)
        }
        return result
    }

    struct Batch: Sendable {
        var states: [String: SatState] = [:]
        var points: [SatGroup: [SkyPoint]] = [:]
        var counts: [SatGroup: Int] = [:]
    }

    static func propagateAll(_ work: [(SatGroup, [Satellite])], pinned: Satellite?, observer: Observer, date: Date, sunAltitude: Double) -> Batch {
        let jd = Astro.julianDate(date)
        let obsECEF = observerECEF(observer)
        let gmst = SGP4.gstime(jd)
        let sunDir = sunDirection(jd: jd)
        let dark = sunAltitude < -6
        let epoch = date.timeIntervalSinceReferenceDate
        var batch = Batch()
        for (group, sats) in work {
            var pts: [SkyPoint] = []
            var up = 0
            let minAlt = group == .starlink ? 0.0 : -10.0
            for sat in sats {
                guard let s = state(for: sat, date: date, observer: observer, obsECEF: obsECEF, gmst: gmst, sunDir: sunDir) else { continue }
                if s.altitude > 0 { up += 1 }
                guard s.altitude > minAlt || sat.id == pinned?.id else { continue }
                batch.states[sat.id] = s
                pts.append(SkyPoint(id: sat.id, kind: sat.kind, vector: s.vector, velocity: s.velocity, epoch: epoch,
                                    radius: sat.kind.baseRadius, color: sat.kind.color,
                                    label: sat.kind == .station ? sat.displayName : nil,
                                    altitude: s.altitude, dimmed: !(s.sunlit && dark), priority: sat.kind.priority))
            }
            batch.points[group] = pts
            batch.counts[group] = up
        }
        if let pinned, batch.states[pinned.id] == nil,
           let s = state(for: pinned, date: date, observer: observer, obsECEF: obsECEF, gmst: gmst, sunDir: sunDir) {
            batch.states[pinned.id] = s
        }
        return batch
    }
}

/// Downloads CelesTrak element sets, caches them and propagates the whole fleet once a second.
@Observable
final class SatelliteTracker {
    enum LoadState: Equatable { case loading, ready, failed }

    private(set) var loadState: [SatGroup: LoadState] = [:]
    private(set) var aboveHorizon: [SatGroup: Int] = [:]
    private(set) var totals: [SatGroup: Int] = [:]

    @ObservationIgnored private(set) var catalog: [SatGroup: [Satellite]] = [:]
    @ObservationIgnored private(set) var byID: [String: Satellite] = [:]
    @ObservationIgnored private(set) var states: [String: SatState] = [:]
    @ObservationIgnored private(set) var points: [SatGroup: [SkyPoint]] = [:]
    @ObservationIgnored private var busy = false

    func ensureLoaded(_ group: SatGroup) {
        guard loadState[group] == nil || loadState[group] == .failed else { return }
        loadState[group] = .loading
        Task.detached(priority: .utility) {
            let sats = try? await Self.fetch(group)
            await MainActor.run {
                guard let sats, !sats.isEmpty else { self.loadState[group] = .failed; return }
                // The curated groups take precedence over the catch-all active group, whichever loads first.
                let fresh = sats.filter { s in
                    guard let existing = self.byID[s.id] else { return true }
                    return existing.group == .active && group != .active
                }
                if group != .active, var others = self.catalog[.active] {
                    let taken = Set(fresh.map(\.id))
                    others.removeAll { taken.contains($0.id) }
                    self.catalog[.active] = others
                    self.totals[.active] = others.count
                }
                self.catalog[group] = fresh
                for s in fresh { self.byID[s.id] = s }
                self.totals[group] = fresh.count
                self.loadState[group] = .ready
            }
        }
    }

    func retryFailed() {
        for (group, state) in loadState where state == .failed { ensureLoaded(group) }
    }

    func propagate(groups: Set<SatGroup>, observer: Observer, date: Date, pinned: String?, sunAltitude: Double) {
        guard !busy else { return }
        let work = groups.compactMap { g in catalog[g].map { (g, $0) } }
        let pinnedSat = pinned.flatMap { byID[$0] }
        guard !work.isEmpty || pinnedSat != nil else {
            if !points.isEmpty { points = [:] }
            return
        }
        busy = true
        Task.detached(priority: .userInitiated) {
            let batch = SatMath.propagateAll(work, pinned: pinnedSat, observer: observer, date: date, sunAltitude: sunAltitude)
            await MainActor.run {
                self.states = batch.states
                self.points = batch.points
                for g in SatGroup.allCases where self.aboveHorizon[g] != batch.counts[g] {
                    self.aboveHorizon[g] = batch.counts[g]
                }
                self.busy = false
            }
        }
    }

    func state(for id: String, observer: Observer) -> SatState? {
        if let s = states[id], abs(s.date.timeIntervalSinceNow) < 3 { return s }
        guard let sat = byID[id] else { return nil }
        return SatMath.state(for: sat, date: Date(), observer: observer)
    }

    private static func fetch(_ group: SatGroup) async throws -> [Satellite] {
        if group == .active {
            // Shares the one download with the Starlink fallback.
            let all = try await ActiveCatalog.shared.records()
            return all.filter { group.matchesFallback($0) }.compactMap { Satellite(omm: $0, group: group) }
        }
        if let records = try? await loadRecords(group: group.celestrakGroup, cacheName: group.rawValue) {
            return records.compactMap { Satellite(omm: $0, group: group) }
        }
        // CelesTrak answers each query only once per IP until its data next updates (about every 2 hours)
        // and returns 403 otherwise, so a phone sharing a network with another downloader can get nothing.
        // Fall back to the full active catalogue, which is a separate query, and filter it.
        let all = try await ActiveCatalog.shared.records()
        let sats = all.filter { group.matchesFallback($0) }.compactMap { Satellite(omm: $0, group: group) }
        guard !sats.isEmpty else { throw URLError(.badServerResponse) }
        return sats
    }

    /// Base URL of the caching proxy in `proxy/` (Info.plist `SkyglassProxyURL`). The `SKYGLASS_PROXY_URL`
    /// environment variable overrides it, e.g. to point a Simulator run at `wrangler dev`.
    private static let proxyBase: URL? = {
        let value = ProcessInfo.processInfo.environment["SKYGLASS_PROXY_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SkyglassProxyURL") as? String
        guard let value, !value.isEmpty else { return nil }
        return URL(string: value)
    }()

    /// Fresh cache (< 6 h) → proxy → CelesTrak → stale cache, in that order.
    fileprivate static func loadRecords(group: String, cacheName: String) async throws -> [OMM] {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("celestrak-\(cacheName).json")
        if let mod = (try? FileManager.default.attributesOfItem(atPath: cache.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(mod) < 6 * 3600,
           let data = try? Data(contentsOf: cache),
           let records = try? JSONDecoder().decode([OMM].self, from: data) {
            return records
        }
        var sources: [URL] = []
        if let proxyBase { sources.append(proxyBase.appendingPathComponent("gp/\(group).json")) }
        sources.append(URL(string: "https://celestrak.org/NORAD/elements/gp.php?GROUP=\(group)&FORMAT=json")!)
        var lastError: Error = URLError(.badServerResponse)
        for url in sources {
            do {
                let (records, data) = try await download(url)
                try? data.write(to: cache, options: .atomic)
                return records
            } catch {
                lastError = error
            }
        }
        guard let data = try? Data(contentsOf: cache),
              let records = try? JSONDecoder().decode([OMM].self, from: data) else { throw lastError }
        return records
    }

    private static func download(_ url: URL) async throws -> ([OMM], Data) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.first == UInt8(ascii: "[") else {
            throw URLError(.badServerResponse)
        }
        return (try JSONDecoder().decode([OMM].self, from: data), data)
    }
}

/// Shares one download of CelesTrak's active catalogue between every group that needs the fallback.
private actor ActiveCatalog {
    static let shared = ActiveCatalog()
    private var task: Task<[OMM], Error>?

    func records() async throws -> [OMM] {
        if let task { return try await task.value }
        let t = Task { try await SatelliteTracker.loadRecords(group: "active", cacheName: "active") }
        task = t
        do {
            return try await t.value
        } catch {
            task = nil
            throw error
        }
    }
}

extension SatGroup {
    /// Picks this group's satellites out of the active catalogue when the group query is refused.
    func matchesFallback(_ omm: OMM) -> Bool {
        let name = omm.OBJECT_NAME.uppercased()
        switch self {
        case .starlink:
            return name.hasPrefix("STARLINK")
        case .station:
            let vehicles = ["ISS ", "CSS ", "SOYUZ", "PROGRESS", "DRAGON", "CYGNUS", "TIANZHOU", "SHENZHOU", "HTV"]
            return Satellite.crewedStations[omm.NORAD_CAT_ID] != nil || vehicles.contains { name.hasPrefix($0) }
        case .visual:
            // Hubble plus large, bright Earth-observation and weather satellites.
            return [20580, 25994, 27424, 39084, 49260, 28654, 33591, 43013].contains(omm.NORAD_CAT_ID)
        case .active:
            return !name.hasPrefix("STARLINK")
        }
    }
}
