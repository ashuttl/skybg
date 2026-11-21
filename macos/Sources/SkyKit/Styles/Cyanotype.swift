import CoreGraphics
import Foundation

// A sun print of the sun. Where the other styles paint the sky, this one
// charts it, white on Prussian blue: the whole compass unrolled across the
// sheet, the horizon a ruled line, and the sun's path for today a wave over
// and under it — a dot for each hour, solid where the sun has been and dotted
// where it has yet to go. Behind it, faintly, the waves of the solstices and
// the equinox: the most and least the sun ever does here. The blue deepens
// from day to night, and the twilights are a wash that seeps under the horizon.

public enum Cyanotype {
    // line, then sky and earth by day, then sky and earth by night
    static let blue = ["e8eef5", "23559b", "1a4380", "0d1b3a", "0a1530"]
    static let paper = ["1d4c8f", "f0f3f2", "e2e8ea", "c3cedb", "b3c0d0"]
    static let sheets = (paper: "f0f3f2", night: "0d1b3a")   // the paper, and the sky at night
    static let horizon = 0.56      // how far down the sheet the horizon is ruled
    static let altScale = 0.5      // of the sheet's height, for 90 degrees of altitude
    static let sunRadius = 0.014, moonRadius = 0.011
    static let referenceDays = [(6, 21), (3, 20), (12, 21)]

    public typealias WavePoint = (minute: Int, x: Double, y: Double)

    /// The bearing at the middle of the sheet: south or north, whichever the
    /// sun stands in at its highest today. In the tropics that turns with
    /// the season.
    public static func centre(lat: Double, lon: Double, midnight: Double) -> Double {
        var best = (elev: -Double.infinity, az: 0.0)
        for minute in stride(from: 0, to: 24 * 60, by: 10) {
            let sun = solarPosition(lat: lat, lon: lon, t: midnight + Double(minute) * 60)
            if sun.elev > best.elev || (sun.elev == best.elev && sun.az > best.az) { best = sun }
        }
        return (90..<270).contains(best.az) ? 180 : 0
    }

    /// Fractions of the sheet's width and height for a bearing and altitude.
    /// The full circle of the horizon runs across the sheet, with the bearing
    /// `centre` in the middle.
    public static func screen(az: Double, alt: Double, centre: Double = 180) -> (x: Double, y: Double) {
        (0.5 + (pmod(az - centre + 180, 360) - 180) / 360, horizon - alt / 90 * altScale)
    }

    /// The sun through one local day: (minute, x, y) every `step` minutes.
    public static func sunWave(lat: Double, lon: Double, midnight: Double, centre: Double = 180,
                               step: Int = 10) -> [WavePoint] {
        stride(from: 0, through: 24 * 60, by: step).map { minute in
            let sun = solarPosition(lat: lat, lon: lon, t: midnight + Double(minute) * 60)
            let at = screen(az: sun.az, alt: sun.elev, centre: centre)
            return (minute, at.x, at.y)
        }
    }

    /// Split a wave where it leaves one edge of the sheet and enters the other.
    public static func runs(_ wave: [WavePoint]) -> [[WavePoint]] {
        var runs: [[WavePoint]] = [[]]
        for point in wave {
            if let last = runs[runs.count - 1].last, abs(point.x - last.x) > 0.5 { runs.append([]) }
            runs[runs.count - 1].append(point)
        }
        return runs.filter { $0.count > 1 }
    }

    /// The wash at an altitude on the sheet, for the sun's elevation.
    /// `washes` are sky and earth by day, then sky and earth by night.
    public static func ground(elev: Double, alt: Double, washes: [V3], line: V3) -> V3 {
        let exposure = smoothstep(-12, 10, elev)
        let sky = lerp(washes[2], washes[0], exposure)
        let earth = lerp(washes[3], washes[1], exposure)
        if alt >= 0 {
            // A little lighter toward the horizon, as skies are.
            return lerp(sky, line, 0.07 * smoothstep(40, 0, alt))
        }
        return lerp(earth, lerp(sky, line, 0.07), 0.6 * smoothstep(-18, 0, alt))
    }

    /// The line and the four washes (Oklab) in the theme's colours. On the
    /// blue sheet the line is the theme's foreground; on paper it is its blue.
    public static func inks(_ colors: Palette) -> (line: V3, washes: [V3]) {
        let tint = themeTint(colors, paper: sheets.paper, night: sheets.night)
        let inks = (colors.isLight ? paper : blue).map { tint(srgbToOklab(hexrgb($0))) }
        var line = inks[0]
        if !colors.isLight {
            line = lerp(srgbToOklab(hexrgb(blue[0])), srgbToOklab(colors["foreground"]), themeInks)
        }
        return (line, Array(inks.dropFirst()))
    }
}

