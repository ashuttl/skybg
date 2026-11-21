import CoreGraphics
import Foundation

// The sky itself: theme colours by the sun's elevation and bearing, a glow
// about the sun, weather graying, and on clear nights the catalogue stars
// and the Milky Way.

/// How bright the day sky gets. At 1.0 it is linecast's sky, mixed from the
/// theme's hues toward its bright foreground; lower mixes the day back toward
/// the theme background, which suits a wallpaper behind dark windows.
let dayBrightness = 0.7

let azSpan = 257.0   // degrees of azimuth across the screen, centred on south
let altTop = 60.0    // altitude at the top edge; the bottom edge is the horizon
let skyGrid = (width: 64, height: 40)

/// (zenith, far, near) colours for a sun elevation, blended from theme
/// colours: the sky overhead, the horizon opposite the sun, and the horizon
/// under it.
///
/// The shape follows linecast's sky view. Through twilight the sunward
/// horizon runs magenta, red, then orange while the far side holds the mauve
/// of the Earth's shadow; by day the horizon is paler than the zenith, not
/// darker, as the air whitens it.
public func skyStops(elev: Double, _ c: Palette) -> (zenith: V3, far: V3, near: V3) {
    let bg = c["background"], dbg = c["darker_background"]
    let blue = c["blue"], cyan = c["cyan"]
    let mag = c["magenta"], orange = c["orange"], red = c["red"], yellow = c["yellow"]

    // By day the sky mixes from the theme's hues toward its bright
    // foreground, as linecast's sky does toward white. Toward the sun the
    // horizon leans to the theme's cyan, but only part way: a teal cyan
    // beside a blue sky reads as green. A touch of the sky's own blue keeps
    // a near-white foreground from bleaching the noon sky.
    let white = lerp(c["bright_foreground"], blue, 0.15)
    let skyCyan = lerp(blue, cyan, 0.6)
    let cream = lerp(yellow, white, 0.5)
    func day(_ color: V3) -> V3 { lerp(bg, color, dayBrightness) }

    let keyframes: [(Double, [V3])] = [
        (-18, [dbg, bg, bg]),
        (-12, [lerp(dbg, blue, 0.06), lerp(bg, mag, 0.10), lerp(bg, mag, 0.18)]),
        (-6, [lerp(dbg, blue, 0.12), lerp(bg, mag, 0.30), lerp(bg, lerp(red, mag, 0.5), 0.45)]),
        (-3, [lerp(bg, mag, 0.20), lerp(bg, lerp(mag, red, 0.3), 0.45), lerp(bg, lerp(red, mag, 0.25), 0.70)]),
        (0, [lerp(bg, lerp(mag, blue, 0.35), 0.45), lerp(bg, lerp(red, mag, 0.4), 0.55),
             lerp(bg, lerp(orange, yellow, 0.3), 0.85)]),
        (3, [lerp(bg, lerp(mag, blue, 0.5), 0.65), lerp(bg, lerp(mag, cyan, 0.3), 0.65),
             lerp(lerp(yellow, orange, 0.3), white, 0.15)]),
        (8, [day(lerp(blue, cyan, 0.20)), day(lerp(lerp(blue, cyan, 0.5), white, 0.30)), day(cream)]),
        (15, [day(lerp(blue, cyan, 0.35)), day(lerp(blue, white, 0.52)), day(lerp(skyCyan, white, 0.55))]),
        (30, [day(lerp(blue, white, 0.45)), day(lerp(blue, white, 0.70)), day(lerp(skyCyan, white, 0.72))]),
        (90, [day(lerp(blue, white, 0.60)), day(lerp(blue, white, 0.80)), day(lerp(skyCyan, white, 0.82))]),
    ]

    var stops = keyframes[0].1
    if elev >= keyframes[keyframes.count - 1].0 {
        stops = keyframes[keyframes.count - 1].1
    } else if elev > keyframes[0].0 {
        for (low, high) in zip(keyframes, keyframes.dropFirst()) where low.0 <= elev && elev <= high.0 {
            let t = smoothstep(low.0, high.0, elev)
            stops = (0..<3).map { lerp(low.1[$0], high.1[$0], t) }
            break
        }
    }
    return (stops[0], stops[1], stops[2])
}

/// Where an azimuth falls across the screen: east left, west right.
public func sunScreenX(_ az: Double) -> Double { 0.5 + (az - 180) / azSpan }

/// The sky by altitude and by bearing from the sun, a glow about the sun,
/// and weather graying, for any point of the screen.
public struct SkyField {
    let zenith: V3, far: V3, near: V3, night: V3, glowColor: V3
    let height: Double, brightness: Double
    let sunX: Double, sunY: Double, sigma: Double, glowStrength: Double
    let grayWeight: Double, dim: Double, sunAz: Double

