import Foundation
import SkyKit

// The same program is the app and its timer. Opened, it shows the window;
// launchd runs it every five minutes as `Skybg tick`, which draws a picture
// and leaves.

@main
enum Main {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let command = arguments.first, let run = commands[command] {
            do {
                try run(Array(arguments.dropFirst()))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("skybg: \(error)\n".utf8))
                exit(1)
            }
        }
        SkybgApp.main()
    }

    static let commands: [String: ([String]) throws -> Void] = [
        "tick": { _ in
            // launchd keeps no output: leave the reason for a failed tick
            // where it can be found.
            do {
                try Engine.tick()
            } catch {
                let log = Settings.stateDirectory.appendingPathComponent("tick.log")
                let line = "\(ISO8601DateFormatter().string(from: Date())) \(error)\n"
                let earlier = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                try? (String(earlier.suffix(20_000)) + line).write(to: log, atomically: true, encoding: .utf8)
                throw error
            }
        },
        "once": { _ in print(describe(try Engine.generateAndSet())) },
        "on": { _ in try Engine.turnOn(); print("on: \(Agent.isOn)") },
        "off": { _ in Engine.turnOff(); print("off") },
        "status": { _ in try status() },
        "render": render,
        "snapshot": { arguments in
            guard let path = arguments.first else { throw SkyError("usage: snapshot OUT.png") }
            try MainActor.assumeIsolated { try snapshotWindow(to: path) }
        },
    ]

    static func describe(_ report: Engine.Report) -> String {
        let weather = !report.style.usesWeather ? "\(report.style.rawValue) style"
            : report.fog ? "fog" : "\(Int((report.cloud * 100).rounded()))% cloud"
        return String(format: "sun at %+.1f° (%@), %@", report.elev, phaseName(report.elev), weather)
    }

    static func status() throws {
        let style = Settings.style
        print("style: \(style.rawValue)")
        if let place = Settings.location {
            let sun = solarPosition(lat: place.lat, lon: place.lon, t: Date().timeIntervalSince1970)
            print(String(format: "location: %.4f, %.4f", place.lat, place.lon))
            print(String(format: "sun: %+.1f° elevation, %.0f° azimuth (%@)", sun.elev, sun.az, phaseName(sun.elev)))
        } else {
            print("location: not set")
        }
        print("timer: \(Agent.isOn ? "on" : Agent.needsApproval ? "needs approval in Login Items" : "off")")
        print("desktop picture: \(Wallpaper.current().map(\.path).joined(separator: ", "))")
        print("drawn by skybg: \(Wallpaper.isOurs ? "yes" : "no")")
    }

    /// render STYLE WIDTHxHEIGHT OUT.png [--time UNIX] [--offset SECONDS]
    ///     [--lat N --lon N] [--cloud 0..1] [--fog] [--dark | --light] [--no-grain]
    /// Draws a picture to a file without touching the desktop: for looking
    /// at a style, and for checking this port against bin/skybg.
    static func render(_ arguments: [String]) throws {
        var plain: [String] = [], options: [String: String] = [:]
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            if ["--fog", "--dark", "--light", "--no-grain"].contains(argument) {
                options[argument] = ""
            } else if argument.hasPrefix("--"), let value = rest.popFirst() {
                options[argument] = value
            } else {
                plain.append(argument)
            }
        }
        let size = plain.count == 3 ? plain[1].split(separator: "x").compactMap { Int($0) } : []
        guard let style = Style(rawValue: plain.first ?? ""), size.count == 2 else {
            throw SkyError("usage: render STYLE WIDTHxHEIGHT OUT.png [--time UNIX] [--offset SECONDS] "
                           + "[--lat N --lon N] [--cloud 0..1] [--fog] [--dark | --light] [--no-grain]")
        }
        func number(_ name: String) -> Double? { options[name].flatMap(Double.init) }
        var moment = Moment(number("--time").map(Date.init(timeIntervalSince1970:)) ?? Date())
        if let offset = number("--offset") { moment.offset = offset }
        let place = Settings.location
        guard let lat = number("--lat") ?? place?.lat, let lon = number("--lon") ?? place?.lon else {
            throw SkyError("no location: pass --lat and --lon")
        }
        let palette = options["--dark"] != nil ? Palette.builtIn(dark: true)
            : options["--light"] != nil ? Palette.builtIn(dark: false) : Settings.palette()
        let scene = SkyScene(moment: moment, lat: lat, lon: lon, cloud: number("--cloud") ?? 0,
                          fog: options["--fog"] != nil, palette: palette)
        let started = Date()
        let bitmap = SkyKit.render(style, width: size[0], height: size[1], scene,
                                   grain: options["--no-grain"] != nil ? 0 : Bitmap.grain)
        let drawn = Date().timeIntervalSince(started)
        try bitmap.writePNG(to: URL(fileURLWithPath: plain[2]))
        print(String(format: "%@ %dx%d: drawn in %.2fs, written in %.2fs", style.rawValue, size[0], size[1],
                     drawn, Date().timeIntervalSince(started) - drawn))
    }
}
