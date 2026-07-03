import CoreMotion
import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit
@preconcurrency import UserNotifications

// MARK: - Model

/// One passively-detected stop (from Core Location Visit monitoring). A short
/// stop with no food place nearby reads as a customer drop-off; a longer stop
/// at (or beside) a restaurant reads as an order pick-up.
struct NativeVisit: Codable, Identifiable, Equatable {
  var id = UUID()
  var latitude: Double
  var longitude: Double
  var arrival: Date
  var departure: Date
  var kindRaw: String = Kind.other.rawValue
  var placeName: String?

  enum Kind: String, Codable, CaseIterable { case pickup, dropoff, other }

  var kind: Kind {
    get { Kind(rawValue: kindRaw) ?? .other }
    set { kindRaw = newValue.rawValue }
  }
  var dwell: TimeInterval { max(0, departure.timeIntervalSince(arrival)) }
  var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
  var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// Whether a given weekday (0 = Sunday … 6 = Saturday) is a working day.
func nativeIsWorkingDay(_ date: Date, settings: NativeSettings) -> Bool {
  let weekday = Calendar.current.component(.weekday, from: date) - 1   // 1-based → 0-based
  return settings.workingDays.contains(weekday)
}

// MARK: - Engine

/// Passive, hands-off tracking. After a one-time "Always" location grant it
/// watches Core Location Visits in the background and, on working days, records
/// pick-up / drop-off stops — the raw material for the shift insights. No taps,
/// no screenshots, no shortcuts.
@MainActor
final class NativeAutoTrackEngine: NSObject, ObservableObject, CLLocationManagerDelegate {
  static let shared = NativeAutoTrackEngine()

  @Published private(set) var visits: [NativeVisit] = []
  @Published private(set) var pendingStartPrompt = false

  private let manager = CLLocationManager()
  private let motionManager = CMMotionActivityManager()
  private let motionQueue = OperationQueue()
  private let storageKey = "uk.okkle.native.autotrack.visits.v1"
  private let startPromptIdentifier = "uk.okkle.native.trip-start-prompt"
  private let promptCooldown: TimeInterval = 12 * 60
  private weak var store: OkkleStore?
  private var motionMonitoring = false
  private var lastPromptedAt: Date?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    motionQueue.name = "uk.okkle.native.auto-track-motion"
    motionQueue.qualityOfService = .utility
    load()
  }

  func configure(store: OkkleStore) {
    self.store = store
    store.onRecordAdded = { [weak self] record in self?.checkOutcome(for: record) }
    refresh()
  }

  /// The self-correcting half of the confidence model: every time pay gets
  /// logged, check whether that date was one the model had called a "peak"
  /// day, and hand the outcome to the tracker. Entirely silent — this never
  /// shows anything, it just quietly keeps the confidence label honest.
  private func checkOutcome(for record: NativeRecord) {
    guard record.kind == .income, let amount = record.amount, let store else { return }
    let weekday = Calendar.current.component(.weekday, from: record.date) - 1
    let peakWeekdays = NativeShiftInsights.build(visits: visits, store: store)
      .weekdayDetails.prefix(3).map(\.weekday)
    NativeOutcomeTracker.shared.record(amount: amount, period: record.period,
                                       wasPredictedPeakDay: peakWeekdays.contains(weekday))
  }

