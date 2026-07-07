import XCTest
@testable import Okkle

final class TaxCalculatorTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  func testTaxYearStartsOnAprilSixth() {
    let interval = TaxCalculator.taxYearInterval(containing: date(2026, 4, 5), calendar: calendar)

    XCTAssertEqual(interval.start, date(2025, 4, 6))
    XCTAssertEqual(interval.end, date(2026, 4, 6))
  }

  func testWeekPeriodRunsMondayToSunday() {
    let bounds = TaxCalculator.periodBounds(for: date(2026, 6, 27), period: .week, calendar: calendar)

    XCTAssertEqual(bounds.start, date(2026, 6, 22))
    XCTAssertEqual(bounds.end, date(2026, 6, 28))
  }

  func testMileageDeductionSplitsFirstTenThousandMileBand() {
    let deduction = TaxCalculator.mileageDeduction(
      miles: 200,
      vehicle: .car,
      totalBefore: 9_900,
      date: date(2025, 6, 1)
    )

    XCTAssertEqual(deduction, 70, accuracy: 0.001)
  }

  func testTaxEstimateUsesTradingAllowanceWhenBetterThanExpenses() {
    let position = TaxCalculator.estimate(
      turnover: 20_000,
      expenses: 400,
      region: .ruk,
      incomeBracket: .basic
    )

    XCTAssertTrue(position.usesTradingAllowance)
    XCTAssertEqual(position.deductionApplied, 1_000, accuracy: 0.001)
    XCTAssertEqual(position.profit, 19_000, accuracy: 0.001)
  }

  func testTaxEstimateAccountsForOtherIncomeStacking() {
    let position = TaxCalculator.estimate(
      turnover: 20_000,
      expenses: 2_000,
      region: .ruk,
      incomeBracket: .higher,
      otherIncome: 45_000
    )

    XCTAssertFalse(position.usesTradingAllowance)
    XCTAssertEqual(position.deductionApplied, 2_000, accuracy: 0.001)
    XCTAssertEqual(position.profit, 18_000, accuracy: 0.001)
    XCTAssertEqual(position.incomeTax, 6_146, accuracy: 0.001)
    XCTAssertEqual(position.class4, 325.8, accuracy: 0.001)
    XCTAssertEqual(position.totalDue, 6_471.8, accuracy: 0.001)
  }

  private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
  }
}


@MainActor
final class NativeInsightsSimulationTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  func testStoredTripHistoryBuildsInsightsWithoutVisitCache() {
    let store = OkkleStore()
    store.trips = [trip(miles: 6, startedAt: date(2026, 6, 23, 18), endedAt: date(2026, 6, 23, 18, 30), timestamped: false)]

    let visits = NativeShiftInsights.enrichedVisits(visits: [], trips: store.trips)
    let insights = NativeShiftInsights.build(visits: visits, store: store)

