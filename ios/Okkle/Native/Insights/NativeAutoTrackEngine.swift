import CoreMotion
import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit
@preconcurrency import UserNotifications

// MARK: - Model

/// One passively-detected stop within an automatic shift. A short stop with
/// no food place nearby reads as a customer drop-off; a longer stop at (or
/// beside) a restaurant reads as an order pick-up.
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

/// Where an automatic shift currently stands. `driving` means we're actively
/// recording a continuous GPS route; `stationaryPending` means motion says
/// we've stopped and we're waiting to see whether that's a delivery stop
/// (driving resumes) or the end of the shift (the stationary timer expires).
enum NativeAutoShiftPhase: Equatable {
  case idle
  case driving
  case stationaryPending
}

/// Passive, hands-off shift tracking. On a working day, the moment Core
/// Motion reports driving, this starts recording a real continuous GPS route
/// — the same fidelity as the manual Start-trip flow, just triggered
/// automatically instead of by a tap. Going stationary pauses recording and
/// starts a countdown: if driving resumes before it expires, the stop
/// becomes a logged pick-up/drop-off and the same shift continues; if it
/// expires, the shift ends, gets saved as a real trip, and the driver gets a
/// notification to check it.
@MainActor
final class NativeAutoTrackEngine: NSObject, ObservableObject, CLLocationManagerDelegate {
  static let shared = NativeAutoTrackEngine()

  @Published private(set) var visits: [NativeVisit] = []
  @Published private(set) var shiftPhase: NativeAutoShiftPhase = .idle
  @Published private(set) var lastAutoShiftID: UUID?
  @Published private(set) var liveShiftVehicle: NativeVehicle = .car
  @Published private(set) var liveShiftMiles: Double = 0
  @Published private(set) var liveShiftStartedAt: Date?
  @Published private(set) var liveShiftPoints: [RoutePoint] = []

  private let manager = CLLocationManager()
  private let motionManager = CMMotionActivityManager()
  private let motionQueue = OperationQueue()
  private let storageKey = "uk.okkle.native.autotrack.visits.v1"
  private let shiftNotificationIdentifier = "uk.okkle.native.shift-logged"
  private weak var store: OkkleStore?
  private var motionMonitoring = false

  // Live shift state — a continuous GPS route, mirroring NativeTripSession's
  // own accumulation approach so automatic shifts get the same real-route
  // mileage as manually-tracked ones, not a straight-line estimate.
  private var shiftPoints: [RoutePoint] = []
  private var shiftMiles: Double = 0
  private var shiftStartedAt: Date?
  private var shiftLastLocation: CLLocation?
  private var shiftLastRoutePointLocation: CLLocation?
  private let routePointDistance: CLLocationDistance = 30

  // A stop currently being timed — may resolve into a logged visit (driving
  // resumes) or trigger shift-end (the stationary timer expires).
  private var stationaryTimer: Timer?
  private var stationarySince: Date?
  private var stationaryCoordinate: CLLocationCoordinate2D?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    manager.distanceFilter = 20
    manager.activityType = .automotiveNavigation
    manager.pausesLocationUpdatesAutomatically = false
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

  /// Start or stop listening for driving on working days, to match the
  /// Automatic-tracking setting. Listening itself is just low-power motion
  /// monitoring — the GPS only turns on once driving is actually detected.
  func refresh() {
    guard let settings = store?.settings,
          settings.autoTrackTrips,
          nativeIsWorkingDay(Date(), settings: settings) else {
      stopMonitoring()
      return
    }
    startMotionMonitoring()
    if manager.authorizationStatus == .notDetermined {
      manager.requestAlwaysAuthorization()
    }
  }

  private func stopMonitoring() {
    stopMotionMonitoring()
    // Turning tracking off mid-shift shouldn't throw away real, already-
    // recorded GPS miles — save what's there rather than silently lose it.
    if shiftPhase != .idle { concludeShift() }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in self.refresh() }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    Task { @MainActor in self.handleShiftLocationUpdates(locations) }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