  /// Start or stop passive monitoring to match the Automatic-tracking setting.
  func refresh() {
    guard let settings = store?.settings,
          settings.autoTrackTrips,
          nativeIsWorkingDay(Date(), settings: settings) else {
      stopMonitoring()
      return
    }
    startMotionMonitoring()
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestAlwaysAuthorization()
    case .authorizedAlways:
      manager.allowsBackgroundLocationUpdates = true
      manager.startMonitoringVisits()
    default:
      // While-in-use still lets us collect visits when the app is foreground.
      manager.startMonitoringVisits()
    }
  }

  private func stopMonitoring() {
    manager.stopMonitoringVisits()
    stopMotionMonitoring()
    pendingStartPrompt = false
  }

  func dismissStartPrompt() {
    pendingStartPrompt = false
  }

  func acceptStartPrompt() {
    pendingStartPrompt = false
    lastPromptedAt = Date()
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in self.refresh() }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    // Ignore the "arrived, still here" event — wait for a completed visit.
    guard visit.departureDate != Date.distantFuture else { return }
    Task { @MainActor in self.record(visit) }
  }

  private func record(_ clVisit: CLVisit) {
    guard let settings = store?.settings,
          settings.autoTrackTrips,
          nativeIsWorkingDay(clVisit.departureDate, settings: settings) else { return }
    let arrival = clVisit.arrivalDate == Date.distantPast ? clVisit.departureDate : clVisit.arrivalDate
    var visit = NativeVisit(
      latitude: clVisit.coordinate.latitude,
      longitude: clVisit.coordinate.longitude,
      arrival: arrival,
      departure: clVisit.departureDate
    )
    // Provisional guess from dwell; MapKit refines it below.
    visit.kind = visit.dwell >= 150 ? .pickup : .dropoff
    visits.append(visit)
    trim()
    save()
    classifyWithMapKit(visit.id, coordinate: visit.coordinate)
    runBackgroundExploration(for: visit)
  }

  private func startMotionMonitoring() {
    guard CMMotionActivityManager.isActivityAvailable(), !motionMonitoring else { return }
    motionMonitoring = true
    motionManager.startActivityUpdates(to: motionQueue) { [weak self] activity in
      guard let activity else { return }
      Task { @MainActor in
        self?.handleMotionActivity(activity)
      }
    }
  }

  private func stopMotionMonitoring() {
    guard motionMonitoring else { return }
    motionManager.stopActivityUpdates()
    motionMonitoring = false
  }

  private func handleMotionActivity(_ activity: CMMotionActivity) {
    guard let settings = store?.settings,
          settings.autoTrackTrips,
          nativeIsWorkingDay(Date(), settings: settings) else { return }
    guard NativeTripSession.shared.phase == .setup else { return }
    guard activity.automotive, activity.confidence != .low else { return }
    promptToStartTrip()
  }

  private func promptToStartTrip() {
    let now = Date()
    if let lastPromptedAt, now.timeIntervalSince(lastPromptedAt) < promptCooldown { return }
    guard !pendingStartPrompt else { return }
    lastPromptedAt = now
    pendingStartPrompt = true

    guard UIApplication.shared.applicationState != .active else { return }
    sendStartTripNotification()
  }

  private func sendStartTripNotification() {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { [startPromptIdentifier] granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = "Start tracking this trip?"
      content.body = "Okkle detected you may be driving. Open the app to start recording miles."
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: startPromptIdentifier,
        content: content,
        trigger: nil
      )
      center.add(request)
    }
  }

  /// The automatic feedback loop for "areas to try", entirely silent: log
  /// this real visit against any candidate patch it lands near (the trial
  /// evidence that eventually validates or drops a guess), then opportunistically
  /// probe for new nearby candidates worth quietly testing next.
  private func runBackgroundExploration(for visit: NativeVisit) {
    guard let store else { return }
    let today = Calendar.current.startOfDay(for: visit.arrival)
    let dayIncome = store.records
      .filter { $0.kind == .income && Calendar.current.isDate($0.date, inSameDayAs: today) }
      .reduce(0.0) { $0 + ($1.amount ?? 0) }
    NativeExploreCandidateStore.shared.recordVisit(visit.coordinate, dayIncome: dayIncome)

    let zones = NativeShiftInsights.build(visits: visits, store: store).zones.map(\.coordinate)
    NativeAreaSuggester.refresh(near: visit.coordinate, knownZones: zones)
  }

  /// Use Apple Maps as an information layer: if there's a food place right by the
  /// stop it's a pick-up; otherwise it's most likely a customer drop-off.
  private func classifyWithMapKit(_ id: UUID, coordinate: CLLocationCoordinate2D) {
    let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 45)
    request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .foodMarket, .brewery, .nightlife])
    MKLocalSearch(request: request).start { [weak self] response, _ in
      guard let self else { return }
      Task { @MainActor in
        guard let index = self.visits.firstIndex(where: { $0.id == id }) else { return }
        if let food = response?.mapItems.first {
          self.visits[index].kind = .pickup
          self.visits[index].placeName = food.name
        } else if self.visits[index].dwell < 240 {
          self.visits[index].kind = .dropoff
        }
        self.save()
      }
    }
  }

  // MARK: Persistence

  private func trim() {
    // Keep the last 60 days of stops — plenty for pattern insights.
    let cutoff = Date().addingTimeInterval(-60 * 86_400)
    visits.removeAll { $0.departure < cutoff }
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: storageKey),
          let saved = try? JSONDecoder().decode([NativeVisit].self, from: data) else { return }
    visits = saved
  }

  private func save() {
    if let data = try? JSONEncoder().encode(visits) {
      UserDefaults.standard.set(data, forKey: storageKey)
    }
  }

  /// Test/demo seeding used by the SEED_DEMO launch flag only.
  func seed(_ seeded: [NativeVisit]) {
    visits = seeded
    save()
  }
}

