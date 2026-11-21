import Foundation

/// The colours a sky is mixed from, by Omarchy's names for them.
public struct Palette: Sendable {
    public var colors: [String: V3]

    public subscript(name: String) -> V3 { colors[name] ?? V3(0.5, 0.5, 0.5) }

    public var isLight: Bool { grayOf(self["background"]).x >= 0.4 }

    // With no theme to match, aim for a realistic sky rather than a neutral
    // one: saturated hue anchors, and a dusk-blue background even for the
    // light appearance (the background is the night sky, and every daytime
    // stop mixes from it, so a near-gray background washes out the cycle).
    static let builtIn: [Bool: [String: String]] = [
        true: ["background": "#1c2536", "foreground": "#dce4f0", "bright_foreground": "#c8d4f0",
               "blue": "#3a80d8", "cyan": "#86c8e8", "magenta": "#a96bb4",
               "red": "#d95c48", "yellow": "#f0bd62", "orange": "#e08a52"],
        false: ["background": "#3a4a68", "foreground": "#eef3fa", "bright_foreground": "#d4e0f6",
                "blue": "#4a90e0", "cyan": "#8fd8f0", "magenta": "#c078b8",
                "red": "#e86a50", "yellow": "#f8d078", "orange": "#f09055"],
    ]

    /// The built-in palette for the dark or light appearance.
    public static func builtIn(dark: Bool) -> Palette { Palette(hex: builtIn[dark]!) }

    /// An Omarchy-style colors.toml: `name = "#rrggbb"` lines.
    public init?(toml url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var hex: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if value.hasPrefix("#"), value.count == 7, UInt32(value.dropFirst(), radix: 16) != nil {
                hex[parts[0].trimmingCharacters(in: .whitespaces)] = value
            }
        }
        self.init(hex: hex)
    }

    /// Normalized so every name skybg uses exists — older or minimal themes
    /// may only define the color0-15 ANSI slots.
    public init(hex: [String: String]) {
        var c = hex.mapValues(hexrgb)
        func setDefault(_ name: String, _ value: @autoclosure () -> V3) {
            if c[name] == nil { c[name] = value() }
        }
        setDefault("background", hexrgb("#20242b"))
        setDefault("foreground", hexrgb("#d0d5da"))
        let slots = [("red", 1), ("green", 2), ("yellow", 3), ("blue", 4), ("magenta", 5), ("cyan", 6)]
        for (name, slot) in slots {
            if c[name] == nil, let ansi = c["color\(slot)"] { c[name] = ansi }
            if c["bright_\(name)"] == nil {
                if let ansi = c["color\(slot + 8)"] {
                    c["bright_\(name)"] = ansi
                } else if let plain = c[name] {
                    c["bright_\(name)"] = lighten(plain, 0.2)
                }
            }
        }
        let hues = ["red": "#b05f58", "green": "#6f9a76", "yellow": "#c4a76a",
                    "blue": "#6d8fb4", "cyan": "#6fa7a0", "magenta": "#9a7fa8"]
        for (name, fallback) in hues { setDefault(name, hexrgb(fallback)) }
        setDefault("orange", lerp(c["red"]!, c["yellow"]!, 0.5))
        setDefault("dark_background", lerp(c["background"]!, V3(), 0.2))
        setDefault("darker_background", lerp(c["background"]!, V3(), 0.35))
        setDefault("lighter_background", lighten(c["background"]!, 0.10))
        setDefault("bright_foreground", lighten(c["foreground"]!, 0.2))
        colors = c
    }
}

// MARK: - theme inks
//
// The printed styles are drawn in fixed inks, chosen by hand, and then taken
// into the theme. A theme's colours are picked to be read as text, not to
// fill a screen, so they are not used as they are: each ink keeps its own
// lightness, turns to the hue of the theme colour that stands for its
// pigment, and loses chroma where the theme has less. The sheet itself — the
// pale inks of a light theme, the dark inks of a dark one — moves onto the
// theme's background.

let themeInks = 1.0   // how far the inks go into the theme; 0 leaves them as printed
// The print's pigments: pink, vermilion, ochre, pale sky, Prussian blue.
let inkPigments = [("pink", "e8809a"), ("red", "d9532f"), ("ochre", "f0b97a"),
                   ("sky", "9cc2d4"), ("blue", "2c66ae")]

/// A function taking a printed ink (Oklab) into the theme `c`. `paper` and
/// `night` are the hex colours of the style's own light and dark sheet,
/// which land on the theme's background.
public func themeTint(_ c: Palette, paper: String, night: String) -> (V3) -> V3 {
    let standIns: [String: V3] = [
        "pink": lerp(c["magenta"], c["red"], 0.3), "red": c["red"],
        "ochre": lerp(c["orange"], c["yellow"], 0.5),
        "sky": lerp(c["blue"], c["cyan"], 0.6), "blue": c["blue"],
    ]
    var anchors: [(hue: Double, turn: Double, keep: Double)] = []
    for (name, pigment) in inkPigments {
        let printed = srgbToOklab(hexrgb(pigment)), themed = srgbToOklab(standIns[name]!)
        let chroma = hypot(themed.y, themed.z)
        // A grey has no hue to turn to; it only drains the ink.
        let turn = chroma > 0.02 ? pmod(oklabHue(themed) - oklabHue(printed) + 180, 360) - 180 : 0
        anchors.append((oklabHue(printed), turn, min(1, chroma / hypot(printed.y, printed.z))))
    }
    anchors.sort { $0.hue < $1.hue }
    let light = c.isLight
    let move = srgbToOklab(c["background"]) - srgbToOklab(hexrgb(light ? paper : night))

    return { lab in
        let hue = oklabHue(lab)
        let after = anchors.firstIndex(where: { $0.hue > hue }) ?? 0
        let a0 = anchors[(after + anchors.count - 1) % anchors.count], a1 = anchors[after]
        let u = pmod(hue - a0.hue, 360) / pmod(a1.hue - a0.hue, 360)
        let onSheet = themeInks * (light ? smoothstep(0.60, 0.90, lab.x) : smoothstep(0.50, 0.25, lab.x))
        let inked = themeInks * (1 - onSheet)
        let chroma = hypot(lab.y, lab.z) * (1 + (lerp(a0.keep, a1.keep, u) - 1) * inked)
        let turned = rad(hue + lerp(a0.turn, a1.turn, u) * inked)
        return V3(lab.x + onSheet * move.x, chroma * cos(turned) + onSheet * move.y,
                  chroma * sin(turned) + onSheet * move.z)
    }
}

/// Inks keyed by sun elevation: the row at and the row above `elev`, and
/// how far between them it lies.
struct InkKey {
    var elev: Double
    var inks: [V3]        // Oklab
    var extents: [Double] = []

    init(_ elev: Double, _ hex: [String], _ extents: [Double] = []) {
        self.elev = elev
        inks = hex.map { srgbToOklab(hexrgb($0)) }
        self.extents = extents
    }

    static func blend(_ keys: [InkKey], _ elev: Double) -> (inks: [V3], extents: [Double]) {
        let elev = clamp(elev, keys[0].elev, keys[keys.count - 1].elev)
        let k = (0..<(keys.count - 1)).last(where: { elev >= keys[$0].elev }) ?? 0
        let low = keys[k], high = keys[k + 1]
        let t = smoothstep(low.elev, high.elev, elev)
        return (zip(low.inks, high.inks).map { lerp($0, $1, t) },
                zip(low.extents, high.extents).map { lerp($0, $1, t) })
    }
}
