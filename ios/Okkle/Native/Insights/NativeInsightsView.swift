import EventKit
import MapKit
import SwiftUI
import UIKit
enum NativeTimeFilter: String, CaseIterable, Identifiable {
  case all
  case morning
  case lunch
  case afternoon
  case dinner
  case late

  var id: String { rawValue }

  var label: String {
    switch self {
    case .all: return "All day"
    case .morning: return "Morning"
    case .lunch: return "Lunch"
    case .afternoon: return "Afternoon"
    case .dinner: return "Dinner"
    case .late: return "Late"
    }
  }

  var startHour: Int? {
    switch self {
    case .all: return nil
    case .morning: return 6
    case .lunch: return 11
    case .afternoon: return 14
    case .dinner: return 17
    case .late: return 21
    }
  }

  func includes(_ date: Date) -> Bool {
    if self == .all { return true }
    let hour = Calendar.current.component(.hour, from: date)
    switch self {
    case .all:
      return true
    case .morning:
      return hour >= 6 && hour < 11
    case .lunch:
      return hour >= 11 && hour < 14
    case .afternoon:
      return hour >= 14 && hour < 17
    case .dinner:
      return hour >= 17 && hour < 21
    case .late:
      return hour >= 21 || hour < 6
    }
  }
}

struct NativeHeatStatChip: View {
  let title: String
  let value: String
  let symbol: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(color)
      Text(value)
        .font(.system(size: 17, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
    .padding(12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

// MARK: - Zone colour scale

/// Quiet → busiest, in one clear ramp (cool blue → teal → green → amber → red)
/// instead of a single colour at varying opacity, so a glance tells you which
/// zones and times are actually worth being in.
func nativeHeatColor(_ t: Double) -> Color {
  let stops: [(Double, Double, Double, Double)] = [
    (0.00, 0.20, 0.47, 0.93),
    (0.35, 0.10, 0.66, 0.62),
    (0.60, 0.24, 0.72, 0.30),
    (0.80, 0.95, 0.66, 0.23),
    (1.00, 0.86, 0.16, 0.16)
  ]
  let clamped = max(0, min(1, t))
  for i in 1..<stops.count {
    guard clamped <= stops[i].0 else { continue }
    let (t0, r0, g0, b0) = stops[i - 1]
    let (t1, r1, g1, b1) = stops[i]
    let f = t1 > t0 ? (clamped - t0) / (t1 - t0) : 0
    return Color(red: r0 + (r1 - r0) * f, green: g0 + (g1 - g0) * f, blue: b0 + (b1 - b0) * f)
  }
  let last = stops.last!
  return Color(red: last.1, green: last.2, blue: last.3)
}

func nativeHeatUIColor(_ t: Double) -> UIColor { UIColor(nativeHeatColor(t)) }

struct NativeHeatLegend: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("Quiet")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
        Capsule()
          .fill(LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.05).map(nativeHeatColor), startPoint: .leading, endPoint: .trailing))
          .frame(maxWidth: .infinity)
          .frame(height: 10)
        Text("Busiest")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
      }
    }
  }
}

// MARK: - One-shot location (so the map has somewhere to show before any data exists)

@MainActor
final class NativeOneShotLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
  static let shared = NativeOneShotLocator()
  @Published private(set) var coordinate: CLLocationCoordinate2D?
  private let manager = CLLocationManager()

  override init() {
    super.init()
    manager.delegate = self
  }

  func request() {
    guard coordinate == nil else { return }
    let status = manager.authorizationStatus
    guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
    manager.requestLocation()
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    Task { @MainActor in self.coordinate = location.coordinate }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// A coloured overlay circle for one zone — a plain MKCircle plus the weight
/// that decides its colour.
final class NativeZoneCircle: MKCircle {
  var weight: Double = 0.5
}

/// Turns a zone coordinate into a short, human area name ("Soho", "Camden") for
/// the daily plan text. On-device reverse geocoding, cached so it only runs
/// once per rounded coordinate; fails silently (the caller just omits the name).
@MainActor
final class NativeAreaNamer: ObservableObject {
  static let shared = NativeAreaNamer()
  @Published private(set) var names: [String: String] = [:]
  private let geocoder = CLGeocoder()
  private var inFlight: Set<String> = []

  func name(for coordinate: CLLocationCoordinate2D) -> String? {
    let key = "\(Int((coordinate.latitude * 200).rounded())),\(Int((coordinate.longitude * 200).rounded()))"
    if let cached = names[key] { return cached }
    guard !inFlight.contains(key) else { return nil }
    inFlight.insert(key)
    geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { [weak self] placemarks, _ in
      guard let self else { return }
      Task { @MainActor in
        self.inFlight.remove(key)
        if let area = placemarks?.first?.subLocality ?? placemarks?.first?.locality {
          self.names[key] = area
        }
      }
    }
    return nil
  }
}

// MARK: - Weather (Open-Meteo — free, no API key)

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

struct NativeShiftMapRepresentable: UIViewRepresentable {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  var interactive: Bool = false
  @ObservedObject private var locator = NativeOneShotLocator.shared

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator
    mapView.isUserInteractionEnabled = interactive
    mapView.showsCompass = interactive
    mapView.showsScale = interactive
    mapView.isPitchEnabled = false
    mapView.showsUserLocation = true
    return mapView
  }

  func updateUIView(_ mapView: MKMapView, context: Context) {
    mapView.removeOverlays(mapView.overlays)

    var visibleRect = MKMapRect.null
    for trip in trips {
      let coordinates = trip.points.map(\.coordinate)
      guard coordinates.count > 1 else { continue }
      let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
      mapView.addOverlay(polyline)
      visibleRect = visibleRect.isNull ? polyline.boundingMapRect : visibleRect.union(polyline.boundingMapRect)
    }

    // Zones layer gradually as stops accumulate — with none yet, nothing draws
    // and the map just centres on you; each new pattern adds a coloured cell.
    for zone in zones {
      let circle = NativeZoneCircle(center: zone.coordinate, radius: 220)
      circle.weight = zone.weight
      mapView.addOverlay(circle)
      let point = MKMapPoint(zone.coordinate)
      let rect = MKMapRect(x: point.x - 400, y: point.y - 400, width: 800, height: 800)
      visibleRect = visibleRect.isNull ? rect : visibleRect.union(rect)
    }

    if visibleRect.isNull {
      let center = locator.coordinate ?? CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)
      mapView.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)), animated: false)
    } else {
      mapView.setVisibleMapRect(
        visibleRect,
        edgePadding: UIEdgeInsets(top: 40, left: 30, bottom: 40, right: 30),
        animated: false
      )
    }
  }

  final class Coordinator: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      if let polyline = overlay as? MKPolyline {
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = UIColor(red: 0.20, green: 0.47, blue: 0.93, alpha: 0.55)
        renderer.lineWidth = 4
        renderer.lineCap = .round
        renderer.lineJoin = .round
        return renderer
      }
      if let circle = overlay as? NativeZoneCircle {
        let color = nativeHeatUIColor(circle.weight)
        let renderer = MKCircleRenderer(circle: circle)
        renderer.fillColor = color.withAlphaComponent(0.34)
        renderer.strokeColor = color.withAlphaComponent(0.8)
        renderer.lineWidth = 1.5
        return renderer
      }
      return MKOverlayRenderer(overlay: overlay)
    }
  }
}