/// Synthetic two-week stop history for the SEED_DEMO launch flag. Thu-Sat get a
/// lunch bump, a quiet afternoon lull (so break detection has something to
/// find) and a busy dinner peak; Sunday is very quiet; Mon-Wed are lunch-only -
/// enough shape to exercise the best-window, break and weekly-pattern logic.
func nativeDemoVisits() -> [NativeVisit] {
  struct Slot { let hour: Int; let count: Int; let latOffset: Double; let lonOffset: Double }

  var out: [NativeVisit] = []
  let cal = Calendar.current
  let base = CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)

  for dayOffset in 1...14 {
    guard let day = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
    let weekday = cal.component(.weekday, from: day) - 1   // 0 = Sun … 6 = Sat

    let slots: [Slot]
    switch weekday {
    case 4, 5, 6:   // Thu, Fri, Sat - lunch, a quiet afternoon lull, then dinner peak
      slots = [
        Slot(hour: 12, count: 2, latOffset: -0.006, lonOffset: -0.004),
        Slot(hour: 15, count: 1, latOffset: 0.002, lonOffset: 0.006),
        Slot(hour: 19, count: 5, latOffset: 0.010, lonOffset: -0.002)
      ]
    case 0:         // Sunday - very quiet
      slots = [Slot(hour: 13, count: 1, latOffset: -0.004, lonOffset: 0.003)]
    default:        // Mon-Wed - lunch only
      slots = [Slot(hour: 12, count: 2, latOffset: -0.006, lonOffset: -0.004)]
    }

    for slot in slots {
      for i in 0..<slot.count {
        let minute = (i % 3) * 18
        guard let start = cal.date(bySettingHour: slot.hour + i / 3, minute: minute, second: 0, of: day) else { continue }
        let dLat = slot.latOffset + Double(i) * 0.0015
        let dLon = slot.lonOffset + Double(i) * 0.0015
        var pickup = NativeVisit(latitude: base.latitude + dLat, longitude: base.longitude + dLon,
                                 arrival: start, departure: start.addingTimeInterval(240))
        pickup.kind = .pickup
        pickup.placeName = "Restaurant"
        out.append(pickup)
        let dropStart = start.addingTimeInterval(600)
        var drop = NativeVisit(latitude: base.latitude + dLat + 0.012, longitude: base.longitude + dLon + 0.01,
                               arrival: dropStart, departure: dropStart.addingTimeInterval(90))
        drop.kind = .dropoff
        out.append(drop)
      }
    }
  }
  return out
}
