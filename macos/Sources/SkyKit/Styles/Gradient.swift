import Foundation

// A plain gradient, but one that knows where the sun is. It is not a picture
// of the sky: it is light falling off from a source. The source stands far
// off the screen in the sun's direction, so the gradient turns once a day
// like the shadow on a sundial — lit from the left at sunrise, from above at
// noon, from the right at sunset and from below at night — and its colours
// run from the colour of the light to the colour of what the light has not
// reached. The colours are the style's own, tinted by the theme.

public enum Gradient {
    // Sun elevation, then five colours from the lit end of the screen to the
    // far end. Dawn runs pink and cool, dusk gold and red, as in bokashi.
    static let night = [InkKey(-18, ["34407a", "262f62", "1a2149", "121736", "0c0f26"])]
    static let twilight: [Bool: [InkKey]] = [
        true: [
            InkKey(-10, ["6a5a96", "433f80", "2a2d62", "1a1e48", "0f1332"]),
            InkKey(-4, ["f2a493", "cf7c9f", "8c69b0", "4d569f", "263670"]),
            InkKey(0.5, ["ffd6a3", "f79c90", "c97db3", "7d7cc9", "3f5cb0"]),
            InkKey(7, ["ffedc6", "f8c6ac", "d6a8cc", "8ba6e2", "4c7bd0"]),
        ],
        false: [
            InkKey(-10, ["7c4f84", "4b3c7c", "2c2b60", "1a1d47", "0f1231"]),
            InkKey(-4, ["f08a5e", "c9567c", "7c4a98", "3e3a86", "1e2459"]),
            InkKey(0.5, ["ffc06e", "f47b55", "c14d85", "6c4ba5", "2e3a8d"]),
            InkKey(7, ["ffdf9c", "f8aa6c", "e07d8e", "8b79c8", "4068c0"]),
        ],
    ]
    static let day = [
        InkKey(18, ["ffefc8", "f0dde6", "a3c6f0", "5591e5", "3a5fc6"]),
        InkKey(40, ["fff6dc", "dcecfa", "86c3f7", "418cee", "3058d0"]),
    ]
    static let sheets = (paper: "fffaf0", night: "1a2149")   // the lightest of the day, the middle of the night
    static let grid = 64          // the field's extent is measured on a grid this many cells across
    static let lean = 0.6         // how far a low sun tips the gradient onto its side
    static let lift = 0.35        // holds the light overhead a while past sunset
    static let distance = 2.5     // of the screen's height, from its centre to the light
    static let reach = 0.75       // below 1, the light gives way to colour sooner
    static let darkDepth = 0.96   // lightness under a dark theme, against dark windows

    /// The five colours (Oklab), lit end first, for a sun elevation.
    public static func ramp(elev: Double, morning: Bool) -> [V3] {
        InkKey.blend(night + twilight[morning]! + day, elev).inks
    }

    /// The direction of the light on the screen, as a unit vector (x right,
    /// y up): the sun's direction seen facing its side of the sky — south in
    /// the northern hemisphere, north in the southern — with east and west
    /// drawn in a little, so the gradient leans rather than lies down.
    public static func light(elev: Double, az: Double, lat: Double) -> (x: Double, y: Double) {
        let side = lat >= 0 ? -1.0 : 1.0
        let x = side * sin(rad(az)) * cos(rad(elev)) * lean
        let y = sin(rad(elev)) + lift
        let length = hypot(x, y)
        return length > 1e-6 ? (x / length, y / length) : (0, 1)
    }

    /// Values 0..1 — 0 nearest the light, 1 farthest — over the screen.
    public struct Field {
        let lx: Double, ly: Double, aspect: Double, near: Double, far: Double
        public let columns: Int, rows: Int

        public init(elev: Double, az: Double, lat: Double, aspect: Double) {
            let light = Gradient.light(elev: elev, az: az, lat: lat)
            lx = light.x * distance
            ly = light.y * distance
            self.aspect = aspect
            columns = grid
            rows = max(2, Int((Double(grid) / aspect).rounded(.toNearestOrEven)))
            // The nearest and farthest of the field are those of its corners
            // and edges, found on the grid.
            var near = Double.infinity, far = 0.0
            for gy in 0..<rows {
                for gx in 0..<columns {
                    let r = hypot((Double(gx) / Double(columns - 1) - 0.5) * aspect - lx,
                                  0.5 - Double(gy) / Double(rows - 1) - ly)
                    near = min(near, r)
                    far = max(far, r)
                }
            }
            self.near = near
            self.far = far
        }

