import Foundation

/// Near-earth SGP4 propagator, after Vallado et al., "Revisiting Spacetrack Report #3" (2006).
/// Deep-space objects (period ≥ 225 min) are rejected; everything this app tracks is in low orbit.
/// Output is in the TEME frame: kilometres and km/s.
final class SGP4: @unchecked Sendable {
    enum Failure: Error { case deepSpace, invalidElements, decayed }

    static let mu = 398600.8
    static let earthRadius = 6378.135
    static let xke = 60.0 / sqrt(earthRadius * earthRadius * earthRadius / mu)
    static let j2 = 0.001082616
    static let j3 = -0.00000253881
    static let j4 = -0.00000165597
    static let j3oj2 = j3 / j2
    static let twoPi = 2 * Double.pi
    static let x2o3 = 2.0 / 3.0

    let epochJD: Double
    let bstar: Double
    let ecco: Double
    let argpo: Double
    let inclo: Double
    let mo: Double
    let no: Double
    let nodeo: Double

    private var isimp = false
    private var aycof = 0.0, con41 = 0.0, cc1 = 0.0, cc4 = 0.0, cc5 = 0.0
    private var d2 = 0.0, d3 = 0.0, d4 = 0.0, delmo = 0.0, eta = 0.0
    private var argpdot = 0.0, omgcof = 0.0, sinmao = 0.0
    private var t2cof = 0.0, t3cof = 0.0, t4cof = 0.0, t5cof = 0.0
    private var x1mth2 = 0.0, x7thm1 = 0.0, mdot = 0.0, nodedot = 0.0
    private var xlcof = 0.0, xmcof = 0.0, nodecf = 0.0

