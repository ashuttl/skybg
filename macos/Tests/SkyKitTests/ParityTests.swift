import Foundation
import Testing
@testable import SkyKit

// The port is checked against bin/skybg itself: parity.json holds what the
// Python computes for a spread of inputs (see Tests/fixtures.py), and each
// case here must come to the same numbers.

private let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

/// The star catalogue and the unzipped Milky Way, where SkyData looks.
private let skyData: Void = {
    let source = here.appendingPathComponent("../../../data").standardizedFileURL
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skybg-tests-\(getpid())")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? FileManager.default.copyItem(at: source.appendingPathComponent("stars.bin"),
                                      to: directory.appendingPathComponent("stars.bin"))
    let unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
    unzip.arguments = ["-c", source.appendingPathComponent("milkyway.bin.gz").path]
    let pipe = Pipe()
    unzip.standardOutput = pipe
    try? unzip.run()
    let raster = pipe.fileHandleForReading.readDataToEndOfFile()
    try? raster.write(to: directory.appendingPathComponent("milkyway.bin"))
    SkyData.directory = directory
}()

private struct Arguments {
    let values: [String: Any]

    func number(_ name: String) -> Double { (values[name] as? NSNumber)?.doubleValue ?? .nan }
    func int(_ name: String) -> Int { (values[name] as? NSNumber)?.intValue ?? 0 }
    func flag(_ name: String) -> Bool { (values[name] as? NSNumber)?.boolValue ?? false }
    func text(_ name: String) -> String { values[name] as? String ?? "" }
    func numbers(_ name: String) -> [Double] { (values[name] as? [NSNumber])?.map(\.doubleValue) ?? [] }
    func vector(_ name: String) -> V3 { let n = numbers(name); return V3(n[0], n[1], n[2]) }
    func cells(_ name: String) -> [(Int, Int)] {
        (values[name] as? [[NSNumber]])?.map { ($0[0].intValue, $0[1].intValue) } ?? []
    }
    var palette: Palette { .builtIn(dark: flag("dark")) }
    var moment: Moment { Moment(t: number("t"), offset: number("offset")) }
}

private func flat(_ v: V3) -> [Double] { [v.x, v.y, v.z] }
private func flat(_ vs: [V3]) -> [Double] { vs.flatMap(flat) }

