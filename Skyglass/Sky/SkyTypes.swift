import SwiftUI
import simd

enum SkyLayer: String, CaseIterable, Identifiable {
    case sky, satellites, starlink
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sky: "Sky"
        case .satellites: "Satellites"
        case .starlink: "Starlink"
        }
    }

    var symbol: String {
        switch self {
        case .sky: "sparkles"
        case .satellites: "antenna.radiowaves.left.and.right"
        case .starlink: "point.3.filled.connected.trianglepath.dotted"
        }
    }

    var tint: Color {
        switch self {
        case .sky: Theme.magenta
        case .satellites: Theme.purple
        case .starlink: Theme.starlink
        }
    }

    var groups: [SatGroup] {
        switch self {
        case .sky: []
        case .satellites: [.station, .visual]
        case .starlink: [.starlink]
        }
    }
}

enum ObjectKind: Sendable {
    case star, deepSky, sun, moon, planet, station, satellite, starlink

    var layer: SkyLayer {
        switch self {
        case .star, .deepSky, .sun, .moon, .planet: .sky
        case .station, .satellite: .satellites
        case .starlink: .starlink
        }
    }

    var color: Color {
        switch self {
        case .station: Theme.station
        case .satellite: Theme.satellite
        case .starlink: Theme.starlink
        case .deepSky: Theme.lavender
        default: .white
        }
    }

    var baseRadius: CGFloat {
        switch self {
        case .station: 4.5
        case .satellite: 2.6
        case .starlink: 1.7
        default: 2
        }
    }

    var priority: Int {
        switch self {
        case .sun, .moon, .planet: 5
        case .station: 4
        case .deepSky, .satellite: 2
        case .star: 1
        case .starlink: 0
        }
    }
}

/// Everything the renderer needs for one dot on the sky, refreshed about once a second.
struct SkyPoint: Sendable {
    let id: String
    let kind: ObjectKind
    var vector: Vec3
    var velocity: Vec3 = .zero          // per second, for smooth satellite motion between updates
    var epoch: TimeInterval = 0         // timeIntervalSinceReferenceDate of `vector`
    var radius: CGFloat
    var color: Color
    var label: String?
    var altitude: Double
    var dimmed = false
    var priority: Int

    func vector(at time: TimeInterval) -> Vec3 {
        velocity == .zero ? vector : simd_normalize(vector + velocity * (time - epoch))
    }
}

struct HitTarget {
    let id: String
    let point: CGPoint
    let priority: Int
}

struct SkyProjector {
    let basis: CameraBasis
    let focal: Double
    let center: CGPoint

    func camera(_ v: Vec3) -> Vec3 {
        Vec3(simd_dot(v, basis.right), simd_dot(v, basis.up), simd_dot(v, basis.forward))
    }

    func project(_ v: Vec3, minZ: Double = 0.15) -> CGPoint? {
        let c = camera(v)
        guard c.z > minZ else { return nil }
        return CGPoint(x: center.x + CGFloat(c.x / c.z * focal), y: center.y - CGFloat(c.y / c.z * focal))
    }
}
