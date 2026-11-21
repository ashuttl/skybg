import Foundation

/// What the user has chosen. Kept in the app's preferences, which the window
/// and the timer's tick both read.
public enum Settings {
    public static let bundleID = "com.skybg.Skybg"

    // Inside the app this is its own domain; run loose (tests, `swift run`)
    // it is still the app's.
    static let store = Bundle.main.bundleIdentifier == bundleID
        ? UserDefaults.standard : UserDefaults(suiteName: bundleID) ?? .standard

    public static var style: Style {
        get { Style(rawValue: store.string(forKey: "style") ?? "") ?? .sky }
        set { store.set(newValue.rawValue, forKey: "style") }
    }

    public static var location: (lat: Double, lon: Double)? {
        get {
            guard store.object(forKey: "latitude") != nil, store.object(forKey: "longitude") != nil else { return nil }
            return (store.double(forKey: "latitude"), store.double(forKey: "longitude"))
        }
        set {
            if let newValue {
                store.set(newValue.lat, forKey: "latitude")
                store.set(newValue.lon, forKey: "longitude")
            } else {
                store.removeObject(forKey: "latitude")
                store.removeObject(forKey: "longitude")
            }
        }
    }

    /// Whether to ask Open-Meteo for cloud cover, for the styles that use it.
    public static var weather: Bool {
        get { store.object(forKey: "weather") == nil ? true : store.bool(forKey: "weather") }
        set { store.set(newValue, forKey: "weather") }
    }

    /// Renders, the weather cache and the lock live here.
    public static let stateDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Skybg", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// The command-line skybg's configuration directory, where a palette may
    /// also be left for the app.
    static let legacyConfig: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config")
        return base.appendingPathComponent("skybg")
    }()

    /// On first run, take the style, location and weather choice from the
    /// command-line skybg's config.json, if there is one.
    public static func importLegacyOnce() {
        if store.bool(forKey: "importedLegacy") { return }
        store.set(true, forKey: "importedLegacy")
        guard let data = try? Data(contentsOf: legacyConfig.appendingPathComponent("config.json")),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let name = config["style"] as? String, let style = Style(rawValue: name) { self.style = style }
        if let weather = config["weather"] as? Bool { self.weather = weather }
        if let place = config["location"] as? [Double], place.count == 2 {
            location = (place[0], place[1])
        } else {
            // "auto": the last place linecast gave it.
            let cache = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/state/skybg/location")
            let parts = (try? String(contentsOf: cache, encoding: .utf8))?.split(separator: " ")
                .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? []
            if parts.count == 2 { location = (parts[0], parts[1]) }
        }
    }

    /// The colours to mix from: a colors.toml the user has left in
    /// ~/.config/skybg, or else the built-in palette for the system's
    /// light or dark appearance.
    public static func palette() -> Palette {
        if let palette = Palette(toml: legacyConfig.appendingPathComponent("colors.toml")) { return palette }
        return .builtIn(dark: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
    }
}
