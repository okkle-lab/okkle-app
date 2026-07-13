import AVFoundation
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
  // True when this pickup/dropoff wasn't a real classified stop, but a stand-in
  // built from a trip's raw start/end GPS point (see
  // NativeShiftInsights.enrichedVisits). For a home-based driver that's
  // usually just "wherever the shift happened to start/end" — not a
  // restaurant or customer address — so it's real signal for deliveries
  // count/mileage/active-hours, but not trustworthy for "where to go".
  var isEndpointGuess: Bool = false
  // True when this visit was recorded while a known vehicle connection
  // dropped. That is a stronger signal than motion alone because the driver
  // probably left the car rather than waiting at lights.
  var vehicleDisconnectConfirmed: Bool? = nil

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
enum NativeAutoShiftPhase: String, Equatable {
  case idle
  case driving
  case stationaryPending
  case paused
}

/// Snapshot of an in-progress automatic shift, persisted so a crash, memory-
/// pressure eviction, or reboot mid-shift doesn't silently lose the miles
/// already recorded — restored and re-armed on the next launch.
private struct NativeAutoShiftSnapshot: Codable {
  var phaseRaw: String
  var points: [RoutePoint]
  var miles: Double
  var startedAt: Date
  var vehicleRaw: String
  var sawVehicleConnection: Bool
  var armedForHomeArrival: Bool
  var lastLocationLat: Double?
  var lastLocationLon: Double?
  var lastLocationTimestamp: Date?
  var lastLocationAccuracy: Double?
  var lastRoutePointLat: Double?
  var lastRoutePointLon: Double?
  var stationarySince: Date?
  var stationaryLat: Double?
  var stationaryLon: Double?
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
enum NativeVehicleConnectionMonitor {
  private static var carPlayConnected = false

  static func setCarPlayConnected(_ connected: Bool) {
    let changed = carPlayConnected != connected
    carPlayConnected = connected
    if changed {
      NotificationCenter.default.post(name: .nativeVehicleConnectionDidChange, object: nil)
    }
  }

  static var isLikelyConnectedToVehicle: Bool {
    carPlayConnected || audioRouteLooksLikeVehicle
  }

  private static var audioRouteLooksLikeVehicle: Bool {
    AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
      switch output.portType {
      case .carAudio, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
        return true
      default:
        return false
      }
    }
  }
}

