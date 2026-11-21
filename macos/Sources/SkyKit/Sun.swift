import Foundation

/// An instant, and the clock it is read on: Unix seconds, and the local
/// zone's seconds east of UTC at that instant.
public struct Moment: Sendable {
    public var t: Double
    public var offset: Double

    public init(t: Double, offset: Double) {
        self.t = t
        self.offset = offset
    }

    public init(_ date: Date = Date(), timeZone: TimeZone = .current) {
        t = date.timeIntervalSince1970
        offset = Double(timeZone.secondsFromGMT(for: date))
    }

    public var date: Date { Date(timeIntervalSince1970: t) }

    /// The start of the local day.
    public var localMidnight: Double { floor((t + offset) / 86400) * 86400 - offset }

    /// Whole seconds into the local day, as a clock shows them.
    public var localSeconds: Double { floor(t + offset) - floor((t + offset) / 86400) * 86400 }

    public var localHour: Double { localSeconds / 3600 }

    /// The start of the given month and day in this moment's local year.
    public func localMidnight(month: Int, day: Int) -> Double {
        let year = civil(fromDays: Int(floor((t + offset) / 86400))).year
        return Double(days(fromCivil: year, month, day)) * 86400 - offset
    }

    /// This local day at another hour of the clock.
    public func at(localHour hour: Double) -> Moment {
        Moment(t: localMidnight + hour * 3600, offset: offset)
    }
}

// Days since 1970-01-01 to and from a calendar date (Howard Hinnant's
// algorithms), so the sun needs no Calendar.
func civil(fromDays days: Int) -> (year: Int, month: Int, day: Int) {
    let z = days + 719468
    let era = (z >= 0 ? z : z - 146096) / 146097
    let doe = z - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
}

func days(fromCivil year: Int, _ month: Int, _ day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
}

/// (elevation, azimuth-from-north) in degrees. NOAA approximation.
public func solarPosition(lat: Double, lon: Double, t: Double) -> (elev: Double, az: Double) {
    let whole = floor(t)
    let day = Int(floor(whole / 86400))
    let fracHour = (whole - Double(day) * 86400) / 3600
    let yday = day - days(fromCivil: civil(fromDays: day).year, 1, 1) + 1
    let gamma = 2 * Double.pi / 365 * (Double(yday) - 1 + (fracHour - 12) / 24)
    var decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
    decl += -0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
    decl += -0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
    var eqtime = 0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
    eqtime += -0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma)
    eqtime *= 229.18
    let ha = rad((fracHour * 60 + eqtime + 4 * lon) / 4 - 180)
    let latR = rad(lat)
    let cosZen = sin(latR) * sin(decl) + cos(latR) * cos(decl) * cos(ha)
    let elev = deg(asin(clamp(cosZen, -1, 1)))
    let az = deg(atan2(sin(ha), cos(ha) * sin(latR) - tan(decl) * cos(latR)))
    return (elev, pmod(az + 180, 360))
}

public func phaseName(_ elev: Double) -> String {
    let phases: [(Double, String)] = [
        (-90, "night"), (-12, "astronomical twilight"), (-6, "nautical twilight"),
        (-4, "civil twilight"), (0.5, "golden hour"), (8, "day"),
    ]
    return phases.last(where: { elev >= $0.0 })?.1 ?? "night"
}

/// Local mean sidereal angle in radians (sufficient for a background).
public func localSiderealAngle(t: Double, lon: Double) -> Double {
    let daysSinceJ2000 = 2440587.5 + t / 86400 - 2451545.0
    let gmst = 280.46061837 + 360.98564736629 * daysSinceJ2000
    return rad(pmod(gmst + lon, 360))
}

let sunRiseElevation = -0.833   // the upper limb on the horizon, with refraction

/// Clock hours of sunrise and sunset on the local day of `moment`, or nil
/// where the sun does not rise or set.
public func sunTimes(lat: Double, lon: Double, _ moment: Moment) -> (rise: Double, set: Double)? {
    let midnight = moment.localMidnight
    var rise: Int?, set: Int?
    var before = solarPosition(lat: lat, lon: lon, t: midnight).elev > sunRiseElevation
    for k in 1..<720 {
        let above = solarPosition(lat: lat, lon: lon, t: midnight + Double(k) * 120).elev > sunRiseElevation
        if above && !before && rise == nil { rise = k }
        if before && !above { set = k }
        before = above
    }
    guard let rise, let set else { return nil }
    return (Double(rise) / 30, Double(set) / 30)
}

/// (altitude, azimuth-from-north, illuminated fraction, waxing) of the
/// moon. Low-precision series, good to a fraction of a degree.
public func moonPosition(lat: Double, lon: Double, t: Double)
    -> (alt: Double, az: Double, fraction: Double, waxing: Bool) {
    let days = t / 86400 + 2440587.5 - 2451545.0
    let c = days / 36525
    func sind(_ d: Double) -> Double { sin(rad(d)) }
    func cosd(_ d: Double) -> Double { cos(rad(d)) }
    var lam = 218.32 + 481267.881 * c + 6.29 * sind(135.0 + 477198.87 * c)
    lam += -1.27 * sind(259.3 - 413335.36 * c) + 0.66 * sind(235.7 + 890534.22 * c)
    lam += 0.21 * sind(269.9 + 954397.74 * c) - 0.19 * sind(357.5 + 35999.05 * c)
    lam += -0.11 * sind(186.5 + 966404.03 * c)
    var beta = 5.13 * sind(93.3 + 483202.02 * c) + 0.28 * sind(228.2 + 960400.89 * c)
    beta += -0.28 * sind(318.3 + 6003.15 * c) - 0.17 * sind(217.6 - 407332.21 * c)
    let tilt = 23.439 - 0.0000004 * days
    let x = cosd(beta) * cosd(lam)
    let y = cosd(tilt) * cosd(beta) * sind(lam) - sind(tilt) * sind(beta)
    let z = sind(tilt) * cosd(beta) * sind(lam) + cosd(tilt) * sind(beta)
    let hourAngle = localSiderealAngle(t: t, lon: lon) - atan2(y, x)
    let dec = asin(z), latR = rad(lat)
    var alt = deg(asin(clamp(sin(latR) * sin(dec) + cos(latR) * cos(dec) * cos(hourAngle), -1, 1)))
    alt -= 0.95 * cosd(alt)   // the moon is near enough for parallax to lower it
    let az = deg(atan2(sin(hourAngle), cos(hourAngle) * sin(latR) - tan(dec) * cos(latR)))
    let anomaly = 357.528 + 0.9856003 * days
    let sun = 280.460 + 0.9856474 * days + 1.915 * sind(anomaly) + 0.020 * sind(2 * anomaly)
    let elongation = pmod(lam - sun, 360)
    return (alt, pmod(az + 180, 360), (1 - cosd(elongation)) / 2, elongation < 180)
}
