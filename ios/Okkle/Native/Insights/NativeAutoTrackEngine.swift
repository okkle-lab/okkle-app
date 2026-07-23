import AVFoundation
import Combine
import CoreMotion
import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit
@preconcurrency import UserNotifications

struct NativeAutoTrackDiagnosticEvent: Codable, Identifiable, Equatable {
  var id = UUID()
  var timestamp: Date
  var kind: String
  var title: String
  var detail: String
}

@MainActor
final class NativeAutoTrackDiagnostics: ObservableObject {
  static let shared = NativeAutoTrackDiagnostics()

  @Published private(set) var events: [NativeAutoTrackDiagnosticEvent] = []

  private let storageKey = "uk.okkle.native.autotrack.diagnostics.v1"
  private var lastPersistedAtByKind: [String: Date] = [:]

  private init() {
    if let data = UserDefaults.standard.data(forKey: storageKey),
       let decoded = try? JSONDecoder().decode([NativeAutoTrackDiagnosticEvent].self, from: data) {
      events = Self.retainedEvents(decoded, now: Date())
      for event in events where event.timestamp > (lastPersistedAtByKind[event.kind] ?? .distantPast) {
        lastPersistedAtByKind[event.kind] = event.timestamp
      }
      save()
    }
  }

  func record(
    kind: String,
    title: String,
    detail: String,
    deduplicateWithin: TimeInterval = 0,
    at timestamp: Date = Date()
  ) {
    var replacedRecentEvent = false
    if deduplicateWithin > 0,
       let index = events.firstIndex(where: {
         $0.kind == kind && timestamp.timeIntervalSince($0.timestamp) < deduplicateWithin
       }) {
      events.remove(at: index)
      replacedRecentEvent = true
    }
    events.insert(NativeAutoTrackDiagnosticEvent(
      timestamp: timestamp,
      kind: kind,
      title: title,
      detail: detail
    ), at: 0)
    events = Self.retainedEvents(events, now: timestamp)
    let lastPersistedAt = lastPersistedAtByKind[kind] ?? .distantPast
    if !replacedRecentEvent || timestamp.timeIntervalSince(lastPersistedAt) >= deduplicateWithin {
      lastPersistedAtByKind[kind] = timestamp
      save()
    }
  }

  func clear() {
    events = []
    lastPersistedAtByKind = [:]
    UserDefaults.standard.removeObject(forKey: storageKey)
  }

  var exportText: String {
    let formatter = ISO8601DateFormatter()
    let lines = events.map { event in
      "\(formatter.string(from: event.timestamp)) | \(event.title) | \(event.detail)"
    }
    return ([
      "Okkle tracking diagnostics",
      "Generated: \(formatter.string(from: Date()))",
      "Location coordinates are not recorded.",
      "",
    ] + lines).joined(separator: "\n")
  }

  static func retainedEvents(
    _ events: [NativeAutoTrackDiagnosticEvent],
    now: Date,
    maximumCount: Int = 200,
    retentionInterval: TimeInterval = 7 * 24 * 60 * 60
  ) -> [NativeAutoTrackDiagnosticEvent] {
    events
      .filter { now.timeIntervalSince($0.timestamp) <= retentionInterval }
      .sorted { $0.timestamp > $1.timestamp }
      .prefix(maximumCount)
      .map { $0 }
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(events) else { return }
    UserDefaults.standard.set(data, forKey: storageKey)
  }
}

private enum NativeAutoTrackMotionState: Equatable {
  case automotive
  case stationary
  case walking
  case other
}

/// Absolute deadlines survive process suspension and relaunch. Persisting the
/// deadline instead of only recreating a Timer prevents every relaunch from
/// silently granting a fresh full dwell window.
struct NativeAutoTrackDeadlines: Codable, Equatable {
  var stationary: Date?
  var homeArrival: Date?
  var vehicleDisconnect: Date?
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
  var deadlines: NativeAutoTrackDeadlines?
  var pendingVisits: [NativeVisit]?
  var startTrigger: String?
  var walkingDetectedDuringStop: Bool?
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
  private static var routeChangeOverride: Bool?

  static var isLikelyConnectedToVehicle: Bool {
    if routeChangeOverride == false { return false }
    return currentPorts.contains(where: NativeAutoTrackPolicy.isVehicleAudioPort)
  }

