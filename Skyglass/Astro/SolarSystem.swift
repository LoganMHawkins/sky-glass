import Foundation
import simd

enum Body: String, CaseIterable, Sendable {
    case sun, moon, mercury, venus, mars, jupiter, saturn, uranus, neptune
    var name: String { rawValue.capitalized }
    var id: String { "body:" + rawValue }
    var isPlanet: Bool { self != .sun && self != .moon }
}

struct BodyState: Sendable {
    static let kmPerAU = 149_597_870.7

    let body: Body
    let ra: Double            // degrees (topocentric for the Moon)
    let dec: Double
    let distanceAU: Double    // from the observer / Earth
    let heliocentricAU: Double
    let magnitude: Double
    let illumination: Double  // 0…1
    let phaseAngle: Double
    let elongation: Double    // angle from the Sun
    let moonAge: Double       // days since new moon (Moon only)
    var ringTilt: Double = 0  // Saturn's ring opening angle seen from Earth, degrees (+ = north face)

    var distanceKm: Double { distanceAU * Self.kmPerAU }
    var waxing: Bool { moonAge < 29.530588 / 2 }
}

/// Sun, Moon and planets from Paul Schlyter's low-precision orbital elements
/// (good to roughly an arcminute for the planets and a few arcminutes for the Moon).
enum SolarSystem {
    private static let deg = Astro.deg, rad = Astro.rad

    private struct Elements { var N, i, w, a, e, M: Double }

    private static func elements(_ b: Body, _ d: Double) -> Elements {
        switch b {
        case .sun:     return Elements(N: 0, i: 0, w: 282.9404 + 4.70935e-5 * d, a: 1, e: 0.016709 - 1.151e-9 * d, M: 356.0470 + 0.9856002585 * d)
        case .moon:    return Elements(N: 125.1228 - 0.0529538083 * d, i: 5.1454, w: 318.0634 + 0.1643573223 * d, a: 60.2666, e: 0.054900, M: 115.3654 + 13.0649929509 * d)
        case .mercury: return Elements(N: 48.3313 + 3.24587e-5 * d, i: 7.0047 + 5.00e-8 * d, w: 29.1241 + 1.01444e-5 * d, a: 0.387098, e: 0.205635 + 5.59e-10 * d, M: 168.6562 + 4.0923344368 * d)
        case .venus:   return Elements(N: 76.6799 + 2.46590e-5 * d, i: 3.3946 + 2.75e-8 * d, w: 54.8910 + 1.38374e-5 * d, a: 0.723330, e: 0.006773 - 1.302e-9 * d, M: 48.0052 + 1.6021302244 * d)
        case .mars:    return Elements(N: 49.5574 + 2.11081e-5 * d, i: 1.8497 - 1.78e-8 * d, w: 286.5016 + 2.92961e-5 * d, a: 1.523688, e: 0.093405 + 2.516e-9 * d, M: 18.6021 + 0.5240207766 * d)
        case .jupiter: return Elements(N: 100.4542 + 2.76854e-5 * d, i: 1.3030 - 1.557e-7 * d, w: 273.8777 + 1.64505e-5 * d, a: 5.20256, e: 0.048498 + 4.469e-9 * d, M: 19.8950 + 0.0830853001 * d)
        case .saturn:  return Elements(N: 113.6634 + 2.38980e-5 * d, i: 2.4886 - 1.081e-7 * d, w: 339.3939 + 2.97661e-5 * d, a: 9.55475, e: 0.055546 - 9.499e-9 * d, M: 316.9670 + 0.0334442282 * d)
        case .uranus:  return Elements(N: 74.0005 + 1.3978e-5 * d, i: 0.7733 + 1.9e-8 * d, w: 96.6612 + 3.0565e-5 * d, a: 19.18171 - 1.55e-8 * d, e: 0.047318 + 7.45e-9 * d, M: 142.5905 + 0.011725806 * d)
        case .neptune: return Elements(N: 131.7806 + 3.0173e-5 * d, i: 1.7700 - 2.55e-7 * d, w: 272.8461 - 6.027e-6 * d, a: 30.05826 + 3.313e-8 * d, e: 0.008606 + 2.15e-9 * d, M: 260.2471 + 0.005995147 * d)
        }
    }

