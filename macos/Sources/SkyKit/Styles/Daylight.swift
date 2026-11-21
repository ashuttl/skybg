import Foundation

// A port of the Daylight wallpaper from Pond (pond-wallpaper 0.2.0: SkyState.js
// and sky.frag). Copyright (c) 2026, Butterfly Interaction Inc. BSD-3-Clause;
// the full notice is in LICENSES/pond-wallpaper.txt. The palette, the
// interpolation and the tone curve are Pond's. What is skybg's: sunrise and
// sunset come from the sun at the configured location rather than a fixed
// 6:30 and 18:30, and the picture is rendered to a file instead of a shader.

public enum Daylight {
    static let brightness = 0.65, saturation = 0.70, warmth = 0.012
    static let horizon = 0.84, twilight = 1.95
    public static let sunrise = 6.5, sunset = 18.5
    static let sunriseLimits = (4.0, 9.0), sunsetLimits = (15.0, 22.0)
    static let maxChroma = 0.085

    public typealias Stop = (position: Double, color: V3)

    // Each anchor is an hour of the palette's own day (sunrise 6.5, sunset
    // 18.5) and six bands down the screen: zenith, upper sky, middle sky,
    // haze, horizon, lower edge. A row is the six band positions, then the
    // six colours in Oklab.
    static let anchors: [(hour: Double, values: [Double])] = [
        (0, [0, 0.33, 0.59, 0.78, 0.90, 1], ["080b16", "0d1220", "141d2d", "1c2939", "26313e", "1b2331"]),
        (3, [0, 0.40, 0.64, 0.80, 0.92, 1], ["090d1b", "111a2b", "21324a", "334958", "514c50", "262c3b"]),
        (4.8, [0, 0.355, 0.61, 0.79, 0.91, 1], ["172036", "2d3e56", "515c6d", "796d76", "a3797e", "504e62"]),
        (6.5, [0, 0.28, 0.515, 0.74, 0.905, 1], ["2e3b52", "4c596d", "76757f", "a6868f", "bf948a", "87717a"]),
        (8.5, [0, 0.25, 0.49, 0.73, 0.905, 1], ["405368", "5b6c7c", "7e888e", "a39b9b", "bca4a0", "a99193"]),
        (12, [0, 0.25, 0.52, 0.75, 0.93, 1], ["4d697b", "617d8b", "7a929c", "94a4a7", "b3b1bc", "aba8b2"]),
        (15, [0, 0.27, 0.52, 0.76, 0.93, 1], ["4e6575", "687d88", "879698", "aba3a8", "bdaba3", "ad9795"]),
        (17.3, [0, 0.25, 0.49, 0.73, 0.905, 1], ["405368", "5b6c7c", "7e888e", "a39b9b", "bca4a0", "a99193"]),
        (18.5, [0, 0.28, 0.515, 0.74, 0.905, 1], ["2e3b52", "4c596d", "76757f", "a6868f", "bf948a", "87717a"]),
        (19.6, [0, 0.355, 0.61, 0.79, 0.91, 1], ["172036", "2d3e56", "515c6d", "796d76", "a3797e", "504e62"]),
        (21, [0, 0.38, 0.63, 0.81, 0.93, 1], ["0f1529", "1c2942", "2e4059", "475369", "62586b", "2d334b"]),
        (23, [0, 0.35, 0.60, 0.80, 0.92, 1], ["090d1b", "10192a", "1b2b3f", "293b4e", "3d4655", "232d3e"]),
    ].map { (hour: Double, positions: [Double], colors: [String]) in
        (hour, positions + colors.flatMap { hex -> [Double] in
            let lab = srgbToOklab(hexrgb(hex))
            return [lab.x, lab.y, lab.z]
        })
    }

    // The palette hours of: twilight's start, sunrise, full morning, the
    // start of evening, sunset, twilight's end.
    static let paletteTimes = [4.8, 6.5, 8.5, 17.3, 18.5, 19.6]