  @discardableResult
  static func handleRouteChange(_ notification: Notification) -> Bool {
    let previousPorts = (notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
      as? AVAudioSessionRouteDescription)?.outputs.map(\.portType) ?? []
    let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)
      .flatMap { AVAudioSession.RouteChangeReason(rawValue: $0.uintValue) }
    let connected = NativeAutoTrackPolicy.vehicleConnectionState(
      currentPorts: currentPorts,
      previousPorts: previousPorts,
      routeChangeReason: reason
    )
    routeChangeOverride = connected
    return connected
  }

  /// Reconcile missed notifications when the app becomes active. A live Car
  /// Audio route is trustworthy here because the route transition has had
  /// time to settle.
  @discardableResult
  static func refreshFromCurrentRoute() -> Bool {
    let connected = currentPorts.contains(where: NativeAutoTrackPolicy.isVehicleAudioPort)
    routeChangeOverride = connected
    return connected
  }

  private static var currentPorts: [AVAudioSession.Port] {
    AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)
  }
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
  @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
  @Published private(set) var locationAccuracyAuthorization: CLAccuracyAuthorization = .reducedAccuracy
  @Published private(set) var readiness: NativeAutoTrackReadiness = .disabled
  @Published private(set) var vehicleStartArmed = false

  /// Standard high-accuracy route recorder. The separate wake manager keeps
  /// significant-change monitoring armed so iOS can relaunch the app if this
  /// process is evicted during a trip.
  private let manager = CLLocationManager()
  private let wakeManager = CLLocationManager()
  private let recorder = NativeTripRecorder.shared
  private let motionManager = CMMotionActivityManager()
  private let motionQueue = OperationQueue()
  private let legacyVisitsStorageKey = "uk.okkle.native.autotrack.visits.v1"
  private let shiftSnapshotKey = "uk.okkle.native.autotrack.liveShift.v1"
  private let shiftPersistenceQueue = DispatchQueue(label: "uk.okkle.native.auto-trip-persist", qos: .utility)
  private static let shiftSnapshotFileURL: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Okkle", isDirectory: true).appendingPathComponent("automatic-trip.json")
  }()
  private var backgroundLocationSession: AnyObject?
  private let shiftNotificationIdentifier = "uk.okkle.native.shift-logged"
  private let shiftStartNotificationIdentifier = "uk.okkle.native.shift-started"
  private var shiftStartNotified = false
  private weak var store: OkkleStore?
  private var tripSubscription: AnyCancellable?
  private var legacyVisits: [NativeVisit] = []
  private var pendingShiftVisits: [NativeVisit] = []
  private var coordinator = NativeAutoTrackCoordinator()
  private var motionMonitoring = false
  private var didAttemptShiftRestore = false
  private var manualTripStartPending = false
  private var lastShiftSnapshotQueuedAt = Date.distantPast
  private var lastMonitoringDiagnosticState: String?
  private var lastMotionState: NativeAutoTrackMotionState?
  private var lastObservedVehicleConnection: Bool?
  private var significantLocationWakeMonitoring = false
  private var highAccuracyLocationRunning = false

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
  private var shiftStartTrigger: String?
  private let drivingDistanceFilter: CLLocationDistance = 10
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
  // A Car Audio route disconnect used to end the shift the
  // instant it happened — no dwell at all. That's wrong for the same reason
  // a single home GPS ping is: stepping out for a minute, a flaky car-audio
  // drop, or briefly parking to run in somewhere all look identical to
  // "shift over" at the moment of disconnect. Wait this long, still
  // disconnected, before actually concluding.
  private let vehicleDisconnectDwellSeconds: TimeInterval = 5 * 60
  private var vehicleConnectionObservers: [NSObjectProtocol] = []
  private var idleWakeLocation: CLLocation?
  private var idleMotionQueryInFlight = false
  private var vehicleArmOrigin: CLLocation?
  private var vehicleArmLastLocation: CLLocation?
  private var vehicleArmLocations: [CLLocation] = []
  private let vehicleArmBufferWindow: TimeInterval = 2 * 60
  private let vehicleArmBufferLimit = 120
  private var homeDwellTimer: Timer?
  private var vehicleDisconnectDwellTimer: Timer?

  // A stop currently being timed — may resolve into a logged visit (driving
  // resumes) or trigger shift-end (the stationary timer expires).
  private var stationaryTimer: Timer?
  private var stationarySince: Date?
  private var stationaryCoordinate: CLLocationCoordinate2D?
  private var walkingDetectedDuringStop = false
  private var deadlines = NativeAutoTrackDeadlines()

  override init() {
    super.init()
    manager.delegate = self
    manager.activityType = .automotiveNavigation
    wakeManager.delegate = self
    wakeManager.activityType = .other
    wakeManager.desiredAccuracy = kCLLocationAccuracyKilometer
    wakeManager.pausesLocationUpdatesAutomatically = true
    configureLocationForDriving()
    motionQueue.name = "uk.okkle.native.auto-track-motion"
    motionQueue.qualityOfService = .utility
    loadLegacyVisits()
    // The Live Activity's "Done driving"/"Still driving" buttons run
    // in-process (LiveActivityIntent) but can't reference this singleton
    // directly — see OkkleTripLiveActivityIntents.swift for why — so they
    // signal over NotificationCenter instead.
    NotificationCenter.default.addObserver(forName: .nativeLiveActivityStopTrackingRequested, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.endCurrentShift() }
    }
    NotificationCenter.default.addObserver(forName: .nativeLiveActivityStillDrivingRequested, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.confirmStillDriving() }
    }
    NotificationCenter.default.addObserver(forName: .nativeManualTripPhaseDidChange, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.handleManualTripPhaseChanged() }
    }
    runRealisticWeekSimulationIfRequested()
    runCaliforniaTestDayIfRequested()
  }

  /// TEMPORARY verification-only hook — drives the real beginShift/
  /// handleShiftLocationUpdates/handleStationarySignal/handleDrivingSignal
  /// pipeline through a realistic week: several working days, several
  /// pickup→dropoff cycles per day, real roads via MKDirections (not
  /// straight-line teleporting), and real MapKit-confirmed food venues
  /// fetched live around Wimbledon so pickup classification resolves the
  /// way it would for a real driver instead of landing on one fixed
  /// coordinate every time.
  ///
  /// Dwell is faked by backdating `stationarySince` right before resuming,
  /// rather than actually waiting minutes per stop — real minimumConfident-
  /// StopDwell/minimumConnectedVehicleStopDwell thresholds still gate
  /// whether a stop records at all, so the *decision* is genuine, it's only
  /// the wall-clock wait that's skipped. Each visit/trip's stored
  /// timestamps are then rewritten onto a fully synthetic calendar so a
  /// whole week's worth of realistic data lands in minutes of real time
  /// instead of days. Will be removed after verification, along with the
  /// dwell-threshold fix above.
  private func runRealisticWeekSimulationIfRequested() {
    guard ProcessInfo.processInfo.arguments.contains("OKKLE_TEST_REALISTIC_DAY") else { return }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      let home = CLLocationCoordinate2D(latitude: 51.4275, longitude: -0.1875)
      let wimbledonCentre = CLLocationCoordinate2D(latitude: 51.4214, longitude: -0.2064)

      // Real, MapKit-confirmed food venues around Wimbledon, fetched once
      // and reused across the week — pickups land on genuine POIs the
      // classifier can actually match, not an arbitrary coordinate.
      var shops: [(name: String, coordinate: CLLocationCoordinate2D)] = []
      let poiRequest = MKLocalPointsOfInterestRequest(center: wimbledonCentre, radius: 1_400)
      poiRequest.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .foodMarket])
      if let response = try? await MKLocalSearch(request: poiRequest).start() {
        shops = response.mapItems.compactMap { item in
          guard let coordinate = item.placemark.location?.coordinate, let name = item.name else { return nil }
          return (name, coordinate)
        }
      }
      if shops.isEmpty {
        // Confirmed in an earlier run to resolve as a food-category POI.
        shops = [("Fallback venue", CLLocationCoordinate2D(latitude: 51.4387, longitude: -0.1966))]
      }
      print("OKKLE-SIM: found \(shops.count) real food venues around Wimbledon")

      @MainActor func driveRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, startingAt clockStart: Date) async -> TimeInterval {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile

        var routeCoordinates: [CLLocationCoordinate2D] = []
        var travelTime: TimeInterval = 5 * 60
        if let route = try? await MKDirections(request: request).calculate().routes.first {
          let count = route.polyline.pointCount
          var raw = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
          route.polyline.getCoordinates(&raw, range: NSRange(location: 0, length: count))
          routeCoordinates = raw
          travelTime = route.expectedTravelTime
        } else {
          routeCoordinates = [origin, destination]
        }

        // Sample down to ~8 breadcrumbs along the real road path, not a
        // straight line through buildings.
        let step = max(1, routeCoordinates.count / 8)
        var sampled: [CLLocationCoordinate2D] = [origin]
        var i = 0
        while i < routeCoordinates.count {
          sampled.append(routeCoordinates[i])
          i += step
        }
        sampled.append(destination)

        var cumulative: [CLLocationDistance] = [0]
        for idx in 1..<sampled.count {
          let a = CLLocation(latitude: sampled[idx - 1].latitude, longitude: sampled[idx - 1].longitude)
          let b = CLLocation(latitude: sampled[idx].latitude, longitude: sampled[idx].longitude)
          cumulative.append(cumulative[idx - 1] + b.distance(from: a))
        }
        let totalDistance = max(cumulative.last ?? 1, 1)

        // Feeds shiftPoints/shiftMiles directly instead of going through
        // handleShiftLocationUpdates -> appendShiftRoutePoint, whose
        // plausibility check (implied speed between consecutive *stored*
        // timestamps) and 30-second-recency guard both assume a real GPS
        // ping arriving every few seconds. A backdated, instantly-delivered
        // simulation breadcrumb can satisfy at most one of those without
        // genuinely waiting tens of seconds per leg in real time — this is
        // what silently dropped nearly every route point in an earlier run
        // (trips ended up with only 2-3 points and no visible line on the
        // map). Mirrors the same distance-delta accumulation those guards
        // would have done, just without re-deriving it from a live feed.
        for idx in 1..<sampled.count {
          let coordinate = sampled[idx]
          let deltaMeters = cumulative[idx] - cumulative[idx - 1]
          let deltaMiles = deltaMeters / 1_609.344
          if deltaMiles > 0.002 && deltaMiles < 1 { self.shiftMiles += deltaMiles }
          let fraction = cumulative[idx] / totalDistance
          self.shiftPoints.append(RoutePoint(
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            timestamp: clockStart.addingTimeInterval(travelTime * fraction)
          ))
        }
        self.shiftLastLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return travelTime
      }

      // Runs a real stop through the genuine detection pipeline (dwell
      // gating, dwell-based provisional kind, async MapKit reclassification)
      // then rewrites the resulting visit's arrival/departure onto the
      // fully synthetic simulated clock, so the *decision* is real but the
      // *timestamp* lands wherever the week's schedule needs it.
      @MainActor func simulateStop(at coordinate: CLLocationCoordinate2D, arrival: Date, dwell: TimeInterval) async {
        self.handleStationarySignal()
        self.stationarySince = Date().addingTimeInterval(-dwell)
        self.stationaryCoordinate = coordinate
        let visitsBefore = self.visits.count
        self.handleDrivingSignal()
        if self.visits.count > visitsBefore, let idx = self.visits.indices.last {
          self.visits[idx].arrival = arrival
          self.visits[idx].departure = arrival.addingTimeInterval(dwell)
        } else {
          print("OKKLE-SIM: WARNING stop at \(coordinate) with dwell=\(Int(dwell))s was NOT recorded")
        }
        // Let classifyWithMapKit's real network round-trip land before the
        // next stop starts — it matches by visit id, so the arrival/
        // departure rewrite above doesn't interfere with it.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
      }

      // Two realistic working weeks (one rest day each), spanning 14
      // calendar days so it can actually reach High confidence (needs
      // daySpan>=14, activeDays>=8, deliveries>=20) rather than stopping at
      // Medium — lets a full Insights build (zones, best window etc.) be
      // inspected instead of just the "still building" gate.
      let daysAgo = [14, 13, 12, 11, 10, 9, 7, 6, 5, 4, 3, 2, 0]
      var totalDeliveries = 0

      for (dayIndex, dOffset) in daysAgo.enumerated() {
        guard let dayAnchor = Calendar.current.date(byAdding: .day, value: -dOffset, to: Date()),
              var clock = Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: dayAnchor)
        else { continue }

        print("OKKLE-SIM: === day -\(dOffset) starting \(clock) ===")
        self.apply(.drivingDetected, trigger: "Realistic test route")
        self.shiftStartedAt = clock
        self.shiftMiles = 0

        var previous = home
        let cycleCount = 3 + (dayIndex % 3)   // 3-5 deliveries a day, varied like a real week
        for cycle in 1...cycleCount {
          let shop = shops[(dayIndex * 7 + cycle) % shops.count]

          let driveToShop = await driveRoute(from: previous, to: shop.coordinate, startingAt: clock)
          clock = clock.addingTimeInterval(driveToShop)
          let pickupDwell = TimeInterval.random(in: 260...420)
          await simulateStop(at: shop.coordinate, arrival: clock, dwell: pickupDwell)
          clock = clock.addingTimeInterval(pickupDwell)
          print("OKKLE-SIM: day -\(dOffset) cycle \(cycle) picked up at \(shop.name)")

          // A different, realistically-scattered delivery address each
          // cycle — varied compass bearing and distance, not a monotonic line.
          let bearing = Double((dayIndex * 5 + cycle) * 47 % 360)
          let distanceKm = 0.4 + Double((dayIndex + cycle) % 5) * 0.35
          let dropoff = nativeOffsetCoordinate(shop.coordinate, distanceKm: distanceKm, bearingDeg: bearing)

          let driveToDropoff = await driveRoute(from: shop.coordinate, to: dropoff, startingAt: clock)
          clock = clock.addingTimeInterval(driveToDropoff)
          let dropoffDwell = TimeInterval.random(in: 250...340)
          await simulateStop(at: dropoff, arrival: clock, dwell: dropoffDwell)
          clock = clock.addingTimeInterval(dropoffDwell)
          totalDeliveries += 1
          print("OKKLE-SIM: day -\(dOffset) cycle \(cycle) dropped off")

          // A realistic gap waiting for the next order.
          clock = clock.addingTimeInterval(TimeInterval.random(in: 120...480))
          previous = dropoff
        }

        _ = await driveRoute(from: previous, to: home, startingAt: clock)
        print("OKKLE-SIM: day -\(dOffset) ending shift, visits so far=\(self.visits.count) miles=\(self.shiftMiles)")
        self.endCurrentShift()

        // saveShiftAsTrip() (inside endCurrentShift/concludeShift) used
        // shiftStartedAt — already backdated above — for the trip's
        // startedAt, but endedAt is real Date(); rewrite it onto the
        // simulated clock so the trip's duration and calendar placement are
        // both realistic instead of "started a week ago, ended just now."
        if let store = self.store, let idx = store.trips.firstIndex(where: { $0.id == self.lastAutoShiftID }) {
          store.trips[idx].endedAt = clock
        }

        // A realistic day's earnings/expenses too, so Reports has real
        // income/expense data to reconcile against, not just mileage.
        if let store = self.store {
          let dayIncome = Double(cycleCount) * Double.random(in: 8.5...11.5)
          store.addRecord(NativeRecord(
            kind: .income, platform: ["Uber Eats", "Deliveroo", "Just Eat"][dayIndex % 3],
            amount: (dayIncome * 100).rounded() / 100, date: clock, period: .day
          ))
          if dayIndex % 3 == 0 {
            store.addRecord(NativeRecord(
              kind: .expense, amount: Double.random(in: 18...32).rounded(), category: "Fuel",
              date: clock, period: .day
            ))
          }
        }
        self.syncPublishedVisits()
        self.persistShiftSnapshot()
        self.store?.save()
      }

      try? await Task.sleep(nanoseconds: 2_000_000_000)
      print("OKKLE-SIM: FINAL visits.count=\(self.visits.count) totalDeliveries=\(totalDeliveries) trips=\(self.store?.trips.count ?? -1)")
      for v in self.visits {
        print("OKKLE-SIM: visit kind=\(v.kind) arrival=\(v.arrival) dwell=\(Int(v.dwell))s place=\(v.placeName ?? "nil") coord=\(v.coordinate)")
      }
    }
  }

  /// TEMPORARY verification-only hook — builds a realistic multi-day San
  /// Francisco courier history (6 consecutive pickup→dropoff cycles/day
  /// against real, well-known SF restaurants) with the store switched to
  /// US/California, so Insights/Reports/exports get exercised against real
  /// trip/record data instead of just unit-test fixtures.
  ///
  /// Deliberately builds `NativeTrip`/`RoutePoint` data directly and hands it
  /// to `NativeTripAnalysisProjector.build` (the same stop-detection pass a
  /// manually-logged trip gets) rather than driving the live
  /// NativeAutoTrackEngine state machine or any MapKit network call — a
  /// Simulator without real network/motion access can otherwise hang this
  /// indefinitely with nothing to show for it. Will be removed after
  /// verification.
  private func runCaliforniaTestDayIfRequested() {
    guard ProcessInfo.processInfo.arguments.contains("OKKLE_TEST_SF_CALIFORNIA_DAY") else { return }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      guard let store = self.store else { return }
      store.settings.taxCountry = .us
      store.settings.usState = .california
      store.settings.platforms = ["DoorDash", "Uber Eats", "Grubhub"]

      let home = CLLocationCoordinate2D(latitude: 37.7599, longitude: -122.4148)   // Mission District

      // Real, well-known San Francisco restaurants — hardcoded rather than a
      // live MapKit lookup, which a Simulator without real network access
      // can hang on indefinitely (see the doc comment above).
      let shops: [(name: String, coordinate: CLLocationCoordinate2D)] = [
        ("Tadich Grill", CLLocationCoordinate2D(latitude: 37.7929, longitude: -122.4033)),
        ("House of Prime Rib", CLLocationCoordinate2D(latitude: 37.7909, longitude: -122.4217)),
        ("Zuni Café", CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4241)),
        ("Tartine Bakery", CLLocationCoordinate2D(latitude: 37.7614, longitude: -122.4241)),
        ("Nopa", CLLocationCoordinate2D(latitude: 37.7757, longitude: -122.4376)),
        ("Foreign Cinema", CLLocationCoordinate2D(latitude: 37.7526, longitude: -122.4204)),
      ]
      print("OKKLE-SIM-CA: using \(shops.count) real San Francisco restaurants")

      // Straight-line leg with a few lightly-jittered intermediate points (so
      // the trip map isn't one dead-straight segment), plus a stationary
      // dwell pair at the destination — two same-spot points far enough
      // apart in time for NativeRouteStopDetector's real dwell gate
      // (>=4 minutes, matching production) to recognize a genuine stop.
      func appendLeg(
        to points: inout [RoutePoint], miles: inout Double,
        from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D,
        arriveAt clock: inout Date, thenDwell dwell: TimeInterval
      ) {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let distanceMeters = destinationLocation.distance(from: originLocation)
        let travelTime = max(60, distanceMeters / 6.7)   // ~15 mph, realistic dense-city driving

        let steps = 4
        let legStart = clock
        var previousLocation = originLocation
        for step in 1...steps {
          let fraction = Double(step) / Double(steps)
          var point = CLLocationCoordinate2D(
            latitude: origin.latitude + (destination.latitude - origin.latitude) * fraction,
            longitude: origin.longitude + (destination.longitude - origin.longitude) * fraction
          )
          if step < steps {
            point.latitude += Double.random(in: -0.0006...0.0006)
            point.longitude += Double.random(in: -0.0006...0.0006)
          }
          let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
          let deltaMiles = pointLocation.distance(from: previousLocation) / 1_609.344
          if deltaMiles > 0.002 && deltaMiles < 1 { miles += deltaMiles }
          points.append(RoutePoint(
            latitude: point.latitude, longitude: point.longitude,
            timestamp: legStart.addingTimeInterval(travelTime * fraction)
          ))
          previousLocation = pointLocation
        }
        clock = legStart.addingTimeInterval(travelTime)
        // The stationary pair: same spot, dwell minutes apart.
        points.append(RoutePoint(latitude: destination.latitude, longitude: destination.longitude, timestamp: clock))
        clock = clock.addingTimeInterval(dwell)
        points.append(RoutePoint(latitude: destination.latitude, longitude: destination.longitude, timestamp: clock))
      }

      // Same day-shape as the UK realistic-week simulation: 13 active days
      // spanning a 14-day window (one rest day) so Insights actually clears
      // the High-confidence bar (daySpan>=14, activeDays>=8, deliveries>=20)
      // instead of sitting cold — 6 consecutive deliveries/day comfortably
      // clears that on its own across 13 days.
      let daysAgo = [14, 13, 12, 11, 10, 9, 7, 6, 5, 4, 3, 2, 0]
      let platforms = ["DoorDash", "Uber Eats", "Grubhub"]
      var totalEarnings = 0.0
      var totalDeliveries = 0

      for (dayIndex, dOffset) in daysAgo.enumerated() {
        guard let dayAnchor = Calendar.current.date(byAdding: .day, value: -dOffset, to: Date()),
              let dayStart = Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: dayAnchor)
        else { continue }

        var clock = dayStart
        var points: [RoutePoint] = [RoutePoint(latitude: home.latitude, longitude: home.longitude, timestamp: clock)]
        var miles = 0.0
        var previous = home

        for cycle in 1...6 {
          let shop = shops[(dayIndex * 7 + cycle) % shops.count]
          let pickupDwell = TimeInterval.random(in: 260...420)
          appendLeg(to: &points, miles: &miles, from: previous, to: shop.coordinate, arriveAt: &clock, thenDwell: pickupDwell)

          let bearing = Double((dayIndex * 5 + cycle) * 47 % 360)
          let distanceKm = 0.4 + Double((dayIndex + cycle) % 5) * 0.35
          let dropoff = nativeOffsetCoordinate(shop.coordinate, distanceKm: distanceKm, bearingDeg: bearing)
          let dropoffDwell = TimeInterval.random(in: 250...340)
          appendLeg(to: &points, miles: &miles, from: shop.coordinate, to: dropoff, arriveAt: &clock, thenDwell: dropoffDwell)
          totalDeliveries += 1

          // A real, per-delivery earnings record — the platform mix and
          // amounts a real SF DoorDash/Uber Eats/Grubhub driver would log.
          let platform = platforms[(dayIndex + cycle) % platforms.count]
          let fare = Double.random(in: 6.5...13.5)
          totalEarnings += fare
          store.addRecord(NativeRecord(
            kind: .income, platform: platform, amount: (fare * 100).rounded() / 100, date: clock, period: .day
          ))

          clock = clock.addingTimeInterval(TimeInterval.random(in: 120...480))
          points.append(RoutePoint(latitude: dropoff.latitude, longitude: dropoff.longitude, timestamp: clock))
          previous = dropoff
        }

        var dummyMiles = 0.0
        appendLeg(to: &points, miles: &dummyMiles, from: previous, to: home, arriveAt: &clock, thenDwell: 0)
        miles += dummyMiles

        var trip = NativeTrip(
          source: .automatic,
          vehicle: .car,
          miles: miles,
          deduction: store.calcDeduction(miles: miles, vehicle: .car, date: dayStart),
          startedAt: dayStart,
          endedAt: clock,
          points: points
        )
        trip.category = .business
        trip.analysis = NativeTripAnalysisProjector.build(for: trip, source: .automatic)
        store.addTrip(trip)
        print("OKKLE-SIM-CA: day -\(dOffset) trip saved, miles=\(String(format: "%.1f", miles)) stops=\(trip.analysis?.stops.count ?? 0)")

        // Real expenses too — gas (San Francisco prices) every driving day,
        // plus the odd bigger one, so Reports/Schedule C has something to
        // reconcile against besides mileage and the standard-mileage
        // deduction.
        store.addRecord(NativeRecord(
          kind: .expense, amount: Double.random(in: 22...38).rounded(), category: "Fuel",
          merchant: "Chevron", date: clock, period: .day
        ))
        if dayIndex % 4 == 0 {
          store.addRecord(NativeRecord(
            kind: .expense, amount: 24.99, category: "Equipment", merchant: "AutoZone", date: clock, period: .day
          ))
        }
      }

      store.save()
      print("OKKLE-SIM-CA: FINAL trips=\(store.trips.count) totalDeliveries=\(totalDeliveries) earnings=$\(String(format: "%.2f", totalEarnings))")
    }
  }

  /// The Live Activity's "Still driving" button — confirms whatever
  /// stationary/dwell window is pending is a false alarm and continues the
  /// same shift, same as CoreMotion detecting real driving motion again.
  func confirmStillDriving() {
    apply(.drivingDetected)
  }

  func configure(store: OkkleStore, launchedForLocationEvent: Bool = false) {
    self.store = store
    if store.migrateTripAnalyses(legacyVisits: legacyVisits) {
      store.save()
    }
    legacyVisits = []
    UserDefaults.standard.removeObject(forKey: legacyVisitsStorageKey)
    tripSubscription = store.$trips.sink { [weak self] trips in
      self?.syncPublishedVisits(from: trips)
    }
    store.onRecordAdded = { [weak self] record in self?.checkOutcome(for: record) }
    if launchedForLocationEvent {
      NativeAutoTrackDiagnostics.shared.record(
        kind: "lifecycle.location-launch",
        title: "Location wake relaunched Okkle",
        detail: "Core Location relaunched the app in the background; tracking services are being restored."
      )
    }
    if !didAttemptShiftRestore {
      didAttemptShiftRestore = true
      restoreShiftIfNeeded()
    }
    startVehicleConnectionMonitoring()
    refresh()
  }

  /// The self-correcting half of the confidence model: every time pay gets
  /// logged, check whether that date was one the model had called a "peak"
  /// day, and hand the outcome to the tracker. Entirely silent — this never
  /// shows anything, it just quietly keeps the confidence label honest.
  private func checkOutcome(for record: NativeRecord) {
    guard record.isInsightRecommendationIncome,
          let amount = record.amount,
          let store,
          store.settings.insightsEnabled else { return }
    let input = NativeInsightInput(visits: visits, store: store)
    Task {
      let insights = await NativeInsightsProjector.shared.project(input).shift
      guard store.settings.insightsEnabled else { return }
      self.recordOutcome(record: record, amount: amount, insights: insights)
    }
  }

  private func recordOutcome(record: NativeRecord, amount: Double, insights: NativeShiftInsights) {

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

  /// Keep the low-power wake service alive whenever permissions allow it, then
  /// separately decide whether today's signals may start a trip.
  func refresh() {
    // The app coming to foreground (e.g. the driver opening it) is itself a
    // wake opportunity — catch up on anything a background timer couldn't
    // fire for immediately, rather than waiting for the next location/motion
    // event.
    catchUpOverdueTimers()
    locationAuthorizationStatus = manager.authorizationStatus
    locationAccuracyAuthorization = manager.accuracyAuthorization
    guard let settings = store?.settings else {
      readiness = .disabled
      recordMonitoringDiagnosticIfChanged(
        state: "unavailable.no-store",
        kind: "monitoring.no-store",
        title: "Automatic tracking unavailable",
        detail: "The app data store is not configured."
      )
      stopMonitoring()
      return
    }
    readiness = NativeAutoTrackPolicy.readiness(
      settings: settings,
      authorizationStatus: locationAuthorizationStatus,
      accuracyAuthorization: locationAccuracyAuthorization,
      date: Date()
    )

    if shiftPhase != .idle {
      guard NativeAutoTrackPolicy.canContinueActiveShift(
        settings: settings,
        authorizationStatus: locationAuthorizationStatus,
        accuracyAuthorization: locationAccuracyAuthorization
      ) else {
        let detail = monitoringInactiveDetail(settings: settings)
        recordMonitoringDiagnosticIfChanged(
          state: "inactive.active.\(detail)",
          kind: "monitoring.inactive",
          title: "Automatic tracking inactive",
          detail: detail
        )
        stopMonitoring()
        return
      }
      recordMonitoringDiagnosticIfChanged(
        state: "ready.active",
        kind: "monitoring.ready",
        title: "Automatic tracking ready",
        detail: "The active trip remains eligible to continue."
      )
      publishLiveShift()
      startMotionMonitoring()
      ensureActiveLocationRecording(reason: "Lifecycle refresh", recordsDiagnostic: false, forceRestart: false)
      return
    }

    guard NativeAutoTrackPolicy.canMaintainWakeMonitoring(
      settings: settings,
      authorizationStatus: locationAuthorizationStatus
    ) else {
      let detail = monitoringInactiveDetail(settings: settings)
      recordMonitoringDiagnosticIfChanged(
        state: "inactive.idle.\(detail)",
        kind: "monitoring.inactive",
        title: "Automatic tracking inactive",
        detail: detail
      )
      stopMonitoring()
      return
    }

    guard readiness == .ready else {
      let detail = monitoringInactiveDetail(settings: settings)
      stopMotionMonitoring()
      disarmVehicleStartDetection(reason: detail)
      configureLocationForIdleWakeIfNeeded()
      recordMonitoringDiagnosticIfChanged(
        state: "waiting.\(detail)",
        kind: "monitoring.waiting",
        title: "Automatic tracking waiting",
        detail: detail
      )
      return
    }

    recordMonitoringDiagnosticIfChanged(
      state: "ready.idle",
      kind: "monitoring.ready",
      title: "Automatic tracking ready",
      detail: "Always and Precise location access are active on a selected working day."
    )
    startMotionMonitoring()
    configureIdleLocationMonitoring()
  }

  private func recordMonitoringDiagnosticIfChanged(
    state: String,
    kind: String,
    title: String,
    detail: String
  ) {
    guard lastMonitoringDiagnosticState != state else { return }
    lastMonitoringDiagnosticState = state
    NativeAutoTrackDiagnostics.shared.record(
      kind: kind,
      title: title,
      detail: detail,
      deduplicateWithin: 60 * 60
    )
  }

  /// Called only from an explicit user action in Settings. Permission prompts
  /// never fire from lifecycle refreshes or a passive background wake.
  func requestAlwaysLocationAuthorization() {
    guard UIApplication.shared.applicationState == .active else { return }
    manager.requestAlwaysAuthorization()
  }

  func requestPreciseLocationAuthorization() {
    guard UIApplication.shared.applicationState == .active else { return }
    manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "TripTracking") { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  private func stopMonitoring() {
    stopMotionMonitoring()
    if shiftPhase == .idle {
      disarmVehicleStartDetection(reason: "Automatic tracking is inactive")
      stopHighAccuracyLocationUpdates()
      stopSignificantLocationWakeMonitoring()
      endBackgroundLocationSession()
      setBackgroundTrackingEnabled(false)
      idleWakeLocation = nil
    }
    // Turning tracking off mid-shift shouldn't throw away real, already-
    // recorded GPS miles — save what's there rather than silently lose it.
    if shiftPhase != .idle {
      requestAutomaticEnd(
        reason: "Automatic tracking became unavailable",
        evidence: NativeTripStopEvidenceSnapshot(),
        force: true
      )
    }
  }

  func manualTripStartRequested() {
    manualTripStartPending = true
    NativeAutoTrackDiagnostics.shared.record(
      kind: "handoff.manual.requested",
      title: "Manual tracking requested",
      detail: "Automatic tracking released location ownership."
    )
    if shiftPhase != .idle {
      requestAutomaticEnd(
        reason: "Manual trip started",
        evidence: NativeTripStopEvidenceSnapshot(),
        force: true
      )
    }
    disarmVehicleStartDetection(reason: "Manual trip requested")
    stopSignificantLocationWakeMonitoring()
    idleWakeLocation = nil
  }

  func manualTripStartCancelled() {
    guard manualTripStartPending else { return }
    manualTripStartPending = false
    NativeAutoTrackDiagnostics.shared.record(
      kind: "handoff.manual.cancelled",
      title: "Manual tracking cancelled",
      detail: "Automatic tracking is taking location ownership again."
    )
    refresh()
  }

  private func handleManualTripPhaseChanged() {
    let phase = NativeTripSession.shared.phase
    manualTripStartPending = false
    NativeAutoTrackDiagnostics.shared.record(
      kind: "handoff.manual.\(phase.rawValue)",
      title: "Manual trip \(phase.diagnosticLabel)",
      detail: phase == .setup
        ? "Automatic tracking may arm again."
        : "Automatic tracking remains suspended."
    )
    if phase == .setup {
      refresh()
    } else if shiftPhase == .idle {
      disarmVehicleStartDetection(reason: "Manual trip owns location tracking")
      stopSignificantLocationWakeMonitoring()
      idleWakeLocation = nil
    }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      self.locationAuthorizationStatus = manager.authorizationStatus
      self.locationAccuracyAuthorization = manager.accuracyAuthorization
      self.refresh()
    }
  }

  nonisolated func locationManager(_ locationManager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    Task { @MainActor in
      if locationManager === self.wakeManager {
        self.handleSignificantLocationWake(locations)
      } else {
        self.handleLocationUpdates(locations)
      }
    }
  }

  nonisolated func locationManagerDidPauseLocationUpdates(_ locationManager: CLLocationManager) {
    Task { @MainActor in
      guard locationManager !== self.wakeManager else { return }
      guard NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: self.shiftPhase) else { return }
      NativeAutoTrackDiagnostics.shared.record(
        kind: "gps.paused",
        title: "Location updates paused",
        detail: "Core Location paused the high-accuracy stream; Okkle requested it again.",
        deduplicateWithin: 60
      )
      self.ensureActiveLocationRecording(reason: "Core Location pause callback")
    }
  }

  nonisolated func locationManagerDidResumeLocationUpdates(_ locationManager: CLLocationManager) {
    Task { @MainActor in
      guard locationManager !== self.wakeManager else { return }
      guard NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: self.shiftPhase) else { return }
      NativeAutoTrackDiagnostics.shared.record(
        kind: "gps.resumed",
        title: "Location updates resumed",
        detail: "Core Location resumed the high-accuracy stream.",
        deduplicateWithin: 60
      )
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in
      NativeAutoTrackDiagnostics.shared.record(
        kind: "gps.error",
        title: "Location manager error",
        detail: error.localizedDescription,
        deduplicateWithin: 30
      )
    }
  }

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
    lastMotionState = nil
  }

  private func handleMotionActivity(_ activity: CMMotionActivity) {
    let isTrustedDriving = activity.automotive && activity.confidence != .low
    // Give a fresh, trusted driving signal the chance to cancel an overdue
    // stop deadline before catch-up evaluates it. Processing the deadline
    // first can end a trip on the same callback that proves it is still moving.
    if !isTrustedDriving { catchUpOverdueTimers() }
    guard let settings = store?.settings else { return }
    let isEligible = shiftPhase == .idle
      ? NativeAutoTrackPolicy.canStartTrip(
          settings: settings,
          authorizationStatus: locationAuthorizationStatus,
          accuracyAuthorization: locationAccuracyAuthorization,
          date: Date()
        )
      : NativeAutoTrackPolicy.canContinueActiveShift(
          settings: settings,
          authorizationStatus: locationAuthorizationStatus,
          accuracyAuthorization: locationAccuracyAuthorization
        )
    guard isEligible else { return }
    // A manual trip already running takes priority — never double-record.
    guard !manualTrackingOwnsLocation else { return }

    if isTrustedDriving {
      let motionStateChanged = lastMotionState != .automotive
      lastMotionState = .automotive
      if motionStateChanged {
        NativeAutoTrackDiagnostics.shared.record(
          kind: "motion.automotive",
          title: "Automotive motion detected",
          detail: "Core Motion confidence: \(motionConfidenceLabel(activity.confidence))."
        )
      }
      if shiftPhase == .driving { cancelVehicleDisconnectDwellTimer() }
      handleDrivingSignal(trigger: "Core Motion automotive")
      catchUpOverdueTimers()
    } else if activity.walking, activity.confidence != .low, shiftPhase == .stationaryPending {
      let motionStateChanged = lastMotionState != .walking
      lastMotionState = .walking
      if !walkingDetectedDuringStop {
        walkingDetectedDuringStop = true
        persistShiftSnapshot()
      }
      if motionStateChanged {
        NativeAutoTrackDiagnostics.shared.record(
          kind: "motion.walking-after-stop",
          title: "Walking detected after stop",
          detail: "This increases confidence that the driver left the vehicle."
        )
      }
    } else if activity.stationary, activity.confidence != .low {
      let motionStateChanged = lastMotionState != .stationary
      lastMotionState = .stationary
      let stationarySignalHasEffect = NativeAutoTrackPolicy.shouldProcessStationarySignal(
        during: shiftPhase,
        vehicleStartArmed: vehicleStartArmed
      )
      guard stationarySignalHasEffect else { return }
      if motionStateChanged {
        NativeAutoTrackDiagnostics.shared.record(
          kind: "motion.stationary",
          title: "Stationary motion detected",
          detail: "Core Motion confidence: \(motionConfidenceLabel(activity.confidence))."
        )
      }
      if shiftPhase == .idle, vehicleStartArmed, motionStateChanged {
        rebaseVehicleArmBuffer(at: vehicleArmLastLocation)
      }
      handleStationarySignal()
    } else {
      lastMotionState = .other
    }
    // Ambiguous readings (walking, unknown, low confidence) don't change
    // phase — a brief wobble shouldn't flip the state machine back and forth.
  }

  private func handleDrivingSignal(
    trigger: String = "Automatic driving signal",
    evidence suppliedEvidence: NativeTripStartEvidence? = nil,
    initialLocations suppliedLocations: [CLLocation]? = nil
  ) {
    let initialLocations = suppliedLocations ?? (vehicleStartArmed
      ? NativeAutoTrackPolicy.armedTripInitialLocations(bufferedLocations: vehicleArmLocations)
      : [])
    let latest = initialLocations.last ?? shiftLastLocation ?? idleWakeLocation
    let displacement = initialLocations.count > 1
      ? initialLocations.last!.distance(from: initialLocations.first!)
      : 0
    let inferredEvidence = NativeTripStartEvidence(
      automotiveMotion: trigger.localizedCaseInsensitiveContains("motion") || trigger.localizedCaseInsensitiveContains("automotive"),
      speedMetersPerSecond: latest?.speed,
      displacementMeters: displacement,
      vehicleConnected: enhancedAutoTrackingEnabled && NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle,
      headingIsConsistent: (latest?.course ?? -1) >= 0
    )
    let evidence = suppliedEvidence ?? inferredEvidence
    if shiftPhase == .stationaryPending {
      guard NativeTrackingConfidenceEvaluator.shouldResumeDriving(evidence) else { return }
      NativeAutoTrackDiagnostics.shared.record(
        kind: "shift.resumed",
        title: "Automatic trip resumed",
        detail: "Driving resumed before the stationary timeout."
      )
    }
    if shiftPhase == .idle {
      let decision = NativeTrackingConfidenceEvaluator.startDecision(evidence)
      guard decision.shouldTransition else {
        NativeAutoTrackDiagnostics.shared.record(
          kind: "shift.start-insufficient-evidence",
          title: "Driving signal held",
          detail: "Trigger: \(trigger). Confidence: \(Int((decision.score * 100).rounded()))%.",
          deduplicateWithin: 30
        )
        return
      }
    }
    apply(.drivingDetected, trigger: trigger, initialLocations: initialLocations)
  }

  private func requestAutomaticEnd(
    reason: String,
    evidence: NativeTripStopEvidenceSnapshot,
    endedAt: Date = Date(),
    force: Bool = false
  ) {
    let timeout = store?.settings.autoTrackCalibration.stationaryTimeoutSeconds ?? 20 * 60
    let decision = NativeTrackingConfidenceEvaluator.stopDecision(evidence, stationaryTimeout: timeout)
    guard force || decision.shouldTransition else {
      NativeAutoTrackDiagnostics.shared.record(
        kind: "shift.end-insufficient-evidence",
        title: "End signal held",
        detail: "Reason: \(reason). Confidence: \(Int((decision.score * 100).rounded()))%.",
        deduplicateWithin: 30
      )
      return
    }
    apply(.endRequested(reason: reason), endedAt: endedAt)
  }

  private func handleStationarySignal() {
    apply(.stationaryDetected)
  }

  private func performStationaryWait() {
    stationarySince = Date()
    stationaryCoordinate = shiftLastLocation?.coordinate
    walkingDetectedDuringStop = false
    configureLocationForStationaryWaiting()
    if let shiftLastLocation { trackHomeArrival(at: shiftLastLocation) }
    armVehicleDisconnectDwellIfNeeded()
    scheduleStationaryTimeout()
    persistShiftSnapshot()
    NativeAutoTrackDiagnostics.shared.record(
      kind: "shift.stationary",
      title: "Automatic trip waiting",
      detail: "Stationary timeout is armed."
    )
    NativeTripLiveActivityController.update(miles: shiftMiles, elapsed: Date().timeIntervalSince(shiftStartedAt ?? Date()), isDriving: false, vehicleLabel: liveShiftVehicle.label, force: true)
  }

  private func scheduleStationaryTimeout() {
    stationaryTimer?.invalidate()
    let timeout = store?.settings.autoTrackCalibration.stationaryTimeoutSeconds ?? 20 * 60
    let deadline = deadlines.stationary ?? stationarySince?.addingTimeInterval(timeout) ?? Date().addingTimeInterval(timeout)
    deadlines.stationary = deadline
    stationaryTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
      Task { @MainActor in self?.catchUpOverdueTimers() }
    }
    stationaryTimer?.tolerance = 30
    persistShiftSnapshot()
  }

  /// `Timer` doesn't reliably fire while iOS has this process suspended in
  /// the background — a dwell/timeout can elapse for real without its
  /// closure ever running, which is why a shift-ended notification could
  /// previously only arrive once the driver reopened the app. Called on
  /// every wake opportunity this engine gets (a location update, a motion
  /// update, or the app coming to foreground) so an overdue timer gets
  /// finalized — and its notification sent — as soon as the process is
  /// actually running again, instead of waiting for the exact scheduled
  /// callback the OS may have skipped.
  private func catchUpOverdueTimers() {
    let now = Date()
    enum DueKind { case stationary, homeArrival, vehicleDisconnect }
    let overdue: [(DueKind, Date)] = [
      deadlines.stationary.map { (.stationary, $0) },
      deadlines.homeArrival.map { (.homeArrival, $0) },
      deadlines.vehicleDisconnect.map { (.vehicleDisconnect, $0) },
    ].compactMap { $0 }.filter { $0.1 <= now }
    guard let next = overdue.min(by: { $0.1 < $1.1 }) else { return }

    switch next.0 {
    case .stationary:
      stationaryTimer?.invalidate()
      stationaryTimer = nil
      deadlines.stationary = nil
      requestAutomaticEnd(
        reason: "Stationary timeout elapsed",
        evidence: NativeTripStopEvidenceSnapshot(
          stationaryDuration: max(0, next.1.timeIntervalSince(stationarySince ?? next.1)),
          stationaryMotion: true,
          walkingDetected: walkingDetectedDuringStop
        ),
        endedAt: next.1
      )
    case .homeArrival:
      confirmHomeArrivalIfStillNearby(endedAt: next.1)
    case .vehicleDisconnect:
      confirmVehicleStillDisconnected(endedAt: next.1)
    }
    if shiftPhase != .idle {
      catchUpOverdueTimers()
    }
  }

  private func apply(
    _ event: NativeAutoTrackEvent,
    trigger: String = "Automatic driving signal",
    initialLocations: [CLLocation] = [],
    endedAt: Date = Date()
  ) {
    let effect = coordinator.handle(event)
    guard effect != .none else { return }
    shiftPhase = coordinator.state.phase

    switch effect {
    case .none:
      break
    case .beginShift:
      performBeginShift(trigger: trigger, initialLocations: initialLocations)
    case .beginStationaryWait:
      performStationaryWait()
    case .resumeFromStationary:
      performResumeFromStationary()
    case .pauseShift:
      performPauseShift()
    case .resumePausedShift:
      performResumePausedShift()
    case let .concludeShift(reason):
      performConcludeShift(endedAt: endedAt, reason: reason)
    }
  }

  private func performBeginShift(
    trigger: String = "Automatic driving signal",
    initialLocations: [CLLocation] = []
  ) {
    vehicleStartArmed = false
    vehicleArmOrigin = nil
    vehicleArmLastLocation = nil
    vehicleArmLocations = []
    shiftPoints = []
    shiftMiles = 0
    pendingShiftVisits = []
    shiftStartTrigger = trigger
    shiftStartedAt = initialLocations.first?.timestamp ?? Date()
    guard recorder.begin(owner: .automatic, startedAt: shiftStartedAt ?? Date()) else {
      coordinator.restore(phase: .idle)
      shiftPhase = .idle
      shiftStartedAt = nil
      shiftStartTrigger = nil
      shiftPoints = []
      shiftMiles = 0
      publishLiveShift()
      clearShiftSnapshot()
      NativeAutoTrackDiagnostics.shared.record(
        kind: "shift.recorder-busy",
        title: "Automatic trip not started",
        detail: "The shared recorder is already owned by a manual trip."
      )
      refresh()
      return
    }
    shiftStartNotified = false
    shiftLastLocation = nil
    shiftLastRoutePointLocation = nil
    shiftSawVehicleConnection = enhancedAutoTrackingEnabled && NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle
    shiftArmedForHomeArrival = false
    deadlines = NativeAutoTrackDeadlines()
    cancelHomeDwellTimer()
    cancelVehicleDisconnectDwellTimer()
    liveShiftVehicle = store?.settings.defaultVehicle ?? .car
    publishLiveShift()
    persistShiftSnapshot()
    NativeTripLiveActivityController.start(source: "auto", vehicleLabel: liveShiftVehicle.label, miles: 0, elapsed: 0, isDriving: true)
    ensureActiveLocationRecording(reason: "Trip start")
    NativeAutoTrackDiagnostics.shared.record(
      kind: "shift.started",
      title: "Automatic trip started",
      detail: "Trigger: \(trigger). Preserved \(initialLocations.count) initial GPS fix\(initialLocations.count == 1 ? "" : "es")."
    )
    if !initialLocations.isEmpty {
      handleShiftLocationUpdates(initialLocations)
      persistShiftSnapshot()
    }
  }

  func pauseCurrentShift() {
    apply(.pauseRequested)
  }

  private func performPauseShift() {
    stationaryTimer?.invalidate()
    stationaryTimer = nil
    deadlines.stationary = nil
    stationarySince = nil
    stationaryCoordinate = nil
    walkingDetectedDuringStop = false
    cancelHomeDwellTimer()
    cancelVehicleDisconnectDwellTimer()
    stopHighAccuracyLocationUpdates()
    stopSignificantLocationWakeMonitoring()
    endBackgroundLocationSession()
    setBackgroundTrackingEnabled(false)
    publishLiveShift()
    persistShiftSnapshot()
    NativeAutoTrackDiagnostics.shared.record(
      kind: "shift.paused",
      title: "Automatic trip paused",
      detail: "Paused by the driver."
    )
    NativeTripLiveActivityController.update(miles: shiftMiles, elapsed: Date().timeIntervalSince(shiftStartedAt ?? Date()), isDriving: false, vehicleLabel: liveShiftVehicle.label, force: true)
  }

  func resumeCurrentShift() {
    apply(.resumeRequested)
  }

  private func performResumePausedShift() {
    ensureActiveLocationRecording(reason: "Manual resume")
    publishLiveShift()
    persistShiftSnapshot()
    NativeAutoTrackDiagnostics.shared.record(
      kind: "shift.resumed.manual",
      title: "Automatic trip resumed",
      detail: "Resumed by the driver."
    )
    NativeTripLiveActivityController.update(miles: shiftMiles, elapsed: Date().timeIntervalSince(shiftStartedAt ?? Date()), isDriving: true, vehicleLabel: liveShiftVehicle.label, force: true)
  }

  func endCurrentShift(reason: String = "Ended by the driver") {
    requestAutomaticEnd(reason: reason, evidence: NativeTripStopEvidenceSnapshot(), force: true)
  }

  /// Driving resumed before the stationary timer expired — the stop that was
  /// being timed becomes a logged pick-up/drop-off, and the same shift (same
  /// trip, same accumulated mileage) keeps going.
  private func performResumeFromStationary() {
    finalizePendingStop(resumedDriving: true)
    stationaryTimer?.invalidate()
    stationaryTimer = nil
    deadlines.stationary = nil
    cancelHomeDwellTimer()
    cancelVehicleDisconnectDwellTimer()
    ensureActiveLocationRecording(reason: "Driving resumed")
    persistShiftSnapshot()
    NativeTripLiveActivityController.update(miles: shiftMiles, elapsed: Date().timeIntervalSince(shiftStartedAt ?? Date()), isDriving: true, vehicleLabel: liveShiftVehicle.label, force: true)
  }

  /// The stationary timer expired (or tracking got turned off mid-shift) —
  /// the shift is over. Save it as a real trip and notify the driver.
  private func performConcludeShift(endedAt: Date, reason: String) {
    if let snapshot = recorder.forceEndpoint(owner: .automatic) {
      applyRecordingSnapshot(snapshot)
    }
    let endingMiles = shiftMiles
    let endingPointCount = shiftPoints.count
    let willSave = shiftMiles > 0.1 || shiftPoints.count > 2
    finalizePendingStop(departure: endedAt)
    saveShiftAsTrip(endedAt: endedAt, reason: reason)
    if !willSave {
      pendingShiftVisits = []
      syncPublishedVisits()
    }
    stopHighAccuracyLocationUpdates()
    stopSignificantLocationWakeMonitoring()
    endBackgroundLocationSession()
    setBackgroundTrackingEnabled(false)
    stationaryTimer?.invalidate()
    stationaryTimer = nil
    deadlines = NativeAutoTrackDeadlines()
    shiftPoints = []
    shiftMiles = 0
    shiftStartedAt = nil
    shiftStartNotified = false
    shiftLastLocation = nil
    shiftLastRoutePointLocation = nil
    shiftSawVehicleConnection = false
    shiftArmedForHomeArrival = false
    shiftStartTrigger = nil
    recorder.release(owner: .automatic)
    cancelHomeDwellTimer()
    cancelVehicleDisconnectDwellTimer()
    stationarySince = nil
    stationaryCoordinate = nil
    walkingDetectedDuringStop = false
    publishLiveShift()
    clearShiftSnapshot()
    NativeTripLiveActivityController.end()
    NativeAutoTrackDiagnostics.shared.record(
      kind: "shift.ended",
      title: willSave ? "Automatic trip saved" : "Automatic trip discarded",
      detail: "Reason: \(reason). Distance: \(String(format: "%.2f", endingMiles)) mi. Route points: \(endingPointCount)."
    )
    refresh()
  }

  private func startVehicleConnectionMonitoring() {
    guard vehicleConnectionObservers.isEmpty else { return }
    let center = NotificationCenter.default
    NativeVehicleConnectionMonitor.refreshFromCurrentRoute()
    lastObservedVehicleConnection = NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle
    vehicleConnectionObservers = [
      center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
        Task { @MainActor in self?.handleVehicleConnectionChanged(notification) }
      },
      center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in
          NativeVehicleConnectionMonitor.refreshFromCurrentRoute()
          self?.handleVehicleConnectionChanged()
        }
      },
      center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.refresh() }
      },
      center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.refresh() }
      },
      center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          if NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: self.shiftPhase) {
            self.ensureActiveLocationRecording(
              reason: "App entered background",
              recordsDiagnostic: false,
              forceRestart: false
            )
            self.persistShiftSnapshot()
          }
        }
      },
      center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in
          guard let self, self.shiftPhase != .idle else { return }
          self.persistShiftSnapshot()
          NativeAutoTrackDiagnostics.shared.record(
            kind: "lifecycle.memory-warning",
            title: "Memory pressure warning",
            detail: "The active tracking snapshot was flushed for recovery.",
            deduplicateWithin: 60
          )
        }
      },
    ]
  }

  private func handleVehicleConnectionChanged(_ notification: Notification? = nil) {
    let connected = notification.map(NativeVehicleConnectionMonitor.handleRouteChange)
      ?? NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle
    let connectionStateChanged = lastObservedVehicleConnection != connected
    lastObservedVehicleConnection = connected
    guard connectionStateChanged else { return }
    NativeAutoTrackDiagnostics.shared.record(
      kind: "vehicle.signal.\(connected ? "connected" : "disconnected")",
      title: connected ? "Vehicle signal connected" : "Vehicle signal disconnected",
      detail: connected ? "The system Car Audio route is available." : "No Car Audio route is available."
    )
    guard enhancedAutoTrackingEnabled else {
      if shiftPhase == .idle {
        disarmVehicleStartDetection(reason: "Enhanced tracking is off")
        configureLocationForIdleWakeIfNeeded()
      }
      return
    }
    if connected {
      cancelVehicleDisconnectDwellTimer()
      if shiftPhase == .idle {
        armVehicleStartDetectionIfNeeded()
      } else {
        shiftSawVehicleConnection = true
        publishLiveShift()
      }
    } else {
      if shiftPhase == .idle {
        disarmVehicleStartDetection(reason: "Vehicle signal disconnected")
        configureLocationForIdleWakeIfNeeded()
      } else {
        armVehicleDisconnectDwellIfNeeded()
      }
    }
  }

  private func armVehicleStartDetectionIfNeeded() {
    guard shiftPhase == .idle else { return }
    guard let settings = store?.settings,
          NativeAutoTrackPolicy.canStartTrip(
            settings: settings,
            authorizationStatus: locationAuthorizationStatus,
            accuracyAuthorization: locationAccuracyAuthorization,
            date: Date()
          ) else { return }
    guard enhancedAutoTrackingEnabled, NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle else { return }
    guard !manualTrackingOwnsLocation else { return }
    guard !vehicleStartArmed else { return }

    vehicleStartArmed = true
    vehicleArmOrigin = nil
    vehicleArmLastLocation = nil
    vehicleArmLocations = []
    idleWakeLocation = nil
    configureLocationForDriving()
    startSignificantLocationWakeMonitoring()
    beginBackgroundLocationSession()
    setBackgroundTrackingEnabled(true)
    startHighAccuracyLocationUpdates()
    NativeAutoTrackDiagnostics.shared.record(
      kind: "vehicle.armed",
      title: "Vehicle tracking armed",
      detail: "Precise GPS is buffering the route until automotive motion or confirmed displacement starts the trip."
    )
  }

  private func disarmVehicleStartDetection(reason: String) {
    guard vehicleStartArmed else { return }
    vehicleStartArmed = false
    vehicleArmOrigin = nil
    vehicleArmLastLocation = nil
    vehicleArmLocations = []
    stopHighAccuracyLocationUpdates()
    endBackgroundLocationSession()
    setBackgroundTrackingEnabled(false)
    NativeAutoTrackDiagnostics.shared.record(
      kind: "vehicle.disarmed",
      title: "Vehicle tracking disarmed",
      detail: reason
    )
  }

  // MARK: Continuous route recording (mirrors NativeTripSession's approach)

  private func handleSignificantLocationWake(_ locations: [CLLocation]) {
    catchUpOverdueTimers()
    if NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: shiftPhase) {
      ensureActiveLocationRecording(reason: "Significant-location wake")
      handleShiftLocationUpdates(locations)
    } else if shiftPhase == .idle {
      handleIdleWakeLocationUpdates(locations)
    }
  }

  private func handleLocationUpdates(_ locations: [CLLocation]) {
    catchUpOverdueTimers()
    if shiftPhase == .idle {
      if vehicleStartArmed {
        handleArmedVehicleLocationUpdates(locations)
      } else {
        handleIdleWakeLocationUpdates(locations)
      }
    } else {
      handleShiftLocationUpdates(locations)
    }
  }

  private func handleIdleWakeLocationUpdates(_ locations: [CLLocation]) {
    guard let settings = store?.settings,
          NativeAutoTrackPolicy.canStartTrip(
            settings: settings,
            authorizationStatus: locationAuthorizationStatus,
            accuracyAuthorization: locationAccuracyAuthorization,
            date: Date()
          ) else { return }
    guard !manualTrackingOwnsLocation else { return }

    for location in locations where shouldUseIdleWakeLocation(location) {
      if let idleWakeLocation, location.distance(from: idleWakeLocation) < idleWakeDistance { continue }
      idleWakeLocation = location

      if enhancedAutoTrackingEnabled, NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle {
        armVehicleStartDetectionIfNeeded()
        handleArmedVehicleLocationUpdates([location])
        return
      }

      if location.speed >= 6 {
        handleDrivingSignal(trigger: "Significant-location speed")
        return
      }

      beginShiftIfRecentAutomotiveActivity()
      return
    }
  }

  private func handleArmedVehicleLocationUpdates(_ locations: [CLLocation]) {
    guard let settings = store?.settings,
          NativeAutoTrackPolicy.canStartTrip(
            settings: settings,
            authorizationStatus: locationAuthorizationStatus,
            accuracyAuthorization: locationAccuracyAuthorization,
            date: Date()
          ),
          !manualTrackingOwnsLocation,
          enhancedAutoTrackingEnabled,
          NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle else {
      refresh()
      return
    }

    for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
      if let rejection = nativeTripLocationRejectionReason(location, since: vehicleArmLastLocation) {
        recordRejectedLocation(location, reason: rejection, context: "armed")
        continue
      }
      if vehicleArmOrigin == nil ||
          location.timestamp.timeIntervalSince(vehicleArmOrigin?.timestamp ?? location.timestamp) > vehicleArmBufferWindow {
        rebaseVehicleArmBuffer(at: location)
      } else {
        vehicleArmLastLocation = location
        vehicleArmLocations.append(location)
        if vehicleArmLocations.count > vehicleArmBufferLimit {
          vehicleArmLocations.removeFirst(vehicleArmLocations.count - vehicleArmBufferLimit)
        }
      }
      if NativeAutoTrackPolicy.shouldStartArmedVehicleTrip(origin: vehicleArmOrigin, current: location) {
        let initialLocations = NativeAutoTrackPolicy.armedTripInitialLocations(
          bufferedLocations: vehicleArmLocations
        )
        handleDrivingSignal(
          trigger: "Vehicle GPS displacement",
          evidence: NativeTripStartEvidence(
            automotiveMotion: false,
            speedMetersPerSecond: nil,
            displacementMeters: vehicleArmOrigin.map { location.distance(from: $0) } ?? 0,
            vehicleConnected: true,
            headingIsConsistent: location.course >= 0
          ),
          initialLocations: initialLocations
        )
        return
      }

      let displacement = vehicleArmOrigin.map { location.distance(from: $0) } ?? 0
      NativeAutoTrackDiagnostics.shared.record(
        kind: "vehicle.movement-check",
        title: "Vehicle movement check",
        detail: "Buffered \(vehicleArmLocations.count) fixes. Displacement: \(Int(displacement.rounded())) m. Accuracy: \(Int(location.horizontalAccuracy.rounded())) m.",
        deduplicateWithin: 15
      )
    }
  }

  private func rebaseVehicleArmBuffer(at location: CLLocation?) {
    vehicleArmOrigin = location
    vehicleArmLastLocation = location
    vehicleArmLocations = location.map { [$0] } ?? []
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
          self.handleDrivingSignal(trigger: "Recent Core Motion automotive activity")
        }
      }
    }
  }

  private func handleShiftLocationUpdates(_ locations: [CLLocation]) {
    guard shiftPhase == .driving || shiftPhase == .stationaryPending else { return }
    if enhancedAutoTrackingEnabled {
      shiftSawVehicleConnection = shiftSawVehicleConnection || NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle
    }
    let receivedAt = Date()
    let activeTripAge = shiftStartedAt.map { max(30, receivedAt.timeIntervalSince($0) + 30) } ?? 30
    for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
      if let rejection = nativeTripLocationRejectionReason(
        location,
        since: shiftLastLocation,
        now: receivedAt,
        maximumAge: activeTripAge,
        earliestTimestamp: shiftStartedAt
      ) {
        recordRejectedLocation(location, reason: rejection, context: "recording")
        continue
      }
    }
    let routePointCountBeforeBatch = shiftPoints.count
    guard let update = recorder.ingest(
      locations,
      owner: .automatic,
      now: receivedAt,
      vehicleConnectionActive: enhancedAutoTrackingEnabled
        ? NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle
        : nil
    ) else { return }
    applyRecordingSnapshot(update.snapshot)
    NativeAutoTrackDiagnostics.shared.record(
      kind: "gps.sampling",
      title: "GPS sampling update",
      detail: "Received \(locations.count) fixes. Accepted \(update.acceptedLocations.count). Added \(shiftPoints.count - routePointCountBeforeBatch) route points. Total route points: \(shiftPoints.count).",
      deduplicateWithin: 30
    )
    for location in update.acceptedLocations {
      if shiftPhase == .stationaryPending, shouldResumeFromStationaryLocation(location) {
        apply(.drivingDetected, trigger: "GPS movement resumed")
      }
      if shiftPhase == .stationaryPending { stationaryCoordinate = location.coordinate }
      trackHomeArrival(at: location)
      armVehicleDisconnectDwellIfNeeded()
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
    persistShiftSnapshot(force: false)
    NativeTripLiveActivityController.update(
      miles: shiftMiles, elapsed: Date().timeIntervalSince(shiftStartedAt ?? Date()),
      isDriving: shiftPhase == .driving, vehicleLabel: liveShiftVehicle.label
    )
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

  private func applyRecordingSnapshot(_ snapshot: NativeTripRecordingSnapshot) {
    shiftPoints = snapshot.points
    shiftMiles = snapshot.miles
    shiftLastLocation = snapshot.lastLocation
    shiftLastRoutePointLocation = snapshot.lastRoutePointLocation
  }

  private func configureLocationForDriving() {
    configureContinuousLocationUpdates(for: .driving)
  }

  private func configureLocationForStationaryWaiting() {
    configureContinuousLocationUpdates(for: .stationaryPending)
  }

  private func configureContinuousLocationUpdates(for phase: NativeAutoShiftPhase) {
    precondition(NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: phase))
    manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    manager.distanceFilter = drivingDistanceFilter
    manager.pausesLocationUpdatesAutomatically = false
  }

  private func configureLocationForIdleWakeIfNeeded() {
    guard shiftPhase == .idle, !vehicleStartArmed else { return }
    guard locationAuthorizationStatus == .authorizedAlways else { return }
    stopHighAccuracyLocationUpdates()
    endBackgroundLocationSession()
    setBackgroundTrackingEnabled(false)
    startSignificantLocationWakeMonitoring()
  }

  private func configureIdleLocationMonitoring() {
    guard shiftPhase == .idle else { return }
    if manualTrackingOwnsLocation {
      disarmVehicleStartDetection(reason: "Manual trip owns location tracking")
      stopHighAccuracyLocationUpdates()
      stopSignificantLocationWakeMonitoring()
      endBackgroundLocationSession()
      setBackgroundTrackingEnabled(false)
      idleWakeLocation = nil
      return
    }
    if enhancedAutoTrackingEnabled,
       NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle {
      armVehicleStartDetectionIfNeeded()
    } else {
      disarmVehicleStartDetection(reason: "No connected vehicle signal")
      configureLocationForIdleWakeIfNeeded()
    }
  }

  private func ensureActiveLocationRecording(
    reason: String,
    recordsDiagnostic: Bool = true,
    forceRestart: Bool = true
  ) {
    guard NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: shiftPhase) else { return }
    configureContinuousLocationUpdates(for: shiftPhase)
    startSignificantLocationWakeMonitoring()
    beginBackgroundLocationSession()
    setBackgroundTrackingEnabled(true)
    startHighAccuracyLocationUpdates(forceRestart: forceRestart)

    if manager.accuracyAuthorization == .reducedAccuracy {
      NativeAutoTrackDiagnostics.shared.record(
        kind: "gps.reduced-accuracy",
        title: "Precise Location is off",
        detail: "iOS is providing reduced-accuracy fixes; enable Precise Location for reliable route tracking.",
        deduplicateWithin: 5 * 60
      )
    }
    if recordsDiagnostic {
      NativeAutoTrackDiagnostics.shared.record(
        kind: "gps.rearmed",
        title: "Background GPS armed",
        detail: "Reason: \(reason). Navigation accuracy and the relaunch wake service are active.",
        deduplicateWithin: 60
      )
    }
  }

  private func startHighAccuracyLocationUpdates(forceRestart: Bool = false) {
    guard forceRestart || !highAccuracyLocationRunning else { return }
    manager.startUpdatingLocation()
    highAccuracyLocationRunning = true
  }

  private func stopHighAccuracyLocationUpdates() {
    guard highAccuracyLocationRunning else { return }
    manager.stopUpdatingLocation()
    highAccuracyLocationRunning = false
  }

  private func startSignificantLocationWakeMonitoring() {
    guard manager.authorizationStatus == .authorizedAlways else { return }
    guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
    guard !significantLocationWakeMonitoring else { return }
    wakeManager.startMonitoringSignificantLocationChanges()
    significantLocationWakeMonitoring = true
  }

  private func stopSignificantLocationWakeMonitoring() {
    guard significantLocationWakeMonitoring else { return }
    wakeManager.stopMonitoringSignificantLocationChanges()
    significantLocationWakeMonitoring = false
  }

  private func beginBackgroundLocationSession() {
    guard supportsBackgroundLocation, backgroundLocationSession == nil else { return }
    if #available(iOS 17.0, *) {
      backgroundLocationSession = CLBackgroundActivitySession()
    }
  }

  private func endBackgroundLocationSession() {
    if #available(iOS 17.0, *),
       let session = backgroundLocationSession as? CLBackgroundActivitySession {
      session.invalidate()
    }
    backgroundLocationSession = nil
  }

  private func setBackgroundTrackingEnabled(_ enabled: Bool) {
    guard supportsBackgroundLocation else { return }
    guard manager.allowsBackgroundLocationUpdates != enabled else { return }
    manager.allowsBackgroundLocationUpdates = enabled
    manager.showsBackgroundLocationIndicator = enabled
  }

  private func shouldResumeFromStationaryLocation(_ location: CLLocation) -> Bool {
    guard let stationaryCoordinate else { return false }
    let stationaryLocation = CLLocation(latitude: stationaryCoordinate.latitude, longitude: stationaryCoordinate.longitude)
    return location.distance(from: stationaryLocation) >= stationaryResumeDistance
  }

  /// A vehicle disconnect alone isn't proof the shift is over — stepping out
  /// briefly, a Car Audio hiccup, or a quick errand all disconnect too. Arms
  /// a dwell timer on the first disconnect instead of concluding right away;
  /// reconnecting before it fires cancels it (see handleVehicleConnectionChanged).
  private func armVehicleDisconnectDwellIfNeeded() {
    guard enhancedAutoTrackingEnabled else { return }
    guard NativeAutoTrackPolicy.shouldArmVehicleDisconnectEnd(during: shiftPhase) else {
      cancelVehicleDisconnectDwellTimer()
      return
    }
    guard shiftSawVehicleConnection, !NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle else {
      cancelVehicleDisconnectDwellTimer()
      return
    }
    guard vehicleDisconnectDwellTimer == nil else { return }
    let deadline = deadlines.vehicleDisconnect ?? Date().addingTimeInterval(vehicleDisconnectDwellSeconds)
    deadlines.vehicleDisconnect = deadline
    vehicleDisconnectDwellTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
      Task { @MainActor in self?.catchUpOverdueTimers() }
    }
    vehicleDisconnectDwellTimer?.tolerance = 15
    persistShiftSnapshot()
    NativeAutoTrackDiagnostics.shared.record(
      kind: "shift.disconnect-timer",
      title: "Vehicle disconnect timer armed",
      detail: "The automatic trip will end after 5 minutes if the vehicle remains disconnected."
    )
  }

  /// The dwell timer fired — re-checks the connection is still actually
  /// disconnected (not just trusting the ping that started the timer) before
  /// concluding the shift.
  private func confirmVehicleStillDisconnected(endedAt: Date = Date()) {
    vehicleDisconnectDwellTimer = nil
    deadlines.vehicleDisconnect = nil
    persistShiftSnapshot()
    guard enhancedAutoTrackingEnabled else { return }
    guard NativeAutoTrackPolicy.shouldArmVehicleDisconnectEnd(during: shiftPhase) else { return }
    guard shiftSawVehicleConnection, !NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle else { return }
    requestAutomaticEnd(
      reason: "Vehicle remained disconnected",
      evidence: NativeTripStopEvidenceSnapshot(
        stationaryDuration: vehicleDisconnectDwellSeconds,
        stationaryMotion: shiftPhase == .stationaryPending,
        vehicleDisconnected: true,
        walkingDetected: walkingDetectedDuringStop
      ),
      endedAt: endedAt
    )
  }

  private func cancelVehicleDisconnectDwellTimer() {
    guard vehicleDisconnectDwellTimer != nil || deadlines.vehicleDisconnect != nil else { return }
    vehicleDisconnectDwellTimer?.invalidate()
    vehicleDisconnectDwellTimer = nil
    deadlines.vehicleDisconnect = nil
    persistShiftSnapshot()
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
      NativeAutoTrackDiagnostics.shared.record(
        kind: "shift.home-timer",
        title: "Home arrival timer armed",
        detail: "The automatic trip will end after the home-arrival dwell is confirmed."
      )
    }
  }

  private func scheduleHomeDwellTimer() {
    homeDwellTimer?.invalidate()
    let deadline = deadlines.homeArrival ?? Date().addingTimeInterval(homeArrivalDwellSeconds)
    deadlines.homeArrival = deadline
    homeDwellTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
      Task { @MainActor in self?.catchUpOverdueTimers() }
    }
    homeDwellTimer?.tolerance = 30
    persistShiftSnapshot()
  }

  /// The dwell timer fired — re-checks against the most recent known
  /// location rather than trusting the ping that started the timer, so a
  /// single stale/inaccurate fix can't lock in a false "still home".
  private func confirmHomeArrivalIfStillNearby(endedAt: Date = Date()) {
    homeDwellTimer = nil
    deadlines.homeArrival = nil
    persistShiftSnapshot()
    guard let shiftLastLocation else { return }
    let homes = selectedHomeLocations
    let nearestHomeDistance = homes.map { shiftLastLocation.distance(from: $0) }.min() ?? .greatestFiniteMagnitude
    guard nearestHomeDistance <= homeArrivalRadius else { return }
    guard abs(shiftLastLocation.timestamp.timeIntervalSinceNow) <= homeArrivalStalenessThreshold else {
      // Can't confirm against a fix this old — check again shortly instead
      // of locking in a possibly-false "still home" read.
      let retryDeadline = Date().addingTimeInterval(homeArrivalRecheckDelay)
      deadlines.homeArrival = retryDeadline
      homeDwellTimer = Timer.scheduledTimer(withTimeInterval: homeArrivalRecheckDelay, repeats: false) { [weak self] _ in
        Task { @MainActor in self?.catchUpOverdueTimers() }
      }
      homeDwellTimer?.tolerance = 15
      persistShiftSnapshot()
      return
    }
    requestAutomaticEnd(
      reason: "Home arrival confirmed",
      evidence: NativeTripStopEvidenceSnapshot(
        stationaryDuration: homeArrivalDwellSeconds,
        stationaryMotion: shiftPhase == .stationaryPending,
        arrivedHome: true,
        walkingDetected: walkingDetectedDuringStop
      ),
      endedAt: endedAt
    )
  }

  private func cancelHomeDwellTimer() {
    guard homeDwellTimer != nil || deadlines.homeArrival != nil else { return }
    homeDwellTimer?.invalidate()
    homeDwellTimer = nil
    deadlines.homeArrival = nil
    persistShiftSnapshot()
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

  private var manualTrackingOwnsLocation: Bool {
    manualTripStartPending || NativeTripSession.shared.phase != .setup
  }

  private func monitoringInactiveDetail(settings: NativeSettings) -> String {
    switch NativeAutoTrackPolicy.readiness(
      settings: settings,
      authorizationStatus: locationAuthorizationStatus,
      accuracyAuthorization: locationAccuracyAuthorization,
      date: Date()
    ) {
    case .disabled:
      return "Automatic tracking is turned off."
    case .needsAlwaysLocation:
      return "Location authorization: \(authorizationLabel(locationAuthorizationStatus))."
    case .needsPreciseLocation:
      return "Precise Location is required to start automatic trips."
    case .waitingForWorkingDay:
      return "Waiting for a selected working day; low-power location monitoring remains active."
    case .ready:
      return "Automatic tracking is ready."
    }
  }

  private func authorizationLabel(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "not determined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorizedAlways: return "Always"
    case .authorizedWhenInUse: return "While Using"
    @unknown default: return "unknown"
    }
  }

  private func motionConfidenceLabel(_ confidence: CMMotionActivityConfidence) -> String {
    switch confidence {
    case .low: return "low"
    case .medium: return "medium"
    case .high: return "high"
    @unknown default: return "unknown"
    }
  }

  private func diagnosticSpeed(_ speed: CLLocationSpeed) -> String {
    guard speed >= 0 else { return "unavailable" }
    return "\(String(format: "%.1f", speed)) m/s"
  }

  private func recordRejectedLocation(
    _ location: CLLocation,
    reason: NativeTripLocationRejectionReason,
    context: String
  ) {
    NativeAutoTrackDiagnostics.shared.record(
      kind: "gps.rejected.\(context).\(reason.rawValue)",
      title: "GPS fix rejected",
      detail: "Context: \(context). Reason: \(reason.diagnosticLabel). Accuracy: \(Int(location.horizontalAccuracy.rounded())) m. Speed: \(diagnosticSpeed(location.speed)). Age: \(Int(abs(location.timestamp.timeIntervalSinceNow).rounded())) s.",
      deduplicateWithin: 30
    )
  }

  private var supportsBackgroundLocation: Bool {
    let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    return backgroundModes.contains("location")
  }

  // MARK: Stop classification + shift finalization

  /// Turns the stop currently being timed into a logged visit — reusing the
  /// same dwell + nearby-food-venue heuristic as before, just fed by the
  /// motion-driven timer instead of a CLVisit callback.
  private func finalizePendingStop(departure: Date = Date(), resumedDriving: Bool = false) {
    guard let stationarySince, let coordinate = stationaryCoordinate else { return }
    guard shouldRecordPendingStop(arrival: stationarySince, departure: departure) else {
      self.stationarySince = nil
      self.stationaryCoordinate = nil
      walkingDetectedDuringStop = false
      return
    }
    var visit = NativeVisit(latitude: coordinate.latitude, longitude: coordinate.longitude,
                            arrival: stationarySince, departure: departure)
    let calibration = store?.settings.autoTrackCalibration ?? NativeAutoTrackCalibration()
    let disconnected = shiftSawVehicleConnection && !NativeVehicleConnectionMonitor.isLikelyConnectedToVehicle
    visit.vehicleDisconnectConfirmed = disconnected
    visit.confidence = disconnected ? 0.95 : min(0.9, 0.55 + visit.dwell / (20 * 60))
    visit.evidence = disconnected ? [.stationaryMotion, .vehicleDisconnect] : [.stationaryMotion]
    if resumedDriving { visit.evidence?.append(.resumedDriving) }
    if walkingDetectedDuringStop {
      visit.evidence?.append(.walkingAfterStop)
      visit.confidence = max(visit.confidence ?? 0, 0.9)
    }
    visit.kind = .other
    pendingShiftVisits.append(visit)
    syncPublishedVisits()
    persistShiftSnapshot()
    classifyWithMapKit(visit.id, coordinate: coordinate, calibration: calibration)
    runBackgroundExploration(for: visit)
    self.stationarySince = nil
    self.stationaryCoordinate = nil
    walkingDetectedDuringStop = false
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

  private func saveShiftAsTrip(endedAt: Date = Date(), reason: String) {
    guard let store, let shiftStartedAt else { return }
    // Skip near-zero noise (a driving reading that immediately went
    // stationary again without covering real distance).
    guard shiftMiles > 0.1 || shiftPoints.count > 2 else { return }
    let vehicle = store.settings.defaultVehicle
    var trip = NativeTrip(
      source: .automatic,
      vehicle: vehicle,
      miles: shiftMiles,
      deduction: store.calcDeduction(miles: shiftMiles, vehicle: vehicle, date: shiftStartedAt),
      startedAt: shiftStartedAt,
      endedAt: endedAt,
      points: shiftPoints
    )
    trip.analysis = NativeTripAnalysisProjector.build(
      for: trip,
      source: .automatic,
      recordedVisits: pendingShiftVisits,
      startTrigger: shiftStartTrigger,
      endReason: reason,
      usedEnhancedTracking: shiftSawVehicleConnection
    )
    pendingShiftVisits = []
    store.addTrip(trip)
    lastAutoShiftID = trip.id
    sendShiftLoggedNotification(trip)
    // Push the logging reminder off today if it was about to fire today —
    // don't wait for the app to be reopened to notice a shift just logged.
    NativeLoggingReminder.refresh(store: store)
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
    guard let store, store.settings.insightsEnabled else { return }
    let today = Calendar.current.startOfDay(for: visit.arrival)
    let dayIncome = store.records
      .filter { $0.isInsightRecommendationIncome && Calendar.current.isDate($0.date, inSameDayAs: today) }
      .reduce(0.0) { $0 + ($1.amount ?? 0) }
    NativeExploreCandidateStore.shared.recordVisit(visit.coordinate, dayIncome: dayIncome)

    let input = NativeInsightInput(visits: visits, store: store)
    Task {
      let zones = await NativeInsightsProjector.shared.project(input).shift.zones.map(\.coordinate)
      guard store.settings.insightsEnabled else { return }
      NativeAreaSuggester.refresh(near: visit.coordinate, knownZones: zones)
    }
  }

  /// Use Apple Maps as an evidence and naming layer. A nearby food venue makes
  /// this stop a stronger possible delivery origin, but does not persist a
  /// pickup/drop-off label as ground truth.
  ///
  /// Deliberately excludes the generic .store category here — a real-day
  /// simulation (10 pickup/drop-off cycles, real MapKit POIs) showed it's
  /// too broad for a hard single-stop classification: 6 of 10 drop-off
  /// addresses landed near an unrelated .store-tagged business (a beauty
  /// studio, a pet shop, a sports-rental shop) purely by proximity, which
  /// flipped them to "pickup" and broke the pickup→dropoff pairing that
  /// counts deliveries — Insights saw 4 deliveries out of 10 real ones.
  /// .store stays in the *zone-density* signal below, where being wrong
  /// occasionally just softens one input to an aggregate score instead of
  /// silently discarding 60% of a shift.
  private func classifyWithMapKit(_ id: UUID, coordinate: CLLocationCoordinate2D, calibration: NativeAutoTrackCalibration) {
    let pickupCategories: Set<MKPointOfInterestCategory> = [.restaurant, .cafe, .bakery, .foodMarket, .brewery, .nightlife, .pharmacy]
    let namingRadius: CLLocationDistance = 110
    let namingCategories = pickupCategories.union([.store, .parking, .publicTransport])
    let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: max(calibration.foodPoiRadiusMeters, namingRadius))
    request.pointOfInterestFilter = MKPointOfInterestFilter(including: Array(namingCategories))
    let stopLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

    func distance(_ item: MKMapItem) -> CLLocationDistance {
      item.placemark.location?.distance(from: stopLocation) ?? .greatestFiniteMagnitude
    }

    MKLocalSearch(request: request).start { [weak self] response, _ in
      guard let self else { return }
      let items = response?.mapItems ?? []
      let nearestPickupPlace = items
        .filter { ($0.pointOfInterestCategory.map(pickupCategories.contains) ?? false) && distance($0) <= calibration.foodPoiRadiusMeters }
        .min { distance($0) < distance($1) }
      let nearestNamed = items
        .filter { ($0.name ?? "").isEmpty == false && distance($0) <= namingRadius }
        .min { distance($0) < distance($1) }

      Task { @MainActor in
        self.updateVisit(id) { visit in
          if let place = nearestPickupPlace {
            visit.placeName = place.name
            var evidence = visit.evidence ?? []
            if !evidence.contains(.nearbyPointOfInterest) {
              evidence.append(.nearbyPointOfInterest)
            }
            visit.evidence = evidence
            visit.confidence = max(visit.confidence ?? 0, 0.9)
          }
          if visit.placeName == nil {
            visit.placeName = nearestNamed?.name
          }
        }
      }
    }
  }

  // MARK: Persistence

  private func loadLegacyVisits() {
    guard let data = UserDefaults.standard.data(forKey: legacyVisitsStorageKey),
          let saved = try? JSONDecoder().decode([NativeVisit].self, from: data) else { return }
    legacyVisits = saved
    visits = saved
  }

  private func syncPublishedVisits(from trips: [NativeTrip]? = nil) {
    let canonical = (trips ?? store?.trips ?? [])
      .flatMap(\.canonicalStops)
    visits = (canonical + pendingShiftVisits).sorted { $0.arrival < $1.arrival }
  }

  private func updateVisit(_ id: UUID, mutation: (inout NativeVisit) -> Void) {
    if let index = pendingShiftVisits.firstIndex(where: { $0.id == id }) {
      mutation(&pendingShiftVisits[index])
      syncPublishedVisits()
      persistShiftSnapshot()
      return
    }

    guard let store,
          let tripIndex = store.trips.firstIndex(where: { trip in
            trip.analysis?.stops.contains(where: { $0.id == id }) == true
          }),
          var analysis = store.trips[tripIndex].analysis,
          let stopIndex = analysis.stops.firstIndex(where: { $0.id == id }) else { return }
    mutation(&analysis.stops[stopIndex])
    var trip = store.trips[tripIndex]
    trip.analysis = analysis
    store.updateTrip(trip)
  }

  private func saveLegacyVisitsForDemo() {
    if let data = try? JSONEncoder().encode(legacyVisits) {
      UserDefaults.standard.set(data, forKey: legacyVisitsStorageKey)
    }
  }

  /// Called on every meaningful shift-state change so a killed/crashed app
  /// doesn't lose an in-progress shift's recorded miles — see
  /// restoreShiftIfNeeded, which reads this back on the next launch.
  private func persistShiftSnapshot(force: Bool = true) {
    guard shiftPhase != .idle, let shiftStartedAt else {
      clearShiftSnapshot()
      return
    }
    let now = Date()
    guard force || now.timeIntervalSince(lastShiftSnapshotQueuedAt) >= 10 else { return }
    lastShiftSnapshotQueuedAt = now
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
      stationaryLon: stationaryCoordinate?.longitude,
      deadlines: deadlines,
      pendingVisits: pendingShiftVisits,
      startTrigger: shiftStartTrigger,
      walkingDetectedDuringStop: walkingDetectedDuringStop
    )
    let url = Self.shiftSnapshotFileURL
    let legacyKey = shiftSnapshotKey
    shiftPersistenceQueue.async {
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
        UserDefaults.standard.removeObject(forKey: legacyKey)
      } catch {
        if let data = try? JSONEncoder().encode(snapshot) {
          UserDefaults.standard.set(data, forKey: legacyKey)
        }
      }
    }
  }

  private func clearShiftSnapshot() {
    UserDefaults.standard.removeObject(forKey: shiftSnapshotKey)
    lastShiftSnapshotQueuedAt = .distantPast
    let url = Self.shiftSnapshotFileURL
    shiftPersistenceQueue.sync {
      try? FileManager.default.removeItem(at: url)
    }
  }

  /// Reads back a shift snapshot left by a previous run that never reached
  /// concludeShift (crash, memory-pressure eviction, reboot) and re-arms
  /// location tracking for it, instead of silently starting fresh at .idle
  /// and losing whatever mileage was already recorded.
  private func restoreShiftIfNeeded() {
    let candidates = [
      try? Data(contentsOf: Self.shiftSnapshotFileURL),
      UserDefaults.standard.data(forKey: shiftSnapshotKey),
    ].compactMap { $0 }
    guard let snapshot = candidates.compactMap({
            try? JSONDecoder().decode(NativeAutoShiftSnapshot.self, from: $0)
          }).first,
          let phase = NativeAutoShiftPhase(rawValue: snapshot.phaseRaw),
          phase != .idle else { return }

    coordinator.restore(phase: phase)
    shiftPhase = coordinator.state.phase
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
      shiftLastRoutePointLocation = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
        altitude: 0,
        horizontalAccuracy: snapshot.lastLocationAccuracy ?? 10,
        verticalAccuracy: -1,
        timestamp: snapshot.points.last?.timestamp ?? snapshot.lastLocationTimestamp ?? snapshot.startedAt
      )
    }
    guard recorder.restore(
      owner: .automatic,
      startedAt: snapshot.startedAt,
      points: snapshot.points,
      miles: snapshot.miles,
      lastLocation: shiftLastLocation,
      lastRoutePointLocation: shiftLastRoutePointLocation
    ) else {
      coordinator.restore(phase: .idle)
      shiftPhase = .idle
      shiftStartedAt = nil
      shiftPoints = []
      shiftMiles = 0
      publishLiveShift()
      clearShiftSnapshot()
      return
    }
    stationarySince = snapshot.stationarySince
    if let lat = snapshot.stationaryLat, let lon = snapshot.stationaryLon {
      stationaryCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    deadlines = snapshot.deadlines ?? NativeAutoTrackDeadlines()
    pendingShiftVisits = snapshot.pendingVisits ?? []
    shiftStartTrigger = snapshot.startTrigger
    walkingDetectedDuringStop = snapshot.walkingDetectedDuringStop ?? false
    syncPublishedVisits()
    if phase == .stationaryPending, deadlines.stationary == nil {
      let timeout = store?.settings.autoTrackCalibration.stationaryTimeoutSeconds ?? 20 * 60
      deadlines.stationary = (stationarySince ?? snapshot.startedAt).addingTimeInterval(timeout)
    }

    publishLiveShift()
    NativeAutoTrackDiagnostics.shared.record(
      kind: "shift.restored",
      title: "Automatic trip restored",
      detail: "Recovered \(shiftPoints.count) route points and \(String(format: "%.2f", shiftMiles)) mi after relaunch."
    )
    guard let settings = store?.settings,
          NativeAutoTrackPolicy.canContinueActiveShift(
            settings: settings,
            authorizationStatus: manager.authorizationStatus,
            accuracyAuthorization: manager.accuracyAuthorization
          ) else {
      requestAutomaticEnd(
        reason: "Restored shift is no longer eligible",
        evidence: NativeTripStopEvidenceSnapshot(),
        endedAt: min(Date(), deadlines.stationary ?? shiftLastLocation?.timestamp ?? Date()),
        force: true
      )
      return
    }

    let lastActivityTimestamp = shiftLastLocation?.timestamp
      ?? shiftPoints.last?.timestamp
      ?? shiftStartedAt
    if phase == .driving,
       let lastActivityTimestamp,
       Date().timeIntervalSince(lastActivityTimestamp) > 30 * 60 {
      requestAutomaticEnd(
        reason: "Restored shift was stale",
        evidence: NativeTripStopEvidenceSnapshot(),
        endedAt: lastActivityTimestamp,
        force: true
      )
      return
    }

    // The previous run's Activity handle doesn't survive relaunch — start a
    // fresh one only after confirming this shift is still valid to resume.
    NativeTripLiveActivityController.start(
      source: "auto", vehicleLabel: liveShiftVehicle.label,
      miles: shiftMiles, elapsed: Date().timeIntervalSince(shiftStartedAt ?? Date()),
      isDriving: phase == .driving
    )

    switch phase {
    case .driving:
      ensureActiveLocationRecording(reason: "Restored active trip")
    case .stationaryPending:
      ensureActiveLocationRecording(reason: "Restored stationary wait")
      scheduleStationaryTimeout()
    case .paused, .idle:
      break
    }

    if deadlines.homeArrival != nil { scheduleHomeDwellTimer() }
    if deadlines.vehicleDisconnect != nil { armVehicleDisconnectDwellIfNeeded() }
    catchUpOverdueTimers()
  }

  /// Test/demo seeding used by the SEED_DEMO launch flag only.
  func seed(_ seeded: [NativeVisit]) {
    legacyVisits = seeded
    visits = seeded
    saveLegacyVisitsForDemo()
  }

  /// Removes a stop the driver flagged as wrong in the shift-review screen.
  func discardVisit(_ id: UUID) {
    if pendingShiftVisits.contains(where: { $0.id == id }) {
      pendingShiftVisits.removeAll { $0.id == id }
      syncPublishedVisits()
      persistShiftSnapshot()
      return
    }
    guard let store,
          let index = store.trips.firstIndex(where: {
            $0.analysis?.stops.contains(where: { $0.id == id }) == true
          }),
          var analysis = store.trips[index].analysis else { return }
    analysis.stops.removeAll { $0.id == id }
    var trip = store.trips[index]
    trip.analysis = analysis
    store.updateTrip(trip)
  }

  /// Flags one stop within a trip as personal (or reverts it) from the
  /// trip-detail screen. `stop` may be a real recorded visit already in
  /// `visits`, or a GPS-detected-but-never-persisted stop (NativeRouteStop-
  /// Detector can surface those without ever adding them here) — either
  /// way it needs to end up as a real, persisted stop so the flag sticks.
  func setVisitPersonal(_ stop: NativeVisit, isPersonal: Bool) {
    if pendingShiftVisits.contains(where: { $0.id == stop.id }) {
      updateVisit(stop.id) { $0.isPersonal = isPersonal }
      return
    }

    guard let store,
          let tripIndex = store.trips.firstIndex(where: { trip in
            trip.id == stop.tripID || trip.analysis?.stops.contains(where: { $0.id == stop.id }) == true
          }) else { return }

    var trip = store.trips[tripIndex]
    var analysis = trip.analysis ?? NativeTripAnalysis(
      routeFingerprint: NativeTripAnalysis.fingerprint(for: trip.points),
      source: trip.source ?? .automatic,
      stops: []
    )
    if let stopIndex = analysis.stops.firstIndex(where: { $0.id == stop.id }) {
      analysis.stops[stopIndex].isPersonal = isPersonal
    } else {
      var promoted = stop
      promoted.tripID = trip.id
      promoted.isPersonal = isPersonal
      analysis.stops.append(promoted)
      analysis.stops.sort { $0.arrival < $1.arrival }
    }
    trip.analysis = analysis
    store.updateTrip(trip)
    syncPublishedVisits()
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
