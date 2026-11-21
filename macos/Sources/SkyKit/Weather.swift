import Foundation

/// Current cloud cover and fog from Open-Meteo.
public enum Weather {
    static let lifetime = 1200.0   // seconds a reading is good for
    static let fogCodes: Set<Int> = [45, 48]
    static var cacheFile: URL { Settings.stateDirectory.appendingPathComponent("weather.json") }

    struct Reading: Codable {
        var ts: Double, cloud: Double, fog: Bool, lat: Double, lon: Double
    }

    /// (cloud fraction 0..1, fog). Cached; degrades to the last reading, then
    /// to a mild 0.3. Waits on the network: not for the main thread.
    public static func current(lat: Double, lon: Double) -> (cloud: Double, fog: Bool) {
        var cached = (try? Data(contentsOf: cacheFile)).flatMap { try? JSONDecoder().decode(Reading.self, from: $0) }
        // A reading from somewhere else is useless, even as a fallback
        // (0.05° ≈ 5 km, comfortably inside forecast granularity).
        if let reading = cached, abs(reading.lat - lat) > 0.05 || abs(reading.lon - lon) > 0.05 { cached = nil }
        if let cached, Date().timeIntervalSince1970 - cached.ts < lifetime { return (cached.cloud, cached.fog) }

        if let reading = fetch(lat: lat, lon: lon) {
            if let data = try? JSONEncoder().encode(reading) { try? data.write(to: cacheFile, options: .atomic) }
            return (reading.cloud, reading.fog)
        }
        if let cached { return (cached.cloud, cached.fog) }
        return (0.3, false)
    }

    static func fetch(lat: Double, lon: Double) -> Reading? {
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
                            + "&current=cloud_cover,weather_code") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        var reading: Reading?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { done.signal() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let cover = current["cloud_cover"] as? Double,
                  let code = current["weather_code"] as? Int else { return }
            reading = Reading(ts: Date().timeIntervalSince1970, cloud: clamp(cover / 100),
                              fog: fogCodes.contains(code), lat: lat, lon: lon)
        }.resume()
        done.wait()
        return reading
    }
}
