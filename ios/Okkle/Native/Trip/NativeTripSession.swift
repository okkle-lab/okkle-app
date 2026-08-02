import CoreLocation
import CoreMotion
import Combine
import Foundation
import UIKit
@preconcurrency import UserNotifications

extension Notification.Name {
  static let nativeManualTripPhaseDidChange = Notification.Name("uk.okkle.native.manualTripPhaseDidChange")
}

enum NativeManualTripStopNotification {
  static let categoryIdentifier = "uk.okkle.native.manual-trip-stop"
  static let endActionIdentifier = "uk.okkle.native.manual-trip-stop.end"
  static let continueActionIdentifier = "uk.okkle.native.manual-trip-stop.continue"
  static let autoCompleteActionIdentifier = "uk.okkle.native.manual-trip-stop.auto-complete"

  static func registerCategory() {
    let endAction = UNNotificationAction(
      identifier: endActionIdentifier,
      title: "End trip",
      options: [.authenticationRequired]
    )
    let continueAction = UNNotificationAction(
      identifier: continueActionIdentifier,
      title: "Keep tracking",
      options: []
    )
    let autoCompleteAction = UNNotificationAction(
      identifier: autoCompleteActionIdentifier,
      title: "Auto-complete",
      options: [.authenticationRequired]
    )
    let category = UNNotificationCategory(
      identifier: categoryIdentifier,
      actions: [endAction, continueAction, autoCompleteAction],
      intentIdentifiers: [],
      options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])
  }
}

private struct NativeManualTripSnapshot: Codable {
  var phase: String
  var vehicle: NativeVehicle
  var miles: Double
  var elapsed: TimeInterval
  var points: [RoutePoint]
  var startedAt: Date
  var reviewEndedAt: Date?
  var lastLocation: RoutePoint?
  var lastMileageLocation: RoutePoint?
  var lastRoutePointLocation: RoutePoint?
  var routeBreakPending: Bool?
  var pedestrianMileageExcluded: Bool?
  var pedestrianExclusionStartedAt: Date?
  var recentMileageSegments: [NativeTripMileageSegment]?
  var mileageCorrections: [NativeTripMileageCorrection]?
  var stationaryAnchorLocation: RoutePoint?
  var stationarySince: Date?
  var promptedForCurrentStationaryPeriod: Bool
  var stopPromptRequested: Bool
}

final class NativeTripSession: NSObject, ObservableObject, CLLocationManagerDelegate {
  static let shared = NativeTripSession()

  enum Phase: String, Equatable, Codable {
    case setup
    case live
    case paused
    case summary

    var diagnosticLabel: String {
      switch self {
      case .setup: return "returned to setup"
      case .live: return "started"
      case .paused: return "paused"
      case .summary: return "entered review"
      }
    }
  }

  @Published var phase: Phase = .setup {
    didSet {
      guard oldValue != phase else { return }
      NotificationCenter.default.post(name: .nativeManualTripPhaseDidChange, object: nil)
    }
  }
  @Published var vehicle: NativeVehicle = .car
  @Published var miles: Double = 0
  @Published var elapsed: TimeInterval = 0
  @Published var points: [RoutePoint] = []
  @Published var permissionMessage: String?
  @Published var stopPromptRequested = false

