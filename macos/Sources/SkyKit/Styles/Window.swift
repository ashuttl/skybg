import Foundation

// Not the sky but what it does indoors: a bare room, seen from where its
// window wall would be, looking at the wall the window faces. The window
// faces the sun's side of the sky and the sun throws its panes into the room
// as it really would. Each point of each surface looks back along the light
// to see whether glass or bar is in the way, so the shapes are the true ones:
// upright on the far wall when the sun is low, sliding down it and out
// across the floor as the sun climbs, sheared along a side wall when the
// light comes from round to one side. Light that only grazes a surface lies
// on it thinly. Edges blur with the length of the ray, the grey of the sky
// comes in through the same window and falls away into the corners, and what
// the sun lights lights the rest of the room in its turn, in its own colour.
// Cloud softens the panes and then puts them out. At night the moon does the
// same, faintly, by its phase. The one liberty: light from far round to the
// side is turned back toward the room, or a summer sunrise, which comes from
// behind the window's wall, would not come in at all.

public enum Room {
    // The room in the dark, in the shade by day, and in the sun when it is
    // low and when it is high; then in moonlight. The theme chooses the stock.
    static let darkInks = ["161d30", "46547a", "f5823f", "f7e3c0", "8a9cc8"]
    static let lightInks = ["8189a0", "d2cec4", "f6a468", "fffaf0", "c9d3ea"]
    static let sheets = (paper: "fffaf0", night: "161d30")   // the sunlit wall, and the room at night
    static let room = (width: 2.2, depth: 1.5)       // in the room's own heights
    static let glass = (width: 0.9, sill: 0.14, head: 0.9)   // the sill and head are above the floor
    static let panes = (across: 3, up: 3)
    static let bar = 0.034            // the glazing bars' thickness
    static let eye = (back: 1.5, height: 0.7)   // how far behind the window's wall the eye stands, and how high
    static let floor = 0.42           // how much of the screen's height the floor takes, below the wall
    static let swing = 65.0           // the widest the light may come in from the side, in degrees
    static let sunWidth = 0.04        // the sun's disc in radians, and more for the glass:
                                      // what softens a shadow's edge, more the further it is thrown
    static let cloudWidth = 0.12      // how much wider a full cloud cover makes the source
    static let haze = (share: 0.3, width: 0.14)   // the share of the light that comes from the glow round
                                      // the sun rather than its disc, and that glow's width in radians
    static let graze = 0.5            // how gently light dims as it slants: 1 is Lambert's law
    static let sky = 9.0              // how strongly the sky's light through the window fills the room
    static let bounce = 5.0           // how strongly what the sun lights lights the rest
    static let moonlight = 0.3        // the full moon's patch, against the sun's
    static let scale = 4              // the room is rendered at this fraction of the screen
    static let glowScale = 3          // and its indirect light at this fraction of that

    public typealias Surface = (point: V3, normal: V3)
    public typealias Lamp = (point: V3, normal: V3, power: Double)
    public typealias Source = (share: Double, width: Double)
    public typealias Trace = (x: Double, z: Double, ray: Double)

    /// The light's bearing off the window's own, in degrees, east negative
    /// for a south window: the window faces south in the northern hemisphere
    /// and north in the southern. Near the window's own bearing it is the
    /// true one; toward the sides it is eased, never passing `swing`, so that
    /// a sun far round to the east or west still comes in.
    public static func bearing(az: Double, lat: Double) -> Double {
        let facing = lat >= 0 ? 180.0 : 0.0
        return swing * tanh((pmod(az - facing + 180, 360) - 180) / swing)
    }

    /// The unit vector from the room toward the light: x to the right as the
    /// eye sees it, y away from the window into the room, z up. The eye has
    /// the window at its back, so a morning sun is at its right shoulder in
    /// the northern hemisphere and throws its light to the left.
    public static func light(alt: Double, bearing: Double) -> V3 {
        let a = rad(alt), b = rad(bearing)
        return V3(-sin(b) * cos(a), -cos(b) * cos(a), sin(a))
    }