/// What the port computes for a case, and how closely it must agree.
private func compute(_ fn: String, _ a: Arguments) -> (out: [Double], tolerance: Double)? {
    let lat = a.number("lat"), lon = a.number("lon"), t = a.number("t")
    let exact = 1e-7
    switch fn {
    case "solar":
        let sun = solarPosition(lat: lat, lon: lon, t: t)
        return ([sun.elev, sun.az], exact)
    case "moon":
        let moon = moonPosition(lat: lat, lon: lon, t: t)
        return ([moon.alt, moon.az, moon.fraction, moon.waxing ? 1 : 0], exact)
    case "sidereal":
        return ([localSiderealAngle(t: t, lon: lon)], exact)
    case "sunTimes":
        let times = sunTimes(lat: lat, lon: lon, a.moment) ?? (Daylight.sunrise, Daylight.sunset)
        return ([times.0, times.1], exact)
    case "cyanotypeCentre":
        return ([Cyanotype.centre(lat: lat, lon: lon, midnight: a.moment.localMidnight)], exact)
    case "sunWave", "referenceWave":
        let midnight = fn == "sunWave" ? a.moment.localMidnight
            : a.moment.localMidnight(month: a.int("month"), day: a.int("day"))
        let wave = Cyanotype.sunWave(lat: lat, lon: lon, midnight: midnight, centre: a.number("centre"))
        let every = fn == "sunWave" ? 12 : 24
        return (stride(from: 0, to: wave.count, by: every).flatMap { [Double(wave[$0].minute), wave[$0].x, wave[$0].y] },
                exact)
    case "oklab":
        return (flat(srgbToOklab(a.vector("rgb"))), exact)
    case "srgb":
        return (flat(oklabToSrgb(a.vector("lab"))), exact)
    case "palette":
        let palette = a.palette
        return ((a.values["keys"] as? [String] ?? []).flatMap { flat(palette[$0]) }, exact)
    case "isLight":
        return ([a.palette.isLight ? 1 : 0], exact)
    case "skyStops":
        let stops = skyStops(elev: a.number("elev"), a.palette)
        return (flat([stops.zenith, stops.far, stops.near]), exact)
    case "slitscanColumn":
        let column = Slitscan.Column(a.palette, elev: a.number("elev"))
        return (a.numbers("rows").flatMap { flat(column.color($0 / 39)) }, exact)
    case "skyField":
        let field = SkyField(a.palette, elev: a.number("elev"), az: a.number("az"), cloud: a.number("cloud"),
                             fog: a.flag("fog"))
        return (a.cells("cells").flatMap { flat(field.color(x: Double($0.0) / 63, p: Double($0.1) / 39)) }, exact)
    case "tint":
        return (flat(themeTint(a.palette, paper: a.text("paper"), night: a.text("night"))(a.vector("lab"))), exact)
    case "cyanotypeInks":
        let inks = Cyanotype.inks(a.palette)
        return (flat(inks.line) + flat(inks.washes), exact)
    case "cyanotypeGround":
        let inks = Cyanotype.inks(a.palette)
        return (flat(Cyanotype.ground(elev: a.number("elev"), alt: a.number("alt"), washes: inks.washes,
                                      line: inks.line)), exact)
    case "daylightStops", "daylightColor":
        let stops = Daylight.stops(hour: a.number("hour"), sunrise: a.number("sunrise"), sunset: a.number("sunset"))
        if fn == "daylightStops" { return (stops.flatMap { [$0.position] + flat($0.color) }, exact) }
        return (a.numbers("ys").flatMap { flat(Daylight.color(stops, $0)) }, exact)
    case "bokashi":
        let inks = Bokashi.inks(elev: a.number("elev"), morning: a.flag("morning"), paper: a.flag("paper"))
        return (flat(inks.inks) + [inks.topReach, inks.horizonReach] + a.numbers("ys").flatMap {
            flat(Bokashi.color(inks.inks, topReach: inks.topReach, horizonReach: inks.horizonReach, $0))
        }, exact)
    case "gradientRamp":
        let ramp = Gradient.ramp(elev: a.number("elev"), morning: a.flag("morning"))
        return (flat(ramp) + a.numbers("ts").flatMap { flat(cubicRamp(ramp, $0)) }, exact)
    case "gradientLight":
        let light = Gradient.light(elev: a.number("elev"), az: a.number("az"), lat: lat)
        return ([light.x, light.y], exact)
    case "gradientField":
        let field = Gradient.Field(elev: a.number("elev"), az: a.number("az"), lat: lat, aspect: a.number("aspect"))
        return ([Double(field.rows)] + a.cells("cells").map {
            field.value(x: Double($0.0) / Double(field.columns - 1), y: Double($0.1) / Double(field.rows - 1))
        }, exact)
    case "moonOutline":
        let outline = moonOutline(cx: a.number("cx"), cy: a.number("cy"), radius: a.number("radius"),
                                  fraction: a.number("fraction"), toward: a.number("toward"))
        return (stride(from: 0, to: outline.count, by: 8).flatMap { [outline[$0].0, outline[$0].1] }, exact)
    case "bokashiScreen":
        return ([43.68, -33.87].flatMap { lat -> [Double] in
            let at = Bokashi.screen(az: a.number("az"), alt: a.number("alt"), lat: lat)
            return [at.x, at.y]
        }, exact)
    case "cyanotypeScreen":
        return ([180.0, 0].flatMap { centre -> [Double] in
            let at = Cyanotype.screen(az: a.number("az"), alt: a.number("alt"), centre: centre)
            return [at.x, at.y]
        }, exact)
    case "roomView":
        let surface = Room.view(u: a.number("u"), v: a.number("v"))
        return (flat(surface.point) + flat(surface.normal), exact)
    case "roomBearing":
        return ([Room.bearing(az: a.number("az"), lat: lat)], exact)
    case "roomLight":
        return (flat(Room.light(alt: a.number("alt"), bearing: a.number("bearing"))), exact)
    case "roomLamps":
        let lamps = a.values["alt"] is NSNull ? Room.lamps()
            : Room.lamps(light: Room.light(alt: a.number("alt"), bearing: a.number("bearing")))
        return (lamps.flatMap { flat($0.point) + flat($0.normal) + [$0.power] }, exact)
    case "roomLanding":
        let landed = Room.landing(x: a.number("x"), z: a.number("z"),
                                  light: Room.light(alt: a.number("alt"), bearing: a.number("bearing")))
        return (flat(landed.point) + flat(landed.normal), exact)
    case "roomSources":
        return (Room.sources(cloud: a.number("cloud")).flatMap { [$0.share, $0.width] }, exact)
    case "roomCover":
        let grain = a.numbers("grain")
        return ([Room.cover((a.number("x"), a.number("z"), a.number("ray")), Room.sources(cloud: a.number("cloud")),
                            grain: (grain[0], grain[1]))], exact)
    case "roomStrengths":
        let strengths = Room.strengths(elev: a.number("elev"), moonAlt: a.number("moonAlt"),
                                       moonFraction: a.number("fraction"), cloud: a.number("cloud"))
        return ([strengths.ambient, strengths.sun, strengths.moon], exact)
    case "roomPicture":
        let scene = SkyScene(moment: Moment(t: t, offset: 0), lat: lat, lon: lon, cloud: a.number("cloud"),
                             fog: a.flag("fog"), palette: a.palette)
        let room = windowRoom(width: a.int("width"), height: a.int("height"), scene)
        guard a.numbers("grid") == [Double(room.width), Double(room.height)] else { return ([], 0) }
        // The Python's is rounded to sixteen bits, and clamped.
        return (a.cells("cells").flatMap { cell in
            (0..<3).map { clamp(Double(room.data[(cell.1 * room.width + cell.0) * 3 + $0])) }
        }, 1e-4)
    case "starProject":
        _ = skyData
        let camera = Camera(width: a.int("width"), height: a.int("height"), lat: lat, lon: lon, t: t)
        let star = SkyData.stars[a.int("index")]
        let at = camera.project(star.direction).map { [$0.x, $0.y] } ?? []
        return (at + [deg(asin(clamp(camera.sinAltitude(star.direction), -1, 1))), star.magnitude, star.bv], exact)
    case "milkyWay":
        _ = skyData
        guard let layer = milkyWayLayer(width: a.int("width"), height: a.int("height"), elev: -30, cloud: 0.1,
                                        .builtIn(dark: true), lat: lat, lon: lon, t: t),
              a.numbers("grid") == [Double(layer.width), Double(layer.height)] else { return ([], 0) }
        // The Python's is rounded to eight bits.
        return (a.cells("cells").flatMap { cell in
            (0..<3).map { Double(layer.data[(cell.1 * layer.width + cell.0) * 3 + $0]) }
        }, 0.51 / 255)
    case "visibility":
        return ([starVisibility(elev: a.number("elev"), cloud: a.number("cloud")),
                 milkyWayVisibility(elev: a.number("elev"), cloud: a.number("cloud"))], exact)
    default:
        return nil
    }
}