/// The small, tappable map embedded in the Shift Patterns card. Tapping opens
/// the full-screen, pannable version.
struct NativeShiftMapPreview: View {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  @State private var showDetail = false
  @ObservedObject private var locator = NativeOneShotLocator.shared

  var body: some View {
    Button { showDetail = true } label: {
      ZStack(alignment: .bottomTrailing) {
        NativeShiftMapRepresentable(trips: trips, zones: zones)
          .frame(height: 190)
          .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
          .allowsHitTesting(false)
        Label("Explore map", systemImage: "arrow.up.left.and.arrow.down.right")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background(.black.opacity(0.55), in: Capsule())
          .padding(10)
      }
    }
    .buttonStyle(.plain)
    .onAppear { locator.request() }
    .sheet(isPresented: $showDetail) {
      NativeShiftMapDetailView(trips: trips, zones: zones)
    }
  }
}

/// A compact button (no always-on map) that opens the full explorable map. The
/// inline map ate too much vertical space and didn't tell the driver what to do.
struct NativeExploreMapButton: View {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  @State private var showDetail = false

  var body: some View {
    Button { showDetail = true } label: {
      HStack(spacing: 10) {
        Image(systemName: "map.fill")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(OkkleColor.brand)
          .frame(width: 30, height: 30)
          .background(OkkleColor.brand.opacity(0.14), in: Circle())
        VStack(alignment: .leading, spacing: 1) {
          Text("Explore your zones")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OkkleColor.ink)
          Text("See your busy areas on the map")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(OkkleColor.muted)
      }
      .padding(12)
      .frame(maxWidth: .infinity)
      .background(OkkleColor.muted.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $showDetail) {
      NativeShiftMapDetailView(trips: trips, zones: zones)
    }
  }
}

struct NativeShiftMapDetailView: View {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        NativeShiftMapRepresentable(trips: trips, zones: zones, interactive: true)
          .ignoresSafeArea(edges: .bottom)
        NativeHeatLegend()
          .padding(16)
          .background(.regularMaterial)
      }
      .navigationTitle("Where you earn")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }.fontWeight(.bold)
        }
      }
    }
  }
}

// MARK: - The main card: Shift Patterns (primary, always shown first)

struct NativeShiftPatternsCard: View {
  let shift: NativeShiftInsights
  let trips: [NativeTrip]
  @Binding var autoTrackTrips: Bool
  @State private var page = 0   // 0 = daily, 1 = weekly

  var body: some View {
    NativeAiCard(banner: "SHIFT PATTERNS") {
      VStack(alignment: .leading, spacing: 16) {
        Text("Where and when you earn most")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)

        if !autoTrackTrips {
          offState
        } else if !shift.hasData {
          buildingState
        } else {
          carousel
        }

        Text(autoTrackTrips
             ? "Learned automatically from your tracked stops — no input needed. Log your pay to sharpen the £/hour estimate."
             : "Turn on automatic tracking to see your best zones and times build up here, with no extra steps.")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var offState: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Turn on automatic tracking so Okkle can learn your best times and zones passively — no screenshots, no shortcuts.")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
      Toggle("Automatic trip tracking", isOn: $autoTrackTrips)
        .font(.system(size: 17, weight: .bold))
        .tint(OkkleColor.brand)
    }
  }