  private let manager = CLLocationManager()
  private let motionManager = CMMotionActivityManager()
  private var lastLocation: CLLocation?
  private var lastMileageLocation: CLLocation?
  private var lastRoutePointLocation: CLLocation?
  private var routeBreakPending = false
  private var pedestrianMileageExcluded = false
  private var pedestrianExclusionStartedAt: Date?
  private var recentMileageSegments: [NativeTripMileageSegment] = []
  private var mileageCorrections: [NativeTripMileageCorrection] = []
  private var motionMonitoring = false
  private var stationaryAnchorLocation: CLLocation?
  private var stationarySince: Date?
  private var promptedForCurrentStationaryPeriod = false
  private var startedAt: Date?
  private var reviewEndedAt: Date?
  private var timer: Timer?
  private var waitingForAuthorization = false
  private let routePointDistance: CLLocationDistance = 10
  private let timerInterval: TimeInterval = 5
  private let stationaryPromptDelay: TimeInterval = 12 * 60
  private let minimumTrackingTimeBeforeStopPrompt: TimeInterval = 10 * 60
  private let stationaryPromptRadius: CLLocationDistance = 60
  private let stopPromptNotificationIdentifier = "uk.okkle.native.manual-trip-stop-prompt"
  private let autoCompletedNotificationIdentifier = "uk.okkle.native.manual-trip-auto-completed"
  private let persistenceQueue = DispatchQueue(label: "uk.okkle.native.manual-trip-persist", qos: .utility)
  private static let snapshotFileURL: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Okkle", isDirectory: true).appendingPathComponent("manual-trip.json")
  }()

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    manager.distanceFilter = 10
    manager.activityType = .automotiveNavigation
    manager.pausesLocationUpdatesAutomatically = false
    restorePersistedTrip()
    // The Live Activity's Pause/Resume/End buttons run
    // in-process (LiveActivityIntent) but can't reference this singleton
    // directly — see OkkleTripLiveActivityIntents.swift for why — so they
    // signal over NotificationCenter instead.
    NotificationCenter.default.addObserver(forName: .nativeLiveActivityStopTrackingRequested, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.handleLiveActivityStopTrackingRequest() }
    }
    NotificationCenter.default.addObserver(forName: .nativeLiveActivityPauseTrackingRequested, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.handleLiveActivityPauseTrackingRequest() }
    }
    NotificationCenter.default.addObserver(forName: .nativeLiveActivityResumeTrackingRequested, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.handleLiveActivityResumeTrackingRequest() }
    }
  }

  @MainActor
  private func handleLiveActivityStopTrackingRequest() {
    guard phase == .live || phase == .paused else { return }
    if let trip = end(store: OkkleStore.shared) {
      OkkleStore.shared.addTrip(trip)
    }
    discard()
  }

  @MainActor
  private func handleLiveActivityPauseTrackingRequest() {
    guard phase == .live else { return }
    pause()
  }

  @MainActor
  private func handleLiveActivityResumeTrackingRequest() {
    guard phase == .paused else { return }
    resume()
  }

  @MainActor
  func start(vehicle: NativeVehicle) {
    // Reserve location ownership before requesting permission so automatic
    // tracking cannot start in the gap between the user's tap and the manual
    // session becoming live.
    NativeAutoTrackEngine.shared.manualTripStartRequested()
    self.vehicle = vehicle
    configureLocationManager(for: vehicle)
    permissionMessage = nil
    let status = manager.authorizationStatus
    if status == .notDetermined {
      waitingForAuthorization = true
      manager.requestWhenInUseAuthorization()
      return
    }
    guard status == .authorizedAlways || status == .authorizedWhenInUse else {
      permissionMessage = "Location permission is needed to track trip distance."
      NativeTripWidgetStore.markTripEnded()
      NativeAutoTrackEngine.shared.manualTripStartCancelled()
      return
    }
    beginTracking()
  }

  private func beginTracking() {
    miles = 0
    elapsed = 0
    points = []
    lastLocation = nil
    lastMileageLocation = nil
    lastRoutePointLocation = nil
    routeBreakPending = false
    pedestrianMileageExcluded = false
    pedestrianExclusionStartedAt = nil
    recentMileageSegments = []
    mileageCorrections = []
    stationaryAnchorLocation = nil
    stationarySince = nil
    promptedForCurrentStationaryPeriod = false
    stopPromptRequested = false
    startedAt = Date()
    reviewEndedAt = nil
    phase = .live
    NativeTripWidgetStore.markTripStarted(startedAt: startedAt ?? Date())
    NativeTripLiveActivityController.start(source: "manual", vehicleLabel: vehicle.label, miles: 0, elapsed: 0, isDriving: true)
    setBackgroundTrackingEnabled(true)
    startMotionMonitoring()
    manager.startUpdatingLocation()
    startTimer()
    waitingForAuthorization = false
    persistState()
  }

  func pause() {
    guard phase == .live else { return }
    phase = .paused
    if let startedAt {
      NativeTripWidgetStore.markTripStarted(startedAt: startedAt)
    }
    NativeTripLiveActivityController.update(
      miles: miles,
      elapsed: elapsed,
      isDriving: false,
      isPausedByUser: true,
      vehicleLabel: vehicle.label,
      force: true
    )
    manager.stopUpdatingLocation()
    stopMotionMonitoring()
    setBackgroundTrackingEnabled(false)
    stopTimer()
    persistState()
  }

  func resume() {
    guard phase == .paused else { return }
    phase = .live
    if let startedAt {
      NativeTripWidgetStore.markTripStarted(startedAt: startedAt)
    }
    NativeTripLiveActivityController.update(miles: miles, elapsed: elapsed, isDriving: true, vehicleLabel: vehicle.label, force: true)
    prepareMileageForLocationRestart()
    setBackgroundTrackingEnabled(true)
    startMotionMonitoring()
    manager.startUpdatingLocation()
    startTimer()
    persistState()
  }

  func continueTrackingAfterEndReview() {
    guard phase == .summary else { return }
    reviewEndedAt = nil
    phase = .live
    if let startedAt {
      NativeTripWidgetStore.markTripStarted(startedAt: startedAt)
    }
    NativeTripLiveActivityController.start(source: "manual", vehicleLabel: vehicle.label, miles: miles, elapsed: elapsed, isDriving: true)
    prepareMileageForLocationRestart()
    setBackgroundTrackingEnabled(true)
    startMotionMonitoring()
    manager.startUpdatingLocation()
    startTimer()
    persistState()
  }

  @MainActor
  func end(store: OkkleStore) -> NativeTrip? {
    guard startedAt != nil else { return nil }
    manager.stopUpdatingLocation()
    stopMotionMonitoring()
    setBackgroundTrackingEnabled(false)
    stopTimer()
    phase = .summary
    NativeTripWidgetStore.markTripEnded()
    NativeTripLiveActivityController.end()
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [stopPromptNotificationIdentifier])
    if let lastMileageLocation {
      appendRoutePoint(for: lastMileageLocation, force: true)
    }
    reviewEndedAt = Date()
    persistState()
    return tripForReview(store: store)
  }

  @MainActor
  func tripForReview(store: OkkleStore) -> NativeTrip? {
    guard phase == .summary, let startedAt else { return nil }
    return NativeTrip(
      vehicle: vehicle,
      miles: miles,
      deduction: store.calcDeduction(miles: miles, vehicle: vehicle, date: startedAt),
      startedAt: startedAt,
      endedAt: reviewEndedAt ?? points.last?.timestamp ?? Date(),
      points: points,
      mileageCorrections: mileageCorrections.isEmpty ? nil : mileageCorrections
    )
  }

  func discard() {
    manager.stopUpdatingLocation()
    stopMotionMonitoring()
    setBackgroundTrackingEnabled(false)
    stopTimer()
    waitingForAuthorization = false
    miles = 0
    elapsed = 0
    points = []
    lastLocation = nil
    lastMileageLocation = nil
    lastRoutePointLocation = nil
    routeBreakPending = false
    pedestrianMileageExcluded = false
    pedestrianExclusionStartedAt = nil
    recentMileageSegments = []
    mileageCorrections = []
    stationaryAnchorLocation = nil
    stationarySince = nil
    promptedForCurrentStationaryPeriod = false
    stopPromptRequested = false
    startedAt = nil
    reviewEndedAt = nil
    phase = .setup
    NativeTripWidgetStore.markTripEnded()
    NativeTripLiveActivityController.end()
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [stopPromptNotificationIdentifier])
    clearPersistedState()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    if status == .authorizedAlways || status == .authorizedWhenInUse {
      permissionMessage = nil
      if waitingForAuthorization {
        beginTracking()
      } else if phase == .live {
        manager.startUpdatingLocation()
      }
    } else if status == .denied || status == .restricted {
      waitingForAuthorization = false
      permissionMessage = "Location permission is needed to track trip distance."
      NativeTripWidgetStore.markTripEnded()
      Task { @MainActor in
        NativeAutoTrackEngine.shared.manualTripStartCancelled()
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard phase == .live else { return }
    var usedLocation = false
    let receivedAt = Date()
    for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) where shouldUse(location, now: receivedAt) {
      usedLocation = true
      lastLocation = location
      updateStationaryState(with: location)
      if pedestrianMileageExcluded,
         NativeTripMileagePolicy.locationConfirmsVehicleTravel(location, vehicle: vehicle) {
        resumeMileageAfterPedestrianTravel()
      }
      if !pedestrianMileageExcluded {
        recordMileageLocation(location)
      }
    }
    if usedLocation {
      permissionMessage = nil
      persistState()
    }
  }

  private func shouldUse(_ location: CLLocation, now: Date) -> Bool {
    let activeTripAge = startedAt.map { max(30, now.timeIntervalSince($0) + 30) } ?? 30
    return nativeShouldAcceptTripLocation(
      location,
      since: lastLocation,
      now: now,
      maximumAge: activeTripAge,
      earliestTimestamp: startedAt
    )
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if let locationError = error as? CLError {
      switch locationError.code {
      case .locationUnknown:
        permissionMessage = "Looking for a GPS signal. This can take a moment, especially in the simulator."
      case .denied:
        permissionMessage = "Location permission is needed to track trip distance."
      case .network:
        permissionMessage = "Location is temporarily unavailable. Check your connection and try again."
      default:
        permissionMessage = "Could not update location. Try moving to an open area."
      }
    } else {
      permissionMessage = "Could not update location. Try moving to an open area."
    }
  }

  private func startTimer() {
    stopTimer()
    timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
      guard let self, let startedAt = self.startedAt else { return }
      self.elapsed = Date().timeIntervalSince(startedAt)
      NativeTripLiveActivityController.update(miles: self.miles, elapsed: self.elapsed, isDriving: true, vehicleLabel: self.vehicle.label)
      self.persistState()
      Task { @MainActor in
        self.promptToStopIfStationary(now: Date())
      }
    }
    timer?.tolerance = 2
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func configureLocationManager(for vehicle: NativeVehicle) {
    manager.activityType = vehicle == .bike ? .fitness : .automotiveNavigation
  }

  private func startMotionMonitoring() {
    guard CMMotionActivityManager.isActivityAvailable(), !motionMonitoring else { return }
    motionMonitoring = true
    motionManager.startActivityUpdates(to: .main) { [weak self] activity in
      guard let self, let activity else { return }
      self.handleMotionActivity(activity)
    }
    reconcileRecentMotionHistory()
  }

  private func stopMotionMonitoring() {
    guard motionMonitoring else { return }
    motionManager.stopActivityUpdates()
    motionMonitoring = false
  }

  private func handleMotionActivity(_ activity: CMMotionActivity) {
    guard phase == .live else { return }
    let state = motionState(for: activity)

    if NativeTripMileagePolicy.excludesMileage(state) {
      beginPedestrianMileageExclusion(since: activity.startDate)
    } else if NativeTripMileagePolicy.confirmsVehicleTravel(state, vehicle: vehicle) {
      resumeMileageAfterPedestrianTravel()
    }
  }

  private func motionState(for activity: CMMotionActivity) -> NativeTripMotionState {
    NativeTripMileagePolicy.motionState(
      automotive: activity.automotive,
      cycling: activity.cycling,
      walking: activity.walking,
      running: activity.running,
      stationary: activity.stationary,
      hasTrustedConfidence: activity.confidence != .low,
      vehicle: vehicle
    )
  }

  private func reconcileRecentMotionHistory() {
    guard let startedAt else { return }
    let end = Date()
    let start = max(startedAt, end.addingTimeInterval(-NativeTripMileagePolicy.reconciliationWindow))
    guard start < end else { return }
    motionManager.queryActivityStarting(from: start, to: end, to: .main) { [weak self] activities, _ in
      guard let self, self.phase == .live, let activities, !activities.isEmpty else { return }
      self.applyHistoricalMotionActivities(activities, through: end)
    }
  }

  private func applyHistoricalMotionActivities(_ activities: [CMMotionActivity], through endDate: Date) {
    let classified = activities.map { (startDate: $0.startDate, state: motionState(for: $0)) }
    let reconciliationStart = max(
      startedAt ?? endDate,
      endDate.addingTimeInterval(-NativeTripMileagePolicy.reconciliationWindow)
    )
    for interval in NativeTripMileagePolicy.pedestrianIntervals(in: classified, through: endDate) {
      let clampedStart = max(interval.start, reconciliationStart)
      if clampedStart < interval.end {
        rollbackMileage(in: DateInterval(start: clampedStart, end: interval.end))
      }
    }

    var shouldExclude = pedestrianMileageExcluded
    var latestPedestrianStart = pedestrianExclusionStartedAt
    for activity in classified.sorted(by: { $0.startDate < $1.startDate }) {
      if NativeTripMileagePolicy.excludesMileage(activity.state) {
        shouldExclude = true
        latestPedestrianStart = activity.startDate
      } else if NativeTripMileagePolicy.confirmsVehicleTravel(activity.state, vehicle: vehicle) {
        shouldExclude = false
        latestPedestrianStart = nil
      }
    }

    pedestrianMileageExcluded = shouldExclude
    pedestrianExclusionStartedAt = shouldExclude ? latestPedestrianStart : nil
    if shouldExclude {
      lastMileageLocation = nil
      routeBreakPending = !points.isEmpty
    }
    updateLiveActivityAfterMileageCorrection()
    persistState()
  }

  private func beginPedestrianMileageExclusion(since activityStartDate: Date) {
    let intervalEnd = Date()
    let intervalStart = max(
      startedAt ?? activityStartDate,
      activityStartDate,
      intervalEnd.addingTimeInterval(-NativeTripMileagePolicy.reconciliationWindow)
    )
    if intervalStart < intervalEnd {
      rollbackMileage(in: DateInterval(start: intervalStart, end: intervalEnd))
    }
    pedestrianMileageExcluded = true
    pedestrianExclusionStartedAt = pedestrianExclusionStartedAt.map { min($0, intervalStart) } ?? intervalStart
    lastMileageLocation = nil
    routeBreakPending = !points.isEmpty
    updateLiveActivityAfterMileageCorrection()
    persistState()
  }

  private func resumeMileageAfterPedestrianTravel() {
    guard pedestrianMileageExcluded else { return }
    pedestrianMileageExcluded = false
    pedestrianExclusionStartedAt = nil
    lastMileageLocation = nil
    routeBreakPending = !points.isEmpty
    updateLiveActivityAfterMileageCorrection()
    persistState()
  }

  private func prepareMileageForLocationRestart() {
    pedestrianMileageExcluded = false
    pedestrianExclusionStartedAt = nil
    lastMileageLocation = nil
    routeBreakPending = !points.isEmpty
  }

  private func recordMileageLocation(_ location: CLLocation) {
    if let lastMileageLocation {
      let delta = location.distance(from: lastMileageLocation) / 1_609.344
      if delta > 0.002 && delta < 1 {
        miles += delta
        recentMileageSegments.append(NativeTripMileageSegment(
          startedAt: lastMileageLocation.timestamp,
          endedAt: location.timestamp,
          miles: delta
        ))
      }
    }
    lastMileageLocation = location

    let shouldForceBreak = routeBreakPending
    if appendRoutePoint(for: location, force: shouldForceBreak, forceBreakBefore: shouldForceBreak) {
      routeBreakPending = false
    }
    recentMileageSegments = NativeTripMileagePolicy.retainedRecentSegments(recentMileageSegments, now: location.timestamp)
  }

  private func rollbackMileage(in interval: DateInterval) {
    let removedSegments = recentMileageSegments.filter { $0.overlaps(interval) }
    let removedPoints = points.filter { point in
      guard let timestamp = point.timestamp else { return false }
      return timestamp >= interval.start && timestamp < interval.end
    }
    let boundaryPointBeforeCorrection = points.first {
      ($0.timestamp ?? .distantPast) >= interval.end
    }
    if !removedSegments.isEmpty || !removedPoints.isEmpty {
      mileageCorrections.append(NativeTripMileageCorrection(
        intervalStart: interval.start,
        intervalEnd: interval.end,
        removedMileageSegments: removedSegments,
        removedRoutePoints: removedPoints,
        boundaryPointBeforeCorrection: boundaryPointBeforeCorrection
      ))
    }
    let removedMiles = removedSegments.reduce(0) { $0 + $1.miles }
    miles = max(0, miles - removedMiles)
    recentMileageSegments.removeAll { $0.overlaps(interval) }

    points.removeAll { point in
      guard let timestamp = point.timestamp else { return false }
      return timestamp >= interval.start && timestamp < interval.end
    }
    if let nextIndex = points.firstIndex(where: { ($0.timestamp ?? .distantPast) >= interval.end }) {
      points[nextIndex].breakBefore = nextIndex > points.startIndex
      routeBreakPending = false
    } else {
      routeBreakPending = !points.isEmpty
    }
    lastRoutePointLocation = location(from: points.last)
    if let lastMileageLocation,
       lastMileageLocation.timestamp >= interval.start,
       lastMileageLocation.timestamp < interval.end {
      self.lastMileageLocation = nil
    }
  }

  private func updateLiveActivityAfterMileageCorrection() {
    NativeTripLiveActivityController.update(
      miles: miles,
      elapsed: elapsed,
      isDriving: !pedestrianMileageExcluded,
      vehicleLabel: vehicle.label,
      force: true
    )
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

  @discardableResult
  private func appendRoutePoint(
    for location: CLLocation,
    force: Bool = false,
    forceBreakBefore: Bool = false
  ) -> Bool {
    guard nativeIsPlausibleRoutePoint(location, since: lastRoutePointLocation) else { return false }
    let breakBefore = forceBreakBefore || lastRoutePointLocation.map {
      nativeRouteSegmentNeedsBreak(from: $0, to: location)
    } ?? false
    if let lastRoutePointLocation {
      let distance = location.distance(from: lastRoutePointLocation)
      guard force ? distance > 1 : distance >= routePointDistance else { return false }
    }
    points.append(RoutePoint(location: location, breakBefore: breakBefore))
    lastRoutePointLocation = location
    return true
  }

  private func updateStationaryState(with location: CLLocation) {
    guard phase == .live else { return }
    guard let anchor = stationaryAnchorLocation else {
      stationaryAnchorLocation = location
      stationarySince = location.timestamp
      return
    }

    if location.distance(from: anchor) > stationaryPromptRadius {
      stationaryAnchorLocation = location
      stationarySince = location.timestamp
      promptedForCurrentStationaryPeriod = false
    }
  }

  @MainActor
  private func promptToStopIfStationary(now: Date) {
    guard phase == .live, !stopPromptRequested, !promptedForCurrentStationaryPeriod else { return }
    guard let startedAt, now.timeIntervalSince(startedAt) >= minimumTrackingTimeBeforeStopPrompt else { return }
    guard let stationarySince, now.timeIntervalSince(stationarySince) >= stationaryPromptDelay else { return }

    promptedForCurrentStationaryPeriod = true
    if OkkleStore.shared.settings.manualTripAutoComplete {
      persistState()
      Task { @MainActor [weak self] in
        self?.completeStoppedManualTrip(store: OkkleStore.shared, notify: true)
      }
      return
    }

    stopPromptRequested = true
    persistState()
    if UIApplication.shared.applicationState != .active {
      sendStopPromptNotification()
    }
  }

  func requestStopPrompt() {
    guard phase == .live || phase == .paused else { return }
    stopPromptRequested = true
    persistState()
  }

  func dismissStopPrompt() {
    stopPromptRequested = false
    persistState()
  }

  @MainActor
  func completeStoppedManualTrip(store: OkkleStore, notify: Bool) {
    guard phase == .live || phase == .paused else { return }
    guard let trip = end(store: store) else { return }
    store.addTrip(trip)
    discard()
    if notify {
      sendAutoCompletedNotification(trip)
    }
  }

  private func sendStopPromptNotification() {
    let center = UNUserNotificationCenter.current()
    let requestIdentifier = stopPromptNotificationIdentifier
    center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = "Looks like you've stopped moving"
      content.body = "End this trip, keep tracking, or let Okkle auto-complete stopped manual trips."
      content.sound = .default
      content.categoryIdentifier = NativeManualTripStopNotification.categoryIdentifier
      content.userInfo = ["type": "manualTripStopPrompt"]
      center.add(UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: nil))
    }
  }

  private func sendAutoCompletedNotification(_ trip: NativeTrip) {
    let center = UNUserNotificationCenter.current()
    let milesText = String(format: "%.1f", trip.miles)
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = "Trip completed automatically"
      content.body = "\(milesText) miles were saved after movement stopped."
      content.sound = .default
      content.userInfo = ["type": "manualTripAutoCompleted", "tripID": trip.id.uuidString]
      center.add(UNNotificationRequest(identifier: self.autoCompletedNotificationIdentifier, content: content, trigger: nil))
    }
  }

  private func restorePersistedTrip() {
    guard let data = try? Data(contentsOf: Self.snapshotFileURL),
          let snapshot = try? JSONDecoder().decode(NativeManualTripSnapshot.self, from: data),
          let restoredPhase = Phase(rawValue: snapshot.phase),
          restoredPhase != .setup else { return }

    vehicle = snapshot.vehicle
    configureLocationManager(for: snapshot.vehicle)
    miles = snapshot.miles
    elapsed = snapshot.elapsed
    points = snapshot.points
    startedAt = snapshot.startedAt
    reviewEndedAt = snapshot.reviewEndedAt
    lastLocation = location(from: snapshot.lastLocation)
    lastMileageLocation = location(from: snapshot.lastMileageLocation) ?? lastLocation
    lastRoutePointLocation = location(from: snapshot.lastRoutePointLocation)
      ?? location(from: snapshot.points.last)
    routeBreakPending = snapshot.routeBreakPending ?? false
    pedestrianMileageExcluded = snapshot.pedestrianMileageExcluded ?? false
    pedestrianExclusionStartedAt = snapshot.pedestrianExclusionStartedAt
    recentMileageSegments = snapshot.recentMileageSegments ?? []
    mileageCorrections = snapshot.mileageCorrections ?? []
    if pedestrianMileageExcluded {
      lastMileageLocation = nil
      routeBreakPending = !points.isEmpty
    }
    stationaryAnchorLocation = location(from: snapshot.stationaryAnchorLocation)
    stationarySince = snapshot.stationarySince
    promptedForCurrentStationaryPeriod = snapshot.promptedForCurrentStationaryPeriod
    stopPromptRequested = snapshot.stopPromptRequested

    let canUseLocation = manager.authorizationStatus == .authorizedAlways ||
      manager.authorizationStatus == .authorizedWhenInUse
    phase = restoredPhase == .live && !canUseLocation ? .paused : restoredPhase

    switch phase {
    case .live:
      elapsed = max(elapsed, Date().timeIntervalSince(snapshot.startedAt))
      NativeTripWidgetStore.markTripStarted(startedAt: snapshot.startedAt)
      NativeTripLiveActivityController.start(
        source: "manual",
        vehicleLabel: vehicle.label,
        miles: miles,
        elapsed: elapsed,
        isDriving: true
      )
      setBackgroundTrackingEnabled(true)
      startMotionMonitoring()
      manager.startUpdatingLocation()
      startTimer()
    case .paused:
      if !canUseLocation {
        permissionMessage = "Location permission is needed to continue this recovered trip."
      }
      NativeTripWidgetStore.markTripStarted(startedAt: snapshot.startedAt)
      NativeTripLiveActivityController.start(
        source: "manual",
        vehicleLabel: vehicle.label,
        miles: miles,
        elapsed: elapsed,
        isDriving: false,
        isPausedByUser: true
      )
    case .summary:
      NativeTripWidgetStore.markTripEnded()
      NativeTripLiveActivityController.end()
    case .setup:
      break
    }
  }

  private func persistState() {
    guard phase != .setup, let startedAt else { return }
    let snapshot = NativeManualTripSnapshot(
      phase: phase.rawValue,
      vehicle: vehicle,
      miles: miles,
      elapsed: elapsed,
      points: points,
      startedAt: startedAt,
      reviewEndedAt: reviewEndedAt,
      lastLocation: lastLocation.map { RoutePoint(location: $0) },
      lastMileageLocation: lastMileageLocation.map { RoutePoint(location: $0) },
      lastRoutePointLocation: lastRoutePointLocation.map { RoutePoint(location: $0) },
      routeBreakPending: routeBreakPending,
      pedestrianMileageExcluded: pedestrianMileageExcluded,
      pedestrianExclusionStartedAt: pedestrianExclusionStartedAt,
      recentMileageSegments: recentMileageSegments,
      mileageCorrections: mileageCorrections,
      stationaryAnchorLocation: stationaryAnchorLocation.map { RoutePoint(location: $0) },
      stationarySince: stationarySince,
      promptedForCurrentStationaryPeriod: promptedForCurrentStationaryPeriod,
      stopPromptRequested: stopPromptRequested
    )
    let url = Self.snapshotFileURL
    persistenceQueue.async {
      do {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try data.write(
          to: url,
          options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
      } catch {
        // The in-memory trip remains authoritative for this run. A later
        // location or timer tick retries the atomic recovery snapshot.
      }
    }
  }

  private func clearPersistedState() {
    let url = Self.snapshotFileURL
    persistenceQueue.async {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private func location(from point: RoutePoint?) -> CLLocation? {
    guard let point else { return nil }
    return CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
      altitude: 0,
      horizontalAccuracy: point.horizontalAccuracy ?? 10,
      verticalAccuracy: -1,
      course: point.course ?? -1,
      speed: point.speed ?? -1,
      timestamp: point.timestamp ?? Date()
    )
  }
}