@Test func portAgreesWithPython() throws {
    let data = try Data(contentsOf: here.appendingPathComponent("parity.json"))
    let cases = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(cases.count > 500)
    var failures: [String: [String]] = [:]
    for entry in cases {
        let fn = entry["fn"] as? String ?? ""
        let arguments = Arguments(values: entry["args"] as? [String: Any] ?? [:])
        let expected = (entry["out"] as? [NSNumber])?.map(\.doubleValue) ?? []
        guard let (got, tolerance) = compute(fn, arguments) else {
            failures[fn, default: []].append("no port to check")
            continue
        }
        if got.count != expected.count {
            failures[fn, default: []].append("\(arguments.values): \(got.count) values, expected \(expected.count)")
            continue
        }
        let worst = zip(got, expected).map { abs($0 - $1) / max(1, abs($1)) }.max() ?? 0
        if !(worst <= tolerance) {
            failures[fn, default: []].append("\(arguments.values): off by \(worst)\n  got \(got.prefix(9))\n  expected \(expected.prefix(9))")
        }
    }
    for (fn, messages) in failures.sorted(by: { $0.key < $1.key }) {
        Issue.record("\(fn): \(messages.count) cases disagree with bin/skybg. First: \(messages[0])")
    }
}

@Test func everyStyleDraws() {
    _ = skyData
    for dark in [false, true] {
        for t in [1766336400.0, 1774302300, 1791352800] {
            let scene = SkyScene(moment: Moment(t: t, offset: -18000), lat: 43.68, lon: -70.37, cloud: 0.2,
                                 palette: .builtIn(dark: dark))
            for style in Style.allCases {
                let bitmap = render(style, width: 320, height: 200, scene)
                #expect(bitmap.bytes.count == 320 * 200 * 4)
                #expect(bitmap.cgImage() != nil)
                // Not a blank sheet: the top and the bottom differ.
                let top = bitmap.bytes[(10 * 320 + 160) * 4..<(10 * 320 + 160) * 4 + 3]
                let bottom = bitmap.bytes[(190 * 320 + 160) * 4..<(190 * 320 + 160) * 4 + 3]
                #expect(Array(top) != Array(bottom), "\(style) at \(t) is flat")
            }
        }
    }
}

