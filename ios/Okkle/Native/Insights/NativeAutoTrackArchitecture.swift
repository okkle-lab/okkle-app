import AVFoundation
import CoreLocation
import Foundation

enum NativeTripSource: String, Codable, Equatable {
  case automatic
  case manual
  case imported
  case integration
  case unknown
}

typealias NativeTripTrackingSource = NativeTripSource

enum NativeRecordSource: String, Codable, Equatable {
  case manual
  case imported
  case tripEarnings
  case integration
  case unknown
}

enum NativeTripStopEvidence: String, Codable, Equatable, Hashable {
  case stationaryMotion
  case routeDwell
  case vehicleDisconnect
  case nearbyPointOfInterest
  case headingChange
  case speedDecay
  case walkingAfterStop
  case resumedDriving
  case repeatedJitter
  case roadIntersection
  case inferredEndpoint
}

/// One stop associated with a recorded trip. Stops are persisted inside the
/// trip analysis; `tripID` remains optional only so the old standalone visit
/// cache can be decoded and migrated.
struct NativeVisit: Codable, Identifiable, Equatable {
  var id = UUID()
  var tripID: UUID? = nil
  var latitude: Double
  var longitude: Double
  var arrival: Date
  var departure: Date
  var kindRaw: String = Kind.other.rawValue
  var placeName: String?
  var isEndpointGuess = false
  var vehicleDisconnectConfirmed: Bool? = nil
  var confidence: Double? = nil
  var evidence: [NativeTripStopEvidence]? = nil

  enum Kind: String, Codable, CaseIterable { case pickup, dropoff, other }

  var kind: Kind {
    get { Kind(rawValue: kindRaw) ?? .other }
    set { kindRaw = newValue.rawValue }
  }

  var dwell: TimeInterval { max(0, departure.timeIntervalSince(arrival)) }
  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
  var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// Versioned, disposable analysis owned by a trip. The route fingerprint makes
/// stale analysis detectable whenever route editing changes the underlying
/// points without coupling validity to unrelated edits such as feedback.
struct NativeTripAnalysis: Codable, Equatable {
  static let currentAlgorithmVersion = 2

  var algorithmVersion: Int = currentAlgorithmVersion
  var routeFingerprint: String
  var source: NativeTripSource
  var stops: [NativeVisit]
  var startTrigger: String? = nil
  var endReason: String? = nil
  var usedEnhancedTracking = false

  static func fingerprint(for points: [RoutePoint]) -> String {
    var hash: UInt64 = 0xcbf29ce484222325

    func mix(_ bytes: some Sequence<UInt8>) {
      for byte in bytes {
        hash ^= UInt64(byte)
        hash &*= 0x100000001b3
      }
    }

    for point in points {
      mix(point.id.uuidString.utf8)
      mix(String(point.latitude.bitPattern).utf8)
      mix(String(point.longitude.bitPattern).utf8)
      mix(String(point.timestamp?.timeIntervalSinceReferenceDate.bitPattern ?? 0).utf8)
      mix([point.breakBefore ? UInt8(1) : UInt8(0)])
    }
    return String(format: "%016llx", hash)
  }

  func isCurrent(for trip: NativeTrip) -> Bool {
    algorithmVersion == Self.currentAlgorithmVersion &&
      routeFingerprint == Self.fingerprint(for: trip.points)
  }
}

extension NativeTrip {
  var canonicalStops: [NativeVisit] {
    guard let analysis, analysis.isCurrent(for: self) else { return [] }
    return analysis.stops.map { stop in
      var linked = stop
      linked.tripID = id
      return linked
    }
  }
}

/// Whether a given weekday (0 = Sunday ... 6 = Saturday) is a working day.
func nativeIsWorkingDay(_ date: Date, settings: NativeSettings) -> Bool {
  let weekday = Calendar.current.component(.weekday, from: date) - 1
  return settings.workingDays.contains(weekday)
}

enum NativeAutoShiftPhase: String, Equatable {
  case idle
  case driving
  case stationaryPending
  case paused
}

enum NativeAutoTrackReadiness: Equatable {
  case disabled
  case needsAlwaysLocation
  case needsPreciseLocation
  case waitingForWorkingDay
  case ready
}

struct NativeAutoTrackCapability: Equatable {
  let settingsEnabled: Bool
  let authorizationStatus: CLAuthorizationStatus
  let accuracyAuthorization: CLAccuracyAuthorization