    init(epochJD: Double, meanMotion revPerDay: Double, eccentricity: Double, inclination: Double,
         raan: Double, argPerigee: Double, meanAnomaly: Double, bstar: Double) throws {
        let d2r = Double.pi / 180
        let re = Self.earthRadius, j2 = Self.j2, j4 = Self.j4, j3oj2 = Self.j3oj2, x2o3 = Self.x2o3
        let noKozai = revPerDay * Self.twoPi / 1440
        guard noKozai > 0, eccentricity >= 0, eccentricity < 1 else { throw Failure.invalidElements }

        let incl = inclination * d2r
        let cosio = cos(incl), cosio2 = cosio * cosio
        let eccsq = eccentricity * eccentricity, omeosq = 1 - eccsq, rteosq = sqrt(omeosq)

        // Recover the original (un-Kozai'd) mean motion
        let ak = pow(Self.xke / noKozai, x2o3)
        let d1 = 0.75 * j2 * (3 * cosio2 - 1) / (rteosq * omeosq)
        var del = d1 / (ak * ak)
        let adel = ak * (1 - del * del - del * (1.0 / 3.0 + 134 * del * del / 81))
        del = d1 / (adel * adel)
        let noUnkozai = noKozai / (1 + del)

        self.epochJD = epochJD
        self.bstar = bstar
        ecco = eccentricity
        inclo = incl
        nodeo = raan * d2r
        argpo = argPerigee * d2r
        mo = meanAnomaly * d2r
        no = noUnkozai

        guard Self.twoPi / no < 225 else { throw Failure.deepSpace }

        let ao = pow(Self.xke / no, x2o3)
        let sinio = sin(inclo)
        let po = ao * omeosq
        let con42 = 1 - 5 * cosio2
        con41 = -con42 - cosio2 - cosio2
        let posq = po * po
        let rp = ao * (1 - ecco)

        isimp = rp < (220 / re + 1)
        var sfour = 78.0 / re + 1.0
        var qzms24 = pow((120.0 - 78.0) / re, 4)
        let perige = (rp - 1) * re
        if perige < 156 {
            sfour = perige - 78
            if perige < 98 { sfour = 20 }
            qzms24 = pow((120 - sfour) / re, 4)
            sfour = sfour / re + 1
        }
        let pinvsq = 1 / posq
        let tsi = 1 / (ao - sfour)
        eta = ao * ecco * tsi
        let etasq = eta * eta
        let eeta = ecco * eta
        let psisq = abs(1 - etasq)
        let coef = qzms24 * pow(tsi, 4)
        let coef1 = coef / pow(psisq, 3.5)
        let cc2 = coef1 * no * (ao * (1 + 1.5 * etasq + eeta * (4 + etasq))
            + 0.375 * j2 * tsi / psisq * con41 * (8 + 3 * etasq * (8 + etasq)))
        cc1 = bstar * cc2
        var cc3 = 0.0
        if ecco > 1e-4 { cc3 = -2 * coef * tsi * j3oj2 * no * sinio / ecco }
        x1mth2 = 1 - cosio2
        cc4 = 2 * no * coef1 * ao * omeosq * (eta * (2 + 0.5 * etasq) + ecco * (0.5 + 2 * etasq)
            - j2 * tsi / (ao * psisq) * (-3 * con41 * (1 - 2 * eeta + etasq * (1.5 - 0.5 * eeta))
            + 0.75 * x1mth2 * (2 * etasq - eeta * (1 + etasq)) * cos(2 * argpo)))
        cc5 = 2 * coef1 * ao * omeosq * (1 + 2.75 * (etasq + eeta) + eeta * etasq)
        let cosio4 = cosio2 * cosio2
        let temp1 = 1.5 * j2 * pinvsq * no
        let temp2 = 0.5 * temp1 * j2 * pinvsq
        let temp3 = -0.46875 * j4 * pinvsq * pinvsq * no
        mdot = no + 0.5 * temp1 * rteosq * con41 + 0.0625 * temp2 * rteosq * (13 - 78 * cosio2 + 137 * cosio4)
        argpdot = -0.5 * temp1 * con42 + 0.0625 * temp2 * (7 - 114 * cosio2 + 395 * cosio4)
            + temp3 * (3 - 36 * cosio2 + 49 * cosio4)
        let xhdot1 = -temp1 * cosio
        nodedot = xhdot1 + (0.5 * temp2 * (4 - 19 * cosio2) + 2 * temp3 * (3 - 7 * cosio2)) * cosio
        omgcof = bstar * cc3 * cos(argpo)
        if ecco > 1e-4 { xmcof = -x2o3 * coef * bstar / eeta }
        nodecf = 3.5 * omeosq * xhdot1 * cc1
        t2cof = 1.5 * cc1
        let denom = abs(cosio + 1) > 1.5e-12 ? (1 + cosio) : 1.5e-12
        xlcof = -0.25 * j3oj2 * sinio * (3 + 5 * cosio) / denom
        aycof = -0.5 * j3oj2 * sinio
        delmo = pow(1 + eta * cos(mo), 3)
        sinmao = sin(mo)
        x7thm1 = 7 * cosio2 - 1
        if !isimp {
            let cc1sq = cc1 * cc1
            d2 = 4 * ao * tsi * cc1sq
            let temp = d2 * tsi * cc1 / 3
            d3 = (17 * ao + sfour) * temp
            d4 = 0.5 * temp * ao * tsi * (221 * ao + 31 * sfour) * cc1
            t3cof = d2 + 2 * cc1sq
            t4cof = 0.25 * (3 * d3 + cc1 * (12 * d2 + 10 * cc1sq))
            t5cof = 0.2 * (3 * d4 + 12 * cc1 * d3 + 6 * d2 * d2 + 15 * cc1sq * (2 * d2 + cc1sq))
        }
    }

