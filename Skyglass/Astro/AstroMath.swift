import Foundation
import simd

typealias Vec3 = SIMD3<Double>

struct Observer: Equatable, Sendable {
    var latitude: Double    // degrees, north positive
    var longitude: Double   // degrees, east positive
    var elevation: Double = 0 // metres
}

struct Horizontal: Sendable {
    var altitude: Double
    var azimuth: Double
    var vector: Vec3 { Astro.skyVector(altitude: altitude, azimuth: azimuth) }
}

struct RiseSet {
    var rise: Date?
    var transit: Date?
    var transitAltitude: Double?
    var set: Date?
    var alwaysUp = false
    var neverUp = false
}

enum Astro {
    static let deg = Double.pi / 180
    static let rad = 180 / Double.pi

    static func julianDate(_ date: Date) -> Double { date.timeIntervalSince1970 / 86400 + 2440587.5 }

    static func julianDate(year: Int, month: Int, day: Double) -> Double {
        var y = year, m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(Double(y) / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + day + b - 1524.5
    }

    /// Parses CelesTrak's `2026-10-23T05:21:44.123456` epochs (always UTC).
    static func julianDate(iso: String) -> Double? {
        let parts = iso.replacingOccurrences(of: "Z", with: "").split(separator: "T")
        guard parts.count == 2 else { return nil }
        let d = parts[0].split(separator: "-").compactMap { Int($0) }
        let t = parts[1].split(separator: ":").compactMap { Double($0) }
        guard d.count == 3, t.count == 3 else { return nil }
        return julianDate(year: d[0], month: d[1], day: Double(d[2]) + (t[0] + t[1] / 60 + t[2] / 3600) / 24)
    }

    static func norm360(_ x: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Greenwich mean sidereal time, degrees.
    static func gmst(jd: Double) -> Double {
        let t = (jd - 2451545.0) / 36525
        return norm360(280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t - t * t * t / 38710000)
    }

    static func lst(jd: Double, longitude: Double) -> Double { norm360(gmst(jd: jd) + longitude) }

    static func horizontal(ra: Double, dec: Double, observer: Observer, lst: Double, refraction: Bool = true) -> Horizontal {
        let h = (lst - ra) * deg, d = dec * deg, p = observer.latitude * deg
        let east = -cos(d) * sin(h)
        let north = sin(d) * cos(p) - cos(d) * cos(h) * sin(p)
        let up = sin(d) * sin(p) + cos(d) * cos(h) * cos(p)
        var alt = asin(max(-1, min(1, up))) * rad
        if refraction { alt += refractionCorrection(alt) }
        return Horizontal(altitude: alt, azimuth: norm360(atan2(east, north) * rad))
    }

    /// Bennett's formula, degrees.
    static func refractionCorrection(_ alt: Double) -> Double {
        guard alt > -1.5 else { return 0 }
        return max(0, 1.02 / tan((alt + 10.3 / (alt + 5.11)) * deg)) / 60
    }

    /// Sky frame used everywhere: x = true north, y = west, z = up.
    /// This matches CoreMotion's `.xTrueNorthZVertical` reference frame.
    static func skyVector(altitude: Double, azimuth: Double) -> Vec3 {
        let a = altitude * deg, z = azimuth * deg
        return Vec3(cos(a) * cos(z), -cos(a) * sin(z), sin(a))
    }

    static func horizontal(from v: Vec3) -> Horizontal {
        let n = simd_normalize(v)
        return Horizontal(altitude: asin(max(-1, min(1, n.z))) * rad, azimuth: norm360(atan2(-n.y, n.x) * rad))
    }

    static func vector(ra: Double, dec: Double) -> Vec3 {
        Vec3(cos(dec * deg) * cos(ra * deg), cos(dec * deg) * sin(ra * deg), sin(dec * deg))
    }

    /// Low-precision precession from J2000 to the given date. Plenty for an overlay.
    static func precess(raHours: Double, dec: Double, jd: Double) -> (ra: Double, dec: Double) {
        let years = (jd - 2451545.0) / 365.25
        let ra = raHours * 15
        let dRA = (3.075 + 1.336 * sin(ra * deg) * tan(max(-89.5, min(89.5, dec)) * deg)) * years / 240
        let dDec = 20.04 * cos(ra * deg) * years / 3600
        return (norm360(ra + dRA), dec + dDec)
    }

    static func compassPoint(_ az: Double) -> String {
        let pts = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        return pts[Int((norm360(az) + 11.25) / 22.5) % 16]
    }

    /// Scans forward in 10-minute steps for the next rise, highest point and set.
    static func riseTransitSet(from start: Date, hours: Double = 24, threshold: Double = 0, altitudeAt: (Date) -> Double) -> RiseSet {
        var result = RiseSet()
        let step: TimeInterval = 600
        let steps = Int(hours * 3600 / step)
        var prevDate = start
        var prevAlt = altitudeAt(start)
        var maxAlt = prevAlt, maxDate = start
        var minAlt = prevAlt
        for i in 1...steps {
            let d = start.addingTimeInterval(Double(i) * step)
            let a = altitudeAt(d)
            if a > maxAlt { maxAlt = a; maxDate = d }
            minAlt = min(minAlt, a)
            let f = (threshold - prevAlt) / (a - prevAlt)
            if prevAlt < threshold, a >= threshold, result.rise == nil {
                result.rise = prevDate.addingTimeInterval(step * f)
            } else if prevAlt >= threshold, a < threshold, result.set == nil {
                result.set = prevDate.addingTimeInterval(step * f)
            }
            prevDate = d
            prevAlt = a
        }
        result.transit = maxDate
        result.transitAltitude = maxAlt
        result.alwaysUp = minAlt > threshold
        result.neverUp = maxAlt < threshold
        return result
    }
}