  var canMaintainWakeMonitoring: Bool {
    settingsEnabled && authorizationStatus == .authorizedAlways
  }

  var canRecordTrip: Bool {
    canMaintainWakeMonitoring && accuracyAuthorization == .fullAccuracy
  }
}

enum NativeAutoTrackPolicy {
  /// Once a trip starts, both driving and stationary-wait phases keep the
  /// standard high-fidelity location stream alive. A brief false stationary
  /// motion classification must never punch a hole in the recorded route.
  static func requiresContinuousLocationUpdates(during phase: NativeAutoShiftPhase) -> Bool {
    phase == .driving || phase == .stationaryPending
  }

  /// Losing Car Audio is supporting stop evidence, never a stop by itself.
  /// Only arm its dwell timer after motion has also put the trip into the
  /// stationary-wait phase; otherwise a flaky audio route can split a drive.
  static func shouldArmVehicleDisconnectEnd(during phase: NativeAutoShiftPhase) -> Bool {
    phase == .stationaryPending
  }

  static func capability(
    settings: NativeSettings,
    authorizationStatus: CLAuthorizationStatus,
    accuracyAuthorization: CLAccuracyAuthorization
  ) -> NativeAutoTrackCapability {
    NativeAutoTrackCapability(
      settingsEnabled: settings.autoTrackTrips,
      authorizationStatus: authorizationStatus,
      accuracyAuthorization: accuracyAuthorization
    )
  }

  static func readiness(
    settings: NativeSettings,
    authorizationStatus: CLAuthorizationStatus,
    accuracyAuthorization: CLAccuracyAuthorization,
    date: Date
  ) -> NativeAutoTrackReadiness {
    guard settings.autoTrackTrips else { return .disabled }
    guard authorizationStatus == .authorizedAlways else { return .needsAlwaysLocation }
    guard accuracyAuthorization == .fullAccuracy else { return .needsPreciseLocation }
    guard nativeIsWorkingDay(date, settings: settings) else { return .waitingForWorkingDay }
    return .ready
  }

  static func canMaintainWakeMonitoring(
    settings: NativeSettings,
    authorizationStatus: CLAuthorizationStatus
  ) -> Bool {
    settings.autoTrackTrips && authorizationStatus == .authorizedAlways
  }

  static func canStartTrip(
    settings: NativeSettings,
    authorizationStatus: CLAuthorizationStatus,
    accuracyAuthorization: CLAccuracyAuthorization,
    date: Date
  ) -> Bool {
    readiness(
      settings: settings,
      authorizationStatus: authorizationStatus,
      accuracyAuthorization: accuracyAuthorization,
      date: date
    ) == .ready
  }

  // Compatibility spelling retained while callers migrate to the clearer
  // distinction between wake monitoring and starting a trip.
  static func canStartMonitoring(
    settings: NativeSettings,
    authorizationStatus: CLAuthorizationStatus,
    accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy,
    date: Date
  ) -> Bool {
    canStartTrip(
      settings: settings,
      authorizationStatus: authorizationStatus,
      accuracyAuthorization: accuracyAuthorization,
      date: date
    )
  }

  static func canContinueActiveShift(
    settings: NativeSettings,
    authorizationStatus: CLAuthorizationStatus,
    accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
  ) -> Bool {
    capability(
      settings: settings,
      authorizationStatus: authorizationStatus,
      accuracyAuthorization: accuracyAuthorization
    ).canRecordTrip
  }