    /// What the eye sees through a point of the screen, `u` to the right of
    /// its centre and `v` above, in screen heights. The floor is z = 0 and
    /// the window's wall y = 0. The eye looks level, as an architect's
    /// camera does, so that uprights stay upright, and the picture is slid
    /// up until the floor runs from the window's wall at the screen's foot
    /// to the far wall `floor` above it.
    public static func view(u: Double, v: Double) -> Surface {
        let focal = floor / (eye.height / eye.back - eye.height / (room.depth + eye.back))
        let v = v - (focal * eye.height / eye.back - 0.5)
        var reach = (room.depth + eye.back) / focal, normal = V3(0, -1, 0)
        if v < 0 && eye.height / -v < reach {
            reach = eye.height / -v
            normal = V3(0, 0, 1)
        }
        if v > 0 && (1 - eye.height) / v < reach {
            reach = (1 - eye.height) / v
            normal = V3(0, 0, -1)
        }
        if u != 0 && room.width / 2 / abs(u) < reach {
            reach = room.width / 2 / abs(u)
            normal = V3(u > 0 ? -1 : 1, 0, 0)
        }
        return (V3(u * reach, focal * reach - eye.back, eye.height + v * reach), normal)
    }

    /// Where light through a point of the glass lands.
    public static func landing(x: Double, z: Double, light: V3) -> Surface {
        let dx = -light.x, dy = -light.y, dz = -light.z
        var reach = room.depth / dy, normal = V3(0, -1, 0)
        if dz < 0 && z / -dz < reach {
            reach = z / -dz
            normal = V3(0, 0, 1)
        }
        if dx != 0 {
            // copysign(x, dx): the size of x with the sign of dx
            let toWall = (room.width / 2 - (dx > 0 ? abs(x) : -abs(x))) / abs(dx)
            if toWall < reach {
                reach = toWall
                normal = V3(dx > 0 ? -1 : 1, 0, 0)
            }
        }
        return (V3(x + dx * reach, dy * reach, z + dz * reach), normal)
    }

    /// How much of a source `soft` wide, centred at `u`, shows through
    /// `count` panes dividing `low`..`high`, with bars `bar` thick between.
    public static func paneCover(_ u: Double, low: Double, high: Double, count: Int, bar: Double,
                                 soft: Double) -> Double {
        if !(low - soft / 2 < u && u < high + soft / 2) { return 0 }
        let pitch = (high - low) / Double(count)
        var total = 0.0
        for k in 0..<count {
            let a = low + Double(k) * pitch + bar / 2, b = low + Double(k + 1) * pitch - bar / 2
            total += smoothstep(-0.5, 0.5, (u - a) / soft) - smoothstep(-0.5, 0.5, (u - b) / soft)
        }
        return total
    }

    /// The light as the sun's disc and the glow of the air round it, so an
    /// edge has a narrow blur inside a wide faint one. Cloud widens both and
    /// moves light from the disc to the glow.
    public static func sources(cloud: Double) -> [Source] {
        let share = haze.share + (1 - haze.share) * 0.6 * cloud
        return [(1 - share, sunWidth + cloudWidth * cloud), (share, haze.width + cloudWidth * cloud)]
    }

    /// Back along the light from a point of the room to the window's wall:
    /// the distance across the wall from the window's middle, the height up
    /// it, and the length of the ray; or nil if the light does not come from
    /// the window's side.
    public static func trace(_ point: V3, light: V3) -> Trace? {
        if light.y > -0.02 || point.y <= 0 { return nil }
        let ray = point.y / -light.y
        return (point.x + light.x * ray, point.z + light.z * ray, ray)
    }

