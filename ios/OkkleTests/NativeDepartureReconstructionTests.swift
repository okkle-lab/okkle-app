import CoreLocation
import XCTest
@testable import Okkle

final class NativeDepartureReconstructionTests: XCTestCase {
  private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func sample(
    _ minutesBefore: Double,
    automotive: Bool = false,
    onFoot: Bool = false,
    stationary: Bool = false
  ) -> NativeDepartureMotionSample {
    NativeDepartureMotionSample(
      startDate: now.addingTimeInterval(-minutesBefore * 60),
      automotive: automotive,
      onFoot: onFoot,
      stationary: stationary
    )
  }

  private func location(_ latitude: Double, _ longitude: Double, minutesBefore: Double, accuracy: Double = 10) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      altitude: 0,
      horizontalAccuracy: accuracy,
      verticalAccuracy: -1,
      timestamp: now.addingTimeInterval(-minutesBefore * 60)
    )
  }

  // MARK: Motion history

  func testDepartureIsStartOfAutomotiveRunAfterWalkingToCar() {
    let samples = [
      sample(20, stationary: true),
      sample(8, onFoot: true),
      sample(6, automotive: true),
      sample(3, automotive: true),
    ]
    XCTAssertEqual(
      NativeDepartureReconstruction.motionDepartureDate(samples: samples, before: now),
      now.addingTimeInterval(-6 * 60)
    )
  }

  func testShortStopDuringDriveDoesNotResetDeparture() {
    let samples = [
      sample(10, automotive: true),
      sample(7, stationary: true), // 1-minute red light
      sample(6, automotive: true),
    ]
    XCTAssertEqual(
      NativeDepartureReconstruction.motionDepartureDate(samples: samples, before: now),
      now.addingTimeInterval(-10 * 60)
    )
  }

  func testLongStationarySpellSeparatesEarlierDriving() {
    let samples = [
      sample(25, automotive: true), // an earlier, different drive
      sample(20, stationary: true), // parked for 15 minutes
      sample(5, automotive: true),
    ]
    XCTAssertEqual(
      NativeDepartureReconstruction.motionDepartureDate(samples: samples, before: now),
      now.addingTimeInterval(-5 * 60)
    )
  }

  func testNoAutomotiveHistoryGivesNoMotionDeparture() {
    let samples = [sample(10, stationary: true), sample(4, onFoot: true)]
    XCTAssertNil(NativeDepartureReconstruction.motionDepartureDate(samples: samples, before: now))
  }

  // MARK: Departure bounds

  func testUsesMotionDepartureWhenPhysicallyPlausible() {
    let anchor = location(51.5000, -0.1000, minutesBefore: 120)
    let firstFix = location(51.5090, -0.1000, minutesBefore: 0) // ~1 km away
    let motion = now.addingTimeInterval(-4 * 60)
    XCTAssertEqual(
      NativeDepartureReconstruction.departureDate(anchor: anchor, firstFix: firstFix, motionDeparture: motion),
      motion
    )
  }

  func testFallsBackToDistanceEstimateWithoutMotionHistory() {
    let anchor = location(51.5000, -0.1000, minutesBefore: 120)
    let firstFix = location(51.5090, -0.1000, minutesBefore: 0)
    let gap = anchor.distance(from: firstFix)
    let departure = NativeDepartureReconstruction.departureDate(anchor: anchor, firstFix: firstFix, motionDeparture: nil)
    XCTAssertEqual(
      departure?.timeIntervalSinceReferenceDate ?? 0,
      now.addingTimeInterval(-gap / NativeDepartureReconstruction.fallbackSpeedMetersPerSecond).timeIntervalSinceReferenceDate,
      accuracy: 0.001
    )
  }

  func testNeverDepartsBeforeArrivingAtAnchor() {
    let anchor = location(51.5000, -0.1000, minutesBefore: 5)
    let firstFix = location(51.5090, -0.1000, minutesBefore: 0)
    let departure = NativeDepartureReconstruction.departureDate(
      anchor: anchor, firstFix: firstFix, motionDeparture: now.addingTimeInterval(-20 * 60)
    )
    XCTAssertEqual(departure, anchor.timestamp)
  }

  func testRejectsImpreciseTooCloseOrTooFarAnchors() {
    let firstFix = location(51.5090, -0.1000, minutesBefore: 0)
    let imprecise = location(51.5000, -0.1000, minutesBefore: 60, accuracy: 500)
    let tooClose = location(51.5085, -0.1000, minutesBefore: 60)
    let tooFar = location(51.7000, -0.1000, minutesBefore: 60)
    for anchor in [imprecise, tooClose, tooFar] {
      XCTAssertNil(NativeDepartureReconstruction.departureDate(anchor: anchor, firstFix: firstFix, motionDeparture: nil))
    }
  }

  func testRejectsTimelineFasterThanPhysicallyPossible() {
    // Arrived at the anchor 10 seconds ago yet the first fix is ~10 km away.
    let anchor = location(51.5000, -0.1000, minutesBefore: 10.0 / 60)
    let firstFix = location(51.5900, -0.1000, minutesBefore: 0)
    XCTAssertNil(NativeDepartureReconstruction.departureDate(anchor: anchor, firstFix: firstFix, motionDeparture: nil))
  }

  func testRoadDistancePlausibility() {
    XCTAssertTrue(NativeDepartureReconstruction.isPlausibleRoadDistance(1_300, straightLineMeters: 1_000))
    XCTAssertFalse(NativeDepartureReconstruction.isPlausibleRoadDistance(600, straightLineMeters: 1_000))
    XCTAssertFalse(NativeDepartureReconstruction.isPlausibleRoadDistance(4_000, straightLineMeters: 1_000))
  }

  func testBicycleFallbackUsesCyclingSpeedNotDrivingSpeed() {
    let anchor = location(51.5000, -0.1000, minutesBefore: 120)
    let firstFix = location(51.5090, -0.1000, minutesBefore: 0)
    let gap = anchor.distance(from: firstFix)
    let departure = NativeDepartureReconstruction.departureDate(
      anchor: anchor, firstFix: firstFix, motionDeparture: nil, vehicle: .bike
    )
    XCTAssertEqual(
      departure?.timeIntervalSinceReferenceDate ?? 0,
      now.addingTimeInterval(-gap / NativeDepartureReconstruction.bicycleFallbackSpeedMetersPerSecond).timeIntervalSinceReferenceDate,
      accuracy: 0.001
    )
  }

  // MARK: Recorder

  func testRecorderPrependsDepartureAheadOfRecordedRoute() {
    let recorder = NativeTripRecorder()
    let startedAt = now.addingTimeInterval(-60)
    XCTAssertTrue(recorder.begin(owner: .automatic, startedAt: startedAt))
    let fixes = (0..<3).map { index in
      CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: 51.5090 + Double(index) * 0.0005, longitude: -0.1),
        altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
        course: 0, speed: 12,
        timestamp: startedAt.addingTimeInterval(Double(index) * 5)
      )
    }
    _ = recorder.ingest(fixes, owner: .automatic, now: startedAt.addingTimeInterval(15))
    let before = recorder.snapshot(owner: .automatic)!

    let departure = now.addingTimeInterval(-5 * 60)
    let anchor = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1),
      altitude: 0, horizontalAccuracy: 20, verticalAccuracy: -1, timestamp: departure
    )
    let after = recorder.prependDeparture(owner: .automatic, points: [anchor], miles: 0.6, startedAt: departure)

    XCTAssertEqual(after?.startedAt, departure)
    XCTAssertEqual(after?.points.count, before.points.count + 1)
    XCTAssertEqual(after?.points.first?.timestamp, departure)
    XCTAssertEqual(after?.miles ?? 0, before.miles + 0.6, accuracy: 0.0001)
  }
}