  static func canMonitor(
    settings: NativeSettings,
    authorizationStatus: CLAuthorizationStatus,
    accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy,
    date: Date
  ) -> Bool {
    canStartTrip(
      settings: settings,
      authorizationStatus: authorizationStatus,
      accuracyAuthorization: accuracyAuthorization,
      date: date
    )
  }

  static func isVehicleAudioPort(_ port: AVAudioSession.Port) -> Bool {
    port == .carAudio
  }

  static func vehicleConnectionState(
    currentPorts: [AVAudioSession.Port],
    previousPorts: [AVAudioSession.Port] = [],
    routeChangeReason: AVAudioSession.RouteChangeReason? = nil
  ) -> Bool {
    let previouslyUsedCarAudio = previousPorts.contains(where: isVehicleAudioPort)
    if routeChangeReason == .oldDeviceUnavailable, previouslyUsedCarAudio {
      return false
    }
    return currentPorts.contains(where: isVehicleAudioPort)
  }

  static func shouldAcceptTripLocation(_ location: CLLocation, since previous: CLLocation?) -> Bool {
    nativeShouldAcceptTripLocation(location, since: previous)
  }

  static func shouldStartArmedVehicleTrip(origin: CLLocation?, current: CLLocation) -> Bool {
    guard nativeShouldAcceptTripLocation(current, since: nil) else { return false }
    if current.speed >= 3 { return true }
    guard let origin else { return false }
    let elapsed = current.timestamp.timeIntervalSince(origin.timestamp)
    guard elapsed > 0, elapsed <= 30 else { return false }
    let distance = current.distance(from: origin)
    return distance >= 35 && distance / elapsed >= 1.5
  }

  static func armedTripInitialLocations(origin: CLLocation?, current: CLLocation) -> [CLLocation] {
    guard let origin, origin.timestamp < current.timestamp else { return [current] }
    return [origin, current]
  }
}

struct NativeTripStartEvidence: Equatable {
  var automotiveMotion = false
  var speedMetersPerSecond: Double? = nil
  var displacementMeters: Double = 0
  var vehicleConnected = false
  var headingIsConsistent = false
}

struct NativeTripStopEvidenceSnapshot: Equatable {
  var stationaryDuration: TimeInterval = 0
  var stationaryMotion = false
  var vehicleDisconnected = false
  var arrivedHome = false
  var walkingDetected = false
  var drivingResumed = false
}

struct NativeTrackingConfidenceDecision: Equatable {
  var score: Double
  var shouldTransition: Bool
}

/// One confidence policy for every sensor path. The separate enter/leave bars
/// provide hysteresis so noisy readings cannot rapidly start and end a trip.
enum NativeTrackingConfidenceEvaluator {
  private static let startThreshold = 0.70
  private static let stopThreshold = 0.70
  private static let resumeThreshold = 0.45

  static func startDecision(_ evidence: NativeTripStartEvidence) -> NativeTrackingConfidenceDecision {
    var score = 0.0
    if evidence.automotiveMotion { score += 0.70 }
    if let speed = evidence.speedMetersPerSecond {
      if speed >= 6 { score += 0.75 }
      else if speed >= 3 { score += 0.50 }
      else if speed >= 1.5 { score += 0.20 }
    }
    if evidence.displacementMeters >= 35 { score += 0.45 }
    if evidence.vehicleConnected { score += 0.25 }
    if evidence.headingIsConsistent { score += 0.10 }
    score = min(score, 1)
    return NativeTrackingConfidenceDecision(score: score, shouldTransition: score >= startThreshold)
  }