    XCTAssertEqual(visits.count, 2)
    XCTAssertEqual(visits.map(\.kind), [.pickup, .dropoff])
    XCTAssertTrue(insights.hasData)
    XCTAssertEqual(insights.deliveries, 1)
    XCTAssertEqual(insights.paidMiles, 6, accuracy: 0.05)
  }

  func testStoredTripDoesNotDoubleCountWhenRealVisitsAlreadyExist() {
    let store = OkkleStore()
    let started = date(2026, 6, 24, 19)
    let ended = date(2026, 6, 24, 19, 25)
    store.trips = [trip(miles: 4, startedAt: started, endedAt: ended, timestamped: true)]
    let existing = [
      visit(kind: .pickup, latitude: 51.50, longitude: -0.12, arrival: started, departure: started.addingTimeInterval(60)),
      visit(kind: .dropoff, latitude: 51.53, longitude: -0.10, arrival: ended.addingTimeInterval(-60), departure: ended)
    ]

    let visits = NativeShiftInsights.enrichedVisits(visits: existing, trips: store.trips)
    let insights = NativeShiftInsights.build(visits: visits, store: store)

    XCTAssertEqual(visits.count, existing.count)
    XCTAssertEqual(insights.deliveries, 1)
  }

  func testStoredTripWithTimestampedRouteKeepsRecordedMileageScale() {
    let store = OkkleStore()
    store.trips = [trip(miles: 8, startedAt: date(2026, 6, 25, 17), endedAt: date(2026, 6, 25, 18), timestamped: true)]

    let insights = NativeShiftInsights.build(
      visits: NativeShiftInsights.enrichedVisits(visits: [], trips: store.trips),
      store: store
    )

    XCTAssertEqual(insights.deliveries, 1)
    XCTAssertEqual(insights.paidMiles, 8, accuracy: 0.15)
  }

  func testHighIncomeCanOverturnDeadMilePreference() {
    let store = OkkleStore()
    let baseDay = calendar.startOfDay(for: Date().addingTimeInterval(-30 * 86_400))
    var visits: [NativeVisit] = []
    var records: [NativeRecord] = []

    for i in 0..<4 {
      // Zone A day: the day's first stop, so 0% dead miles — but a small order.
      let aDay = calendar.date(byAdding: .day, value: i * 4, to: baseDay)!.addingTimeInterval(10 * 3600)
      visits.append(visit(kind: .pickup, latitude: 51.500, longitude: -0.120, arrival: aDay, departure: aDay))
      visits.append(visit(kind: .dropoff, latitude: 51.501, longitude: -0.120, arrival: aDay.addingTimeInterval(5 * 60), departure: aDay.addingTimeInterval(5 * 60)))
      records.append(record(date: aDay, amount: 5))

      // Zone B day: a long (~5.5km) unpaid approach leg to reach it — but a
      // big enough order that the trip still pays off per mile.
      let bDay = calendar.date(byAdding: .day, value: i * 4 + 2, to: baseDay)!.addingTimeInterval(10 * 3600)
      visits.append(visit(kind: .dropoff, latitude: 52.00, longitude: -1.00, arrival: bDay, departure: bDay.addingTimeInterval(60)))
      visits.append(visit(kind: .pickup, latitude: 52.05, longitude: -1.00, arrival: bDay.addingTimeInterval(10 * 60), departure: bDay.addingTimeInterval(10 * 60)))
      visits.append(visit(kind: .dropoff, latitude: 52.051, longitude: -1.00, arrival: bDay.addingTimeInterval(15 * 60), departure: bDay.addingTimeInterval(15 * 60)))
      records.append(record(date: bDay, amount: 60))
    }

    store.records = records
    let insights = NativeShiftInsights.build(visits: visits, store: store)

    let zoneA = insights.zones.first { $0.coordinate.latitude == 51.500 }
    let zoneB = insights.zones.first { $0.coordinate.latitude == 52.05 }
    XCTAssertNotNil(zoneA)
    XCTAssertNotNil(zoneB)
    XCTAssertEqual(zoneA?.deadMilePct, 0)
    XCTAssertGreaterThan(zoneB?.deadMilePct ?? 0, 90)
    // Zone B has far worse dead-mile efficiency, but its orders are big
    // enough that its real attributed £/mile still wins out overall.
    XCTAssertGreaterThan(zoneB?.weight ?? 0, zoneA?.weight ?? 1)
  }

  func testZoneWeightFavorsLowerDeadMilePercentage() {
    let store = OkkleStore()
    // Zone A: the very first visit overall, so no approach leg is possible —
    // a short, efficient paid leg (0% dead miles).
    let aArrival = Date().addingTimeInterval(-3600)
    let visits = [
      visit(kind: .pickup, latitude: 51.500, longitude: -0.120, arrival: aArrival, departure: aArrival),
      visit(kind: .dropoff, latitude: 51.501, longitude: -0.120, arrival: aArrival.addingTimeInterval(5 * 60), departure: aArrival.addingTimeInterval(5 * 60)),
      // An unrelated stop far from zone B, just before it, so zone B's
      // pickup carries a long (~5.5km) unpaid approach leg.
      visit(kind: .dropoff, latitude: 52.00, longitude: -1.00, arrival: aArrival.addingTimeInterval(20 * 60), departure: aArrival.addingTimeInterval(21 * 60)),
      visit(kind: .pickup, latitude: 52.05, longitude: -1.00, arrival: aArrival.addingTimeInterval(30 * 60), departure: aArrival.addingTimeInterval(30 * 60)),
      visit(kind: .dropoff, latitude: 52.051, longitude: -1.00, arrival: aArrival.addingTimeInterval(35 * 60), departure: aArrival.addingTimeInterval(35 * 60))
    ]

    let insights = NativeShiftInsights.build(visits: visits, store: store)
    XCTAssertEqual(insights.zones.count, 2)
    let zoneA = insights.zones.first { $0.coordinate.latitude == 51.500 }
    let zoneB = insights.zones.first { $0.coordinate.latitude == 52.05 }
    XCTAssertNotNil(zoneA)
    XCTAssertNotNil(zoneB)
    XCTAssertEqual(zoneA?.deadMilePct, 0)
    XCTAssertGreaterThan(zoneB?.deadMilePct ?? 0, 90)
    // Same recency, same raw count — only the dead-mile efficiency differs,
    // so the cleaner zone should rank higher.
    XCTAssertGreaterThan(zoneA?.weight ?? 0, zoneB?.weight ?? 1)
  }

  func testZoneWeightDecaysWithAge() {
    let store = OkkleStore()
    let recent = Date().addingTimeInterval(-3600)
    let old = Date().addingTimeInterval(-200 * 86_400)
    let visits = [
      visit(kind: .pickup, latitude: 51.500, longitude: -0.120, arrival: recent, departure: recent),
      visit(kind: .dropoff, latitude: 51.501, longitude: -0.120, arrival: recent.addingTimeInterval(5 * 60), departure: recent.addingTimeInterval(5 * 60)),
      visit(kind: .pickup, latitude: 52.00, longitude: -1.00, arrival: old, departure: old),
      visit(kind: .dropoff, latitude: 52.001, longitude: -1.00, arrival: old.addingTimeInterval(5 * 60), departure: old.addingTimeInterval(5 * 60))
    ]

    let insights = NativeShiftInsights.build(visits: visits, store: store)
    let recentZone = insights.zones.first { $0.coordinate.latitude == 51.500 }
    let oldZone = insights.zones.first { $0.coordinate.latitude == 52.00 }
    XCTAssertNotNil(recentZone)
    XCTAssertNotNil(oldZone)
    // Same count, same (zero) dead miles for both — only age differs, so a
    // 200-day-old delivery should rank well below a fresh one.
    XCTAssertGreaterThan(recentZone?.weight ?? 0, oldZone?.weight ?? 1)
  }

  func testTripDerivedVisitsDoNotProduceLocationZones() {
    let store = OkkleStore()
    store.trips = [trip(miles: 6, startedAt: date(2026, 6, 23, 18), endedAt: date(2026, 6, 23, 18, 30), timestamped: false)]

    let visits = NativeShiftInsights.enrichedVisits(visits: [], trips: store.trips)
    let insights = NativeShiftInsights.build(visits: visits, store: store)

    // A trip's raw start/end point is just "wherever the shift happened to
    // start" — not a real classified stop — so it should count toward
    // deliveries/mileage but never get named as a "where to go" zone.
    XCTAssertEqual(insights.deliveries, 1)
    XCTAssertTrue(insights.zones.isEmpty)
  }

  func testRealClassifiedVisitsStillProduceLocationZones() {
    let store = OkkleStore()
    let started = date(2026, 6, 24, 19)
    let ended = date(2026, 6, 24, 19, 25)
    let visits = [
      visit(kind: .pickup, latitude: 51.50, longitude: -0.12, arrival: started, departure: started.addingTimeInterval(60)),
      visit(kind: .dropoff, latitude: 51.53, longitude: -0.10, arrival: ended.addingTimeInterval(-60), departure: ended)
    ]

    let insights = NativeShiftInsights.build(visits: visits, store: store)

    XCTAssertEqual(insights.deliveries, 1)
    XCTAssertFalse(insights.zones.isEmpty)
  }

  private func trip(miles: Double, startedAt: Date, endedAt: Date, timestamped: Bool) -> NativeTrip {
    let timestamps: [Date?] = timestamped
      ? [startedAt, startedAt.addingTimeInterval(20 * 60), startedAt.addingTimeInterval(40 * 60), endedAt]
      : [nil, nil, nil, nil]
    let latitudeDelta = miles * 1609.34 / 111_000
    let points = [
      RoutePoint(latitude: 51.5000, longitude: -0.1200, timestamp: timestamps[0]),
      RoutePoint(latitude: 51.5000 + latitudeDelta * 0.33, longitude: -0.1200, timestamp: timestamps[1]),
      RoutePoint(latitude: 51.5000 + latitudeDelta * 0.66, longitude: -0.1200, timestamp: timestamps[2]),
      RoutePoint(latitude: 51.5000 + latitudeDelta, longitude: -0.1200, timestamp: timestamps[3])
    ]
    return NativeTrip(
      vehicle: .car,
      miles: miles,
      deduction: miles * 0.45,
      startedAt: startedAt,
      endedAt: endedAt,
      points: points
    )
  }

  private func visit(kind: NativeVisit.Kind, latitude: Double, longitude: Double, arrival: Date, departure: Date) -> NativeVisit {
    var visit = NativeVisit(latitude: latitude, longitude: longitude, arrival: arrival, departure: departure)
    visit.kind = kind
    return visit
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  private func record(date: Date, amount: Double) -> NativeRecord {
    NativeRecord(kind: .income, platform: "Uber Eats", vehicle: nil, amount: amount, miles: nil,
                 deduction: nil, category: nil, date: date, period: .day, receiptImageData: nil)
  }
}


@MainActor
final class NativeNotificationReminderTests: XCTestCase {
  func testManualRecordTodayCountsAsLoggedForReminderSuppression() {
    let store = OkkleStore()
    store.records = [record(date: Date())]

    XCTAssertTrue(NativeLoggingReminder.hasLoggedToday(store: store, calendar: .current))
  }

  func testOlderManualRecordDoesNotSuppressTodaysReminder() {
    let store = OkkleStore()
    store.records = [record(date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!)]
    store.trips = []

    XCTAssertFalse(NativeLoggingReminder.hasLoggedToday(store: store, calendar: .current))
  }

  private func record(date: Date) -> NativeRecord {
    NativeRecord(
      kind: .income,
      platform: "Uber Eats",
      vehicle: nil,
      amount: 42,
      miles: nil,
      deduction: nil,
      category: nil,
      date: date,
      period: .day,
      receiptImageData: nil
    )
  }
}
