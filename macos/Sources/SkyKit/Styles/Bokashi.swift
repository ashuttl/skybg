import CoreGraphics
import Foundation

// A sky the way a woodblock print makes one. Bokashi is the printer's wiped
// gradation: a deep band of ink along the top edge, a flat ground, and a band
// of colour rising from the horizon. On that sits a flat sun, where the sun
// is from here, and by night the moon, in its phase and leaning toward the
// sun. The inks below are the print's own; the theme chooses the stock and
// then tints them (see theme inks).

public enum Bokashi {
    // Sun elevation, then the inks: top band, ground, glow above the horizon,
    // the horizon itself; then how far down the top band reaches and how far
    // up the horizon band does, as fractions of the sheet. Dawn is pink, dusk
    // is red.
    static let twilight: [Bool: [InkKey]] = [
        false: [
            InkKey(-18, ["0d1020", "1a2238", "27324a", "303c52"], [0.50, 0.40]),
            InkKey(-9, ["111a38", "26365a", "4a4c72", "7a5a78"], [0.50, 0.42]),
            InkKey(-3, ["1b2c5c", "50608c", "d08a8a", "c8553d"], [0.46, 0.46]),
            InkKey(0.5, ["24468a", "a9a3b8", "f0b97a", "d9532f"], [0.40, 0.50]),
        ],
        true: [
            InkKey(-18, ["0d1020", "1a2238", "27324a", "303c52"], [0.50, 0.40]),
            InkKey(-9, ["111a38", "26365a", "4c5078", "80648a"], [0.50, 0.42]),
            InkKey(-3, ["1b2c5c", "56668f", "e0a0b0", "d0708a"], [0.46, 0.46]),
            InkKey(0.5, ["24468a", "b0aabd", "f6c9b0", "e8809a"], [0.40, 0.50]),
        ],
    ]
    // By day the sheet shows its stock. Under a light theme it is natural
    // paper: the sky is the bare sheet between a blue band and a pale
    // horizon. Under a dark theme it is indigo-dyed: the sky is printed blue
    // and the horizon pale. Keyed by stock (paper is true), then by morning.
    static let day: [Bool: [Bool: [InkKey]]] = [
        true: [
            false: [InkKey(7, ["2a5aa0", "e3d6c6", "f4d49a", "eaa27e"], [0.34, 0.42])],
            true: [InkKey(7, ["2a5aa0", "e6dace", "f6dcc0", "f0b6b0"], [0.34, 0.42])],
        ],
        false: [
            false: [InkKey(7, ["244c90", "7d8fb2", "f1c58f", "e9966f"], [0.38, 0.44])],
            true: [InkKey(7, ["244c90", "8192b6", "f3c9b6", "eda3a8"], [0.38, 0.44])],
        ],
    ]
    static let high: [Bool: [InkKey]] = [
        true: [InkKey(22, ["2c66ae", "ece6d6", "ebe8d8", "d5e2dc"], [0.30, 0.30]),
               InkKey(60, ["2c66ae", "efeadc", "eceadc", "d2e3e0"], [0.28, 0.26])],
        false: [InkKey(22, ["1f4f98", "5f8abb", "a8c6d2", "e4e3cf"], [0.36, 0.36]),
                InkKey(60, ["1d4c96", "5587bd", "9cc2d4", "dfe5d6"], [0.36, 0.32])],
    ]
    static let sunLow = "d6402b", sunHigh = "e8694a", moon = "f1ead6"
    static let sunRadius = 0.060    // of the sheet's height
    static let moonRadius = 0.042
    static let altTop = 75.0        // altitude at the top edge; the bottom edge is the horizon
    static let indigoDepth = 0.90   // lightness of the indigo sheet, against dark windows
    static let dayMoon = 0.5        // how much of the moon shows while the sun is up
    static let sheets = (paper: "ece6d6", night: "1a2238")   // the paper, and the ground at night

    /// The four inks (Oklab) and two band extents for a sun elevation.
    public static func inks(elev: Double, morning: Bool, paper: Bool)
        -> (inks: [V3], topReach: Double, horizonReach: Double) {
        let keys = twilight[morning]! + day[paper]![morning]! + high[paper]!
        let (inks, extents) = InkKey.blend(keys, elev)
        return (inks, extents[0], extents[1])
    }