  private var buildingState: some View {
    Label("Building your pattern — keep driving on your working days and this fills in automatically.", systemImage: "hourglass")
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(OkkleColor.brandDark)
      .padding(14)
      .background(OkkleColor.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
  }

  // Two swipeable panels: Daily plan and Weekly pattern.
  private var carousel: some View {
    VStack(spacing: 10) {
      TabView(selection: $page) {
        NativeDailyInsightPanel(shift: shift, trips: trips).tag(0)
        NativeWeeklyInsightPanel(shift: shift).tag(1)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .frame(height: 470)

      HStack(spacing: 7) {
        ForEach(0..<2, id: \.self) { i in
          Capsule()
            .fill(page == i ? OkkleColor.brand : OkkleColor.muted.opacity(0.3))
            .frame(width: page == i ? 18 : 7, height: 7)
            .animation(.easeInOut(duration: 0.2), value: page)
        }
        Text(page == 0 ? "Daily" : "Weekly")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(OkkleColor.muted)
          .padding(.leading, 4)
      }
      .frame(maxWidth: .infinity)
    }
  }
}

// MARK: - Daily panel

struct NativeDailyInsightPanel: View {
  let shift: NativeShiftInsights
  let trips: [NativeTrip]
  @ObservedObject private var areaNamer = NativeAreaNamer.shared
  @ObservedObject private var weather = NativeWeatherService.shared
  @ObservedObject private var locator = NativeOneShotLocator.shared

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 12) {
        if let plan = shift.todayPlan {
          let strongDay = shift.weekdayDetails.prefix(3).contains { $0.weekday == plan.weekday }

          Text(plan.isToday
               ? "TODAY · \(Calendar.current.weekdaySymbols[plan.weekday].uppercased())"
               : "NEXT WORKING DAY · \(Calendar.current.weekdaySymbols[plan.weekday].uppercased())")
            .font(.system(size: 12, weight: .heavy)).tracking(0.4)
            .foregroundStyle(OkkleColor.muted)

          weatherSection(plan: plan, strongDay: strongDay)

          if let now = rightNow(plan) {
            HStack(alignment: .top, spacing: 10) {
              Image(systemName: "location.fill.viewfinder")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(OkkleColor.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
              Text(now)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(OkkleColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OkkleColor.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
          }

          ForEach(plan.driveWindows) { window in
            planRow(
              symbol: "bolt.fill", color: OkkleColor.brand,
              title: window.id == plan.peakWindow?.id ? "Busiest — drive" : "Worth driving",
              value: window.label,
              detail: window.id == plan.peakWindow?.id ? areaText(for: plan.zone) : nil
            )
          }

          if let brk = plan.breakWindow {
            planRow(symbol: "cup.and.saucer.fill", color: OkkleColor.amber,
                    title: "Predicted lull — take your break", value: brk.label, detail: nil)
          } else if plan.driveWindows.isEmpty {
            Text("Not enough on \(plan.dayLabel) yet — a couple more shifts and the timing will sharpen up.")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
          }

          if let pace = goalPace(plan) {
            planRow(symbol: "target", color: .green, title: "Aim for", value: pace.money, detail: pace.detail)
          }

          NativeHourStrip(hourCounts: plan.hourCounts)
            .padding(.top, 2)
        }

        NativeExploreMapButton(trips: trips, zones: shift.zones)
      }
      .padding(.bottom, 4)
    }
    .onAppear {
      locator.request()
      if let c = locator.coordinate { weather.refresh(for: c) }
    }
    .onChange(of: locator.coordinate?.latitude) { _ in
      if let c = locator.coordinate { weather.refresh(for: c) }
    }
  }

  // MARK: Goal pacing

  private func goalPace(_ plan: NativeDayPlan) -> (money: String, detail: String)? {
    guard let perHour = shift.perHour else { return nil }
    let activeHours = max(1, plan.hourCounts.filter { $0 > 0 }.count)
    let target = perHour * Double(activeHours)
    return (gbp(target, whole: true), "≈ \(activeHours)h out at your ~\(gbp(perHour, whole: true))/hr")
  }

  // MARK: Weather layer + "big night" alert

  @ViewBuilder private func weatherSection(plan: NativeDayPlan, strongDay: Bool) -> some View {
    if let today = weather.today, let insight = weatherInsight(today, plan: plan, strongDay: strongDay) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: insight.symbol)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(insight.busy ? OkkleColor.brand : OkkleColor.muted)
          .frame(width: 30)
        VStack(alignment: .leading, spacing: 2) {
          Text(insight.headline)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(insight.busy ? OkkleColor.brandDark : OkkleColor.ink)
          Text(insight.detail)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background((insight.busy ? OkkleColor.brand : OkkleColor.muted).opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
  }

  private func weatherInsight(_ weather: NativeDayWeather, plan: NativeDayPlan, strongDay: Bool) -> (symbol: String, headline: String, detail: String, busy: Bool)? {
    // Look at the working part of the day only.
    let daytime = weather.hours.filter { (10...23).contains($0.hour) }
    guard !daytime.isEmpty else { return nil }
    let boost = daytime.filter(\.boostsDemand)

    if let start = boost.map(\.hour).min(), let end = boost.map(\.hour).max() {
      let range = "\(nativeHourLabel(start))–\(nativeHourLabel(end + 1))"
      let wet = boost.contains(where: \.isWet)
      let cold = boost.contains(where: \.isCold)
      let dayName = Calendar.current.weekdaySymbols[plan.weekday]

      // Big night: bad weather landing on one of your strong days.
      if strongDay {
        let cond = (wet && cold) ? "Cold and wet" : (wet ? "Wet" : "Cold")
        return ("flame.fill",
                "Don't skip \(plan.isToday ? "tonight" : dayName) — big one likely",
                "\(cond) on a \(dayName), your classic busy night. Get out around \(range).",
                true)
      }
      let symbol = wet ? "cloud.rain.fill" : "thermometer.snowflake"
      let headline = wet ? "Rain around \(range) — likely busier" : "Cold around \(range) — likely busier"
      return (symbol, headline, "Orders usually spike and fewer drivers are out, so it can pay to be on.", true)
    }

    // No demand boost — just show a calm conditions summary from midday.
    guard let mid = weather.at(15) ?? daytime.first else { return nil }
    return (mid.symbol, "\(mid.label), \(Int(mid.temperature.rounded()))°",
            "Fair conditions — expect a normal day out there.", false)
  }

  /// Continuous-analysis positioning: given the clock, where to head now.
  private func rightNow(_ plan: NativeDayPlan) -> String? {
    guard plan.isToday, !plan.driveWindows.isEmpty else { return nil }
    let hour = Calendar.current.component(.hour, from: Date())
    let area = areaNamer.name(for: plan.zone ?? CLLocationCoordinate2D()).map { " near \($0)" } ?? ""
    if let current = plan.driveWindows.first(where: { $0.startHour <= hour && hour <= $0.endHour }) {
      return "You're in a busy window (\(current.label)) — stay out\(area)."
    }
    if let next = plan.driveWindows.first(where: { $0.startHour > hour }) {
      return "Head out for \(nativeHourLabel(next.startHour))\(area) — that's when it picks up."
    }
    return "Your busy windows were earlier today — expect it quieter from here."
  }

  private func planRow(symbol: String, color: Color, title: String, value: String, detail: String?) -> some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(color)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
        HStack(spacing: 5) {
          Text(value)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(OkkleColor.ink)
          if let detail {
            Text(detail)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
          }
        }
      }
      Spacer(minLength: 0)
    }
  }

  private func areaText(for coordinate: CLLocationCoordinate2D?) -> String? {
    guard let coordinate, let name = areaNamer.name(for: coordinate) else { return nil }
    return "near \(name)"
  }
}

/// A slim hour-by-hour intensity strip (9am–11pm) so "when exactly" is visible.
struct NativeHourStrip: View {
  let hourCounts: [Int]
  private let hours = Array(9...23)

  var body: some View {
    let peak = max(1, hourCounts.max() ?? 1)
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .bottom, spacing: 3) {
        ForEach(hours, id: \.self) { h in
          let value = h < hourCounts.count ? hourCounts[h] : 0
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(value == 0 ? OkkleColor.muted.opacity(0.15) : nativeHeatColor(Double(value) / Double(peak)))
            .frame(maxWidth: .infinity)
            .frame(height: max(5, CGFloat(value) / CGFloat(peak) * 44))
        }
      }
      .frame(height: 44, alignment: .bottom)
      HStack(spacing: 0) {
        ForEach([9, 12, 15, 18, 21], id: \.self) { h in
          Text(nativeHourLabel(h))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }
}

// MARK: - Weekly panel

struct NativeWeeklyInsightPanel: View {
  let shift: NativeShiftInsights
  @ObservedObject private var areaNamer = NativeAreaNamer.shared
  private var todayWeekday: Int { Calendar.current.component(.weekday, from: Date()) - 1 }