func renderCyanotype(width: Int, height: Int, _ scene: SkyScene, grain: Double) -> Bitmap {
    let (line, washes) = Cyanotype.inks(scene.palette)
    let lineColor = oklabToSrgb(line)
    let (elev, az) = scene.sun
    let nowMinute = scene.moment.localSeconds / 60

    var canvas = Canvas(width: width, height: height)
    canvas.fillRows { y, row in
        let alt = (Cyanotype.horizon - (Double(y) + 0.5) / Double(height)) / Cyanotype.altScale * 90
        let color = oklabToSrgb(Cyanotype.ground(elev: elev, alt: alt, washes: washes, line: line))
        for x in 0..<width { row.put(x, color) }
    }
    let bitmap = Bitmap(canvas, grain: 0)

    let w = Double(width), h = Double(height)
    let unit = h / 1200   // a hairline
    let midnight = scene.moment.localMidnight
    let centre = Cyanotype.centre(lat: scene.lat, lon: scene.lon, midnight: midnight)
    let today = Cyanotype.sunWave(lat: scene.lat, lon: scene.lon, midnight: midnight, centre: centre)
    let moon = scene.moon

    bitmap.draw { context in
        context.setLineCap(.round)
        context.setLineJoin(.round)

        func polyline(_ points: [(Double, Double)], _ opacity: Double, _ weight: Double, dash: [Double] = []) {
            context.stroke(lineColor, opacity)
            // A line keeps some body on a small sheet, and a dotted one is
            // as stout as ImageMagick draws it.
            let width = max(weight * unit, 0.6)
            context.setLineWidth(dash.isEmpty ? width : max(width + 0.45, 1.3))
            context.setLineDash(phase: 0, lengths: dash.map { CGFloat($0 * unit) })
            context.beginPath()
            context.addLines(between: points.map { CGPoint(x: $0.0 * w, y: $0.1 * h) })
            context.strokePath()
        }
        func wave(_ points: [Cyanotype.WavePoint], _ opacity: Double, _ weight: Double, dash: [Double] = []) {
            for run in Cyanotype.runs(points) { polyline(run.map { ($0.x, $0.y) }, opacity, weight, dash: dash) }
        }
        func dot(_ x: Double, _ y: Double, _ radius: Double, _ opacity: Double, hollow: Bool = false) {
            if hollow {
                context.stroke(lineColor, opacity)
                context.setLineWidth(max(1.4 * unit, 0.6))
                context.setLineDash(phase: 0, lengths: [])
                context.ring(x * w, y * h, radius)
            } else {
                context.fill(lineColor, opacity)
                context.disc(x * w, y * h, radius)
            }
        }

        // The horizon, the compass along it, and the three depths of twilight.
        let horizon = Cyanotype.horizon
        polyline([(0, horizon), (1, horizon)], 0.55, 1.0)
        for bearing in stride(from: 0, to: 360, by: 15) {
            let reach = bearing % 90 == 0 ? 0.012 : bearing % 45 == 0 ? 0.006 : 0.003
            let x = Double(bearing) / 360
            polyline([(x, horizon - reach), (x, horizon + reach)], 0.55, 1.0)
        }
        for depth in [6.0, 12, 18] {
            let y = horizon + depth / 90 * Cyanotype.altScale
            polyline([(0, y), (1, y)], 0.16, 0.8, dash: [1, 7])
        }

        // The year's extremes, then today: travelled, and still to come.
        for (month, day) in Cyanotype.referenceDays {
            let start = scene.moment.localMidnight(month: month, day: day)
            wave(Cyanotype.sunWave(lat: scene.lat, lon: scene.lon, midnight: start, centre: centre), 0.17, 0.8)
        }
        wave(today.filter { Double($0.minute) <= nowMinute }, 0.85, 1.5)
        wave(today.filter { Double($0.minute) >= nowMinute }, 0.5, 1.2, dash: [1, 5])
        for point in today.dropLast() where point.minute % 60 == 0 {
            dot(point.x, point.y, (point.minute / 60 % 6 == 0 ? 3.4 : 2.2) * unit,
                Double(point.minute) <= nowMinute ? 0.85 : 0.5)
        }

        // The moon in its phase, and the sun: solid above the horizon, a ring below.
        let sunAt = Cyanotype.screen(az: az, alt: elev, centre: centre)
        let moonAt = Cyanotype.screen(az: moon.az, alt: moon.alt, centre: centre)
        var radius = Cyanotype.moonRadius * h
        let toward = atan2((sunAt.y - moonAt.y) * h, (sunAt.x - moonAt.x) * w)
        dot(moonAt.x, moonAt.y, radius, 0.35, hollow: true)
        context.fill(lineColor, 0.85)
        context.polygon(moonOutline(cx: moonAt.x * w, cy: moonAt.y * h, radius: radius,
                                    fraction: moon.fraction, toward: toward))
        radius = Cyanotype.sunRadius * h
        if elev > 0 {
            dot(sunAt.x, sunAt.y, radius * 3.2, 0.07)
            dot(sunAt.x, sunAt.y, radius * 1.9, 0.12)
            dot(sunAt.x, sunAt.y, radius, 1.0)
        } else {
            context.fill(oklabToSrgb(Cyanotype.ground(elev: elev, alt: elev, washes: washes, line: line)), 1)
            context.disc(sunAt.x * w, sunAt.y * h, radius)
            dot(sunAt.x, sunAt.y, radius, 0.9, hollow: true)
        }
    }
    bitmap.addGrain(grain)
    return bitmap
}