@Test func grainIsEvenAndUnpatterned() {
    var canvas = Canvas(width: 400, height: 300)
    canvas.fill { _, _ in V3(0.5, 0.5, 0.5) }
    let bitmap = Bitmap(canvas)
    let values = stride(from: 0, to: bitmap.bytes.count, by: 4).map { Double(bitmap.bytes[$0]) }
    let mean = values.reduce(0, +) / Double(values.count)
    let deviation = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    #expect(abs(mean - 127.5) < 0.2)
    #expect(abs(deviation - 5) < 0.3)
    // A row must not repeat its neighbour, shifted or not.
    func correlation(_ shift: Int) -> Double {
        var sum = 0.0
        for y in 0..<299 {
            for x in 0..<(400 - shift) {
                sum += (values[y * 400 + x + shift] - mean) * (values[(y + 1) * 400 + x] - mean)
            }
        }
        return sum / Double(299 * (400 - shift)) / (deviation * deviation)
    }
    for shift in 0..<4 { #expect(abs(correlation(shift)) < 0.05) }
}

@Test func paletteReadsColorsToml() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("skybg-colors-\(getpid()).toml")
    let lines = ["background = \"#101820\"", "foreground = \"#d0d0d0\""]
        + (0..<16).map { "color\($0) = \"#\(String(format: "%02x%02x%02x", $0 * 16, $0 * 8, 255 - $0 * 16))\"" }
    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let palette = try #require(Palette(toml: file))
    #expect(palette["background"] == hexrgb("#101820"))
    #expect(palette["blue"] == palette["color4"])
    #expect(palette["bright_blue"] == palette["color12"])
    for name in ["orange", "darker_background", "bright_foreground", "magenta"] {
        #expect(palette.colors[name] != nil)
    }
}

@Test func rendersTakeNamesNoDesktopStillShows() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("skybg-renders-\(getpid())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func path(_ k: Int) -> String { directory.appendingPathComponent("sky-\(k).png").path }
    for (k, age) in [(0, 300.0), (1, 200), (2, 100), (5, 400)] {
        FileManager.default.createFile(atPath: path(k), contents: Data())
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)],
                                              ofItemAtPath: path(k))
    }
    FileManager.default.createFile(atPath: directory.appendingPathComponent("weather.json").path, contents: Data())

    // Newest first, and only the renders.
    #expect(Wallpaper.renders(in: directory).map(\.path) == [path(2), path(1), path(0), path(5)])
    // The lowest name that nothing shows.
    #expect(Wallpaper.nextRender(in: directory, avoiding: [path(0), path(1), path(2)]).path == path(3))
    #expect(Wallpaper.nextRender(in: directory, avoiding: [path(1)]).path == path(0))
    // Pruning leaves what is kept, and what is not a render.
    Wallpaper.prune(in: directory, keeping: [path(1), path(2)])
    let left = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    #expect(left == ["sky-1.png", "sky-2.png", "weather.json"])
}

@Test func wallpaperStoreIsReadThroughItsNestedPlists() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("skybg-store-\(getpid())").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func choice(_ name: String) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: ["type": "imageFile", "url": ["relative": "file://\(directory.path)/\(name)"]],
            format: .binary, options: 0)
    }
    let index: [String: Any] = [
        "AllSpacesAndDisplays": ["Desktop": ["Content": ["Choices": [["Configuration": try choice("sky-0.png")]]]]],
        "Spaces": ["A1": ["Default": ["Desktop": ["Content": ["Choices": [
            ["Configuration": try choice("sky-4.png")], ["Configuration": Data("bplist-broken".utf8)],
        ]]]]]],
    ]
    let store = directory.appendingPathComponent("Index.plist")
    try PropertyListSerialization.data(fromPropertyList: index, format: .binary, options: 0).write(to: store)
    #expect(Wallpaper.storePaths(in: store) == ["\(directory.path)/sky-0.png", "\(directory.path)/sky-4.png"])
    #expect(Wallpaper.storePaths(in: directory.appendingPathComponent("missing.plist")).isEmpty)
}