/// Bike rides must start as reliably as drives, even though Core Motion's
/// cycling detection on iPhone is weaker than its automotive detection.
final class NativeBicycleTrackingTests: XCTestCase {
  private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func motionState(
    automotive: Bool = false,
    cycling: Bool = false,
    walking: Bool = false,
    trusted: Bool = true,
    vehicle: NativeVehicle = .bike
  ) -> NativeTripMotionState {
    NativeTripMileagePolicy.motionState(
      automotive: automotive, cycling: cycling, walking: walking, running: false,
      stationary: false, hasTrustedConfidence: trusted, vehicle: vehicle
    )
  }

  /// Fixes heading north at a steady speed, one every 2 seconds.
  private func ride(speed: Double, seconds: Int) -> [CLLocation] {
    stride(from: 0, through: seconds, by: 2).map { second in
      let metres = speed * Double(second)
      return CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: 51.5 + metres / 111_000, longitude: -0.1),
        altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
        course: 0, speed: speed,
        timestamp: now.addingTimeInterval(Double(second - seconds))
      )
    }
  }

  func testCyclingMotionCountsAsBikeTravel() {
    XCTAssertEqual(motionState(cycling: true), .cycling)
    XCTAssertTrue(NativeTripMileagePolicy.confirmsVehicleTravel(.cycling, vehicle: .bike))
  }

  func testEBikeReportedAsAutomotiveStillCountsAsBikeTravel() {
    XCTAssertEqual(motionState(automotive: true), .cycling)
    XCTAssertTrue(NativeAutoTrackPolicy.isDrivingMotion(automotive: true, cycling: false, vehicle: .bike))
  }

  func testWalkingIsNotBikeTravel() {
    XCTAssertEqual(motionState(walking: true), .pedestrian)
    XCTAssertFalse(NativeTripMileagePolicy.confirmsVehicleTravel(.pedestrian, vehicle: .bike))
  }

  func testLowConfidenceMotionIsIgnored() {
    XCTAssertEqual(motionState(cycling: true, trusted: false), .unknown)
  }

  func testCarProfileStillIgnoresCyclingMotion() {
    XCTAssertEqual(motionState(cycling: true, vehicle: .car), .unknown)
  }

  func testTrustedCyclingMotionAloneStartsABikeTrip() {
    let decision = NativeTrackingConfidenceEvaluator.startDecision(
      NativeTripStartEvidence(automotiveMotion: true), vehicle: .bike
    )
    XCTAssertTrue(decision.shouldTransition)
  }

  func testCyclingSpeedGPSAloneStartsABikeTrip() {
    let decision = NativeTrackingConfidenceEvaluator.startDecision(
      NativeTripStartEvidence(speedMetersPerSecond: 4.0), vehicle: .bike
    )
    XCTAssertTrue(decision.shouldTransition)
  }

  func testWalkingSpeedGPSDoesNotStartABikeTrip() {
    let decision = NativeTrackingConfidenceEvaluator.startDecision(
      NativeTripStartEvidence(speedMetersPerSecond: 1.4), vehicle: .bike
    )
    XCTAssertFalse(decision.shouldTransition)
  }

  func testPreTripBufferConfirmsATypicalBikeRide() {
    var buffer = NativePreTripBuffer()
    buffer.append(ride(speed: 4.5, seconds: 12), now: now)
    XCTAssertTrue(buffer.confirmsMovement(vehicle: .bike))
    XCTAssertFalse(buffer.tripStartLocations(vehicle: .bike).isEmpty)
  }

  func testPreTripBufferConfirmsASlowUrbanBikeRide() {
    var buffer = NativePreTripBuffer()
    buffer.append(ride(speed: 3.0, seconds: 12), now: now)
    XCTAssertTrue(buffer.confirmsMovement(vehicle: .bike))
  }

  func testPreTripBufferRejectsWalkingPace() {
    var buffer = NativePreTripBuffer()
    buffer.append(ride(speed: 1.4, seconds: 30), now: now)
    XCTAssertFalse(buffer.confirmsMovement(vehicle: .bike))
  }

  func testPreTripBufferRejectsASingleSpeedSpike() {
    var buffer = NativePreTripBuffer()
    buffer.append(Array(ride(speed: 5, seconds: 2).suffix(1)), now: now)
    XCTAssertFalse(buffer.confirmsMovement(vehicle: .bike))
  }
}