    /// Map a clock hour onto the palette's day, so that its sunrise and
    /// sunset fall on the real ones, continuously through midnight.
    public static func paletteHour(_ clock: Double, sunrise: Double, sunset: Double) -> Double {
        let twilight = min(Daylight.twilight, (24 - sunset + sunrise) / 3)
        let times = [sunrise - twilight, sunrise, sunrise + twilight,
                     sunset - twilight, sunset, sunset + twilight]
        var hour = pmod(clock, 24)
        if hour < times[0] { hour += 24 }
        let knots = periodicKnots(times, hour)
        let x = knots.map(\.hour)
        let y = knots.map { paletteTimes[$0.index] + (($0.hour - times[$0.index]) / 24).rounded() * 24 }
        let h0 = x[1] - x[0], h = x[2] - x[1], h2 = x[3] - x[2]
        let d0 = (y[1] - y[0]) / h0, d1 = (y[2] - y[1]) / h, d2 = (y[3] - y[2]) / h2
        return pmod(hermite(y[1], y[2], pchipSlope(d0, d1, h0, h), pchipSlope(d1, d2, h, h2),
                            h, (hour - x[1]) / h), 24)
    }

    /// Six (position, Oklab colour) bands for a clock hour.
    public static func stops(hour: Double, sunrise: Double = sunrise, sunset: Double = sunset) -> [Stop] {
        let sunrise = clamp(sunrise, sunriseLimits.0, sunriseLimits.1)
        let sunset = clamp(sunset, sunsetLimits.0, sunsetLimits.1)
        let paletteHour = paletteHour(hour, sunrise: sunrise, sunset: sunset)
        let knots = periodicKnots(anchors.map(\.hour), paletteHour)
        let a = anchors[knots[0].index].values, b = anchors[knots[1].index].values
        let c = anchors[knots[2].index].values, d = anchors[knots[3].index].values
        let h0 = knots[1].hour - knots[0].hour, h = knots[2].hour - knots[1].hour
        let h2 = knots[3].hour - knots[2].hour
        let u = (paletteHour - knots[1].hour) / h
        let values = b.indices.map { k -> Double in
            let d0 = (b[k] - a[k]) / h0, d1 = (c[k] - b[k]) / h, d2 = (d[k] - c[k]) / h2
            return hermite(b[k], c[k], pchipSlope(d0, d1, h0, h), pchipSlope(d1, d2, h, h2), h, u)
        }
        let bend = log(horizon) / log(0.9)
        return (0..<6).map { i in
            (pow(clamp(values[i]), bend), V3(values[6 + 3 * i], values[7 + 3 * i], values[8 + 3 * i]))
        }
    }

    /// sRGB at height `y` (0 top, 1 bottom): interpolate the bands, then
    /// Pond's tone curve, saturation, warmth and gamut fit.
    public static func color(_ stops: [Stop], _ y: Double) -> V3 {
        let i = (1...4).last(where: { y >= stops[$0].position }) ?? 0
        let (pa, a) = stops[max(i - 1, 0)], (pb, b) = stops[i]
        let (pc, c) = stops[i + 1], (pd, d) = stops[min(i + 2, 5)]
        let h0 = pb - pa, h = pc - pb, h2 = pd - pc
        let u = (y - pb) / h
        var lab = V3()
        for k in 0..<3 {
            let d1 = (c[k] - b[k]) / h
            let m0 = h0 > 0 ? pchipSlope((b[k] - a[k]) / h0, d1, h0, h) : d1
            let m1 = h2 > 0 ? pchipSlope(d1, (d[k] - c[k]) / h2, h, h2) : d1
            lab[k] = hermite(b[k], c[k], m0, m1, h, u)
        }
        let lightness = brightness * tanh(lab.x / 0.75)
        var ca = lab.y * saturation
        var cb = lab.z * saturation + warmth * lightness
        let chroma = hypot(ca, cb)
        if chroma > maxChroma {
            ca *= maxChroma / chroma
            cb *= maxChroma / chroma
        }
        var color = oklabToSrgb(V3(lightness, ca, cb))
        for _ in 0..<16 {
            if (0...1).contains(color.x) && (0...1).contains(color.y) && (0...1).contains(color.z) { break }
            ca *= 0.85
            cb *= 0.85
            color = oklabToSrgb(V3(lightness, ca, cb))
        }
        return color
    }
}

func renderDaylight(width: Int, height: Int, _ scene: SkyScene, grain: Double) -> Bitmap {
    let times = sunTimes(lat: scene.lat, lon: scene.lon, scene.moment) ?? (Daylight.sunrise, Daylight.sunset)
    let stops = Daylight.stops(hour: scene.moment.localHour, sunrise: times.0, sunset: times.1)
    // The picture varies only down the screen.
    var canvas = Canvas(width: width, height: height)
    canvas.fillRows { y, row in
        let color = Daylight.color(stops, (Double(y) + 0.5) / Double(height))
        for x in 0..<width { row.put(x, color) }
    }
    return Bitmap(canvas, grain: grain)
}