        /// The value at `x` across and `y` down, each 0..1 from edge to edge.
        public func value(x: Double, y: Double) -> Double {
            let r = hypot((x - 0.5) * aspect - lx, 0.5 - y - ly)
            return pow(clamp((r - near) / (far - near)), reach)
        }
    }
}

func renderGradient(width: Int, height: Int, _ scene: SkyScene, grain: Double) -> Bitmap {
    let (elev, az) = scene.sun
    let ramp = Gradient.ramp(elev: elev, morning: az < 180)
    let tint = themeTint(scene.palette, paper: Gradient.sheets.paper, night: Gradient.sheets.night)
    let depth = scene.palette.isLight ? 1.0 : Gradient.darkDepth
    let field = Gradient.Field(elev: elev, az: az, lat: scene.lat, aspect: Double(width) / Double(height))
    // The colour depends only on the field's value: work it out along the
    // ramp once, finely, and look it up for each pixel.
    let steps = 2048
    let colors: [V3] = (0...steps).map { k in
        let lab = cubicRamp(ramp, Double(k) / Double(steps))
        return oklabToSrgb(tint(V3(lab.x * depth, lab.y, lab.z)))
    }
    var canvas = Canvas(width: width, height: height)
    canvas.fillRows { py, row in
        let y = gridParameter((Double(py) + 0.5) / Double(height), field.rows)
        for px in 0..<width {
            let x = gridParameter((Double(px) + 0.5) / Double(width), field.columns)
            let at = field.value(x: x, y: y) * Double(steps)
            let k = min(Int(at), steps - 1)
            row.put(px, lerp(colors[k], colors[k + 1], at - Double(k)))
        }
    }
    return Bitmap(canvas, grain: grain)
}

// MARK: - slitscan
//
// A whole day in one picture, the way a slit-scan camera makes one: every
// column of the screen is the sky at a different moment. Now is the middle
// column; the twelve hours gone run out to the left edge and the twelve to
// come to the right, so the night is as wide as the night is long, and the
// picture slides a column to the left every few minutes. Each column is the
// sky style's sky for its moment, from the zenith at the top down to the
// horizon, in the theme's colours, without the weather.

public enum Slitscan {
    static let hours = 24.0          // the span of time across the screen
    static let grid = (width: 192, height: 40)
    static let sunward = 0.65        // how far each horizon leans to its sunward colour

    /// Hours from now, negative for the past, at `x` across the screen (0..1).
    public static func hour(_ x: Double) -> Double { (x - 0.5) * hours }

    /// The sky style's clear sky for a sun elevation, down one column: the
    /// far and sunward horizons mixed into one.
    public struct Column {
        let zenith: V3, horizon: V3, night: V3, height: Double, brightness: Double

        public init(_ c: Palette, elev: Double) {
            let stops = skyStops(elev: elev, c)
            zenith = stops.zenith
            horizon = lerp(stops.far, stops.near, sunward)
            night = c["darker_background"]
            height = 18.0 + 30.0 * clamp(elev / 30)
            brightness = clamp((elev + 18) / 18)
        }

        /// The colour at `p` down the column: 0 the zenith, 1 the horizon.
        public func color(_ p: Double) -> V3 {
            let v = exp(-altTop * (1 - p) / height)
            return lerp(night, lerp(zenith, horizon, v), brightness + (1 - brightness) * v)
        }
    }
}

func renderSlitscan(width: Int, height: Int, _ scene: SkyScene, grain: Double) -> Bitmap {
    let columns = (0..<width).map { px -> Slitscan.Column in
        let x = gridParameter((Double(px) + 0.5) / Double(width), Slitscan.grid.width)
        let t = scene.moment.t + Slitscan.hour(x) * 3600
        return Slitscan.Column(scene.palette, elev: solarPosition(lat: scene.lat, lon: scene.lon, t: t).elev)
    }
    var canvas = Canvas(width: width, height: height)
    canvas.fillRows { py, row in
        let p = gridParameter((Double(py) + 0.5) / Double(height), Slitscan.grid.height)
        for px in 0..<width { row.put(px, columns[px].color(p)) }
    }
    return Bitmap(canvas, grain: grain)
}