    private static func eccentricAnomaly(M: Double, e: Double) -> Double {
        var E = M + e * rad * sin(M * deg) * (1 + e * cos(M * deg))
        for _ in 0..<12 {
            let dE = (E - e * rad * sin(E * deg) - M) / (1 - e * cos(E * deg))
            E -= dE
            if abs(dE) < 1e-7 { break }
        }
        return E
    }

    /// Ecliptic rectangular position for a set of elements.
    private static func orbitPosition(_ el: Elements) -> Vec3 {
        let M = Astro.norm360(el.M)
        let E = eccentricAnomaly(M: M, e: el.e)
        let xv = el.a * (cos(E * deg) - el.e)
        let yv = el.a * sqrt(1 - el.e * el.e) * sin(E * deg)
        let v = atan2(yv, xv)
        let r = sqrt(xv * xv + yv * yv)
        let N = el.N * deg, i = el.i * deg, vw = v + el.w * deg
        return Vec3(r * (cos(N) * cos(vw) - sin(N) * sin(vw) * cos(i)),
                    r * (sin(N) * cos(vw) + cos(N) * sin(vw) * cos(i)),
                    r * sin(vw) * sin(i))
    }

    private static func spherical(_ p: Vec3) -> (lon: Double, lat: Double, r: Double) {
        (Astro.norm360(atan2(p.y, p.x) * rad), atan2(p.z, sqrt(p.x * p.x + p.y * p.y)) * rad, simd_length(p))
    }

    private static func cartesian(lon: Double, lat: Double, r: Double) -> Vec3 {
        Vec3(r * cos(lon * deg) * cos(lat * deg), r * sin(lon * deg) * cos(lat * deg), r * sin(lat * deg))
    }

    private static func toEquatorial(_ p: Vec3, ecl: Double) -> Vec3 {
        Vec3(p.x, p.y * cos(ecl) - p.z * sin(ecl), p.y * sin(ecl) + p.z * cos(ecl))
    }

    private static func raDec(_ p: Vec3) -> (ra: Double, dec: Double) {
        (Astro.norm360(atan2(p.y, p.x) * rad), atan2(p.z, sqrt(p.x * p.x + p.y * p.y)) * rad)
    }

    /// Geocentric RA/Dec of the Sun only — cheap, used for satellite lighting.
    static func sun(jd: Double) -> (ra: Double, dec: Double) {
        let d = jd - 2451543.5
        return raDec(toEquatorial(orbitPosition(elements(.sun, d)), ecl: (23.4393 - 3.563e-7 * d) * deg))
    }

