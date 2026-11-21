import Foundation

// The stars are the Yale Bright Star Catalogue to magnitude 6.5; the Milky
// Way is NASA's Deep Star Maps 2020 diffuse layer as a brightness raster in
// celestial coordinates. Both are baked by scripts/build-sky-data.py and
// described in data/SOURCES.md. The app carries them in its Resources, the
// raster unzipped.

public struct Star {
    public var direction: V3      // unit vector in equatorial coordinates
    public var magnitude: Double
    public var bv: Double
}

public enum SkyData {
    public static let milkyWaySize = (width: 1080, height: 540)

    /// Where stars.bin and milkyway.bin are: $SKYBG_DATA, or the app's Resources.
    public static var directory: URL? = {
        if let path = ProcessInfo.processInfo.environment["SKYBG_DATA"] {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.resourceURL
    }()

    /// The catalogue, brightest first. Empty when the data is missing: the
    /// sky is then drawn without its stars.
    public static let stars: [Star] = {
        guard let url = directory?.appendingPathComponent("stars.bin"),
              let raw = try? Data(contentsOf: url) else { return [] }
        return stride(from: 0, to: raw.count - 5, by: 6).map { i in
            let ra = rad(Double(UInt16(raw[i]) | UInt16(raw[i + 1]) << 8) / 100)
            let dec = rad(Double(Int16(bitPattern: UInt16(raw[i + 2]) | UInt16(raw[i + 3]) << 8)) / 100)
            return Star(direction: V3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec)),
                        magnitude: Double(Int8(bitPattern: raw[i + 4])) / 10,
                        bv: Double(Int8(bitPattern: raw[i + 5])) / 50)
        }
    }()

    /// The Milky Way's brightness, 0-255, row-major; right ascension 0h in
    /// the middle column increasing leftward, declination +90 at the top.
    public static let milkyWay: [UInt8]? = {
        guard let url = directory?.appendingPathComponent("milkyway.bin"),
              let raw = try? Data(contentsOf: url),
              raw.count == milkyWaySize.width * milkyWaySize.height else { return nil }
        return [UInt8](raw)
    }()
}