    public init(_ c: Palette, elev: Double, az: Double, cloud: Double, fog: Bool) {
        let cloud = fog ? max(cloud, 0.85) : cloud
        var (zenith, far, near) = skyStops(elev: elev, c)
        night = c["darker_background"]

        // Cloud hides the sunward glow and flattens the sky toward one tone.
        near = lerp(near, far, 0.7 * cloud)
        far = lerp(far, zenith, 0.35 * cloud)
        near = lerp(near, zenith, 0.35 * cloud)
        zenith = lerp(zenith, far, 0.15 * cloud)

        // Afternoon runs slightly warmer than morning.
        let warm = 0.10 * smoothstep(180, 250, az) * smoothstep(4, 15, elev)
        if warm > 0 { near = lerp(near, c["orange"], warm) }
        self.zenith = zenith
        self.far = far
        self.near = near

        // The horizon's colour reaches up the sky a little at night and in
        // twilight and a long way by day (an exponential in altitude, its
        // scale height in degrees); toward the zenith the twilight sky keeps
        // some night.
        height = 18.0 + 30.0 * clamp(elev / 30)
        brightness = clamp((elev + 18) / 18)

        // Sun screen position: azimuth east->left, west->right; low sun sits low.
        sunX = clamp(sunScreenX(az), 0.06, 0.94)
        sunY = 1.05 - 0.9 * clamp((elev + 6) / 66)
        sigma = 0.33 + 0.15 * clamp(elev / 60)
        var glow = 0.4 * exp(-pow((elev - 1) / 11, 2)) + 0.12 * smoothstep(10, 30, elev)
        glow *= 1 - 0.85 * cloud
        glowStrength = elev < -7 ? 0 : glow
        glowColor = lerp(c["orange"], lighten(c["yellow"], 0.25), clamp(elev / 20))

        grayWeight = 0.55 * cloud
        dim = 1 - 0.07 * cloud * smoothstep(0, 8, elev)
        sunAz = rad(az)
    }

    /// A column's bearing from the sun: 1 under it, 0 opposite, bell-shaped
    /// about it, so the warm side stays a band and the far side keeps its mauve.
    public func toward(x: Double) -> Double {
        let columnAz = rad(180 + (x - 0.5) * azSpan)
        let half = (1 + cos(columnAz - sunAz)) / 2
        return half * half * half * half
    }

    /// The colour at `x` across (0 east, 1 west) and `p` down (0 the top
    /// edge, 1 the horizon).
    public func color(x: Double, p: Double) -> V3 {
        color(x: x, p: p, horizon: lerp(far, near, toward(x: x)))
    }

    func color(x: Double, p: Double, horizon: V3) -> V3 {
        let v = exp(-altTop * (1 - p) / height)
        let keep = brightness + (1 - brightness) * v
        var color = lerp(night, lerp(zenith, horizon, v), keep)
        if glowStrength > 0 {
            let dx = (x - sunX) / (sigma * 1.7), dy = (p - sunY) / sigma
            let g = glowStrength * exp(-(dx * dx + dy * dy))
            if g > 0.003 { color = lerp(color, glowColor, clamp(g, 0, 0.55)) }
        }
        if grayWeight > 0 { color = lerp(color, grayOf(color), grayWeight) }
        return color * dim
    }
}

/// How strongly stars should show through twilight and cloud.
public func starVisibility(elev: Double, cloud: Double) -> Double {
    clamp((-elev - 4) / 5) * clamp((0.65 - cloud) / 0.5)
}

/// The Milky Way waits for astronomical dark, and thin cloud takes it
/// before it takes the stars.
public func milkyWayVisibility(elev: Double, cloud: Double) -> Double {
    clamp((-elev - 12) / 6) * pow(clamp((0.65 - cloud) / 0.5), 1.5)
}

// MARK: - the camera
// The observer faces south (north in the southern hemisphere) and looks up
// enough that the horizon runs along the bottom edge of the screen. The
// projection is stereographic, so the Milky Way keeps its shape from the
// horizon to near the zenith, and stars rise on the left and set on the
// right as sidereal time advances.

let fieldOfView = 110.0   // degrees of sky across the width of the screen

public struct Camera {
    /// Equatorial to camera space (x right, y up, z forward), by rows.
    public let matrix: [V3]
    /// Equatorial to the local horizontal frame (east, north, up), by rows.
    public let horizontal: [V3]
    public let focal: Double, cx: Double, cy: Double

