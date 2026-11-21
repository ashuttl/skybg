import Foundation

public enum Style: String, CaseIterable, Identifiable, Sendable {
    case sky, daylight, bokashi, cyanotype, gradient, window, slitscan

    public var id: String { rawValue }

    public var name: String { rawValue.capitalized }

    public var summary: String {
        switch self {
        case .sky: return "The sky as it is: the sun's glow, the weather, the stars"
        case .daylight: return "Pond's calm six-band gradient, paced by the real sun"
        case .bokashi: return "A woodblock print, with the sun and the moon in its phase"
        case .cyanotype: return "A chart of the sun's path, white on Prussian blue"
        case .gradient: return "A plain gradient, lit from wherever the sun is"
        case .window: return "The sun through a window, thrown into a bare room"
        case .slitscan: return "The whole day at once, with now in the middle"
        }
    }

    /// Whether cloud cover and fog change the picture.
    public var usesWeather: Bool { self == .sky || self == .window }
}

/// Everything a picture depends on besides its style and size.
public struct SkyScene: Sendable {
    public var moment: Moment
    public var lat: Double, lon: Double
    public var cloud: Double, fog: Bool
    public var palette: Palette

    public init(moment: Moment = Moment(), lat: Double, lon: Double, cloud: Double = 0, fog: Bool = false,
                palette: Palette) {
        self.moment = moment
        self.lat = lat
        self.lon = lon
        self.cloud = cloud
        self.fog = fog
        self.palette = palette
    }

    /// Cloud cover as the sky shows it: fog counts as heavy cloud.
    public var veil: Double { fog ? max(cloud, 0.85) : cloud }

    public var sun: (elev: Double, az: Double) { solarPosition(lat: lat, lon: lon, t: moment.t) }
    public var moon: (alt: Double, az: Double, fraction: Double, waxing: Bool) {
        moonPosition(lat: lat, lon: lon, t: moment.t)
    }
}

/// Draw `style` for `scene`. `grain` is the dither that goes in with the
/// rounding to eight bits; 0 gives the same picture every time.
public func render(_ style: Style, width: Int, height: Int, _ scene: SkyScene,
                   grain: Double = Bitmap.grain) -> Bitmap {
    switch style {
    case .sky: return renderSky(width: width, height: height, scene, grain: grain)
    case .daylight: return renderDaylight(width: width, height: height, scene, grain: grain)
    case .bokashi: return renderBokashi(width: width, height: height, scene, grain: grain)
    case .cyanotype: return renderCyanotype(width: width, height: height, scene, grain: grain)
    case .gradient: return renderGradient(width: width, height: height, scene, grain: grain)
    case .window: return renderWindow(width: width, height: height, scene, grain: grain)
    case .slitscan: return renderSlitscan(width: width, height: height, scene, grain: grain)
    }
}
