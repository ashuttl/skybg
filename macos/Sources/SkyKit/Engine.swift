import Foundation
import ServiceManagement

/// The timer: a launch agent inside the app, which launchd runs every five
/// minutes whether or not the app is open.
public enum Agent {
    static let service = SMAppService.agent(plistName: "com.skybg.agent.plist")

    public static var isOn: Bool { service.status == .enabled }

    /// Turned off for skybg in System Settings › General › Login Items.
    public static var needsApproval: Bool { service.status == .requiresApproval }

    public static func enable() throws {
        if service.status != .enabled { try service.register() }
    }

    public static func disable() {
        try? service.unregister()
    }
}

public enum Engine {
    public struct Report {
        public var style: Style
        public var elev: Double, az: Double
        public var cloud: Double, fog: Bool
    }

    static var foreignMarker: URL { Settings.stateDirectory.appendingPathComponent("foreign-seen") }

    /// The scene at `moment` for the configured place: its weather, if the
    /// style uses it and the user allows it, and the current palette.
    public static func scene(for style: Style, at moment: Moment = Moment()) throws -> SkyScene {
        guard let place = Settings.location else {
            throw SkyError("no location set; open Skybg and choose one")
        }
        var weather = (cloud: 0.0, fog: false)
        if style.usesWeather && Settings.weather { weather = Weather.current(lat: place.lat, lon: place.lon) }
        return SkyScene(moment: moment, lat: place.lat, lon: place.lon, cloud: weather.cloud, fog: weather.fog,
                     palette: Settings.palette())
    }

    /// Render the chosen style for now and make it the desktop picture.
    @discardableResult
    public static func generateAndSet() throws -> Report {
        try locked {
            let style = Settings.style
            let scene = try scene(for: style)
            let size = Wallpaper.screenSize()
            let inUse = Wallpaper.rendersInUse()
            let url = Wallpaper.nextRender(avoiding: inUse)
            try render(style, width: size.width, height: size.height, scene).writePNG(to: url)
            try Wallpaper.set(url)
            Wallpaper.prune(keeping: inUse.union([url.path]))
            let sun = scene.sun
            return Report(style: style, elev: sun.elev, az: sun.az, cloud: scene.cloud, fog: scene.fog)
        }
    }

    /// Turn the timer on, with a fresh picture to start.
    public static func turnOn() throws {
        try? FileManager.default.removeItem(at: foreignMarker)
        try generateAndSet()
        try Agent.enable()
    }

    /// Turn the timer off. The desktop picture stays as it is.
    public static func turnOff() {
        try? FileManager.default.removeItem(at: foreignMarker)
        Agent.disable()
    }

    /// The timer's entry point: refresh if skybg still owns the desktop
    /// picture; after two ticks of someone else's, stop the timer.
    public static func tick() throws {
        let files = FileManager.default
        if Wallpaper.isOurs {
            try? files.removeItem(at: foreignMarker)
            try generateAndSet()
        } else if files.fileExists(atPath: foreignMarker.path) {
            // Another picture two ticks in a row: the user really did choose
            // something else. Bow out.
            try? files.removeItem(at: foreignMarker)
            Agent.disable()
        } else {
            // The first sighting may be a change in progress. Leave the
            // picture alone and decide next tick.
            files.createFile(atPath: foreignMarker.path, contents: nil)
        }
    }

    /// One render at a time, across the app and the timer.
    static func locked<T>(_ body: () throws -> T) throws -> T {
        let descriptor = open(Settings.stateDirectory.appendingPathComponent("render.lock").path,
                              O_CREAT | O_WRONLY, 0o644)
        guard descriptor >= 0 else { throw SkyError("could not open the render lock") }
        defer { close(descriptor) }
        flock(descriptor, LOCK_EX)
        return try body()
    }
}