    /// Oklab at height `y` (0 top, 1 bottom): each band wiped into the ground.
    public static func color(_ inks: [V3], topReach: Double, horizonReach: Double, _ y: Double) -> V3 {
        let stops = [(0.0, inks[0]), (topReach, inks[1]), (1 - horizonReach, inks[1]),
                     (1 - 0.42 * horizonReach, inks[2]), (1.0, inks[3])]
        for (low, high) in zip(stops, stops.dropFirst()) where y <= high.0 {
            return lerp(low.1, high.1, smoothstep(low.0, high.0, y))
        }
        return inks[3]
    }

    /// Where a bearing and altitude fall on the sheet, as fractions of its
    /// width and height. The sheet faces the sun's side of the sky: south in
    /// the northern hemisphere, north in the southern; the bottom edge is
    /// the horizon.
    public static func screen(az: Double, alt: Double, lat: Double) -> (x: Double, y: Double) {
        let x = lat >= 0 ? 0.5 + (az - 180) / azSpan : 0.5 + (pmod(az + 180, 360) - 180) / azSpan
        return (x, 1 - alt / altTop)
    }
}

/// The lit part of the moon as polygon points: the limb on the side facing
/// `toward` (radians, screen angle), closed by the terminator.
public func moonOutline(cx: Double, cy: Double, radius: Double, fraction: Double, toward: Double)
    -> [(Double, Double)] {
    var points: [(Double, Double)] = []
    let steps = 48
    for k in 0...steps {
        let a = -Double.pi / 2 + Double.pi * Double(k) / Double(steps)
        points.append((radius * cos(a), radius * sin(a)))
    }
    for k in 0...steps {
        let a = Double.pi / 2 - Double.pi * Double(k) / Double(steps)
        points.append((radius * cos(a) * (1 - 2 * fraction), radius * sin(a)))
    }
    let c = cos(toward), s = sin(toward)
    return points.map { (cx + $0.0 * c - $0.1 * s, cy + $0.0 * s + $0.1 * c) }
}

func renderBokashi(width: Int, height: Int, _ scene: SkyScene, grain: Double) -> Bitmap {
    let (elev, az) = scene.sun
    let paper = scene.palette.isLight
    let (inks, topReach, horizonReach) = Bokashi.inks(elev: elev, morning: az < 180, paper: paper)
    let depth = paper ? 1.0 : Bokashi.indigoDepth
    let tint = themeTint(scene.palette, paper: Bokashi.sheets.paper, night: Bokashi.sheets.night)
    func paint(_ lab: V3) -> V3 { oklabToSrgb(tint(V3(lab.x * depth, lab.y, lab.z))) }
    func paint(hex: String) -> V3 { paint(srgbToOklab(hexrgb(hex))) }

    var canvas = Canvas(width: width, height: height)
    canvas.fillRows { y, row in
        let color = paint(Bokashi.color(inks, topReach: topReach, horizonReach: horizonReach,
                                        (Double(y) + 0.5) / Double(height)))
        for x in 0..<width { row.put(x, color) }
    }
    let bitmap = Bitmap(canvas, grain: 0)

    let w = Double(width), h = Double(height)
    let sun = Bokashi.screen(az: az, alt: elev, lat: scene.lat)
    let moon = scene.moon
    let moonAt = Bokashi.screen(az: moon.az, alt: moon.alt, lat: scene.lat)
    let shown = max(smoothstep(8, -4, elev), Bokashi.dayMoon)
    // The sun and moon sink into the horizon band rather than being cut by the edge.
    bitmap.drawVeiled({ smoothstep(1.0, 0.86, $0) }) { context in
        var radius = Bokashi.sunRadius * h
        if sun.y * h - radius < h {
            let ink = lerp(hexrgb(Bokashi.sunLow), hexrgb(Bokashi.sunHigh), smoothstep(0, 40, elev))
            context.fill(paint(srgbToOklab(ink)), 1)
            context.disc(sun.x * w, sun.y * h, radius)
        }
        radius = Bokashi.moonRadius * h
        if moonAt.y * h - radius < h {
            let cx = moonAt.x * w, cy = moonAt.y * h
            let toward = atan2((sun.y - moonAt.y) * h, (sun.x - moonAt.x) * w)
            context.fill(paint(hex: Bokashi.moon), 0.10 * shown)
            context.disc(cx, cy, radius)
            context.fill(paint(hex: Bokashi.moon), 0.95 * shown)
            context.polygon(moonOutline(cx: cx, cy: cy, radius: radius, fraction: moon.fraction, toward: toward))
        }
    }
    bitmap.addGrain(grain)
    return bitmap
}