  static func stopDecision(
    _ evidence: NativeTripStopEvidenceSnapshot,
    stationaryTimeout: TimeInterval
  ) -> NativeTrackingConfidenceDecision {
    var score = min(0.55, evidence.stationaryDuration / max(stationaryTimeout, 1) * 0.55)
    if evidence.stationaryMotion { score += 0.25 }
    if evidence.vehicleDisconnected { score += 0.60 }
    if evidence.arrivedHome { score += 0.65 }
    if evidence.walkingDetected { score += 0.20 }
    if evidence.drivingResumed { score -= 0.70 }
    score = min(max(score, 0), 1)
    return NativeTrackingConfidenceDecision(score: score, shouldTransition: score >= stopThreshold)
  }

  static func shouldResumeDriving(_ evidence: NativeTripStartEvidence) -> Bool {
    startDecision(evidence).score >= resumeThreshold
  }
}

struct NativeAutoTrackState: Equatable {
  var phase: NativeAutoShiftPhase
}

enum NativeAutoTrackEvent: Equatable {
  case drivingDetected
  case stationaryDetected
  case pauseRequested
  case resumeRequested
  case endRequested(reason: String)
}

enum NativeAutoTrackEffect: Equatable {
  case none
  case beginShift
  case beginStationaryWait
  case resumeFromStationary
  case pauseShift
  case resumePausedShift
  case concludeShift(reason: String)
}

private struct NativeAutoTrackTransition: Equatable {
  var state: NativeAutoTrackState
  var effect: NativeAutoTrackEffect
}

/// The only authority for live automatic-trip phase transitions. Sensor and UI
/// callbacks produce events; the coordinator executes the returned effect.
private enum NativeAutoTrackReducer {
  static func reduce(state: NativeAutoTrackState, event: NativeAutoTrackEvent) -> NativeAutoTrackTransition {
    switch (state.phase, event) {
    case (.idle, .drivingDetected):
      return NativeAutoTrackTransition(state: NativeAutoTrackState(phase: .driving), effect: .beginShift)
    case (.stationaryPending, .drivingDetected):
      return NativeAutoTrackTransition(state: NativeAutoTrackState(phase: .driving), effect: .resumeFromStationary)
    case (.driving, .stationaryDetected):
      return NativeAutoTrackTransition(state: NativeAutoTrackState(phase: .stationaryPending), effect: .beginStationaryWait)
    case (.driving, .pauseRequested), (.stationaryPending, .pauseRequested):
      return NativeAutoTrackTransition(state: NativeAutoTrackState(phase: .paused), effect: .pauseShift)
    case (.paused, .resumeRequested):
      return NativeAutoTrackTransition(state: NativeAutoTrackState(phase: .driving), effect: .resumePausedShift)
    case (.idle, .endRequested):
      return NativeAutoTrackTransition(state: state, effect: .none)
    case (_, let .endRequested(reason)):
      return NativeAutoTrackTransition(state: NativeAutoTrackState(phase: .idle), effect: .concludeShift(reason: reason))
    default:
      return NativeAutoTrackTransition(state: state, effect: .none)
    }
  }
}

/// Owns the authoritative phase state while the engine remains an adapter for
/// Core Motion, Core Location, timers and user commands.
struct NativeAutoTrackCoordinator {
  private(set) var state: NativeAutoTrackState

  init(phase: NativeAutoShiftPhase = .idle) {
    state = NativeAutoTrackState(phase: phase)
  }

  mutating func restore(phase: NativeAutoShiftPhase) {
    state = NativeAutoTrackState(phase: phase)
  }

  mutating func handle(_ event: NativeAutoTrackEvent) -> NativeAutoTrackEffect {
    let transition = NativeAutoTrackReducer.reduce(state: state, event: event)
    state = transition.state
    return transition.effect
  }
}

enum NativeTripRecorderOwner: String, Equatable {
  case manual
  case automatic
}

struct NativeTripRecordingSnapshot {
  var owner: NativeTripRecorderOwner
  var startedAt: Date
  var points: [RoutePoint]
  var miles: Double
  var lastLocation: CLLocation?
  var lastRoutePointLocation: CLLocation?
}

struct NativeTripRecordingUpdate {
  var snapshot: NativeTripRecordingSnapshot
  var acceptedLocations: [CLLocation]
}

/// The sole route and mileage accumulator for both trip modes. Start/stop
/// policy remains with the manual session and automatic coordinator; this
/// recorder only owns accepted fixes and guarantees that the two modes cannot
/// record concurrently.
final class NativeTripRecorder {
  static let shared = NativeTripRecorder()

