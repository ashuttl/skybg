import AppKit
import CoreLocation
import SkyKit
import SwiftUI

/// What the window shows and changes. Settings are saved as they are made;
/// pictures are drawn off the main thread and published as they finish.
@MainActor
final class AppModel: ObservableObject {
    @Published var style: Style
    @Published var isOn: Bool
    @Published var weather: Bool
    @Published var latitude: String
    @Published var longitude: String
    /// The hour of today the previews show, or nil for now.
    @Published var previewHour: Double?
    @Published var hero: CGImage?
    @Published var thumbnails: [Style: CGImage] = [:]
    @Published var caption = ""
    @Published var problem: String?
    @Published var locating = false
    @Published var busy = false

    private var sky = (cloud: 0.0, fog: false)
    private let painter = DispatchQueue(label: "com.skybg.previews", qos: .userInitiated)
    private let worker = DispatchQueue(label: "com.skybg.wallpaper", qos: .userInitiated)
    private let latest = Counter()
    private var clock: Timer?
    private lazy var locator = Locator()

    init() {
        Settings.importLegacyOnce()
        style = Settings.style
        isOn = Agent.isOn
        weather = Settings.weather
        latitude = Settings.location.map { Self.format($0.lat) } ?? ""
        longitude = Settings.location.map { Self.format($0.lon) } ?? ""
    }

    var hasLocation: Bool { Settings.location != nil }

    /// The shape of the largest display, which the previews take.
    var aspect: Double {
        let size = Wallpaper.screenSize()
        return Double(size.width) / Double(size.height)
    }

    func start() {
        guard clock == nil else { return }
        refreshWeather()
        clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isOn = Agent.isOn
                if self.previewHour == nil { self.refresh() }
            }
        }
    }

    // MARK: choices

    func choose(_ style: Style) {
        self.style = style
        Settings.style = style
        refresh()
        applyIfOn()
    }

    func setWeather(_ on: Bool) {
        weather = on
        Settings.weather = on
        refreshWeather()
        applyIfOn()
    }

    func commitLocation() {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespaces)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespaces)),
              (-90...90).contains(lat), (-180...180).contains(lon) else {
            problem = "Latitude runs from −90 to 90 and longitude from −180 to 180."
            return
        }
        problem = nil
        Settings.location = (lat, lon)
        refreshWeather()
        applyIfOn()
    }

    func useCurrentLocation() {
        locating = true
        locator.find { [weak self] result in
            guard let self else { return }
            self.locating = false
            switch result {
            case .success(let place):
                // A hundredth of a degree is a kilometre: plenty for the sun.
                self.latitude = Self.format((place.latitude * 100).rounded() / 100)
                self.longitude = Self.format((place.longitude * 100).rounded() / 100)
                self.commitLocation()
            case .failure(let error):
                self.problem = "Could not find your location: \(error.localizedDescription)"
            }
        }
    }

    func setOn(_ on: Bool) {
        busy = true
        problem = nil
        worker.async {
            var failure: String?
            if on {
                do { try Engine.turnOn() } catch { failure = "\(error)" }
            } else {
                Engine.turnOff()
            }
            DispatchQueue.main.async {
                self.busy = false
                self.isOn = Agent.isOn
                if let failure {
                    self.problem = failure
                } else if on && !self.isOn {
                    self.problem = "Allow Skybg under System Settings › General › Login Items, then turn this on again."
                }
            }
        }
    }

    private func applyIfOn() {
        guard isOn else { return }
        worker.async {
            do {
                try Engine.generateAndSet()
            } catch {
                DispatchQueue.main.async { self.problem = "\(error)" }
            }
        }
    }

    // MARK: previews

    private func refreshWeather() {
        guard let place = Settings.location, Settings.weather else {
            sky = (0, false)
            refresh()
            return
        }
        refresh()
        worker.async {
            let reading = Weather.current(lat: place.lat, lon: place.lon)
            DispatchQueue.main.async {
                self.sky = reading
                self.refresh()
            }
        }
    }

    /// Draw the large preview and then the small ones, for the hour shown.
    /// A newer request overtakes one still waiting.
    func refresh() {
        guard let place = Settings.location else {
            hero = nil
            thumbnails = [:]
            caption = ""
            return
        }
        let now = Moment()
        let moment = previewHour.map { now.at(localHour: $0) } ?? now
        let palette = Settings.palette()
        let sky = sky, chosen = style, aspect = aspect
        let request = latest.next()
        let sun = solarPosition(lat: place.lat, lon: place.lon, t: moment.t)
        caption = String(format: "%@ · sun %+.0f°, %@", Self.clock(moment), sun.elev, phaseName(sun.elev))
            .replacingOccurrences(of: "-", with: "−")

        painter.async { [latest] in
            func picture(_ style: Style, width: Int) -> CGImage? {
                let scene = SkyScene(moment: moment, lat: place.lat, lon: place.lon,
                                  cloud: style.usesWeather ? sky.cloud : 0, fog: style.usesWeather && sky.fog,
                                  palette: palette)
                // A preview is the desktop seen small, and its grain is small with it.
                return render(style, width: width, height: Int((Double(width) / aspect).rounded()), scene,
                              grain: Bitmap.grain / 4).cgImage()
            }
            guard latest.isCurrent(request) else { return }
            let hero = picture(chosen, width: 1440)
            DispatchQueue.main.async { if latest.isCurrent(request) { self.hero = hero } }
            for style in Style.allCases {
                guard latest.isCurrent(request) else { return }
                let small = picture(style, width: 288)
                DispatchQueue.main.async { if latest.isCurrent(request) { self.thumbnails[style] = small } }
            }
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.4f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private static func clock(_ moment: Moment) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: moment.date)
    }
}

/// Numbers requests, so that a stale one can tell.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    func isCurrent(_ request: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value == request
    }
}

/// Asks Core Location where the Mac is, once.
final class Locator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var done: ((Result<CLLocationCoordinate2D, Error>) -> Void)?

    func find(_ done: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void) {
        self.done = done
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let place = locations.last else { return }
        finish(.success(place.coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        DispatchQueue.main.async {
            self.done?(result)
            self.done = nil
        }
    }
}
