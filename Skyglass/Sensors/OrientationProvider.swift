import CoreMotion
import simd

/// Where the back camera points, expressed in the sky frame (north, west, up).
struct CameraBasis {
    var forward: Vec3
    var right: Vec3
    var up: Vec3

    static func looking(altitude: Double, azimuth: Double) -> CameraBasis {
        let f = Astro.skyVector(altitude: altitude, azimuth: azimuth)
        let r = Astro.skyVector(altitude: 0, azimuth: azimuth + 90)
        return CameraBasis(forward: f, right: r, up: simd_normalize(simd_cross(r, f)))
    }
}

/// Turns CoreMotion attitude into a camera basis, or falls back to a drag-controlled
/// virtual camera when there's no motion hardware (the Simulator).
final class OrientationProvider {
    private let motion = CMMotionManager()
    private(set) var basis = CameraBasis.looking(altitude: 25, azimuth: 180)
    private(set) var isLive = false
    private(set) var needsCalibration = false
    private(set) var usingTrueNorth = false

    var simAltitude = 25.0 { didSet { updateSimBasis() } }
    var simAzimuth = 180.0 { didSet { updateSimBasis() } }

    /// CoreMotion's quaternion convention is resolved once from gravity, so a sign mix-up
    /// can never leave the overlay mirrored.
    private var quaternionMapsDeviceToSky: Bool?

    var hasMotion: Bool { motion.isDeviceMotionAvailable }

    func start(trueNorth: Bool = true) {
        guard motion.isDeviceMotionAvailable else { isLive = false; return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let wantTrue = trueNorth && frames.contains(.xTrueNorthZVertical)
        if motion.isDeviceMotionActive {
            guard wantTrue != usingTrueNorth else { return }
            motion.stopDeviceMotionUpdates()
        }
        usingTrueNorth = wantTrue
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.showsDeviceMovementDisplay = true
        isLive = true
        motion.startDeviceMotionUpdates(using: wantTrue ? .xTrueNorthZVertical : .xMagneticNorthZVertical, to: .main) { [weak self] m, error in
            guard let self else { return }
            if error != nil, self.usingTrueNorth {
                // True north needs a location fix; use magnetic north until we have one.
                self.motion.stopDeviceMotionUpdates()
                self.start(trueNorth: false)
                return
            }
            if let m { self.update(m) }
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }

    private func updateSimBasis() {
        guard !isLive else { return }
        basis = .looking(altitude: simAltitude, azimuth: simAzimuth)
    }

    private func update(_ m: CMDeviceMotion) {
        let q = m.attitude.quaternion
        let M = simd_matrix3x3(simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w))
        let g = Vec3(m.gravity.x, m.gravity.y, m.gravity.z)

        if quaternionMapsDeviceToSky == nil, simd_length(g) > 0.5 {
            // If M maps device→sky, gravity in the device frame is Mᵀ·(0,0,-1); otherwise M·(0,0,-1).
            let gA = -Vec3(M[0][2], M[1][2], M[2][2])
            let gB = -M[2]
            let errA = simd_length(gA - g), errB = simd_length(gB - g)
            if abs(g.z) < 0.85, abs(errA - errB) > 0.25 { quaternionMapsDeviceToSky = errA < errB }
        }
        let D = (quaternionMapsDeviceToSky ?? true) ? M : M.transpose

        var f = D * Vec3(0, 0, -1)
        var r = D * Vec3(1, 0, 0)
        // Light smoothing to calm sensor jitter
        f = simd_normalize(simd_mix(basis.forward, f, Vec3(repeating: 0.35)))
        r = simd_normalize(simd_mix(basis.right, r, Vec3(repeating: 0.35)))
        r = simd_normalize(r - simd_dot(r, f) * f)
        basis = CameraBasis(forward: f, right: r, up: simd_cross(r, f))

        needsCalibration = m.magneticField.accuracy == .uncalibrated
    }
}