final class NativeWorkingHoursTests: XCTestCase {
  private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    return calendar
  }()

  /// 2026-10-19 is a Monday.
  private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
  }

  private func settings(days: [Int] = Array(0...6), hours: (Int, Int)?) -> NativeSettings {
    var settings = NativeSettings()
    settings.workingDays = days
    if let hours {
      settings.workingHoursEnabled = true
      settings.workStartMinute = hours.0 * 60
      settings.workEndMinute = hours.1 * 60
    }
    return settings
  }

  func testHoursOffFollowsWorkingDaysOnly() {
    let weekdays = settings(days: [1, 2, 3, 4, 5], hours: nil)
    XCTAssertTrue(nativeIsWithinWorkingTime(date(day: 19, hour: 3), settings: weekdays, calendar: calendar))
    XCTAssertFalse(nativeIsWithinWorkingTime(date(day: 18, hour: 12), settings: weekdays, calendar: calendar))
  }

  func testDaytimeWindow() {
    let nineToFive = settings(hours: (9, 17))
    XCTAssertFalse(nativeIsWithinWorkingTime(date(day: 19, hour: 8, minute: 59), settings: nineToFive, calendar: calendar))
    XCTAssertTrue(nativeIsWithinWorkingTime(date(day: 19, hour: 9), settings: nineToFive, calendar: calendar))
    XCTAssertTrue(nativeIsWithinWorkingTime(date(day: 19, hour: 16, minute: 59), settings: nineToFive, calendar: calendar))
    XCTAssertFalse(nativeIsWithinWorkingTime(date(day: 19, hour: 17), settings: nineToFive, calendar: calendar))
  }

  func testDaytimeWindowStillRespectsWorkingDays() {
    let weekdaysNineToFive = settings(days: [1, 2, 3, 4, 5], hours: (9, 17))
    XCTAssertFalse(nativeIsWithinWorkingTime(date(day: 18, hour: 12), settings: weekdaysNineToFive, calendar: calendar))
  }

  func testOvernightWindowBelongsToTheDayItStarted() {
    // Friday-only evening shift, 18:00-02:00.
    let fridayNights = settings(days: [5], hours: (18, 2))
    XCTAssertTrue(nativeIsWithinWorkingTime(date(day: 23, hour: 22), settings: fridayNights, calendar: calendar))
    XCTAssertTrue(nativeIsWithinWorkingTime(date(day: 24, hour: 1), settings: fridayNights, calendar: calendar))   // Sat 01:00
    XCTAssertFalse(nativeIsWithinWorkingTime(date(day: 24, hour: 3), settings: fridayNights, calendar: calendar))
    XCTAssertFalse(nativeIsWithinWorkingTime(date(day: 23, hour: 1), settings: fridayNights, calendar: calendar))  // Fri 01:00 is Thursday's shift
    XCTAssertFalse(nativeIsWithinWorkingTime(date(day: 24, hour: 22), settings: fridayNights, calendar: calendar))
  }

  func testOldSettingsDecodeWithHoursOff() throws {
    let decoded = try JSONDecoder().decode(NativeSettings.self, from: Data("{}".utf8))
    XCTAssertFalse(decoded.workingHoursEnabled)
    XCTAssertEqual(decoded.workStartMinute, 8 * 60)
    XCTAssertEqual(decoded.workEndMinute, 20 * 60)
  }
}