    static func compute(jd: Double, observer: Observer) -> [Body: BodyState] {
        let d = jd - 2451543.5
        let ecl = (23.4393 - 3.563e-7 * d) * deg
        func s(_ x: Double) -> Double { sin(x * deg) }
        func c(_ x: Double) -> Double { cos(x * deg) }
        func clampAcos(_ x: Double) -> Double { acos(max(-1, min(1, x))) * rad }
        var result: [Body: BodyState] = [:]

        // Sun
        let sunEl = elements(.sun, d)
        let sunPos = orbitPosition(sunEl)
        let sunSph = spherical(sunPos)
        let sunEq = raDec(toEquatorial(sunPos, ecl: ecl))
        result[.sun] = BodyState(body: .sun, ra: sunEq.ra, dec: sunEq.dec, distanceAU: sunSph.r, heliocentricAU: 0,
                                 magnitude: -26.74, illumination: 1, phaseAngle: 0, elongation: 0, moonAge: 0)

        // Moon, with the main perturbation terms and topocentric parallax
        let moonEl = elements(.moon, d)
        var m = spherical(orbitPosition(moonEl))
        let Ms = Astro.norm360(sunEl.M), Mm = Astro.norm360(moonEl.M)
        let Ls = Ms + sunEl.w
        let Lm = Mm + moonEl.w + moonEl.N
        let D = Lm - Ls, F = Lm - moonEl.N
        m.lon += -1.274 * s(Mm - 2 * D) + 0.658 * s(2 * D) - 0.186 * s(Ms) - 0.059 * s(2 * Mm - 2 * D)
            - 0.057 * s(Mm - 2 * D + Ms) + 0.053 * s(Mm + 2 * D) + 0.046 * s(2 * D - Ms) + 0.041 * s(Mm - Ms)
            - 0.035 * s(D) - 0.031 * s(Mm + Ms) - 0.015 * s(2 * F - 2 * D) + 0.011 * s(Mm - 4 * D)
        m.lat += -0.173 * s(F - 2 * D) - 0.055 * s(Mm - F - 2 * D) - 0.046 * s(Mm + F - 2 * D)
            + 0.033 * s(F + 2 * D) + 0.017 * s(2 * Mm + F)
        m.r += -0.58 * c(Mm - 2 * D) - 0.46 * c(2 * D)
        let moonGeo = toEquatorial(cartesian(lon: m.lon, lat: m.lat, r: m.r), ecl: ecl)
        let lst = Astro.lst(jd: jd, longitude: observer.longitude) * deg
        let phi = observer.latitude
        let gclat = (phi - 0.1924 * s(2 * phi)) * deg
        let rho = 0.99833 + 0.00167 * c(2 * phi)
        let moonTopo = moonGeo - Vec3(rho * cos(gclat) * cos(lst), rho * cos(gclat) * sin(lst), rho * sin(gclat))
        let moonEq = raDec(moonTopo)
        let moonKm = simd_length(moonTopo) * 6378.14
        let moonElong = clampAcos(c(sunSph.lon - m.lon) * c(m.lat))
        let moonFV = 180 - moonElong
        result[.moon] = BodyState(body: .moon, ra: moonEq.ra, dec: moonEq.dec, distanceAU: moonKm / BodyState.kmPerAU,
                                  heliocentricAU: sunSph.r, magnitude: -12.73 + 0.026 * moonFV + 4e-9 * pow(moonFV, 4),
                                  illumination: (1 + c(moonFV)) / 2, phaseAngle: moonFV, elongation: moonElong,
                                  moonAge: Astro.norm360(m.lon - sunSph.lon) / 360 * 29.530588)

        // Planets
        let Mj = Astro.norm360(elements(.jupiter, d).M)
        let Msat = Astro.norm360(elements(.saturn, d).M)
        let Mu = Astro.norm360(elements(.uranus, d).M)
        for body in [Body.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune] {
            var h = spherical(orbitPosition(elements(body, d)))
            switch body {
            case .jupiter:
                h.lon += -0.332 * s(2 * Mj - 5 * Msat - 67.6) - 0.056 * s(2 * Mj - 2 * Msat + 21) + 0.042 * s(3 * Mj - 5 * Msat + 21)
                    - 0.036 * s(Mj - 2 * Msat) + 0.022 * c(Mj - Msat) + 0.023 * s(2 * Mj - 3 * Msat + 52) - 0.016 * s(Mj - 5 * Msat - 69)
            case .saturn:
                h.lon += 0.812 * s(2 * Mj - 5 * Msat - 67.6) - 0.229 * c(2 * Mj - 4 * Msat - 2) + 0.119 * s(Mj - 2 * Msat - 3)
                    + 0.046 * s(2 * Mj - 6 * Msat - 69) + 0.014 * s(Mj - 3 * Msat + 32)
                h.lat += -0.020 * c(2 * Mj - 4 * Msat - 2) + 0.018 * s(2 * Mj - 6 * Msat - 49)
            case .uranus:
                h.lon += 0.040 * s(Msat - 2 * Mu + 6) + 0.035 * s(Msat - 3 * Mu + 33) - 0.015 * s(Mj - Mu + 20)
            default: break
            }
            let geo = cartesian(lon: h.lon, lat: h.lat, r: h.r) + sunPos
            let g = spherical(geo)
            let eq = raDec(toEquatorial(geo, ecl: ecl))
            let r = h.r, R = g.r, sd = sunSph.r
            let fv = clampAcos((r * r + R * R - sd * sd) / (2 * r * R))
            let elong = clampAcos((sd * sd + R * R - r * r) / (2 * sd * R))
            let base = 5 * log10(r * R)
            let mag: Double
            var ringTilt = 0.0
            switch body {
            case .mercury: mag = -0.36 + base + 0.027 * fv + 2.2e-13 * pow(fv, 6)
            case .venus:   mag = -4.34 + base + 0.013 * fv + 4.2e-7 * pow(fv, 3)
            case .mars:    mag = -1.51 + base + 0.016 * fv
            case .jupiter: mag = -9.25 + base + 0.014 * fv
            case .saturn:
                let ir = 28.06 * deg, nr = (169.51 + 3.82e-5 * d) * deg
                let B = asin(sin(g.lat * deg) * cos(ir) - cos(g.lat * deg) * sin(ir) * sin(g.lon * deg - nr))
                mag = -9.0 + base + 0.044 * fv - 2.6 * sin(abs(B)) + 1.2 * pow(sin(B), 2)
                ringTilt = B * rad
            case .uranus:  mag = -7.15 + base + 0.001 * fv
            default:       mag = -6.90 + base + 0.001 * fv
            }
            result[body] = BodyState(body: body, ra: eq.ra, dec: eq.dec, distanceAU: R, heliocentricAU: r, magnitude: mag,
                                     illumination: (1 + c(fv)) / 2, phaseAngle: fv, elongation: elong, moonAge: 0, ringTilt: ringTilt)
        }
        return result
    }
}