    public init(width: Int, height: Int, lat: Double, lon: Double, t: Double) {
        let focal = Double(width) / (4 * tan(rad(fieldOfView) / 4))
        // Looking up until the horizon meets the bottom edge, but never past
        // the point where the zenith reaches the top: a tall frame keeps some
        // of the ground instead.
        let pitch = min(Double.pi / 4, 2 * atan(Double(height) / (4 * focal)))
        let theta = localSiderealAngle(t: t, lon: lon), phi = rad(lat)
        let st = sin(theta), ct = cos(theta), sp = sin(phi), cp = cos(phi)
        let horizontal = [V3(-st, ct, 0), V3(-sp * ct, -sp * st, cp), V3(cp * ct, cp * st, sp)]
        let facing = lat >= 0 ? -1.0 : 1.0   // forward's north component's sign
        let s = sin(pitch), c = cos(pitch)
        // West is on the right when facing south.
        let frame = [V3(facing, 0, 0), V3(0, -facing * s, c), V3(0, facing * c, s)]
        matrix = frame.map { row in
            horizontal[0] * row.x + horizontal[1] * row.y + horizontal[2] * row.z
        }
        self.horizontal = horizontal
        self.focal = focal
        cx = Double(width) / 2
        cy = Double(height) / 2
    }

    /// Screen position of an equatorial unit vector, or nil behind.
    public func project(_ q: V3) -> (x: Double, y: Double)? {
        let x = (matrix[0] * q).sum(), y = (matrix[1] * q).sum(), z = (matrix[2] * q).sum()
        if z < 0.05 { return nil }
        return (cx + 2 * focal * x / (1 + z), cy - 2 * focal * y / (1 + z))
    }

    /// The equatorial unit vector through a screen position.
    public func unproject(_ px: Double, _ py: Double) -> V3 {
        let u = (px - cx) / (2 * focal), v = (cy - py) / (2 * focal)
        let d = 1 + u * u + v * v
        let x = 2 * u / d, y = 2 * v / d, z = (2 - d) / d
        return matrix[0] * x + matrix[1] * y + matrix[2] * z
    }

    public func sinAltitude(_ q: V3) -> Double { (horizontal[2] * q).sum() }
}

// MARK: - stars and the Milky Way

/// The catalogue's B-V colour as a gentle cast on the theme's star colour:
/// blue-white for the hot stars, warm for the giants.
func starTint(_ base: V3, _ bv: Double) -> V3 {
    let blue = clamp((0.3 - bv) / 0.6) * 0.45
    let warm = clamp((bv - 0.8) / 0.8) * 0.5
    return lerp(lerp(base, V3(0.72, 0.82, 1.0), blue), V3(1.0, 0.86, 0.66), warm)
}

public struct StarMark {
    public var x: Double, y: Double, radius: Double, alpha: Double, color: V3, glows: Bool
}

/// The catalogue stars above the horizon. Brightness follows magnitude: the
/// faint stars are single points, the bright ones small discs with a soft
/// halo. The horizon takes the low ones, as the air does.
public func starMarks(width: Int, height: Int, elev: Double, cloud: Double, _ c: Palette,
                      lat: Double, lon: Double, t: Double) -> [StarMark] {
    let visibility = starVisibility(elev: elev, cloud: cloud)
    if visibility <= 0 { return [] }
    let base = lighten(c["bright_foreground"], 0.3)
    let camera = Camera(width: width, height: height, lat: lat, lon: lon, t: t)
    let scale = Double(width) / 2560
    // A small render (a preview panel) keeps only the brighter stars, so the
    // sky stays a sky and not a grain.
    let limit = 6.5 - 2.5 * clamp((1600 - Double(width)) / 1400)
    var marks: [StarMark] = []
    for star in SkyData.stars {
        if star.magnitude > limit { break }
        guard let (x, y) = camera.project(star.direction) else { continue }
        if x < -2 || x > Double(width) + 2 || y < -2 || y > Double(height) + 2 { continue }
        let alt = deg(asin(clamp(camera.sinAltitude(star.direction), -1, 1)))
        if alt <= 0 { continue }
        let brightness = clamp((6.5 - star.magnitude) / 8)
        let alpha = (0.30 + 0.70 * pow(brightness, 1.2)) * visibility * smoothstep(0, 10, alt)
        if alpha < 0.02 { continue }
        marks.append(StarMark(x: x, y: y, radius: max(0.45, (0.6 + 2.6 * brightness) * scale), alpha: alpha,
                              color: starTint(base, star.bv), glows: brightness > 0.45))
    }
    return marks
}

let milkyWayStrength = 0.30   // the brightest of the band as light added over the sky
let milkyWayScale = 6         // the layer is worked out at this fraction of the screen