extension Notification.Name {
  static let nativeVehicleConnectionDidChange = Notification.Name("uk.okkle.native.vehicleConnectionDidChange")
}

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
  @Published private(set) var liveShiftUsesEnhancedTracking = false

  private let manager = CLLocationManager()
  private let motionManager = CMMotionActivityManager()
  private let motionQueue = OperationQueue()
  private let storageKey = "uk.okkle.native.autotrack.visits.v1"
  private let shiftSnapshotKey = "uk.okkle.native.autotrack.liveShift.v1"
  private let shiftNotificationIdentifier = "uk.okkle.native.shift-logged"
  private let shiftStartNotificationIdentifier = "uk.okkle.native.shift-started"
  private var shiftStartNotified = false
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
  private var shiftSawVehicleConnection = false
  private var shiftArmedForHomeArrival = false
  private let routePointDistance: CLLocationDistance = 30
  private let drivingDistanceFilter: CLLocationDistance = 20
  private let stationaryDistanceFilter: CLLocationDistance = 150
  private let stationaryResumeDistance: CLLocationDistance = 150
  private let idleWakeDistance: CLLocationDistance = 450
  private let minimumConfidentStopDwell: TimeInterval = 90
  private let minimumConnectedVehicleStopDwell: TimeInterval = 4 * 60
  private let homeArrivalRadius: CLLocationDistance = 120
  private let homeDepartureRadius: CLLocationDistance = 220
  // How long the driver must actually stay within homeArrivalRadius before
  // a shift concludes via home-arrival — a single GPS ping within range
  // (e.g. driving past home on the way to another stop) isn't enough on
  // its own, see concludeShiftIfArrivedHome.
  private let homeArrivalDwellSeconds: TimeInterval = 15 * 60
  // How fresh shiftLastLocation must be for the dwell-timer recheck to trust
  // it as "still home right now" — the significant-location-change service
  // used while waiting can go quiet for a while, so a location older than
  // this can't prove the driver hasn't already left.
  private let homeArrivalStalenessThreshold: TimeInterval = 3 * 60
  private let homeArrivalRecheckDelay: TimeInterval = 3 * 60
  private var vehicleConnectionObservers: [NSObjectProtocol] = []
  private var idleWakeLocation: CLLocation?
  private var idleMotionQueryInFlight = false
  private var homeDwellTimer: Timer?

  // A stop currently being timed — may resolve into a logged visit (driving
  // resumes) or trigger shift-end (the stationary timer expires).
  private var stationaryTimer: Timer?
  private var stationarySince: Date?
  private var stationaryCoordinate: CLLocationCoordinate2D?

  override init() {
    super.init()
    manager.delegate = self
    manager.activityType = .automotiveNavigation
    configureLocationForDriving()
    motionQueue.name = "uk.okkle.native.auto-track-motion"
    motionQueue.qualityOfService = .utility
    load()
    restoreShiftIfNeeded()
  }

  func configure(store: OkkleStore) {
    self.store = store
    store.onRecordAdded = { [weak self] record in self?.checkOutcome(for: record) }
    startVehicleConnectionMonitoring()
    refresh()
  }

  /// The self-correcting half of the confidence model: every time pay gets
  /// logged, check whether that date was one the model had called a "peak"
  /// day, and hand the outcome to the tracker. Entirely silent — this never
  /// shows anything, it just quietly keeps the confidence label honest.
  private func checkOutcome(for record: NativeRecord) {
    guard record.isInsightRecommendationIncome, let amount = record.amount, let store else { return }
    let insights = NativeShiftInsights.build(visits: visits, store: store)

    // Every weekday this record's own period actually spans — a "Week" entry
    // covers seven of them, not just the single day the driver happened to
    // pick when logging (the picker labels it "Week ending", which is only
    // where the period ends). Shared by both self-correction checks below.
    let periodStart = Calendar.current.startOfDay(for: record.periodStart ?? record.date)
    let periodEnd = Calendar.current.startOfDay(for: record.periodEnd ?? record.date)
    var weekdaysInPeriod = Set<Int>()
    var cursor = periodStart
    while cursor <= periodEnd {
      weekdaysInPeriod.insert(Calendar.current.component(.weekday, from: cursor) - 1)
      guard let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }

    // Day half: was any weekday in this record's period one the model had
    // called a "peak" day?
    let peakWeekdays = Set(insights.weekdayDetails.prefix(3).map(\.weekday))
    NativeOutcomeTracker.shared.record(amount: amount, period: record.period,
                                       wasPredictedPeakDay: !peakWeekdays.isDisjoint(with: weekdaysInPeriod))

    // Zone half of the same self-correction: did work happen anywhere near a
    // recommended zone at any point during this record's own period. Entirely
    // silent — feeds NativeZoneOutcomeTracker.zoneHitRate, which only ever
    // dampens future zone weights, never boosts them.
    let recommendedZonesInPeriod = weekdaysInPeriod.compactMap { wd in
      insights.weekdayDetails.first(where: { $0.weekday == wd })?.coordinate
    }
    if !recommendedZonesInPeriod.isEmpty {
      let periodEndExclusive = Calendar.current.date(byAdding: .day, value: 1, to: periodEnd) ?? periodEnd.addingTimeInterval(86_400)
      let wasNear = visits.contains { visit in
        guard visit.arrival >= periodStart, visit.arrival < periodEndExclusive else { return false }
        return recommendedZonesInPeriod.contains { zone in
          visit.location.distance(from: CLLocation(latitude: zone.latitude, longitude: zone.longitude)) <= 600
        }
      }
      NativeZoneOutcomeTracker.shared.record(amount: amount, period: record.period, wasNearRecommendedZone: wasNear)
    }
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
    if shiftPhase != .idle {
      publishLiveShift()
    }
    startMotionMonitoring()
    configureLocationForIdleWakeIfNeeded()
    // The primed first ask happens in the onboarding location-permission
    // step, not here — this only covers a driver who reaches this point
    // still undetermined (e.g. access was reset in Settings after the
    // fact, or automatic tracking got turned on some other way).
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
    } else if manager.authorizationStatus == .authorizedWhenInUse {
      requestAlwaysUpgradeIfNeeded()
    }
  }

  private func stopMonitoring() {
    stopMotionMonitoring()
    if shiftPhase == .idle {
      manager.stopMonitoringSignificantLocationChanges()
      idleWakeLocation = nil
    }
    // Turning tracking off mid-shift shouldn't throw away real, already-
    // recorded GPS miles — save what's there rather than silently lose it.
    if shiftPhase != .idle { concludeShift() }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in self.refresh() }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    Task { @MainActor in self.handleLocationUpdates(locations) }
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
    case .driving, .paused:
      break
    }
  }

  private func handleStationarySignal() {
    guard shiftPhase == .driving else { return }
    shiftPhase = .stationaryPending
    stationarySince = Date()
    stationaryCoordinate = shiftLastLocation?.coordinate
    configureLocationForStationaryWaiting()
    persistShiftSnapshot()
    if let shiftLastLocation { trackHomeArrival(at: shiftLastLocation) }
    if concludeShiftIfVehicleDisconnected() { return }
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
    shiftStartNotified = false
    shiftLastLocation = nil
    shiftLastRoutePointLocation = nil
    shiftSawVehicleConnection = enhancedAutoTrackingEnabled && NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle
    shiftArmedForHomeArrival = false
    cancelHomeDwellTimer()
    liveShiftVehicle = store?.settings.defaultVehicle ?? .car
    publishLiveShift()
    persistShiftSnapshot()
    configureLocationForDriving()
    setBackgroundTrackingEnabled(true)
    manager.startUpdatingLocation()
  }

  func pauseCurrentShift() {
    guard shiftPhase == .driving || shiftPhase == .stationaryPending else { return }
    stationaryTimer?.invalidate()
    stationaryTimer = nil
    stationarySince = nil
    stationaryCoordinate = nil
    cancelHomeDwellTimer()
    shiftPhase = .paused
    manager.stopUpdatingLocation()
    manager.stopMonitoringSignificantLocationChanges()
    setBackgroundTrackingEnabled(false)
    publishLiveShift()
    persistShiftSnapshot()
  }

  func resumeCurrentShift() {
    guard shiftPhase == .paused else { return }
    shiftPhase = .driving
    configureLocationForDriving()
    setBackgroundTrackingEnabled(true)
    manager.startUpdatingLocation()
    publishLiveShift()
    persistShiftSnapshot()
  }

  func endCurrentShift() {
    guard shiftPhase != .idle else { return }
    concludeShift()
  }

  /// Driving resumed before the stationary timer expired — the stop that was
  /// being timed becomes a logged pick-up/drop-off, and the same shift (same
  /// trip, same accumulated mileage) keeps going.
  private func resumeShift() {
    finalizePendingStop()
    stationaryTimer?.invalidate()
    stationaryTimer = nil
    cancelHomeDwellTimer()
    shiftPhase = .driving
    configureLocationForDriving()
    manager.startUpdatingLocation()
    persistShiftSnapshot()
  }

  /// The stationary timer expired (or tracking got turned off mid-shift) —
  /// the shift is over. Save it as a real trip and notify the driver.
  private func concludeShift() {
    guard shiftPhase != .idle else { return }
    finalizePendingStop()
    saveShiftAsTrip()
    manager.stopUpdatingLocation()
    manager.stopMonitoringSignificantLocationChanges()
    setBackgroundTrackingEnabled(false)
    stationaryTimer?.invalidate()
    stationaryTimer = nil
    shiftPhase = .idle
    shiftPoints = []
    shiftMiles = 0
    shiftStartedAt = nil
    shiftStartNotified = false
    shiftLastLocation = nil
    shiftLastRoutePointLocation = nil
    shiftSawVehicleConnection = false
    shiftArmedForHomeArrival = false
    cancelHomeDwellTimer()
    stationarySince = nil
    stationaryCoordinate = nil
    publishLiveShift()
    clearShiftSnapshot()
    refresh()
  }

  private func startVehicleConnectionMonitoring() {
    guard vehicleConnectionObservers.isEmpty else { return }
    let center = NotificationCenter.default
    vehicleConnectionObservers = [
      center.addObserver(forName: .nativeVehicleConnectionDidChange, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.handleVehicleConnectionChanged() }
      },
      center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.handleVehicleConnectionChanged() }
      },
    ]
  }

  private func handleVehicleConnectionChanged() {
    guard enhancedAutoTrackingEnabled else { return }
    if NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle {
      shiftSawVehicleConnection = true
      beginShiftFromVehicleConnectionIfNeeded()
      publishLiveShift()
    } else {
      _ = concludeShiftIfVehicleDisconnected()
    }
  }

  private func beginShiftFromVehicleConnectionIfNeeded() {
    guard shiftPhase == .idle else { return }
    guard let settings = store?.settings,
          settings.autoTrackTrips,
          nativeIsWorkingDay(Date(), settings: settings) else { return }
    guard NativeTripSession.shared.phase == .setup else { return }
    let status = manager.authorizationStatus
    guard status == .authorizedAlways || status == .authorizedWhenInUse else {
      refresh()
      return
    }
    beginShift()
  }

  // MARK: Continuous route recording (mirrors NativeTripSession's approach)

  private func handleLocationUpdates(_ locations: [CLLocation]) {
    if shiftPhase == .idle {
      handleIdleWakeLocationUpdates(locations)
    } else {
      handleShiftLocationUpdates(locations)
    }
  }

  private func handleIdleWakeLocationUpdates(_ locations: [CLLocation]) {
    guard let settings = store?.settings,
          settings.autoTrackTrips,
          nativeIsWorkingDay(Date(), settings: settings) else { return }
    guard NativeTripSession.shared.phase == .setup else { return }

    for location in locations where shouldUseIdleWakeLocation(location) {
      if let idleWakeLocation, location.distance(from: idleWakeLocation) < idleWakeDistance { continue }
      idleWakeLocation = location

      if enhancedAutoTrackingEnabled, NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle {
        shiftSawVehicleConnection = true
        beginShiftFromVehicleConnectionIfNeeded()
        return
      }

      if location.speed >= 6 {
        handleDrivingSignal()
        return
      }

      beginShiftIfRecentAutomotiveActivity()
      return
    }
  }

  private func beginShiftIfRecentAutomotiveActivity() {
    guard !idleMotionQueryInFlight else { return }
    guard CMMotionActivityManager.isActivityAvailable() else { return }
    idleMotionQueryInFlight = true

    let end = Date()
    let start = end.addingTimeInterval(-3 * 60)
    motionManager.queryActivityStarting(from: start, to: end, to: motionQueue) { [weak self] activities, _ in
      let hasRecentDriving = activities?.contains(where: { $0.automotive && $0.confidence != .low }) ?? false
      Task { @MainActor in
        guard let self else { return }
        self.idleMotionQueryInFlight = false
        if hasRecentDriving {
          self.handleDrivingSignal()
        }
      }
    }
  }

  private func handleShiftLocationUpdates(_ locations: [CLLocation]) {
    guard shiftPhase == .driving || shiftPhase == .stationaryPending else { return }
    if enhancedAutoTrackingEnabled {
      shiftSawVehicleConnection = shiftSawVehicleConnection || NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle
    }
    for location in locations where shouldUseShiftLocation(location) {
      if shiftPhase == .stationaryPending, shouldResumeFromStationaryLocation(location) {
        resumeShift()
      }
      if let shiftLastLocation {
        let delta = location.distance(from: shiftLastLocation) / 1_609.344
        if delta > 0.002 && delta < 1 { shiftMiles += delta }
      }
      shiftLastLocation = location
      appendShiftRoutePoint(for: location)
      if shiftPhase == .stationaryPending { stationaryCoordinate = location.coordinate }
      trackHomeArrival(at: location)
      if concludeShiftIfVehicleDisconnected() { return }
    }
    // Tell the driver recording has started — but only once the shift shows
    // real recorded distance, not on the raw driving signal. A bus ride or a
    // motion blip can open a shift that's discarded as near-zero noise; every
    // "started" notification here is one that will end in a logged trip.
    if !shiftStartNotified, shiftMiles >= 0.2 {
      shiftStartNotified = true
      sendShiftStartedNotification()
    }
    publishLiveShift()
    persistShiftSnapshot()
  }

  private func shouldUseIdleWakeLocation(_ location: CLLocation) -> Bool {
    guard location.horizontalAccuracy >= 0 else { return false }
    guard abs(location.timestamp.timeIntervalSinceNow) < 10 * 60 else { return false }
    return location.horizontalAccuracy <= 1_000
  }

  private func publishLiveShift() {
    liveShiftMiles = shiftMiles
    liveShiftStartedAt = shiftStartedAt
    liveShiftPoints = shiftPoints
    liveShiftUsesEnhancedTracking = enhancedAutoTrackingEnabled && shiftSawVehicleConnection
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
    shiftPoints.append(RoutePoint(
      location: location,
      vehicleConnectionActive: enhancedAutoTrackingEnabled ? NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle : nil
    ))
    shiftLastRoutePointLocation = location
  }

  private func configureLocationForDriving() {
    manager.stopMonitoringSignificantLocationChanges()
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    manager.distanceFilter = drivingDistanceFilter
    manager.pausesLocationUpdatesAutomatically = false
  }

  private func configureLocationForStationaryWaiting() {
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.distanceFilter = stationaryDistanceFilter
    manager.pausesLocationUpdatesAutomatically = true
    manager.stopUpdatingLocation()
    manager.startMonitoringSignificantLocationChanges()
  }

  private func configureLocationForIdleWakeIfNeeded() {
    guard shiftPhase == .idle else { return }
    let status = manager.authorizationStatus
    guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
    manager.desiredAccuracy = kCLLocationAccuracyKilometer
    manager.distanceFilter = idleWakeDistance
    manager.pausesLocationUpdatesAutomatically = true
    manager.startMonitoringSignificantLocationChanges()
  }

  private func setBackgroundTrackingEnabled(_ enabled: Bool) {
    guard supportsBackgroundLocation else { return }
    manager.allowsBackgroundLocationUpdates = enabled
    manager.showsBackgroundLocationIndicator = enabled
  }

  private func shouldResumeFromStationaryLocation(_ location: CLLocation) -> Bool {
    guard let stationaryCoordinate else { return false }
    let stationaryLocation = CLLocation(latitude: stationaryCoordinate.latitude, longitude: stationaryCoordinate.longitude)
    return location.distance(from: stationaryLocation) >= stationaryResumeDistance
  }

  private func concludeShiftIfVehicleDisconnected() -> Bool {
    guard enhancedAutoTrackingEnabled else { return false }
    guard shiftSawVehicleConnection, !NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle else { return false }
    concludeShift()
    return true
  }

  /// A single GPS ping inside homeArrivalRadius isn't enough to call the
  /// shift over — driving past home on the way to another stop reads
  /// identically to actually stopping there. This starts a dwell timer on
  /// the first such ping instead, and only concludes (via
  /// confirmHomeArrivalIfStillNearby) once the driver has stayed put for
  /// homeArrivalDwellSeconds; any ping in between showing they've left
  /// cancels it.
  private func trackHomeArrival(at location: CLLocation) {
    guard enhancedAutoTrackingEnabled else { return }
    guard shiftPhase == .driving || shiftPhase == .stationaryPending else { return }
    let homes = selectedHomeLocations
    guard !homes.isEmpty else { return }
    let nearestHomeDistance = homes.map { location.distance(from: $0) }.min() ?? .greatestFiniteMagnitude
    if nearestHomeDistance > homeDepartureRadius {
      shiftArmedForHomeArrival = true
      cancelHomeDwellTimer()
      return
    }
    guard shiftArmedForHomeArrival, nearestHomeDistance <= homeArrivalRadius else {
      // Within the wider departure band but not tight enough to count as
      // "at home" (e.g. 150m out) — not a real arrival either.
      cancelHomeDwellTimer()
      return
    }
    if homeDwellTimer == nil {
      scheduleHomeDwellTimer()
    }
  }

  private func scheduleHomeDwellTimer() {
    homeDwellTimer?.invalidate()
    homeDwellTimer = Timer.scheduledTimer(withTimeInterval: homeArrivalDwellSeconds, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.confirmHomeArrivalIfStillNearby() }
    }
    homeDwellTimer?.tolerance = 30
  }

  /// The dwell timer fired — re-checks against the most recent known
  /// location rather than trusting the ping that started the timer, so a
  /// single stale/inaccurate fix can't lock in a false "still home".
  private func confirmHomeArrivalIfStillNearby() {
    homeDwellTimer = nil
    guard let shiftLastLocation else { return }
    let homes = selectedHomeLocations
    let nearestHomeDistance = homes.map { shiftLastLocation.distance(from: $0) }.min() ?? .greatestFiniteMagnitude
    guard nearestHomeDistance <= homeArrivalRadius else { return }
    guard abs(shiftLastLocation.timestamp.timeIntervalSinceNow) <= homeArrivalStalenessThreshold else {
      // Can't confirm against a fix this old — check again shortly instead
      // of locking in a possibly-false "still home" read.
      homeDwellTimer = Timer.scheduledTimer(withTimeInterval: homeArrivalRecheckDelay, repeats: false) { [weak self] _ in
        Task { @MainActor in self?.confirmHomeArrivalIfStillNearby() }
      }
      homeDwellTimer?.tolerance = 15
      return
    }
    concludeShift()
  }

  private func cancelHomeDwellTimer() {
    homeDwellTimer?.invalidate()
    homeDwellTimer = nil
  }

  private var selectedHomeLocations: [CLLocation] {
    guard let store else { return [] }
    return store.settings.excludedPlaces
      .filter { $0.label.caseInsensitiveCompare("Home") == .orderedSame }
      .map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
  }

  private var enhancedAutoTrackingEnabled: Bool {
    guard let settings = store?.settings else { return true }
    return settings.autoTrackTrips && settings.enhancedAutoTracking
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
    guard shouldRecordPendingStop(arrival: stationarySince, departure: departure) else {
      self.stationarySince = nil
      self.stationaryCoordinate = nil
      return
    }
    var visit = NativeVisit(latitude: coordinate.latitude, longitude: coordinate.longitude,
                            arrival: stationarySince, departure: departure)
    let calibration = store?.settings.autoTrackCalibration ?? NativeAutoTrackCalibration()
    visit.vehicleDisconnectConfirmed = shiftSawVehicleConnection && !NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle
    visit.kind = visit.dwell >= calibration.pickupDwellThreshold ? .pickup : .dropoff
    visits.append(visit)
    trim()
    save()
    classifyWithMapKit(visit.id, coordinate: coordinate, calibration: calibration)
    runBackgroundExploration(for: visit)
    self.stationarySince = nil
    self.stationaryCoordinate = nil
  }

  private func shouldRecordPendingStop(arrival: Date, departure: Date) -> Bool {
    let dwell = departure.timeIntervalSince(arrival)
    guard dwell >= minimumConfidentStopDwell else { return false }

    let disconnectedFromKnownVehicle = shiftSawVehicleConnection && !NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle
    if disconnectedFromKnownVehicle {
      return true
    }

    return dwell >= minimumConnectedVehicleStopDwell
  }

  private func saveShiftAsTrip() {
    guard let store, let shiftStartedAt else { return }
    // Skip near-zero noise (a driving reading that immediately went
    // stationary again without covering real distance).
    guard shiftMiles > 0.1 || shiftPoints.count > 2 else { return }
    let vehicle = store.settings.defaultVehicle
    let endedAt = Date()
    let trip = NativeTrip(
      vehicle: vehicle,
      miles: shiftMiles,
      deduction: store.calcDeduction(miles: shiftMiles, vehicle: vehicle, date: shiftStartedAt),
      startedAt: shiftStartedAt,
      endedAt: endedAt,
      points: shiftPoints
    )
    store.addTrip(trip)
    lastAutoShiftID = trip.id
    ensureShiftHasVisitPair(shiftStart: shiftStartedAt, shiftEnd: endedAt)
    sendShiftLoggedNotification(trip)
    // Push the logging reminder off today if it was about to fire today —
    // don't wait for the app to be reopened to notice a shift just logged.
    NativeLoggingReminder.refresh(store: store)
    requestAlwaysUpgradeIfNeeded()
  }

  /// Asked once, the first time automatic tracking actually catches and
  /// saves a real trip — not upfront during onboarding. Background
  /// tracking needs Always access to keep working once the app isn't in
  /// the foreground, but leading with that broader request reads as
  /// invasive; asking right after the driver has just seen the feature
  /// work is the natural, low-friction moment to ask for the upgrade.
  private func requestAlwaysUpgradeIfNeeded() {
    guard manager.authorizationStatus == .authorizedWhenInUse else { return }
    guard UIApplication.shared.applicationState == .active else { return }
    let key = "uk.okkle.native.autotrack.requestedAlwaysUpgrade"
    guard !UserDefaults.standard.bool(forKey: key) else { return }
    UserDefaults.standard.set(true, forKey: key)
    manager.requestAlwaysAuthorization()
  }

  // Insights (NativeShiftInsights) treats a pickup→dropoff visit pair as the
  // signal that there's real delivery data — a plain point-to-point drive
  // with no recognized intermediate stop never produces one, even though it
  // just got saved as a real, GPS-tracked trip above. Without this, a driver
  // who never has a classifiable mid-shift stop would see the "Learning your
  // week" cold-start card forever, no matter how much they actually drive.
  // Only synthesize when the shift genuinely produced zero real stops —
  // leave any real (if imperfectly paired) classification alone.
  private func ensureShiftHasVisitPair(shiftStart: Date, shiftEnd: Date) {
    guard !visits.contains(where: { $0.arrival >= shiftStart }) else { return }
    let startCoordinate = shiftPoints.first.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
      ?? shiftLastLocation?.coordinate
    let endCoordinate = shiftPoints.last.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
      ?? shiftLastLocation?.coordinate
    guard let start = startCoordinate, let end = endCoordinate else { return }
    var pickup = NativeVisit(latitude: start.latitude, longitude: start.longitude, arrival: shiftStart, departure: shiftStart)
    pickup.kind = .pickup
    var dropoff = NativeVisit(latitude: end.latitude, longitude: end.longitude, arrival: shiftEnd, departure: shiftEnd)
    dropoff.kind = .dropoff
    visits.append(contentsOf: [pickup, dropoff])
    trim()
    save()
  }

  private func sendShiftStartedNotification() {
    sendAutoTrackNotification(
      identifier: "\(shiftStartNotificationIdentifier)-\(Int((shiftStartedAt ?? Date()).timeIntervalSince1970))",
      title: "Automatic tracking started",
      body: "Okkle is recording this trip automatically. Tap to check or pause it.",
      userInfo: ["type": "autoShiftStarted"]
    )
  }

  private func sendShiftLoggedNotification(_ trip: NativeTrip) {
    let miles = String(format: "%.1f", trip.miles)
    sendAutoTrackNotification(
      identifier: "\(shiftNotificationIdentifier)-\(trip.id.uuidString)",
      title: "Automatic tracking ended",
      body: "\(miles) miles were saved automatically. Tap to review the trip.",
      userInfo: ["type": "autoShiftReview", "tripID": trip.id.uuidString]
    )
  }

  private func sendAutoTrackNotification(identifier: String, title: String, body: String, userInfo: [String: String] = [:]) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      content.userInfo = userInfo
      center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
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
      .filter { $0.isInsightRecommendationIncome && Calendar.current.isDate($0.date, inSameDayAs: today) }
      .reduce(0.0) { $0 + ($1.amount ?? 0) }
    NativeExploreCandidateStore.shared.recordVisit(visit.coordinate, dayIncome: dayIncome)

    let zones = NativeShiftInsights.build(visits: visits, store: store).zones.map(\.coordinate)
    NativeAreaSuggester.refresh(near: visit.coordinate, knownZones: zones)
  }

  /// Use Apple Maps as an information layer: if there's a food place right by the
  /// stop it's a pick-up; otherwise it's most likely a customer drop-off. A
  /// single search covers both the tight food-radius classification and the
  /// wider any-POI naming fallback, instead of two sequential network calls.
  private func classifyWithMapKit(_ id: UUID, coordinate: CLLocationCoordinate2D, calibration: NativeAutoTrackCalibration) {
    let foodCategories: Set<MKPointOfInterestCategory> = [.restaurant, .cafe, .bakery, .foodMarket, .brewery, .nightlife]
    let namingRadius: CLLocationDistance = 110
    let namingCategories = foodCategories.union([.store, .pharmacy, .parking, .publicTransport])
    let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: max(calibration.foodPoiRadiusMeters, namingRadius))
    request.pointOfInterestFilter = MKPointOfInterestFilter(including: Array(namingCategories))
    let stopLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

    func distance(_ item: MKMapItem) -> CLLocationDistance {
      item.placemark.location?.distance(from: stopLocation) ?? .greatestFiniteMagnitude
    }

    MKLocalSearch(request: request).start { [weak self] response, _ in
      guard let self else { return }
      let items = response?.mapItems ?? []
      let nearestFood = items
        .filter { ($0.pointOfInterestCategory.map(foodCategories.contains) ?? false) && distance($0) <= calibration.foodPoiRadiusMeters }
        .min { distance($0) < distance($1) }
      let nearestNamed = items
        .filter { ($0.name ?? "").isEmpty == false && distance($0) <= namingRadius }
        .min { distance($0) < distance($1) }

      Task { @MainActor in
        guard let index = self.visits.firstIndex(where: { $0.id == id }) else { return }
        if let food = nearestFood {
          self.visits[index].kind = .pickup
          self.visits[index].placeName = food.name
        } else if self.visits[index].dwell < calibration.dropoffMaxDwellThreshold {
          self.visits[index].kind = .dropoff
        }
        if self.visits[index].placeName == nil {
          self.visits[index].placeName = nearestNamed?.name
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

  /// Called on every meaningful shift-state change so a killed/crashed app
  /// doesn't lose an in-progress shift's recorded miles — see
  /// restoreShiftIfNeeded, which reads this back on the next launch.
  private func persistShiftSnapshot() {
    guard shiftPhase != .idle, let shiftStartedAt else {
      clearShiftSnapshot()
      return
    }
    let snapshot = NativeAutoShiftSnapshot(
      phaseRaw: shiftPhase.rawValue,
      points: shiftPoints,
      miles: shiftMiles,
      startedAt: shiftStartedAt,
      vehicleRaw: liveShiftVehicle.rawValue,
      sawVehicleConnection: shiftSawVehicleConnection,
      armedForHomeArrival: shiftArmedForHomeArrival,
      lastLocationLat: shiftLastLocation?.coordinate.latitude,
      lastLocationLon: shiftLastLocation?.coordinate.longitude,
      lastLocationTimestamp: shiftLastLocation?.timestamp,
      lastLocationAccuracy: shiftLastLocation?.horizontalAccuracy,
      lastRoutePointLat: shiftLastRoutePointLocation?.coordinate.latitude,
      lastRoutePointLon: shiftLastRoutePointLocation?.coordinate.longitude,
      stationarySince: stationarySince,
      stationaryLat: stationaryCoordinate?.latitude,
      stationaryLon: stationaryCoordinate?.longitude
    )
    if let data = try? JSONEncoder().encode(snapshot) {
      UserDefaults.standard.set(data, forKey: shiftSnapshotKey)
    }
  }

  private func clearShiftSnapshot() {
    UserDefaults.standard.removeObject(forKey: shiftSnapshotKey)
  }

  /// Reads back a shift snapshot left by a previous run that never reached
  /// concludeShift (crash, memory-pressure eviction, reboot) and re-arms
  /// location tracking for it, instead of silently starting fresh at .idle
  /// and losing whatever mileage was already recorded.
  private func restoreShiftIfNeeded() {
    guard let data = UserDefaults.standard.data(forKey: shiftSnapshotKey),
          let snapshot = try? JSONDecoder().decode(NativeAutoShiftSnapshot.self, from: data),
          let phase = NativeAutoShiftPhase(rawValue: snapshot.phaseRaw),
          phase != .idle else { return }

    shiftPhase = phase
    shiftPoints = snapshot.points
    shiftMiles = snapshot.miles
    shiftStartedAt = snapshot.startedAt
    liveShiftVehicle = NativeVehicle(rawValue: snapshot.vehicleRaw) ?? .car
    shiftSawVehicleConnection = snapshot.sawVehicleConnection
    shiftArmedForHomeArrival = snapshot.armedForHomeArrival
    // Already told the driver this shift started, in the run that recorded
    // this snapshot — don't repeat the notification after a silent restore.
    shiftStartNotified = true

    if let lat = snapshot.lastLocationLat, let lon = snapshot.lastLocationLon {
      shiftLastLocation = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
        altitude: 0,
        horizontalAccuracy: snapshot.lastLocationAccuracy ?? 10,
        verticalAccuracy: -1,
        timestamp: snapshot.lastLocationTimestamp ?? snapshot.startedAt
      )
    }
    if let lat = snapshot.lastRoutePointLat, let lon = snapshot.lastRoutePointLon {
      shiftLastRoutePointLocation = CLLocation(latitude: lat, longitude: lon)
    }
    stationarySince = snapshot.stationarySince
    if let lat = snapshot.stationaryLat, let lon = snapshot.stationaryLon {
      stationaryCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    publishLiveShift()

    switch phase {
    case .driving:
      configureLocationForDriving()
      setBackgroundTrackingEnabled(true)
      manager.startUpdatingLocation()
    case .stationaryPending:
      // The original countdown's remaining time wasn't persisted — restart a
      // full timeout rather than guessing, so a restored shift never
      // auto-concludes sooner than it would have.
      configureLocationForStationaryWaiting()
      setBackgroundTrackingEnabled(true)
      scheduleStationaryTimeout()
    case .paused, .idle:
      break
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