    /// How much of the light shows through the panes, 0..1, from the far end
    /// of a ray traced back to the window's wall. The edges blur by the ray's
    /// length, and by `grain`, the size across and up the wall of what one
    /// cell of the picture takes in.
    public static func cover(_ trace: Trace, _ sources: [Source], grain: (Double, Double) = (0, 0)) -> Double {
        var total = 0.0
        for source in sources {
            let soft = max(source.width * trace.ray, 0.012)
            let rise = paneCover(trace.z, low: glass.sill, high: glass.head, count: panes.up, bar: bar,
                                 soft: soft + grain.1)
            if rise > 0.0005 {
                total += source.share * rise * paneCover(trace.x, low: -glass.width / 2, high: glass.width / 2,
                                                         count: panes.across, bar: bar, soft: soft + grain.0)
            }
        }
        return total
    }

    /// The panes as lamps. With no `light` they are the panes themselves,
    /// glowing with the sky; with one, they are the places in the room where
    /// its light through each pane lands, which shine back by as much as came
    /// through the glass.
    public static func lamps(light: V3? = nil) -> [Lamp] {
        let area = glass.width * (glass.head - glass.sill) / Double(panes.across * panes.up)
        var lamps: [Lamp] = []
        for i in 0..<panes.across {
            for k in 0..<panes.up {
                let x = ((Double(i) + 0.5) / Double(panes.across) - 0.5) * glass.width
                let z = glass.sill + (Double(k) + 0.5) / Double(panes.up) * (glass.head - glass.sill)
                if let light {
                    if light.y < -0.02 {
                        let landed = landing(x: x, z: z, light: light)
                        lamps.append((landed.point, landed.normal, area * -light.y))
                    }
                } else {
                    lamps.append((V3(x, 0, z), V3(0, 1, 0), area))
                }
            }
        }
        return lamps
    }

    /// The light a point of the room gets from a set of lamps: each shines
    /// most straight out from its surface, falls off with the square of the
    /// distance, and lights best what faces it.
    public static func glow(_ surface: Surface, _ lamps: [Lamp]) -> Double {
        var total = 0.0
        for lamp in lamps {
            let d = surface.point - lamp.point
            let r2 = (d * d).sum() + 0.1
            let out = (d * lamp.normal).sum(), into = -(d * surface.normal).sum()
            if out > 0 && into > 0 { total += lamp.power * out * into / (Double.pi * r2 * r2) }
        }
        return total
    }

    /// (ambient, sun, moon): how much daylight fills the room, and how
    /// strongly the sun and the moon each throw the window into it.
    public static func strengths(elev: Double, moonAlt: Double, moonFraction: Double, cloud: Double)
        -> (ambient: Double, sun: Double, moon: Double) {
        let clear = pow(1 - cloud, 1.5)
        let ambient = smoothstep(-9, 8, elev) * (1 - 0.2 * cloud)
        let sun = smoothstep(-0.8, 2, elev) * clear
        let moon = moonlight * moonFraction * smoothstep(0, 8, moonAlt) * smoothstep(-5, -12, elev) * clear
        return (ambient, sun, moon)
    }
}

/// A grid of values, sampled between its cells.
struct Grid {
    let width: Int, height: Int
    var values: [Double]

    func sample(_ u: Double, _ v: Double) -> Double {
        let x = clamp(u * Double(width) - 0.5, 0, Double(width) - 1.001)
        let y = clamp(v * Double(height) - 0.5, 0, Double(height) - 1.001)
        let x0 = Int(x), y0 = Int(y)
        let fx = x - Double(x0), fy = y - Double(y0)
        let top = values[y0 * width + x0] * (1 - fx) + values[y0 * width + x0 + 1] * fx
        let bottom = values[(y0 + 1) * width + x0] * (1 - fx) + values[(y0 + 1) * width + x0 + 1] * fx
        return top * (1 - fy) + bottom * fy
    }
}