  private var orderedWeekdayStats: [NativeWeekdayStat] {
    [1, 2, 3, 4, 5, 6, 0].compactMap { wd in shift.weekdayStats.first { $0.weekday == wd } }
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 12) {
        Text("THIS WEEK'S PATTERN")
          .font(.system(size: 12, weight: .heavy)).tracking(0.4)
          .foregroundStyle(OkkleColor.muted)

        let maxShare = max(1, shift.weekdayStats.map(\.sharePct).max() ?? 1)
        HStack(alignment: .bottom, spacing: 8) {
          ForEach(orderedWeekdayStats) { stat in
            VStack(spacing: 6) {
              Capsule()
                .fill(stat.count == 0 ? OkkleColor.muted.opacity(0.18) : nativeHeatColor(Double(stat.sharePct) / Double(maxShare)))
                .frame(width: 10, height: max(6, CGFloat(stat.sharePct) / CGFloat(maxShare) * 60))
              Text(stat.symbol)
                .font(.system(size: 11, weight: stat.weekday == todayWeekday ? .heavy : .semibold))
                .foregroundStyle(stat.weekday == todayWeekday ? OkkleColor.ink : OkkleColor.muted)
            }
            .frame(maxWidth: .infinity)
          }
        }
        .frame(height: 78, alignment: .bottom)

        // When & where each of your best days was good.
        VStack(alignment: .leading, spacing: 8) {
          Text("YOUR BEST DAYS")
            .font(.system(size: 12, weight: .heavy)).tracking(0.4)
            .foregroundStyle(OkkleColor.muted)
          ForEach(shift.weekdayDetails.prefix(3)) { day in
            HStack(spacing: 8) {
              Text(day.shortName)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(OkkleColor.ink)
                .frame(width: 38, alignment: .leading)
              Text(day.band.label.lowercased())
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OkkleColor.brandDark)
              if let area = areaText(for: day.coordinate) {
                Text("· \(area)")
                  .font(.system(size: 13, weight: .medium))
                  .foregroundStyle(OkkleColor.muted)
                  .lineLimit(1)
              }
              Spacer(minLength: 0)
            }
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OkkleColor.muted.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

        HStack(spacing: 10) {
          NativeHeatStatChip(title: "Deliveries", value: "\(shift.deliveries)", symbol: "bag.fill", color: OkkleColor.brand)
          NativeHeatStatChip(title: "Unpaid miles", value: "\(shift.deadMilePct)%", symbol: "arrow.triangle.turn.up.right.diamond.fill", color: OkkleColor.amber)
          NativeHeatStatChip(title: "Per hour", value: shift.perHour.map { gbp($0, whole: true) } ?? "—", symbol: "sterlingsign.circle.fill", color: .green)
        }

        if let last = shift.lastShift {
          debriefView(last)
        }

        ForEach(shift.weeklyTips, id: \.self) { tip in
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.up.right.circle.fill")
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(OkkleColor.brand)
              .padding(.top, 1)
            Text(tip)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(OkkleColor.ink)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .padding(.bottom, 4)
    }
  }

  private func areaText(for coordinate: CLLocationCoordinate2D?) -> String? {
    guard let coordinate, let name = areaNamer.name(for: coordinate) else { return nil }
    return name
  }

  @ViewBuilder private func debriefView(_ last: NativeShiftDebrief) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("LAST SHIFT · \(last.dayName.uppercased())")
        .font(.system(size: 12, weight: .heavy)).tracking(0.4)
        .foregroundStyle(OkkleColor.muted)
      HStack(spacing: 6) {
        Text("\(gbp(last.perHour, whole: true))/hr")
          .font(.system(size: 16, weight: .heavy))
          .foregroundStyle(OkkleColor.ink)
        if let avg = last.weekdayAvgPerHour {
          let up = last.perHour >= avg
          Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(up ? OkkleColor.brand : OkkleColor.amber)
          Text("vs \(last.dayName) avg \(gbp(avg, whole: true))")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
        }
      }
      if last.finishedBeforePeak, let peak = last.peakLabel {
        Text("You clocked off before your usual \(peak.lowercased()) peak — worth staying out for it next time.")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(OkkleColor.muted.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
  }
}

struct NativeInsightsView: View {
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared
  private var shift: NativeShiftInsights {
    NativeShiftInsights.build(visits: autoTrack.visits, store: store)
  }

  var body: some View {
    NativeScreen(title: "Insights", collapsedTitle: "Insights", subtitle: "AI guidance, smart nudges and patterns from your work.") {
      NativeShiftPatternsCard(
        shift: shift,
        trips: store.trips,
        autoTrackTrips: Binding(
          get: { store.settings.autoTrackTrips },
          set: { store.settings.autoTrackTrips = $0 }
        )
      )

      // These two cards are one-time set-up prompts: they only appear while
      // the feature is off. Once you turn one on it disappears here — the on/off
      // switch then lives in Settings.
      if !store.settings.loggingReminder {
        NativeAiCard(banner: "REMINDERS") {
          VStack(alignment: .leading, spacing: 16) {
            Text("Keep your records fresh")
              .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Get a gentle nudge to log your miles and pay so nothing slips through the week.")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
            Toggle("Logging reminder", isOn: Binding(
              get: { store.settings.loggingReminder },
              set: { store.settings.loggingReminder = $0 }
            ))
            .font(.system(size: 17, weight: .bold))
            .tint(OkkleColor.brand)
          }
        }
      }

      if !store.settings.taxDeadlineReminders {
        NativeKeyTaxDatesPanel()
      }

      if store.history.isEmpty {
        NativeEmptyState(symbol: "sparkles", title: "Insights will grow with your data", message: "Track trips and log pay to unlock best zones, hours, platform mix and tax-aware suggestions.")
      }
    }
  }
}

struct NativeTaxDeadline: Identifiable {
  let title: String
  let month: Int
  let day: Int
  let note: String

  var id: String { title }

  func nextOccurrence(from reference: Date = Date()) -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: reference)
    let year = calendar.component(.year, from: reference)
    var components = DateComponents(year: year, month: month, day: day, hour: 9, minute: 0)
    var date = calendar.date(from: components) ?? reference
    if date < today {
      components.year = year + 1
      date = calendar.date(from: components) ?? reference
    }
    return date
  }
}

let nativeTaxDeadlines = [
  NativeTaxDeadline(title: "Register for Self Assessment", month: 10, day: 5, note: "Only if this was your first year self-employed."),
  NativeTaxDeadline(title: "File your return & pay your tax", month: 1, day: 31, note: "Online Self Assessment deadline for the previous tax year."),
  NativeTaxDeadline(title: "Second payment on account", month: 7, day: 31, note: "Only if HMRC asked you for payments on account.")
]

func nativeDaysUntil(_ date: Date) -> Int {
  let calendar = Calendar.current
  let today = calendar.startOfDay(for: Date())
  let target = calendar.startOfDay(for: date)
  return calendar.dateComponents([.day], from: today, to: target).day ?? 0
}

func nativeTaxDateLabel(_ date: Date) -> String {
  date.formatted(.dateTime.day().month(.wide).year())
}

@MainActor
func nativeAddDeadlineToCalendar(_ deadline: NativeTaxDeadline) async -> Bool {
  let eventStore = EKEventStore()
  do {
    let granted: Bool
    if #available(iOS 17.0, *) {
      granted = try await eventStore.requestFullAccessToEvents()
    } else {
      granted = try await withCheckedThrowingContinuation { continuation in
        eventStore.requestAccess(to: .event) { granted, error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: granted)
          }
        }
      }
    }
    guard granted, let calendar = eventStore.defaultCalendarForNewEvents else { return false }

    let start = deadline.nextOccurrence()
    let end = Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? start.addingTimeInterval(1800)
    let event = EKEvent(eventStore: eventStore)
    event.calendar = calendar
    event.title = "HMRC: \(deadline.title)"
    event.startDate = start
    event.endDate = end
    event.notes = deadline.note
    event.addAlarm(EKAlarm(relativeOffset: -60 * 60 * 24 * 7))
    try eventStore.save(event, span: .thisEvent)
    return true
  } catch {
    return false
  }
}