/// A small layer of the Milky Way to screen over the sky, or nil when it
/// would not show. Each cell looks along the camera into the raster; the
/// band thins toward the horizon and fades with twilight and cloud faster
/// than the stars do.
public func milkyWayLayer(width: Int, height: Int, elev: Double, cloud: Double, _ c: Palette,
                          lat: Double, lon: Double, t: Double) -> Canvas? {
    let visibility = milkyWayVisibility(elev: elev, cloud: cloud)
    guard visibility > 0, let raster = SkyData.milkyWay else { return nil }
    let milky = lerp(lighten(c["bright_foreground"], 0.3), V3(0.78, 0.84, 1.0), 0.25)
    let gw = max(16, width / milkyWayScale), gh = max(10, height / milkyWayScale)
    let camera = Camera(width: width, height: height, lat: lat, lon: lon, t: t)
    let step = Double(width) / Double(gw)
    let strength = milkyWayStrength * visibility
    let rw = SkyData.milkyWaySize.width, rh = SkyData.milkyWaySize.height
    var layer = Canvas(width: gw, height: gh)
    raster.withUnsafeBufferPointer { raster in
        layer.fillRows { gy, row in
            for gx in 0..<gw {
                let q = camera.unproject((Double(gx) + 0.5) * step, (Double(gy) + 0.5) * step)
                let sinAlt = camera.sinAltitude(q)
                if sinAlt <= 0 { continue }
                let ra = deg(atan2(q.y, q.x)), dec = deg(asin(clamp(q.z, -1, 1)))
                let col = pmod(Double(rw) / 2 - ra * Double(rw) / 360, Double(rw))
                let line = min(Double(rh) - 1.001, (90 - dec) * Double(rh) / 180)
                let c0 = Int(col), r0 = Int(line)
                let fc = col - Double(c0), fr = line - Double(r0)
                let c1 = (c0 + 1) % rw
                let top = Double(raster[r0 * rw + c0]) * (1 - fc) + Double(raster[r0 * rw + c1]) * fc
                let bottom = Double(raster[(r0 + 1) * rw + c0]) * (1 - fc) + Double(raster[(r0 + 1) * rw + c1]) * fc
                var level = (top * (1 - fr) + bottom * fr) / 255
                level *= strength * min(1, deg(asin(sinAlt)) / 14)
                row.put(gx, V3(clamp(milky.x * level), clamp(milky.y * level), clamp(milky.z * level)))
            }
        }
    }
    return layer
}

func renderSky(width: Int, height: Int, _ scene: SkyScene, grain: Double) -> Bitmap {
    let (elev, az) = scene.sun
    let field = SkyField(scene.palette, elev: elev, az: az, cloud: scene.cloud, fog: scene.fog)
    let columns: [(x: Double, horizon: V3)] = (0..<width).map { px in
        let x = gridParameter((Double(px) + 0.5) / Double(width), skyGrid.width)
        return (x, lerp(field.far, field.near, field.toward(x: x)))
    }
    let milky = milkyWayLayer(width: width, height: height, elev: elev, cloud: scene.veil, scene.palette,
                              lat: scene.lat, lon: scene.lon, t: scene.moment.t)?
        .resized(width: width, height: height)
    var canvas = Canvas(width: width, height: height)
    canvas.fillRows { y, row in
        let p = gridParameter((Double(y) + 0.5) / Double(height), skyGrid.height)
        for x in 0..<width {
            row.put(x, field.color(x: columns[x].x, p: p, horizon: columns[x].horizon))
        }
    }
    if let milky {
        // Screened: light added over the sky.
        for i in canvas.data.indices {
            canvas.data[i] = 1 - (1 - min(1, max(0, canvas.data[i]))) * (1 - min(1, max(0, milky.data[i])))
        }
    }
    let bitmap = Bitmap(canvas, grain: grain)
    let stars = starMarks(width: width, height: height, elev: elev, cloud: scene.veil, scene.palette,
                          lat: scene.lat, lon: scene.lon, t: scene.moment.t)
    if !stars.isEmpty {
        bitmap.draw { context in
            for star in stars {
                // The bright ones glow: a stack of wider, fainter discs.
                if star.glows {
                    for (spread, share) in [(3.0, 0.06), (2.0, 0.12), (1.4, 0.3)] {
                        context.fill(star.color, star.alpha * share)
                        context.disc(star.x, star.y, star.radius * spread)
                    }
                }
                context.fill(star.color, star.alpha)
                context.disc(star.x, star.y, star.radius)
            }
        }
    }
    return bitmap
}
