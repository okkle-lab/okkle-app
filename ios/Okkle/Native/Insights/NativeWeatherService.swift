import Combine
import CoreLocation
import Foundation

func nativeWeatherSymbol(_ code: Int) -> String {
  switch code {
  case 0: return "sun.max.fill"
  case 1, 2: return "cloud.sun.fill"
  case 3: return "cloud.fill"
  case 45, 48: return "cloud.fog.fill"
  case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
  case 61, 63, 65, 66, 67: return "cloud.rain.fill"
  case 71, 73, 75, 77: return "snowflake"
  case 80, 81, 82: return "cloud.heavyrain.fill"
  case 85, 86: return "snowflake"
  case 95, 96, 99: return "cloud.bolt.rain.fill"
  default: return "cloud.fill"
  }
}

func nativeWeatherLabel(_ code: Int) -> String {
  switch code {
  case 0: return "Clear"
  case 1, 2: return "Partly cloudy"
  case 3: return "Cloudy"
  case 45, 48: return "Fog"
  case 51, 53, 55, 56, 57: return "Drizzle"
  case 61, 63, 65: return "Rain"
  case 66, 67: return "Freezing rain"
  case 71, 73, 75, 77: return "Snow"
  case 80, 81, 82: return "Showers"
  case 85, 86: return "Snow showers"
  case 95, 96, 99: return "Thunderstorm"
  default: return "Cloudy"
  }
}

struct NativeHourWeather: Identifiable, Equatable {
  let hour: Int
  let temperature: Double
  let precipitation: Double
  let precipProbability: Int
  let code: Int

  var id: Int { hour }
  var isWet: Bool { precipitation >= 0.15 || precipProbability >= 55 }
  var isCold: Bool { temperature <= 7 }
  /// Rain and cold both drive up delivery demand while thinning out drivers —
  /// classically the better-paying conditions to be out in.
  var boostsDemand: Bool { isWet || isCold }
  var symbol: String { nativeWeatherSymbol(code) }
  var label: String { nativeWeatherLabel(code) }
}

struct NativeDayWeather: Equatable {
  let hours: [NativeHourWeather]
  func at(_ hour: Int) -> NativeHourWeather? { hours.first { $0.hour == hour } }
}

/// Fetches today's hourly forecast from Open-Meteo (no key, HTTPS, on-device),
/// throttled so it only refetches when stale or you've moved a few km. Fails
/// silently — weather is an extra layer, never load-bearing.
@MainActor
final class NativeWeatherService: ObservableObject {
  static let shared = NativeWeatherService()
  @Published private(set) var today: NativeDayWeather?

  private var lastCoord: CLLocationCoordinate2D?
  private var lastFetch: Date?
  private var seeded = false

  func seed(_ weather: NativeDayWeather) {
    today = weather
    seeded = true
  }

  func refresh(for coordinate: CLLocationCoordinate2D) {
    guard !seeded else { return }
    if let lc = lastCoord, let lf = lastFetch,
       Date().timeIntervalSince(lf) < 1800,
       CLLocation(latitude: lc.latitude, longitude: lc.longitude)
         .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 5000 {
      return
    }
    lastCoord = coordinate
    lastFetch = Date()
    Task { await fetch(coordinate) }
  }

  private func fetch(_ coordinate: CLLocationCoordinate2D) async {
    var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
    comps?.queryItems = [
      URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
      URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
      URLQueryItem(name: "hourly", value: "temperature_2m,precipitation,precipitation_probability,weather_code"),
      URLQueryItem(name: "timezone", value: "auto"),
      URLQueryItem(name: "forecast_days", value: "1")
    ]
    guard let url = comps?.url else { return }
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      let decoded = try JSONDecoder().decode(NativeOpenMeteoResponse.self, from: data)
      today = decoded.dayWeather()
    } catch {
      // silent — no weather layer this session
    }
  }
}

private struct NativeOpenMeteoResponse: Decodable {
  struct Hourly: Decodable {
    let time: [String]
    let temperature_2m: [Double?]
    let precipitation: [Double?]
    let precipitation_probability: [Int?]
    let weather_code: [Int?]
  }
  let hourly: Hourly

  func dayWeather() -> NativeDayWeather {
    var hours: [NativeHourWeather] = []
    for (i, stamp) in hourly.time.enumerated() {
      guard let hh = stamp.split(separator: "T").last?.prefix(2), let hour = Int(hh) else { continue }
      hours.append(NativeHourWeather(
        hour: hour,
        temperature: hourly.temperature_2m[safe: i]?.flatMap { $0 } ?? 0,
        precipitation: hourly.precipitation[safe: i]?.flatMap { $0 } ?? 0,
        precipProbability: hourly.precipitation_probability[safe: i]?.flatMap { $0 } ?? 0,
        code: hourly.weather_code[safe: i]?.flatMap { $0 } ?? 0
      ))
    }
    return NativeDayWeather(hours: hours)
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

/// Demo forecast for the SEED_DEMO launch flag: a wet, cold 6–8pm so the demand
/// signal has something to react to.
func nativeDemoWeather() -> NativeDayWeather {
  let hours = (0..<24).map { h -> NativeHourWeather in
    let wet = (18...20).contains(h)
    return NativeHourWeather(hour: h, temperature: wet ? 8 : 15,
                             precipitation: wet ? 1.4 : 0, precipProbability: wet ? 85 : 10,
                             code: wet ? 63 : 2)
  }
  return NativeDayWeather(hours: hours)
}

// MARK: - Map (tracked routes + zone colouring, defaulting to the user's location)

/// A numbered marker for a ranked top area on the detail map.
