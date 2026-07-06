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
}