struct NativeKeyTaxDatesPanel: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var showSheet = false

  var body: some View {
    NativeAiCard(banner: "KEY TAX DATES") {
      VStack(alignment: .leading, spacing: 16) {
        Text("Keep HMRC deadlines close")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Review Self Assessment dates and add reminders to your calendar.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
        Toggle("Tax deadline reminders", isOn: Binding(
          get: { store.settings.taxDeadlineReminders },
          set: { store.settings.taxDeadlineReminders = $0 }
        ))
        .font(.system(size: 17, weight: .bold))
        .tint(OkkleColor.brand)
        Button {
          showSheet = true
        } label: {
          HStack {
            Text("View dates")
              .font(.system(size: 16, weight: .bold))
            Spacer()
            Image(systemName: "chevron.up")
              .font(.system(size: 15, weight: .bold))
          }
          .foregroundStyle(Color.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
          .background(OkkleColor.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .sheet(isPresented: $showSheet) {
      NativeKeyTaxDatesSheet()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
  }
}

struct NativeKeyTaxDatesSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var alertMessage: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Add these dates to Calendar with a reminder one week before.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)

          NativeGlassCard {
            VStack(spacing: 0) {
              ForEach(nativeTaxDeadlines) { deadline in
                NativeTaxDeadlineRow(deadline: deadline) { message in
                  alertMessage = message
                }
                if deadline.id != nativeTaxDeadlines.last?.id {
                  Divider().padding(.leading, 0)
                }
              }
            }
          }

          Button {
            Task {
              var added = 0
              for deadline in nativeTaxDeadlines {
                if await nativeAddDeadlineToCalendar(deadline) {
                  added += 1
                }
              }
              alertMessage = added == nativeTaxDeadlines.count
                ? "All key tax dates were added to your calendar."
                : "Added \(added) of \(nativeTaxDeadlines.count) dates. Please allow calendar access and try again for the rest."
            }
          } label: {
            Label("Add all dates", systemImage: "calendar.badge.plus")
              .font(.system(size: 16, weight: .bold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 15)
              .foregroundStyle(Color.white)
              .background(OkkleColor.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          }
          .buttonStyle(.plain)

          Text("Keep your records for at least 5 years after the 31 January deadline. MTD for Income Tax adds quarterly updates once your income passes the threshold.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
      }
      .background(NativeBackground())
      .navigationTitle("Key tax dates")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .fontWeight(.bold)
        }
      }
      .alert("Calendar", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(alertMessage ?? "")
      }
    }
  }
}

struct NativeTaxDeadlineRow: View {
  let deadline: NativeTaxDeadline
  let onResult: (String) -> Void
  @State private var busy = false

  var body: some View {
    let next = deadline.nextOccurrence()
    let days = nativeDaysUntil(next)
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(deadline.title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
        Text("\(nativeTaxDateLabel(next)) - \(daysLabel(days))")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.brandDark)
        Text(deadline.note)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Button {
        busy = true
        Task {
          let ok = await nativeAddDeadlineToCalendar(deadline)
          busy = false
          onResult(ok
            ? "\(deadline.title) was added to your calendar with a reminder one week before."
            : "Could not add \(deadline.title). Please allow calendar access and try again.")
        }
      } label: {
        Label(busy ? "Adding" : "Add", systemImage: "calendar.badge.plus")
          .font(.system(size: 13, weight: .bold))
          .labelStyle(.titleAndIcon)
          .foregroundStyle(OkkleColor.brandDark)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(OkkleColor.brand.opacity(0.13), in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(busy)
    }
    .padding(.vertical, 13)
  }

  private func daysLabel(_ days: Int) -> String {
    if days == 0 { return "today" }
    if days == 1 { return "tomorrow" }
    return "in \(days) days"
  }
}

// MARK: - Analysis

/// One weekday + time-of-day bucket, ranked by how many deliveries land in it.
struct NativeShiftWindow: Identifiable, Equatable {
  let weekday: Int   // 0 = Sunday … 6 = Saturday
  let band: NativeTimeFilter
  let count: Int
  let sharePct: Int

  var id: String { "\(weekday)|\(band.rawValue)" }
  var label: String { "\(Calendar.current.shortWeekdaySymbols[weekday]) \(band.label.lowercased())" }
}

/// A clustered zone of pick-up/drop-off activity, for colouring the map by how
/// busy each area has been — not a real-time heatmap, just your own history.
struct NativeZonePoint: Identifiable, Equatable {
  let id = UUID()
  let coordinate: CLLocationCoordinate2D
  let weight: Double   // 0 (quiet) ... 1 (your busiest zone)

  static func == (lhs: NativeZonePoint, rhs: NativeZonePoint) -> Bool {
    lhs.id == rhs.id
  }
}

/// How many deliveries land on one weekday, for the weekly overview bar list.
struct NativeWeekdayStat: Identifiable, Equatable {
  let weekday: Int   // 0 = Sunday … 6 = Saturday
  let count: Int
  let sharePct: Int

  var id: Int { weekday }
  var symbol: String { Calendar.current.veryShortWeekdaySymbols[weekday] }
  var name: String { Calendar.current.weekdaySymbols[weekday] }
}

/// "6pm", "12pm", "1am" — a compact clock label for one hour of the day.
func nativeHourLabel(_ hour: Int) -> String {
  let h = ((hour % 24) + 24) % 24
  let suffix = h < 12 ? "am" : "pm"
  var twelve = h % 12
  if twelve == 0 { twelve = 12 }
  return "\(twelve)\(suffix)"
}

/// A contiguous run of busy (or, for a break, quiet) hours: "6–9pm".
struct NativeHourWindow: Identifiable, Equatable {
  let startHour: Int
  let endHour: Int   // inclusive last hour
  let count: Int

  var id: Int { startHour }
  var label: String { "\(nativeHourLabel(startHour))–\(nativeHourLabel(endHour + 1))" }
}

/// Per-weekday summary for the weekly panel: best band, roughly where, and how
/// busy — so "this week" can say *when and where* each day was good.
struct NativeWeekdayDetail: Identifiable, Equatable {
  let weekday: Int
  let band: NativeTimeFilter
  let count: Int
  let coordinate: CLLocationCoordinate2D?

  var id: Int { weekday }
  var name: String { Calendar.current.weekdaySymbols[weekday] }
  var shortName: String { Calendar.current.shortWeekdaySymbols[weekday] }

  static func == (lhs: NativeWeekdayDetail, rhs: NativeWeekdayDetail) -> Bool {
    lhs.weekday == rhs.weekday && lhs.band == rhs.band && lhs.count == rhs.count
  }
}

/// A same-day plan: the best window to work, a natural lull worth treating as
/// a break, and roughly where the work has been — built from your own history
/// for that specific weekday, not the whole week averaged together.
struct NativeDayPlan {
  let weekday: Int
  let isToday: Bool
  let deliveries: Int
  let bestBand: NativeTimeFilter?
  let breakBand: NativeTimeFilter?
  let zone: CLLocationCoordinate2D?
  let hourCounts: [Int]              // 24 buckets of delivery counts for this day
  let driveWindows: [NativeHourWindow]
  let breakWindow: NativeHourWindow?

  var dayLabel: String { isToday ? "Today" : Calendar.current.weekdaySymbols[weekday] }

  /// The busiest drive window (most deliveries) — the one to anchor the day on.
  var peakWindow: NativeHourWindow? { driveWindows.max { $0.count < $1.count } }
}

/// A short "how did that shift go" read on your most recent logged day: the
/// day's £/hr versus your usual for that weekday, and whether you clocked off
/// before your typical peak.
struct NativeShiftDebrief {
  let weekday: Int
  let perHour: Double
  let weekdayAvgPerHour: Double?
  let finishedBeforePeak: Bool
  let peakLabel: String?

  var dayName: String { Calendar.current.shortWeekdaySymbols[weekday] }
}

/// Everything the passive engine can tell a driver, derived from the stops plus
/// their (weekly) logged income. Aggregate totals stay exact; only the
/// within-week distribution is modelled, so estimates are bounded.
struct NativeShiftInsights {
  let deliveries: Int
  let activeHours: Double
  let paidMiles: Double
  let deadMiles: Double
  let bestWindow: String?
  let perHour: Double?
  let windows: [NativeShiftWindow]
  let quietWindow: NativeShiftWindow?
  let zones: [NativeZonePoint]
  let weekdayStats: [NativeWeekdayStat]
  let weekdayDetails: [NativeWeekdayDetail]   // active days, busiest first
  let todayPlan: NativeDayPlan?
  let lastShift: NativeShiftDebrief?

  var hasData: Bool { deliveries > 0 }
  var totalMiles: Double { paidMiles + deadMiles }
  var deadMilePct: Int {
    guard totalMiles > 0 else { return 0 }
    return Int((deadMiles / totalMiles * 100).rounded())
  }

  static let empty = NativeShiftInsights(
    deliveries: 0, activeHours: 0, paidMiles: 0, deadMiles: 0,
    bestWindow: nil, perHour: nil, windows: [], quietWindow: nil, zones: [],
    weekdayStats: [], weekdayDetails: [], todayPlan: nil, lastShift: nil
  )

  /// A weekly tip or two — kept short, since the panels now carry the detail.
  var weeklyTips: [String] {
    var tips: [String] = []
    if deadMilePct >= 20 {
      tips.append("\(deadMilePct)% of your miles are unpaid repositioning — wait nearer a pick-up zone between orders.")
    }
    if perHour == nil {
      tips.append("Log your pay after a shift to unlock a real £/hour estimate.")
    }
    return tips
  }

  @MainActor
  static func build(visits: [NativeVisit], store: OkkleStore) -> NativeShiftInsights {
    let sorted = visits.sorted { $0.arrival < $1.arrival }
    guard sorted.count > 1 else { return .empty }

    let roadFactor = 1.3
    let shiftGap: TimeInterval = 45 * 60   // a gap longer than this ends a shift

    // Total distance + active time across legs within a shift.
    var totalMeters = 0.0
    var activeSeconds = 0.0
    for k in 1..<sorted.count {
      let prev = sorted[k - 1], cur = sorted[k]
      let gap = cur.arrival.timeIntervalSince(prev.departure)
      if gap < shiftGap {
        totalMeters += cur.location.distance(from: prev.location)
        activeSeconds += max(0, gap) + prev.dwell
      }
    }
    activeSeconds += sorted.last?.dwell ?? 0

    // Deliveries + paid distance: a pick-up drives to the next drop-off.
    var deliveries = 0
    var paidMeters = 0.0
    var deliveryHits: [(weekday: Int, band: NativeTimeFilter, hour: Int, coordinate: CLLocationCoordinate2D)] = []
    var index = 0
    while index < sorted.count {
      if sorted[index].kind == .pickup,
         let dropIndex = (index + 1..<sorted.count).first(where: { sorted[$0].kind == .dropoff }) {
        deliveries += 1
        // Paid = the active delivery leg (restaurant → customer). Everything
        // else (repositioning back out to the next pick-up, idle wandering) is
        // unpaid mileage.
        paidMeters += sorted[dropIndex].location.distance(from: sorted[index].location)
        let date = sorted[dropIndex].arrival
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        let hour = Calendar.current.component(.hour, from: date)
        let band = NativeTimeFilter.allCases.first { $0 != .all && $0.includes(date) } ?? .afternoon
        deliveryHits.append((weekday, band, hour, sorted[index].coordinate))
        index = dropIndex + 1
      } else {
        index += 1
      }
    }

    let paidMiles = paidMeters / 1609.34 * roadFactor
    let totalMiles = max(totalMeters / 1609.34 * roadFactor, paidMiles)
    let deadMiles = max(0, totalMiles - paidMiles)
    let activeHours = activeSeconds / 3600

    // Rank every weekday + time-band bucket by delivery count.
    var counts: [String: Int] = [:]
    for hit in deliveryHits {
      counts["\(hit.weekday)|\(hit.band.rawValue)", default: 0] += 1
    }
    let ranked: [NativeShiftWindow] = counts
      .compactMap { key, count -> NativeShiftWindow? in
        let parts = key.split(separator: "|")
        guard parts.count == 2, let wd = Int(parts[0]), let band = NativeTimeFilter(rawValue: String(parts[1])) else { return nil }
        let share = deliveries > 0 ? Int((Double(count) / Double(deliveries) * 100).rounded()) : 0
        return NativeShiftWindow(weekday: wd, band: band, count: count, sharePct: share)
      }
      .sorted { $0.count > $1.count }
    let bestWindow = ranked.first?.label
    // The quietest bucket that still has a couple of data points — distinct
    // from the best one, so "avoid this" is a real, different recommendation.
    let quietWindow = ranked.count > 1 ? ranked.filter { $0.count >= 2 }.min { $0.count < $1.count } : nil

    // Cluster delivery start points into zones (~500m cells) so the map can
    // show relative busyness rather than a wall of overlapping pins.
    var cells: [String: (coordinate: CLLocationCoordinate2D, count: Int)] = [:]
    let cellSize = 0.006
    for hit in deliveryHits {
      let key = "\(Int((hit.coordinate.latitude / cellSize).rounded())),\(Int((hit.coordinate.longitude / cellSize).rounded()))"
      if let existing = cells[key] {
        cells[key] = (existing.coordinate, existing.count + 1)
      } else {
        cells[key] = (hit.coordinate, 1)
      }
    }
    let maxCount = cells.values.map(\.count).max() ?? 1
    let zones = cells.values.map { NativeZonePoint(coordinate: $0.coordinate, weight: Double($0.count) / Double(maxCount)) }

    // £/hr over the last 14 days: logged income ÷ active hours in the window.
    let windowStart = Date().addingTimeInterval(-14 * 86_400)
    let income = store.records
      .filter { $0.kind == .income && $0.date >= windowStart }
      .reduce(0.0) { $0 + ($1.amount ?? 0) }
    let recentActive = recentActiveHours(sorted, since: windowStart, shiftGap: shiftGap)
    let perHour: Double? = (income > 0 && recentActive > 0.25) ? income / recentActive : nil

    // Weekly overview: how deliveries split across the seven weekdays.
    var weekdayCounts: [Int: Int] = [:]
    for hit in deliveryHits { weekdayCounts[hit.weekday, default: 0] += 1 }
    let weekdayStats = (0...6).map { wd -> NativeWeekdayStat in
      let count = weekdayCounts[wd] ?? 0
      let share = deliveries > 0 ? Int((Double(count) / Double(deliveries) * 100).rounded()) : 0
      return NativeWeekdayStat(weekday: wd, count: count, sharePct: share)
    }

    // Per-weekday best band + zone (busiest first) — the "when & where" list.
    let weekdayDetails: [NativeWeekdayDetail] = (0...6)
      .filter { (weekdayCounts[$0] ?? 0) > 0 }
      .map { wd -> NativeWeekdayDetail in
        let (band, zone) = bestBandAndZone(for: wd, deliveryHits: deliveryHits, cellSize: cellSize)
        return NativeWeekdayDetail(weekday: wd, band: band, count: weekdayCounts[wd] ?? 0, coordinate: zone)
      }
      .sorted { $0.count > $1.count }

    // Today's plan: today if it has data, otherwise the next weekday (working
    // day or not — we only ever have data on working days anyway) that does.
    let todayWeekday = Calendar.current.component(.weekday, from: Date()) - 1
    let planWeekday = (0..<7)
      .map { (todayWeekday + $0) % 7 }
      .first { weekdayCounts[$0, default: 0] > 0 }
    let todayPlan: NativeDayPlan? = planWeekday.map { wd in
      let (bestBand, topZone) = bestBandAndZone(for: wd, deliveryHits: deliveryHits, cellSize: cellSize)

      // Hour-level shape for that weekday → concrete drive/break windows.
      var hourCounts = Array(repeating: 0, count: 24)
      for hit in deliveryHits where hit.weekday == wd { hourCounts[hit.hour] += 1 }
      let drives = nativeHourWindows(from: hourCounts)
      let breakWin = nativeBreakWindow(from: drives)

      var bandCounts: [NativeTimeFilter: Int] = [:]
      for hit in deliveryHits where hit.weekday == wd { bandCounts[hit.band, default: 0] += 1 }
      let order: [NativeTimeFilter] = [.morning, .lunch, .afternoon, .dinner, .late]
      let breakBand = order
        .filter { $0 != bestBand && (bandCounts[$0] ?? 0) >= 1 }
        .min { (bandCounts[$0] ?? 0) < (bandCounts[$1] ?? 0) }

      return NativeDayPlan(
        weekday: wd,
        isToday: wd == todayWeekday,
        deliveries: weekdayCounts[wd] ?? 0,
        bestBand: bestBand,
        breakBand: breakBand,
        zone: topZone,
        hourCounts: hourCounts,
        driveWindows: drives,
        breakWindow: breakWin
      )
    }

    let lastShift = debrief(sorted: sorted, deliveryHits: deliveryHits, store: store, shiftGap: shiftGap, cellSize: cellSize)

    return NativeShiftInsights(
      deliveries: deliveries,
      activeHours: activeHours,
      paidMiles: paidMiles,
      deadMiles: deadMiles,
      bestWindow: bestWindow,
      perHour: perHour,
      windows: Array(ranked.prefix(5)),
      quietWindow: quietWindow,
      zones: zones,
      weekdayStats: weekdayStats,
      weekdayDetails: weekdayDetails,
      todayPlan: todayPlan,
      lastShift: lastShift
    )
  }

  /// Read on the most recent day (in the last fortnight) that has both stops
  /// and logged income: that day's £/hr vs your usual for that weekday, and
  /// whether you finished before your typical peak band.
  @MainActor
  private static func debrief(sorted: [NativeVisit], deliveryHits: [NativeDeliveryHit], store: OkkleStore, shiftGap: TimeInterval, cellSize: Double) -> NativeShiftDebrief? {
    let cal = Calendar.current
    // Income by calendar day (last 14 days).
    let since = Date().addingTimeInterval(-14 * 86_400)
    var incomeByDay: [Date: Double] = [:]
    for r in store.records where r.kind == .income && r.date >= since {
      incomeByDay[cal.startOfDay(for: r.date), default: 0] += r.amount ?? 0
    }
    guard !incomeByDay.isEmpty else { return nil }

    // The most recent day that also has tracked stops.
    let daysWithStops = Set(sorted.map { cal.startOfDay(for: $0.arrival) })
    guard let day = incomeByDay.keys.filter({ daysWithStops.contains($0) }).max() else { return nil }

    let dayVisits = sorted.filter { cal.isDate($0.arrival, inSameDayAs: day) }
    let activeHours = recentActiveHours(dayVisits, since: day, shiftGap: shiftGap)
    guard activeHours > 0.25, let income = incomeByDay[day], income > 0 else { return nil }
    let perHour = income / activeHours
    let weekday = cal.component(.weekday, from: day) - 1

    // Average £/hr for that weekday across the fortnight.
    var wdIncome = 0.0
    for (d, inc) in incomeByDay where cal.component(.weekday, from: d) - 1 == weekday { wdIncome += inc }
    var wdHours = 0.0
    let grouped = Dictionary(grouping: sorted.filter { cal.component(.weekday, from: $0.arrival) - 1 == weekday }) { cal.startOfDay(for: $0.arrival) }
    for (d, vs) in grouped { wdHours += recentActiveHours(vs, since: d, shiftGap: shiftGap) }
    let weekdayAvg: Double? = wdHours > 0.25 ? wdIncome / wdHours : nil

    // Did they finish before their usual peak band for that weekday?
    let (peakBand, _) = bestBandAndZone(for: weekday, deliveryHits: deliveryHits, cellSize: cellSize)
    let lastHour = dayVisits.map { cal.component(.hour, from: $0.arrival) }.max() ?? 0
    let peakStart = peakBand.startHour
    let finishedBeforePeak = peakStart != nil && lastHour < (peakStart ?? 0)

    return NativeShiftDebrief(
      weekday: weekday,
      perHour: perHour,
      weekdayAvgPerHour: weekdayAvg,
      finishedBeforePeak: finishedBeforePeak,
      peakLabel: peakBand.label
    )
  }

  private static func recentActiveHours(_ sorted: [NativeVisit], since: Date, shiftGap: TimeInterval) -> Double {
    var seconds = 0.0
    for k in 1..<max(sorted.count, 1) {
      let prev = sorted[k - 1], cur = sorted[k]
      guard cur.arrival >= since else { continue }
      let gap = cur.arrival.timeIntervalSince(prev.departure)
      if gap < shiftGap { seconds += max(0, gap) + prev.dwell }
    }
    return seconds / 3600
  }
}

typealias NativeDeliveryHit = (weekday: Int, band: NativeTimeFilter, hour: Int, coordinate: CLLocationCoordinate2D)

/// The busiest time-band and roughly-where for one weekday.
func bestBandAndZone(for weekday: Int, deliveryHits: [NativeDeliveryHit], cellSize: Double) -> (band: NativeTimeFilter, zone: CLLocationCoordinate2D?) {
  var bandCounts: [NativeTimeFilter: Int] = [:]
  var cells: [String: (coordinate: CLLocationCoordinate2D, count: Int)] = [:]
  for hit in deliveryHits where hit.weekday == weekday {
    bandCounts[hit.band, default: 0] += 1
    let key = "\(Int((hit.coordinate.latitude / cellSize).rounded())),\(Int((hit.coordinate.longitude / cellSize).rounded()))"
    if let existing = cells[key] {
      cells[key] = (existing.coordinate, existing.count + 1)
    } else {
      cells[key] = (hit.coordinate, 1)
    }
  }
  let band = bandCounts.max { $0.value < $1.value }?.key ?? .afternoon
  let zone = cells.values.max { $0.count < $1.count }?.coordinate
  return (band, zone)
}

/// Contiguous runs of "busy" hours (≥ 40% of the day's peak), each a drive window.
func nativeHourWindows(from hourCounts: [Int]) -> [NativeHourWindow] {
  let peak = hourCounts.max() ?? 0
  guard peak > 0 else { return [] }
  let threshold = max(1, Int((Double(peak) * 0.4).rounded(.up)))
  var windows: [NativeHourWindow] = []
  var start: Int?
  var runCount = 0
  for h in 0..<24 {
    if hourCounts[h] >= threshold {
      if start == nil { start = h; runCount = 0 }
      runCount += hourCounts[h]
    } else if let s = start {
      windows.append(NativeHourWindow(startHour: s, endHour: h - 1, count: runCount))
      start = nil
    }
  }
  if let s = start { windows.append(NativeHourWindow(startHour: s, endHour: 23, count: runCount)) }
  return windows
}

/// The widest quiet gap between two drive windows — the natural break.
func nativeBreakWindow(from drives: [NativeHourWindow]) -> NativeHourWindow? {
  guard drives.count >= 2 else { return nil }
  var best: NativeHourWindow?
  for i in 1..<drives.count {
    let gapStart = drives[i - 1].endHour + 1
    let gapEnd = drives[i].startHour - 1
    guard gapEnd >= gapStart else { continue }
    let length = gapEnd - gapStart + 1
    if best == nil || length > (best!.endHour - best!.startHour + 1) {
      best = NativeHourWindow(startHour: gapStart, endHour: gapEnd, count: 0)
    }
  }
  return best
}