struct PlanetFacts {
    let type: String
    let diameter: String
    let moons: String
    let day: String
    let year: String
    let temperature: String
    let blurb: String

    static let all: [Body: PlanetFacts] = [
        .mercury: PlanetFacts(type: "Rocky planet", diameter: "4,879 km", moons: "None", day: "176 Earth days", year: "88 days", temperature: "−180 to 430 °C",
                              blurb: "The smallest planet and the closest to the Sun. It never strays far from the Sun in our sky, so look low in twilight just after sunset or before sunrise."),
        .venus: PlanetFacts(type: "Rocky planet", diameter: "12,104 km", moons: "None", day: "243 Earth days (spins backwards)", year: "225 days", temperature: "465 °C",
                            blurb: "Wrapped in brilliant clouds of sulphuric acid, Venus is the brightest thing in the night sky after the Moon — often mistaken for a plane's landing light."),
        .mars: PlanetFacts(type: "Rocky planet", diameter: "6,779 km", moons: "2 — Phobos & Deimos", day: "24 h 37 min", year: "687 days", temperature: "−63 °C average",
                           blurb: "The Red Planet gets its colour from rusty iron dust. It brightens dramatically every 26 months when Earth laps it at opposition."),
        .jupiter: PlanetFacts(type: "Gas giant", diameter: "139,820 km", moons: "95 known", day: "9 h 56 min", year: "11.9 years", temperature: "−110 °C at the cloud tops",
                              blurb: "More than twice as massive as every other planet combined. Even small binoculars show its four big Galilean moons lined up beside it."),
        .saturn: PlanetFacts(type: "Gas giant", diameter: "116,460 km", moons: "270+ known", day: "10 h 33 min", year: "29.4 years", temperature: "−140 °C at the cloud tops",
                             blurb: "Its rings are made of countless chunks of ice and rock, yet are mostly only tens of metres thick. Any small telescope will show them."),
        .uranus: PlanetFacts(type: "Ice giant", diameter: "50,724 km", moons: "28 known", day: "17 h 14 min", year: "84 years", temperature: "−195 °C",
                             blurb: "An ice giant tipped on its side, so each pole gets 42 years of sunlight then 42 years of darkness. Just visible to the eye under very dark skies."),
        .neptune: PlanetFacts(type: "Ice giant", diameter: "49,244 km", moons: "16 known", day: "16 h 6 min", year: "165 years", temperature: "−200 °C",
                              blurb: "The windiest world known, with storms over 2,000 km/h. It was found by mathematics before anyone saw it. You'll need binoculars or a telescope."),
    ]
}