    /// - Parameter t: minutes since the element epoch.
    func propagate(minutes t: Double) throws -> (position: Vec3, velocity: Vec3) {
        let j2 = Self.j2, xke = Self.xke, twoPi = Self.twoPi

        let xmdf = mo + mdot * t
        let argpdf = argpo + argpdot * t
        let nodedf = nodeo + nodedot * t
        var argpm = argpdf
        var mm = xmdf
        let t2 = t * t
        var nodem = nodedf + nodecf * t2
        var tempa = 1 - cc1 * t
        var tempe = bstar * cc4 * t
        var templ = t2cof * t2
        if !isimp {
            let delomg = omgcof * t
            let delmtemp = 1 + eta * cos(xmdf)
            let delm = xmcof * (delmtemp * delmtemp * delmtemp - delmo)
            let temp = delomg + delm
            mm = xmdf + temp
            argpm = argpdf - temp
            let t3 = t2 * t, t4 = t3 * t
            tempa = tempa - d2 * t2 - d3 * t3 - d4 * t4
            tempe = tempe + bstar * cc5 * (sin(mm) - sinmao)
            templ = templ + t3cof * t3 + t4 * (t4cof + t * t5cof)
        }
        let am = pow(xke / no, Self.x2o3) * tempa * tempa
        guard am > 0 else { throw Failure.decayed }
        let nm = xke / pow(am, 1.5)
        var em = ecco - tempe
        guard em < 1, em >= -0.001 else { throw Failure.decayed }
        if em < 1e-6 { em = 1e-6 }
        mm = mm + no * templ
        var xlm = mm + argpm + nodem
        nodem = fmod(nodem, twoPi)
        argpm = fmod(argpm, twoPi)
        xlm = fmod(xlm, twoPi)
        mm = fmod(xlm - argpm - nodem, twoPi)

        let sinip = sin(inclo), cosip = cos(inclo)
        let axnl = em * cos(argpm)
        var temp = 1 / (am * (1 - em * em))
        let aynl = em * sin(argpm) + temp * aycof
        let xl = mm + argpm + nodem + temp * xlcof * axnl

        // Kepler's equation
        let u = fmod(xl - nodem, twoPi)
        var eo1 = u, tem5 = 9999.9, ktr = 1
        var sineo1 = 0.0, coseo1 = 0.0
        while abs(tem5) >= 1e-12 && ktr <= 10 {
            sineo1 = sin(eo1)
            coseo1 = cos(eo1)
            tem5 = 1 - coseo1 * axnl - sineo1 * aynl
            tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5
            if abs(tem5) >= 0.95 { tem5 = tem5 > 0 ? 0.95 : -0.95 }
            eo1 += tem5
            ktr += 1
        }

        let ecose = axnl * coseo1 + aynl * sineo1
        let esine = axnl * sineo1 - aynl * coseo1
        let el2 = axnl * axnl + aynl * aynl
        let pl = am * (1 - el2)
        guard pl >= 0 else { throw Failure.decayed }
        let rl = am * (1 - ecose)
        let rdotl = sqrt(am) * esine / rl
        let rvdotl = sqrt(pl) / rl
        let betal = sqrt(1 - el2)
        temp = esine / (1 + betal)
        let sinu = am / rl * (sineo1 - aynl - axnl * temp)
        let cosu = am / rl * (coseo1 - axnl + aynl * temp)
        var su = atan2(sinu, cosu)
        let sin2u = (cosu + cosu) * sinu
        let cos2u = 1 - 2 * sinu * sinu
        temp = 1 / pl
        let temp1 = 0.5 * j2 * temp
        let temp2 = temp1 * temp

        // Short-period periodics
        let mrt = rl * (1 - 1.5 * temp2 * betal * con41) + 0.5 * temp1 * x1mth2 * cos2u
        su = su - 0.25 * temp2 * x7thm1 * sin2u
        let xnode = nodem + 1.5 * temp2 * cosip * sin2u
        let xinc = inclo + 1.5 * temp2 * cosip * sinip * cos2u
        let mvt = rdotl - nm * temp1 * x1mth2 * sin2u / xke
        let rvdot = rvdotl + nm * temp1 * (x1mth2 * cos2u + 1.5 * con41) / xke

        let sinsu = sin(su), cossu = cos(su)
        let snod = sin(xnode), cnod = cos(xnode)
        let sini = sin(xinc), cosi = cos(xinc)
        let xmx = -snod * cosi, xmy = cnod * cosi
        let ux = xmx * sinsu + cnod * cossu
        let uy = xmy * sinsu + snod * cossu
        let uz = sini * sinsu
        let vx = xmx * cossu - cnod * sinsu
        let vy = xmy * cossu - snod * sinsu
        let vz = sini * cossu

        guard mrt >= 1 else { throw Failure.decayed }
        let re = Self.earthRadius
        let vkm = re * xke / 60
        return (Vec3(mrt * ux, mrt * uy, mrt * uz) * re,
                Vec3(mvt * ux + rvdot * vx, mvt * uy + rvdot * vy, mvt * uz + rvdot * vz) * vkm)
    }

    /// Greenwich mean sidereal time in radians (IAU-82, as used by SGP4).
    static func gstime(_ jdut1: Double) -> Double {
        let tut1 = (jdut1 - 2451545.0) / 36525.0
        var temp = -6.2e-6 * tut1 * tut1 * tut1 + 0.093104 * tut1 * tut1
            + (876600.0 * 3600 + 8640184.812866) * tut1 + 67310.54841
        temp = fmod(temp * (Double.pi / 180) / 240.0, twoPi)
        if temp < 0 { temp += twoPi }
        return temp
    }
}