  private let lock = NSLock()
  private var state: NativeTripRecordingSnapshot?
  private let routePointDistance: CLLocationDistance = 10

  @discardableResult
  func begin(owner: NativeTripRecorderOwner, startedAt: Date = Date()) -> Bool {
    withLock {
      guard state == nil else { return false }
      state = NativeTripRecordingSnapshot(
        owner: owner,
        startedAt: startedAt,
        points: [],
        miles: 0,
        lastLocation: nil,
        lastRoutePointLocation: nil
      )
      return true
    }
  }

  @discardableResult
  func restore(
    owner: NativeTripRecorderOwner,
    startedAt: Date,
    points: [RoutePoint],
    miles: Double,
    lastLocation: CLLocation?,
    lastRoutePointLocation: CLLocation?
  ) -> Bool {
    withLock {
      guard state == nil || state?.owner == owner else { return false }
      state = NativeTripRecordingSnapshot(
        owner: owner,
        startedAt: startedAt,
        points: points,
        miles: miles,
        lastLocation: lastLocation,
        lastRoutePointLocation: lastRoutePointLocation
      )
      return true
    }
  }

  func ingest(
    _ locations: [CLLocation],
    owner: NativeTripRecorderOwner,
    now: Date = Date(),
    vehicleConnectionActive: Bool? = nil
  ) -> NativeTripRecordingUpdate? {
    withLock {
      guard var state, state.owner == owner else { return nil }
      let maximumAge = max(30, now.timeIntervalSince(state.startedAt) + 30)
      var accepted: [CLLocation] = []
      for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
        guard nativeTripLocationRejectionReason(
          location,
          since: state.lastLocation,
          now: now,
          maximumAge: maximumAge,
          earliestTimestamp: state.startedAt
        ) == nil else { continue }

        if let previous = state.lastLocation {
          let delta = (nativeTripMovementDistance(from: previous, to: location) ?? 0) / 1_609.344
          if delta > 0.002, delta < 1 { state.miles += delta }
        }
        state.lastLocation = location
        appendRoutePoint(
          location,
          vehicleConnectionActive: vehicleConnectionActive,
          force: false,
          state: &state
        )
        accepted.append(location)
      }
      self.state = state
      return NativeTripRecordingUpdate(snapshot: state, acceptedLocations: accepted)
    }
  }

  func forceEndpoint(owner: NativeTripRecorderOwner) -> NativeTripRecordingSnapshot? {
    withLock {
      guard var state, state.owner == owner else { return nil }
      if let last = state.lastLocation {
        appendRoutePoint(last, vehicleConnectionActive: nil, force: true, state: &state)
      }
      self.state = state
      return state
    }
  }

  func snapshot(owner: NativeTripRecorderOwner) -> NativeTripRecordingSnapshot? {
    withLock { state?.owner == owner ? state : nil }
  }

  func release(owner: NativeTripRecorderOwner) {
    withLock {
      guard state?.owner == owner else { return }
      state = nil
    }
  }

  private func appendRoutePoint(
    _ location: CLLocation,
    vehicleConnectionActive: Bool?,
    force: Bool,
    state: inout NativeTripRecordingSnapshot
  ) {
    guard nativeIsPlausibleRoutePoint(location, since: state.lastRoutePointLocation) else { return }
    if let previous = state.lastRoutePointLocation {
      let distance = location.distance(from: previous)
      guard force ? distance > 1 : distance >= routePointDistance else { return }
    }
    state.points.append(RoutePoint(
      location: location,
      vehicleConnectionActive: vehicleConnectionActive
    ))
    state.lastRoutePointLocation = location
  }

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
