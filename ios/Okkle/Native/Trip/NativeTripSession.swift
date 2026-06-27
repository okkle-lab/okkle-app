import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
final class NativeTripSession: NSObject, ObservableObject, CLLocationManagerDelegate {
  enum Phase {
    case setup
    case live
    case paused
    case summary
  }

  @Published var phase: Phase = .setup
  @Published var vehicle: NativeVehicle = .car
  @Published var miles: Double = 0
  @Published var elapsed: TimeInterval = 0
  @Published var points: [RoutePoint] = []
  @Published var permissionMessage: String?

  private let manager = CLLocationManager()
  private var lastLocation: CLLocation?
  private var lastRoutePointLocation: CLLocation?
  private var startedAt: Date?
  private var timer: Timer?
  private var waitingForAuthorization = false
  private let routePointDistance: CLLocationDistance = 30
  private let timerInterval: TimeInterval = 5

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    manager.distanceFilter = 20
    manager.activityType = .automotiveNavigation
    manager.pausesLocationUpdatesAutomatically = true
  }

  func start(vehicle: NativeVehicle) {
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
      return
    }
    beginTracking()
  }

  private func beginTracking() {
    miles = 0
    elapsed = 0
    points = []
    lastLocation = nil
    lastRoutePointLocation = nil
    startedAt = Date()
    phase = .live
    NativeTripWidgetStore.markTripStarted(startedAt: startedAt ?? Date())
    setBackgroundTrackingEnabled(true)
    manager.startUpdatingLocation()
    startTimer()
    waitingForAuthorization = false
  }

  func pause() {
    guard phase == .live else { return }
    phase = .paused
    if let startedAt {
      NativeTripWidgetStore.markTripStarted(startedAt: startedAt)
    }
    manager.stopUpdatingLocation()
    setBackgroundTrackingEnabled(false)
    stopTimer()
  }

  func resume() {
    guard phase == .paused else { return }
    phase = .live
    if let startedAt {
      NativeTripWidgetStore.markTripStarted(startedAt: startedAt)
    }
    setBackgroundTrackingEnabled(true)
    manager.startUpdatingLocation()
    startTimer()
  }

  func continueTrackingAfterEndReview() {
    guard phase == .summary else { return }
    phase = .live
    if let startedAt {
      NativeTripWidgetStore.markTripStarted(startedAt: startedAt)
    }
    setBackgroundTrackingEnabled(true)
    manager.startUpdatingLocation()
    startTimer()
  }

  @MainActor
  func end(store: OkkleStore) -> NativeTrip? {
    guard let startedAt else { return nil }
    manager.stopUpdatingLocation()
    setBackgroundTrackingEnabled(false)
    stopTimer()
    phase = .summary
    NativeTripWidgetStore.markTripEnded()
    if let lastLocation {
      appendRoutePoint(for: lastLocation, force: true)
    }
    let trip = NativeTrip(
      vehicle: vehicle,
      miles: miles,
      deduction: store.calcDeduction(miles: miles, vehicle: vehicle, date: startedAt),
      startedAt: startedAt,
      endedAt: Date(),
      points: points
    )
    return trip
  }

  func discard() {
    manager.stopUpdatingLocation()
    setBackgroundTrackingEnabled(false)
    stopTimer()
    waitingForAuthorization = false
    miles = 0
    elapsed = 0
    points = []
    lastLocation = nil
    lastRoutePointLocation = nil
    startedAt = nil
    phase = .setup
    NativeTripWidgetStore.markTripEnded()
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
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard phase == .live else { return }
    var usedLocation = false
    for location in locations where shouldUse(location) {
      usedLocation = true
      if let lastLocation {
        let delta = location.distance(from: lastLocation) / 1_609.344
        if delta > 0.002 && delta < 1 {
          miles += delta
        }
      }
      lastLocation = location
      appendRoutePoint(for: location)
    }
    if usedLocation {
      permissionMessage = nil
    }
  }

  private func shouldUse(_ location: CLLocation) -> Bool {
    guard location.horizontalAccuracy >= 0 else { return false }
    guard abs(location.timestamp.timeIntervalSinceNow) < 30 else { return false }
    // iOS can provide approximate or still-settling GPS fixes above 60m accuracy.
    // Keep those points so the trip visibly starts instead of staying at 0.
    return location.horizontalAccuracy <= 250
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

  private func setBackgroundTrackingEnabled(_ enabled: Bool) {
    guard supportsBackgroundLocation else { return }
    manager.allowsBackgroundLocationUpdates = enabled
    manager.showsBackgroundLocationIndicator = enabled
  }

  private var supportsBackgroundLocation: Bool {
    let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    return backgroundModes.contains("location")
  }

  private func appendRoutePoint(for location: CLLocation, force: Bool = false) {
    if let lastRoutePointLocation {
      let distance = location.distance(from: lastRoutePointLocation)
      guard force ? distance > 1 : distance >= routePointDistance else { return }
    }
    points.append(RoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
    lastRoutePointLocation = location
  }
}