  // MARK: Motion → shift state machine

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
    // A manual trip already running takes priority — never double-record.
    guard NativeTripSession.shared.phase == .setup else { return }

    if activity.automotive, activity.confidence != .low {
      handleDrivingSignal()
    } else if activity.stationary, activity.confidence != .low {
      handleStationarySignal()
    }
    // Ambiguous readings (walking, unknown, low confidence) don't change
    // phase — a brief wobble shouldn't flip the state machine back and forth.
  }

  private func handleDrivingSignal() {
    switch shiftPhase {
    case .idle:
      beginShift()
    case .stationaryPending:
      resumeShift()
    case .driving:
      break
    }
  }

  private func handleStationarySignal() {
    guard shiftPhase == .driving else { return }
    shiftPhase = .stationaryPending
    stationarySince = Date()
    stationaryCoordinate = shiftLastLocation?.coordinate
    scheduleStationaryTimeout()
  }

  private func scheduleStationaryTimeout() {
    stationaryTimer?.invalidate()
    let timeout = store?.settings.autoTrackCalibration.stationaryTimeoutSeconds ?? 20 * 60
    stationaryTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.concludeShift() }
    }
    stationaryTimer?.tolerance = 30
  }

  private func beginShift() {
    shiftPhase = .driving
    shiftPoints = []
    shiftMiles = 0
    shiftStartedAt = Date()
    shiftLastLocation = nil
    shiftLastRoutePointLocation = nil
    liveShiftVehicle = store?.settings.defaultVehicle ?? .car
    publishLiveShift()
    setBackgroundTrackingEnabled(true)
    manager.startUpdatingLocation()
  }

  /// Driving resumed before the stationary timer expired — the stop that was
  /// being timed becomes a logged pick-up/drop-off, and the same shift (same
  /// trip, same accumulated mileage) keeps going.
  private func resumeShift() {
    finalizePendingStop()
    stationaryTimer?.invalidate()
    stationaryTimer = nil
    shiftPhase = .driving
  }

  /// The stationary timer expired (or tracking got turned off mid-shift) —
  /// the shift is over. Save it as a real trip and notify the driver.
  private func concludeShift() {
    guard shiftPhase != .idle else { return }
    finalizePendingStop()
    saveShiftAsTrip()
    manager.stopUpdatingLocation()
    setBackgroundTrackingEnabled(false)
    stationaryTimer?.invalidate()
    stationaryTimer = nil
    shiftPhase = .idle
    shiftPoints = []
    shiftMiles = 0
    shiftStartedAt = nil
    shiftLastLocation = nil
    shiftLastRoutePointLocation = nil
    stationarySince = nil
    stationaryCoordinate = nil
    publishLiveShift()
  }

  // MARK: Continuous route recording (mirrors NativeTripSession's approach)

  private func handleShiftLocationUpdates(_ locations: [CLLocation]) {
    guard shiftPhase == .driving || shiftPhase == .stationaryPending else { return }
    for location in locations where shouldUseShiftLocation(location) {
      if let shiftLastLocation {
        let delta = location.distance(from: shiftLastLocation) / 1_609.344
        if delta > 0.002 && delta < 1 { shiftMiles += delta }
      }
      shiftLastLocation = location
      appendShiftRoutePoint(for: location)
      if shiftPhase == .stationaryPending { stationaryCoordinate = location.coordinate }
    }
    publishLiveShift()
  }

  private func publishLiveShift() {
    liveShiftMiles = shiftMiles
    liveShiftStartedAt = shiftStartedAt
    liveShiftPoints = shiftPoints
  }

  private func shouldUseShiftLocation(_ location: CLLocation) -> Bool {
    guard location.horizontalAccuracy >= 0 else { return false }
    guard abs(location.timestamp.timeIntervalSinceNow) < 30 else { return false }
    return location.horizontalAccuracy <= 250
  }

  private func appendShiftRoutePoint(for location: CLLocation) {
    if let shiftLastRoutePointLocation {
      guard location.distance(from: shiftLastRoutePointLocation) >= routePointDistance else { return }
    }
    shiftPoints.append(RoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, timestamp: location.timestamp))
    shiftLastRoutePointLocation = location
  }

  private func setBackgroundTrackingEnabled(_ enabled: Bool) {
    guard supportsBackgroundLocation else { return }
    manager.allowsBackgroundLocationUpdates = enabled
    manager.showsBackgroundLocationIndicator = enabled
  }

  private var supportsBackgroundLocation: Bool {
    let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    return backgroundModes.contains("location")
  }

  // MARK: Stop classification + shift finalization

  /// Turns the stop currently being timed into a logged visit — reusing the
  /// same dwell + nearby-food-venue heuristic as before, just fed by the
  /// motion-driven timer instead of a CLVisit callback.
  private func finalizePendingStop() {
    guard let stationarySince, let coordinate = stationaryCoordinate else { return }
    let departure = Date()
    var visit = NativeVisit(latitude: coordinate.latitude, longitude: coordinate.longitude,
                            arrival: stationarySince, departure: departure)
    let calibration = store?.settings.autoTrackCalibration ?? NativeAutoTrackCalibration()
    visit.kind = visit.dwell >= calibration.pickupDwellThreshold ? .pickup : .dropoff
    visits.append(visit)
    trim()
    save()
    classifyWithMapKit(visit.id, coordinate: coordinate, calibration: calibration)
    runBackgroundExploration(for: visit)
    self.stationarySince = nil
    self.stationaryCoordinate = nil
  }

  private func saveShiftAsTrip() {
    guard let store, let shiftStartedAt else { return }
    // Skip near-zero noise (a driving reading that immediately went
    // stationary again without covering real distance).
    guard shiftMiles > 0.1 || shiftPoints.count > 2 else { return }
    let vehicle = store.settings.defaultVehicle
    let trip = NativeTrip(
      vehicle: vehicle,
      miles: shiftMiles,
      deduction: store.calcDeduction(miles: shiftMiles, vehicle: vehicle, date: shiftStartedAt),
      startedAt: shiftStartedAt,
      endedAt: Date(),
      points: shiftPoints
    )
    store.addTrip(trip)
    lastAutoShiftID = trip.id
    sendShiftLoggedNotification(trip)
  }

  private func sendShiftLoggedNotification(_ trip: NativeTrip) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { [shiftNotificationIdentifier] granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = "Shift logged"
      let miles = String(format: "%.1f", trip.miles)
      content.body = "\(miles) miles logged automatically. Tap to check it's right."
      content.sound = .default
      content.userInfo = ["type": "autoShiftReview", "tripID": trip.id.uuidString]
      let request = UNNotificationRequest(
        identifier: "\(shiftNotificationIdentifier)-\(trip.id.uuidString)",
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
  private func classifyWithMapKit(_ id: UUID, coordinate: CLLocationCoordinate2D, calibration: NativeAutoTrackCalibration) {
    let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: calibration.foodPoiRadiusMeters)
    request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .foodMarket, .brewery, .nightlife])
    MKLocalSearch(request: request).start { [weak self] response, _ in
      guard let self else { return }
      Task { @MainActor in
        guard let index = self.visits.firstIndex(where: { $0.id == id }) else { return }
        if let food = response?.mapItems.first {
          self.visits[index].kind = .pickup
          self.visits[index].placeName = food.name
        } else if self.visits[index].dwell < calibration.dropoffMaxDwellThreshold {
          self.visits[index].kind = .dropoff
        }
        self.save()
      }
    }
  }

  // MARK: Persistence

  private func trim() {
    // Keep just over a year of stops — the Insights carousel's Yearly period
    // needs real history to show, not just whatever a 60-day window left.
    let cutoff = Date().addingTimeInterval(-370 * 86_400)
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

  /// Removes a stop the driver flagged as wrong in the shift-review screen.
  func discardVisit(_ id: UUID) {
    visits.removeAll { $0.id == id }
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