/// The room at the size it is worked out at, before it is enlarged.
func windowRoom(width: Int, height: Int, _ scene: SkyScene) -> Canvas {
    let cloud = scene.fog ? max(scene.cloud, 0.9) : scene.cloud
    let (elev, az) = scene.sun
    let moon = scene.moon
    let strength = Room.strengths(elev: elev, moonAlt: moon.alt, moonFraction: moon.fraction, cloud: cloud)
    let tint = themeTint(scene.palette, paper: Room.sheets.paper, night: Room.sheets.night)
    let inks = (scene.palette.isLight ? Room.lightInks : Room.darkInks).map { tint(srgbToOklab(hexrgb($0))) }
    let night = inks[0], shade = inks[1], moonlit = inks[4]
    let sunlit = lerp(inks[2], inks[3], smoothstep(0, 28, elev))
    let sources = Room.sources(cloud: cloud)
    // (strength, colour, direction) of each light that is up
    let lights: [(strength: Double, ink: V3, light: V3)] = [
        (strength.sun, sunlit, elev, az), (strength.moon, moonlit, moon.alt, moon.az),
    ].filter { $0.0 > 0.002 }.map {
        ($0.0, $0.1, Room.light(alt: max($0.2, 0.3), bearing: Room.bearing(az: $0.3, lat: scene.lat)))
    }

    let aspect = Double(width) / Double(height)
    let gw = max(48, width / Room.scale), gh = max(30, height / Room.scale)
    // The indirect light is smooth, and so is worked out on a coarser grid:
    // the sky's through the panes, then what each light's patch gives back.
    let cw = max(16, gw / Room.glowScale), ch = max(10, gh / Room.glowScale)
    let lampSets = [Room.lamps()] + lights.map { Room.lamps(light: $0.light) }
    var glows = lampSets.map { _ in Grid(width: cw, height: ch, values: []) }
    for cy in 0..<ch {
        for cx in 0..<cw {
            let surface = Room.view(u: ((Double(cx) + 0.5) / Double(cw) - 0.5) * aspect,
                                      v: 0.5 - (Double(cy) + 0.5) / Double(ch))
            for (k, lamps) in lampSets.enumerated() { glows[k].values.append(Room.glow(surface, lamps)) }
        }
    }

    func viewRow(_ gy: Int) -> [Room.Surface] {
        (0...gw).map { gx in
            Room.view(u: ((Double(gx) + 0.5) / Double(gw) - 0.5) * aspect,
                        v: 0.5 - (Double(gy) + 0.5) / Double(gh))
        }
    }

    var canvas = Canvas(width: gw, height: gh)
    canvas.fillRows { gy, row in
        let fy = (Double(gy) + 0.5) / Double(gh)
        let views = viewRow(gy), below = viewRow(gy + 1)
        for gx in 0..<gw {
            let fx = (Double(gx) + 0.5) / Double(gw)
            let (point, normal) = views[gx]
            let sky = Room.sky * glows[0].sample(fx, fy)
            var lab = lerp(night, shade, strength.ambient * (0.3 + 0.7 * sky / (1 + sky)))
            for (k, light) in lights.enumerated() {
                let bounce = Room.bounce * light.strength * glows[k + 1].sample(fx, fy)
                lab = lerp(lab, light.ink, bounce / (1 + bounce))
                let facing = (normal * light.light).sum()
                guard facing > 0, let trace = Room.trace(point, light: light.light) else { continue }
                // A cell of the picture takes in a stretch of the room, and
                // so of the window, most where it looks along the floor.
                let beside = Room.trace(views[gx + 1].point, light: light.light) ?? trace
                let under = Room.trace(below[gx].point, light: light.light) ?? trace
                let grain = (abs(beside.x - trace.x) + abs(under.x - trace.x),
                             abs(beside.z - trace.z) + abs(under.z - trace.z))
                let direct = light.strength * Room.cover(trace, sources, grain: grain)
                if direct > 0 { lab = lerp(lab, light.ink, direct * pow(facing, Room.graze)) }
            }
            row.put(gx, oklabToSrgb(lab))
        }
    }
    return canvas
}

func renderWindow(width: Int, height: Int, _ scene: SkyScene, grain: Double) -> Bitmap {
    Bitmap(windowRoom(width: width, height: height, scene).resized(width: width, height: height), grain: grain)
}
