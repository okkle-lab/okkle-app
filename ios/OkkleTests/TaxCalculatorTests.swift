import AVFoundation
import CoreLocation
import SwiftUI
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

  @MainActor
  func testAccountantPackPdfStillRendersAfterSharedRendererRefactor() {
    let store = OkkleStore()
    let recentDate = Date().addingTimeInterval(-3 * 86_400)
    store.trips = [
      NativeTrip(vehicle: .car, miles: 50, deduction: 0, startedAt: recentDate, endedAt: recentDate.addingTimeInterval(3_600), points: [])
    ]
    store.records = [
      NativeRecord(kind: .income, platform: "Uber Eats", vehicle: nil, amount: 120, miles: nil,
                   deduction: nil, category: nil, date: recentDate, period: .day, receiptImageData: nil)
    ]
    let pdf = nativeAccountantPackPdfData(store: store)
    XCTAssertGreaterThan(pdf.count, 0)
    XCTAssertEqual(pdf.prefix(4), Data("%PDF".utf8))
  }

  @MainActor
  func testMileageReportPdfRendersForEmptyAndPopulatedStore() {
    let emptyStore = OkkleStore()
    let emptyPdf = nativeMileageReportPdfData(store: emptyStore)
    XCTAssertGreaterThan(emptyPdf.count, 0)
    XCTAssertEqual(emptyPdf.prefix(4), Data("%PDF".utf8))

    // Also exercise a populated store, including a trip past the 10,000-mile
    // threshold — mainly to catch a crash in the two-band summary rendering,
    // since PDF byte size doesn't reliably track how much content is on the
    // page (compression, font subsetting) so isn't worth asserting on.
    let populatedStore = OkkleStore()
    let recentDate = Date().addingTimeInterval(-3 * 86_400)
    populatedStore.trips = [
      NativeTrip(vehicle: .car, miles: 12_000, deduction: 0, startedAt: recentDate, endedAt: recentDate.addingTimeInterval(3_600), points: [])
    ]
    let populatedPdf = nativeMileageReportPdfData(store: populatedStore)
    XCTAssertGreaterThan(populatedPdf.count, 0)
    XCTAssertEqual(populatedPdf.prefix(4), Data("%PDF".utf8))
  }

  @MainActor
  func testMileageLogRowsMatchYearMileageDeductionAcrossThreshold() {
    let store = OkkleStore()
    let earlierDate = Date().addingTimeInterval(-10 * 86_400)
    let laterDate = Date().addingTimeInterval(-5 * 86_400)
    store.trips = [
      NativeTrip(vehicle: .car, miles: 9_500, deduction: 0, startedAt: earlierDate, endedAt: earlierDate.addingTimeInterval(3_600), points: []),
      NativeTrip(vehicle: .car, miles: 1_000, deduction: 0, startedAt: laterDate, endedAt: laterDate.addingTimeInterval(3_600), points: [])
    ]

    let rows = store.yearMileageLogRows
    XCTAssertEqual(rows.count, 2)
    // The exported rows must sum to exactly the tax-year figure shown
    // elsewhere in Reports — a trip's own naively-stored `deduction` field
    // (computed at logging time with no running total) would not, once the
    // combined car/van mileage crosses the 10,000-mile threshold.
    let rowTotal = rows.reduce(0.0) { $0 + $1.deduction }
    XCTAssertEqual(rowTotal, store.yearMileageDeduction, accuracy: 0.01)

    // The second trip's 1,000 miles should split 500 at the first-band rate
    // and 500 at the after-threshold rate, not all at the first-band rate.
    let rate = NativeVehicle.car.rateBand(on: laterDate)
    let expectedSecondRowDeduction = 500 * rate.first + 500 * rate.after
    XCTAssertEqual(rows[1].deduction, expectedSecondRowDeduction, accuracy: 0.01)
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

  func testAdditionalRateThresholdAccountsForTaperedAllowance() {
    // At gross £120,000 the personal allowance is already tapered down to
    // £2,570 (£12,570 minus half of the £20,000 over £100,000). A fixed
    // taxable-income cutoff of £112,570 for the 45% band (125,140 minus the
    // *standard* £12,570 allowance) would tax roughly £4,860 of this at the
    // additional rate — but the real 45% band only starts at £125,140 of
    // *gross* income, and £120,000 is still under that, so none of it
    // should be taxed at 45% yet.
    let tax = TaxCalculator.incomeTax(income: 120_000, region: .ruk)
    XCTAssertEqual(tax, 39_432, accuracy: 0.01)
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
final class NativeSheetDependencyTests: XCTestCase {
  func testTripDetailRendersWithExplicitStoreWithoutAmbientEnvironmentObject() {
    let startedAt = Date(timeIntervalSinceReferenceDate: 100_000)
    let trip = NativeTrip(
      vehicle: .car,
      miles: 2,
      deduction: 0.9,
      startedAt: startedAt,
      endedAt: startedAt.addingTimeInterval(600),
      points: []
    )
    let store = OkkleStore()
    store.trips = [trip]
    let detail = NativeHistoryDetailSheet(
      item: .trip(trip),
      store: store,
      onEdit: {},
      onDelete: {}
    )
    let host = UIHostingController(rootView: detail)

    host.loadViewIfNeeded()
    host.view.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
    host.view.layoutIfNeeded()

    XCTAssertNotNil(host.view)
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

  func testVehicleTypeChangesEstimatedCostAndZoneValue() {
    let store = OkkleStore()
    let carDay = date(2026, 6, 1, 10)
    let bikeDay = date(2026, 6, 3, 10)
    let carDropoffArrival = carDay.addingTimeInterval(15 * 60)
    let bikeDropoffArrival = bikeDay.addingTimeInterval(15 * 60)

    // Identical ~2km unpaid approach leg and paid leg either side — the only
    // difference is which vehicle actually covered the trip.
    let visits: [NativeVisit] = [
      visit(kind: .dropoff, latitude: 51.400, longitude: -0.500, arrival: carDay, departure: carDay.addingTimeInterval(60)),
      visit(kind: .pickup, latitude: 51.418, longitude: -0.500, arrival: carDay.addingTimeInterval(10 * 60), departure: carDay.addingTimeInterval(10 * 60)),
      visit(kind: .dropoff, latitude: 51.4181, longitude: -0.500, arrival: carDropoffArrival, departure: carDropoffArrival),

      visit(kind: .dropoff, latitude: 51.600, longitude: -0.700, arrival: bikeDay, departure: bikeDay.addingTimeInterval(60)),
      visit(kind: .pickup, latitude: 51.618, longitude: -0.700, arrival: bikeDay.addingTimeInterval(10 * 60), departure: bikeDay.addingTimeInterval(10 * 60)),
      visit(kind: .dropoff, latitude: 51.6181, longitude: -0.700, arrival: bikeDropoffArrival, departure: bikeDropoffArrival)
    ]
    store.trips = [
      trip(miles: 1, startedAt: carDay.addingTimeInterval(-60), endedAt: carDay.addingTimeInterval(20 * 60), timestamped: false, vehicle: .car),
      trip(miles: 1, startedAt: bikeDay.addingTimeInterval(-60), endedAt: bikeDay.addingTimeInterval(20 * 60), timestamped: false, vehicle: .bike)
    ]
    store.records = [record(date: carDropoffArrival, amount: 30), record(date: bikeDropoffArrival, amount: 30)]

    let insights = NativeShiftInsights.build(visits: visits, store: store)
    let carZone = insights.zones.first { $0.coordinate.latitude == 51.418 }
    let bikeZone = insights.zones.first { $0.coordinate.latitude == 51.618 }
    XCTAssertNotNil(carZone)
    XCTAssertNotNil(bikeZone)
    // Same income, same distance either side — only the vehicle differs —
    // so the far cheaper-to-run bike should net a higher value than the car.
    XCTAssertGreaterThan(bikeZone?.weight ?? 0, carZone?.weight ?? 1)
  }

  func testInconsistentIncomeDampensZoneConfidenceVersusSteadyIncome() {
    let store = OkkleStore()
    let baseDay = calendar.startOfDay(for: Date().addingTimeInterval(-40 * 86_400))
    var visits: [NativeVisit] = []
    var records: [NativeRecord] = []
    // Same £20/day average and same (moderately inefficient) approach leg on
    // both zones — the only difference is how steady the daily amount is.
    let steadyAmounts: [Double] = [20, 20, 20, 20]
    let luckyAmounts: [Double] = [5, 5, 5, 65]

    for i in 0..<4 {
      let steadyDay = calendar.date(byAdding: .day, value: i * 4, to: baseDay)!.addingTimeInterval(10 * 3600)
      visits.append(visit(kind: .dropoff, latitude: 51.300, longitude: -0.300, arrival: steadyDay, departure: steadyDay.addingTimeInterval(60)))
      visits.append(visit(kind: .pickup, latitude: 51.318, longitude: -0.300, arrival: steadyDay.addingTimeInterval(10 * 60), departure: steadyDay.addingTimeInterval(10 * 60)))
      visits.append(visit(kind: .dropoff, latitude: 51.3181, longitude: -0.300, arrival: steadyDay.addingTimeInterval(15 * 60), departure: steadyDay.addingTimeInterval(15 * 60)))
      records.append(record(date: steadyDay.addingTimeInterval(15 * 60), amount: steadyAmounts[i]))

      let luckyDay = calendar.date(byAdding: .day, value: i * 4 + 2, to: baseDay)!.addingTimeInterval(10 * 3600)
      visits.append(visit(kind: .dropoff, latitude: 51.500, longitude: -0.500, arrival: luckyDay, departure: luckyDay.addingTimeInterval(60)))
      visits.append(visit(kind: .pickup, latitude: 51.518, longitude: -0.500, arrival: luckyDay.addingTimeInterval(10 * 60), departure: luckyDay.addingTimeInterval(10 * 60)))
      visits.append(visit(kind: .dropoff, latitude: 51.5181, longitude: -0.500, arrival: luckyDay.addingTimeInterval(15 * 60), departure: luckyDay.addingTimeInterval(15 * 60)))
      records.append(record(date: luckyDay.addingTimeInterval(15 * 60), amount: luckyAmounts[i]))
    }

    store.records = records
    let insights = NativeShiftInsights.build(visits: visits, store: store)
    let steadyZone = insights.zones.first { $0.coordinate.latitude == 51.318 }
    let luckyZone = insights.zones.first { $0.coordinate.latitude == 51.518 }
    XCTAssertNotNil(steadyZone)
    XCTAssertNotNil(luckyZone)
    // Same total and average income, same distances either side — only the
    // day-to-day consistency differs, so the steady zone should be trusted
    // (and therefore rank) higher than the one carried by a single lucky day.
    XCTAssertGreaterThan(steadyZone?.weight ?? 0, luckyZone?.weight ?? 1)
  }

  func testWeekPeriodIncomeSpreadsAcrossActualDeliveryDays() {
    let store = OkkleStore()
    // Three deliveries on different days of the same week, all in one zone —
    // none of them on the Sunday the week-ending record is dated.
    let monday = date(2026, 6, 1, 12)
    let wednesday = date(2026, 6, 3, 12)
    let friday = date(2026, 6, 5, 12)
    var visits: [NativeVisit] = []
    for day in [monday, wednesday, friday] {
      visits.append(visit(kind: .dropoff, latitude: 51.700, longitude: -0.900, arrival: day, departure: day.addingTimeInterval(60)))
      visits.append(visit(kind: .pickup, latitude: 51.718, longitude: -0.900, arrival: day.addingTimeInterval(10 * 60), departure: day.addingTimeInterval(10 * 60)))
      visits.append(visit(kind: .dropoff, latitude: 51.7181, longitude: -0.900, arrival: day.addingTimeInterval(15 * 60), departure: day.addingTimeInterval(15 * 60)))
    }

    // Logged as one "Week" entry dated the Sunday it ends — no delivery
    // happened on that exact day, only Mon/Wed/Fri within its period.
    var weekRecord = record(date: date(2026, 6, 7, 18), amount: 90)
    weekRecord.period = .week
    weekRecord.periodStart = date(2026, 6, 1, 0)
    weekRecord.periodEnd = date(2026, 6, 7, 0)
    store.records = [weekRecord]

    let insights = NativeShiftInsights.build(visits: visits, store: store)
    let zone = insights.zones.first { $0.coordinate.latitude == 51.718 }
    XCTAssertNotNil(zone)

    // Same shift with no income logged at all — if the week entry were
    // silently ignored (matching only `date`, the bug this fixes), the two
    // weights would come out identical.
    let insightsWithoutIncome = NativeShiftInsights.build(visits: visits, store: OkkleStore())
    let zoneWithoutIncome = insightsWithoutIncome.zones.first { $0.coordinate.latitude == 51.718 }
    XCTAssertNotNil(zoneWithoutIncome)
    XCTAssertNotEqual(zone?.weight, zoneWithoutIncome?.weight)
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

  private func trip(miles: Double, startedAt: Date, endedAt: Date, timestamped: Bool, vehicle: NativeVehicle = .car) -> NativeTrip {
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
      vehicle: vehicle,
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
    var record = NativeRecord(kind: .income, platform: "Uber Eats", vehicle: nil, amount: amount, miles: nil,
                              deduction: nil, category: nil, date: date, period: .day, receiptImageData: nil)
    record.legacyID = "sqlite-trip-earnings-\(UUID().uuidString)"
    return record
  }
}


@MainActor
final class NativeNotificationReminderTests: XCTestCase {
  func testAutomaticTrackingSuppressesLoggingReminderScheduling() {
    var settings = NativeSettings()
    settings.hasCompletedOnboarding = true
    settings.loggingReminder = true
    settings.autoTrackTrips = false

    XCTAssertTrue(NativeLoggingReminder.shouldSchedule(settings: settings))

    settings.autoTrackTrips = true
    XCTAssertFalse(NativeLoggingReminder.shouldSchedule(settings: settings))

    settings.autoTrackTrips = false
    XCTAssertTrue(NativeLoggingReminder.shouldSchedule(settings: settings))
  }

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


final class NativeRouteStopDetectorTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  func testRouteStopsFilterEndpointVisitsAndKeepIntermediateStops() {
    let started = date(2026, 7, 6, 18, 0)
    let ended = date(2026, 7, 6, 19, 0)
    let points = [
      RoutePoint(latitude: 51.5000, longitude: -0.1200, timestamp: started),
      RoutePoint(latitude: 51.5200, longitude: -0.1100, timestamp: started.addingTimeInterval(30 * 60)),
      RoutePoint(latitude: 51.5400, longitude: -0.1000, timestamp: ended)
    ]

    let stops = NativeRouteStopDetector.routeStops(
      in: points,
      startedAt: started,
      endedAt: ended,
      recordedVisits: [
        visit(latitude: 51.5001, longitude: -0.1201, arrival: started, departure: started.addingTimeInterval(60), placeName: "Home"),
        visit(latitude: 51.5200, longitude: -0.1100, arrival: started.addingTimeInterval(28 * 60), departure: started.addingTimeInterval(32 * 60), placeName: "Restaurant"),
        visit(latitude: 51.5399, longitude: -0.1001, arrival: ended.addingTimeInterval(-60), departure: ended, placeName: "Home")
      ]
    )

    XCTAssertEqual(stops.count, 1)
    XCTAssertEqual(stops.first?.placeName, "Restaurant")
  }

  func testRouteStopsIncludeDetectedStationaryStops() {
    let started = date(2026, 7, 6, 18, 0)
    let ended = date(2026, 7, 6, 18, 30)
    let points = [
      RoutePoint(latitude: 51.5000, longitude: -0.1200, timestamp: started),
      RoutePoint(latitude: 51.5200, longitude: -0.1100, timestamp: started.addingTimeInterval(10 * 60)),
      RoutePoint(latitude: 51.5202, longitude: -0.1101, timestamp: started.addingTimeInterval(18 * 60)),
      RoutePoint(latitude: 51.5400, longitude: -0.1000, timestamp: ended)
    ]

    let stops = NativeRouteStopDetector.routeStops(
      in: points,
      startedAt: started,
      endedAt: ended,
      recordedVisits: []
    )

    XCTAssertEqual(stops.count, 1)
    XCTAssertEqual(stops.first?.placeName, "Detected from movement")
  }

  private func visit(
    latitude: Double,
    longitude: Double,
    arrival: Date,
    departure: Date,
    placeName: String
  ) -> NativeVisit {
    var visit = NativeVisit(latitude: latitude, longitude: longitude, arrival: arrival, departure: departure)
    visit.kind = .other
    visit.placeName = placeName
    return visit
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }
}


@MainActor
final class NativeAutoTrackPolicyTests: XCTestCase {
  func testActiveTripKeepsContinuousGPSWhileWaitingForStationaryTimeout() {
    XCTAssertEqual(NativeAutoTrackPolicy.locationStrategy(during: .driving), .continuousWithRelaunchWake)
    XCTAssertEqual(NativeAutoTrackPolicy.locationStrategy(during: .stationaryPending), .continuousWithRelaunchWake)
    XCTAssertEqual(NativeAutoTrackPolicy.locationStrategy(during: .idle), .significantChangeOnly)
    XCTAssertEqual(NativeAutoTrackPolicy.locationStrategy(during: .paused), .off)
    XCTAssertTrue(NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: .driving))
    XCTAssertTrue(NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: .stationaryPending))
    XCTAssertFalse(NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: .idle))
    XCTAssertFalse(NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: .paused))
  }

  func testAutomaticMonitoringRequiresAlwaysAuthorizationAndAWorkingDay() {
    var settings = NativeSettings()
    settings.autoTrackTrips = true
    settings.workingDays = Array(0...6)

    XCTAssertFalse(NativeAutoTrackPolicy.canMonitor(
      settings: settings,
      authorizationStatus: .authorizedWhenInUse,
      date: Date()
    ))
    XCTAssertTrue(NativeAutoTrackPolicy.canMonitor(
      settings: settings,
      authorizationStatus: .authorizedAlways,
      date: Date()
    ))

    settings.workingDays = []
    XCTAssertFalse(NativeAutoTrackPolicy.canMonitor(
      settings: settings,
      authorizationStatus: .authorizedAlways,
      date: Date()
    ))
  }

  func testActiveShiftCanContinueAfterWorkingDayEnds() {
    var settings = NativeSettings()
    settings.autoTrackTrips = true
    settings.workingDays = []

    XCTAssertFalse(NativeAutoTrackPolicy.canStartMonitoring(
      settings: settings,
      authorizationStatus: .authorizedAlways,
      date: Date()
    ))
    XCTAssertTrue(NativeAutoTrackPolicy.canContinueActiveShift(
      settings: settings,
      authorizationStatus: .authorizedAlways
    ))
    XCTAssertFalse(NativeAutoTrackPolicy.canContinueActiveShift(
      settings: settings,
      authorizationStatus: .authorizedWhenInUse
    ))

    settings.autoTrackTrips = false
    XCTAssertFalse(NativeAutoTrackPolicy.canContinueActiveShift(
      settings: settings,
      authorizationStatus: .authorizedAlways
    ))
  }

  func testOnlyExplicitCarAudioCountsAsAVehicleRoute() {
    XCTAssertTrue(NativeAutoTrackPolicy.isVehicleAudioPort(.carAudio))
    XCTAssertFalse(NativeAutoTrackPolicy.isVehicleAudioPort(.bluetoothA2DP))
    XCTAssertFalse(NativeAutoTrackPolicy.isVehicleAudioPort(.bluetoothHFP))
    XCTAssertFalse(NativeAutoTrackPolicy.isVehicleAudioPort(.bluetoothLE))
  }

  func testExplicitCarAudioRemovalOverridesAStaleCurrentRoute() {
    XCTAssertFalse(NativeAutoTrackPolicy.vehicleConnectionState(
      currentPorts: [.carAudio],
      previousPorts: [.carAudio],
      routeChangeReason: .oldDeviceUnavailable
    ))
    XCTAssertTrue(NativeAutoTrackPolicy.vehicleConnectionState(
      currentPorts: [.carAudio],
      previousPorts: [],
      routeChangeReason: .newDeviceAvailable
    ))
  }

  func testAutomaticTrackingUsesSeparateMotorizedAndBicycleThresholds() {
    let car = NativeVehicle.car.automaticTrackingThresholds
    let bicycle = NativeVehicle.bike.automaticTrackingThresholds

    XCTAssertEqual(NativeVehicle.car.automaticTrackingProfile, .motorized)
    XCTAssertEqual(NativeVehicle.van.automaticTrackingProfile, .motorized)
    XCTAssertEqual(NativeVehicle.motorbike.automaticTrackingProfile, .motorized)
    XCTAssertEqual(NativeVehicle.bike.automaticTrackingProfile, .bicycle)

    // Preserve the existing car behavior while making slower bicycle starts
    // and shorter bicycle resumptions possible.
    XCTAssertEqual(car.startSpeedMetersPerSecond, 6)
    XCTAssertEqual(car.stationaryResumeDistanceMeters, 150)
    XCTAssertEqual(car.gpsStationaryConfirmationSeconds, 120)
    XCTAssertEqual(car.gpsStationaryRadiusMeters, 90)
    XCTAssertEqual(bicycle.startSpeedMetersPerSecond, 2.5)
    XCTAssertEqual(bicycle.stationaryResumeDistanceMeters, 60)
    XCTAssertEqual(bicycle.gpsStationaryConfirmationSeconds, 180)
    XCTAssertEqual(bicycle.gpsStationaryRadiusMeters, 45)
  }

  func testCoreMotionDrivingSignalMatchesTheSelectedVehicleProfile() {
    XCTAssertTrue(NativeAutoTrackPolicy.isDrivingMotion(
      automotive: true,
      cycling: false,
      vehicle: .car
    ))
    XCTAssertFalse(NativeAutoTrackPolicy.isDrivingMotion(
      automotive: false,
      cycling: true,
      vehicle: .car
    ))
    XCTAssertTrue(NativeAutoTrackPolicy.isDrivingMotion(
      automotive: false,
      cycling: true,
      vehicle: .bike
    ))
    XCTAssertFalse(NativeAutoTrackPolicy.isDrivingMotion(
      automotive: true,
      cycling: false,
      vehicle: .bike
    ))
  }

  func testStationaryTimeoutCalibrationLearnsSeparatelyForCarsAndBicycles() throws {
    var calibration = NativeAutoTrackCalibration()
    calibration.nudgeStationaryTimeout(toward: 10 * 60, for: .bike)

    XCTAssertEqual(calibration.stationaryTimeout(for: .car), 20 * 60)
    XCTAssertEqual(calibration.stationaryTimeout(for: .van), 20 * 60)
    XCTAssertEqual(calibration.stationaryTimeout(for: .bike), 18 * 60)

    calibration.nudgeStationaryTimeout(toward: 30 * 60, for: .car)
    XCTAssertEqual(calibration.stationaryTimeout(for: .car), 22 * 60)
    XCTAssertEqual(calibration.stationaryTimeout(for: .bike), 18 * 60)

    let legacy = Data(#"{"stationaryTimeoutSeconds":1500}"#.utf8)
    let restored = try JSONDecoder().decode(NativeAutoTrackCalibration.self, from: legacy)
    XCTAssertEqual(restored.stationaryTimeout(for: .car), 1500)
    XCTAssertEqual(restored.stationaryTimeout(for: .bike), 20 * 60)
  }

  func testMileageAndRouteShareTheSamePlausibilityFilter() {
    let now = Date()
    let first = location(latitude: 51.5000, longitude: -0.1200, accuracy: 8, timestamp: now)
    let plausible = location(latitude: 51.5005, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(10))
    let inaccurate = location(latitude: 51.5006, longitude: -0.1200, accuracy: 200, timestamp: now.addingTimeInterval(20))
    let teleport = location(latitude: 52.0000, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(11))
    let outOfOrder = location(latitude: 51.5006, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(9))

    XCTAssertTrue(NativeAutoTrackPolicy.shouldAcceptTripLocation(first, since: nil))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldAcceptTripLocation(plausible, since: first))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldAcceptTripLocation(inaccurate, since: plausible))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldAcceptTripLocation(teleport, since: plausible))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldAcceptTripLocation(outOfOrder, since: plausible))
  }

  func testLocationRejectionsExplainWhyAFixWasDropped() {
    let now = Date()
    let previous = location(latitude: 51.5000, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(-10))
    let inaccurate = location(latitude: 51.5001, longitude: -0.1200, accuracy: 120, timestamp: now)
    let outOfOrder = location(latitude: 51.5001, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(-11))
    let teleport = location(latitude: 52.0000, longitude: -0.1200, accuracy: 8, timestamp: now)

    XCTAssertEqual(nativeTripLocationRejectionReason(inaccurate, since: previous, now: now), .inaccurate)
    XCTAssertEqual(nativeTripLocationRejectionReason(outOfOrder, since: previous, now: now), .outOfOrder)
    XCTAssertEqual(nativeTripLocationRejectionReason(teleport, since: previous, now: now), .implausibleSpeed)
  }

  func testBackgroundLocationBatchIsAcceptedOnlyWithinTheActiveTrip() {
    let now = Date()
    let startedAt = now.addingTimeInterval(-5 * 60)
    let batched = location(
      latitude: 51.5000,
      longitude: -0.1200,
      accuracy: 8,
      timestamp: now.addingTimeInterval(-3 * 60)
    )
    let slightlyBeforeTrip = location(
      latitude: 51.4990,
      longitude: -0.1200,
      accuracy: 8,
      timestamp: startedAt.addingTimeInterval(-1)
    )
    let beforeTrip = location(
      latitude: 51.4980,
      longitude: -0.1200,
      accuracy: 8,
      timestamp: startedAt.addingTimeInterval(-6)
    )

    XCTAssertEqual(nativeTripLocationRejectionReason(batched, since: nil, now: now), .stale)
    XCTAssertNil(nativeTripLocationRejectionReason(
      batched,
      since: nil,
      now: now,
      maximumAge: 10 * 60,
      earliestTimestamp: startedAt
    ))
    XCTAssertNil(nativeTripLocationRejectionReason(
      slightlyBeforeTrip,
      since: nil,
      now: now,
      maximumAge: 10 * 60,
      earliestTimestamp: startedAt
    ))
    XCTAssertEqual(nativeTripLocationRejectionReason(
      beforeTrip,
      since: nil,
      now: now,
      maximumAge: 10 * 60,
      earliestTimestamp: startedAt
    ), .beforeTrip)
  }

  func testVehicleDisconnectCanOnlyEndAStationaryTrip() {
    XCTAssertFalse(NativeAutoTrackPolicy.shouldArmVehicleDisconnectEnd(during: .idle))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldArmVehicleDisconnectEnd(during: .driving))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldArmVehicleDisconnectEnd(during: .paused))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldArmVehicleDisconnectEnd(during: .stationaryPending))
  }

  func testVehicleDisconnectBeginsAProvisionalStopWhileDriving() {
    XCTAssertFalse(NativeAutoTrackPolicy.shouldBeginStationaryWaitForVehicleDisconnect(during: .idle))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldBeginStationaryWaitForVehicleDisconnect(during: .driving))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldBeginStationaryWaitForVehicleDisconnect(during: .stationaryPending))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldBeginStationaryWaitForVehicleDisconnect(during: .paused))
  }

  func testSustainedLowGPSDisplacementConfirmsAStopWithoutCoreMotion() {
    let now = Date()
    let anchor = location(
      latitude: 37.3230,
      longitude: -122.0322,
      accuracy: 8,
      timestamp: now
    )
    let jitterBeforeDwell = location(
      latitude: 37.3231,
      longitude: -122.0322,
      accuracy: 8,
      timestamp: now.addingTimeInterval(90)
    )
    let jitterAfterDwell = location(
      latitude: 37.3232,
      longitude: -122.0322,
      accuracy: 8,
      timestamp: now.addingTimeInterval(150)
    )

    XCTAssertEqual(
      NativeAutoTrackPolicy.gpsStationaryObservation(
        anchor: anchor,
        current: jitterBeforeDwell,
        minimumDwell: 120,
        maximumRadius: 90
      ),
      .waiting
    )
    XCTAssertEqual(
      NativeAutoTrackPolicy.gpsStationaryObservation(
        anchor: anchor,
        current: jitterAfterDwell,
        minimumDwell: 120,
        maximumRadius: 90
      ),
      .confirmed
    )
  }

  func testSignificantGPSDisplacementResetsTheStopCandidate() {
    let now = Date()
    let anchor = location(
      latitude: 37.3230,
      longitude: -122.0322,
      accuracy: 8,
      timestamp: now
    )
    let moved = location(
      latitude: 37.3242,
      longitude: -122.0322,
      accuracy: 8,
      timestamp: now.addingTimeInterval(150)
    )

    XCTAssertEqual(
      NativeAutoTrackPolicy.gpsStationaryObservation(
        anchor: anchor,
        current: moved,
        minimumDwell: 120,
        maximumRadius: 90
      ),
      .moved
    )
  }

  func testStaleAutomotiveMotionCannotEraseGPSOrDisconnectStopEvidence() {
    XCTAssertFalse(NativeAutoTrackPolicy.shouldResumeStationaryWaitFromDrivingSignal(
      source: .gpsDwell,
      vehicleConnected: true
    ))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldResumeStationaryWaitFromDrivingSignal(
      source: .vehicleDisconnect,
      vehicleConnected: false
    ))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldResumeStationaryWaitFromDrivingSignal(
      source: .vehicleDisconnect,
      vehicleConnected: true
    ))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldResumeStationaryWaitFromDrivingSignal(
      source: .motion,
      vehicleConnected: false
    ))
  }

  func testStationarySignalsAreIgnoredWhenTheyCannotChangeTrackingState() {
    XCTAssertFalse(NativeAutoTrackPolicy.shouldProcessStationarySignal(
      during: .idle,
      vehicleStartArmed: false
    ))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldProcessStationarySignal(
      during: .idle,
      vehicleStartArmed: true
    ))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldProcessStationarySignal(
      during: .driving,
      vehicleStartArmed: false
    ))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldProcessStationarySignal(
      during: .stationaryPending,
      vehicleStartArmed: false
    ))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldProcessStationarySignal(
      during: .paused,
      vehicleStartArmed: false
    ))
  }

  func testDrivingAndStationaryTripsBothRequireContinuousLocationUpdates() {
    XCTAssertTrue(NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: .driving))
    XCTAssertTrue(NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: .stationaryPending))
    XCTAssertFalse(NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: .idle))
    XCTAssertFalse(NativeAutoTrackPolicy.requiresContinuousLocationUpdates(during: .paused))
  }

  func testConnectedVehicleWaitsForRealMovementBeforeStarting() {
    let now = Date()
    let origin = location(latitude: 51.5000, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(-20))
    let parked = location(latitude: 51.5001, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(-10))
    let speedWithoutDisplacement = location(
      latitude: 51.5001, longitude: -0.1200, accuracy: 8,
      timestamp: now.addingTimeInterval(-10), speed: 3.2
    )
    let movingByDisplacement = location(
      latitude: 51.5004, longitude: -0.1200, accuracy: 8,
      timestamp: now
    )
    let slowOrigin = location(latitude: 51.5000, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(-90))
    let slowMovement = location(
      latitude: 51.5004, longitude: -0.1200, accuracy: 8,
      timestamp: now, speed: -1
    )
    let inaccurateOrigin = location(latitude: 51.5000, longitude: -0.1200, accuracy: 30, timestamp: now.addingTimeInterval(-20))
    let inaccurateDrift = location(
      latitude: 51.5004, longitude: -0.1200, accuracy: 30,
      timestamp: now, speed: -1
    )

    XCTAssertFalse(NativeAutoTrackPolicy.shouldStartArmedVehicleTrip(origin: nil, current: parked))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldStartArmedVehicleTrip(origin: origin, current: parked))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldStartArmedVehicleTrip(origin: nil, current: speedWithoutDisplacement))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldStartArmedVehicleTrip(origin: origin, current: speedWithoutDisplacement))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldStartArmedVehicleTrip(origin: origin, current: movingByDisplacement))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldStartArmedVehicleTrip(origin: slowOrigin, current: slowMovement))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldStartArmedVehicleTrip(origin: inaccurateOrigin, current: inaccurateDrift))

    let bicycleMovement = location(
      latitude: 51.50027,
      longitude: -0.1200,
      accuracy: 5,
      timestamp: now
    )
    XCTAssertFalse(NativeAutoTrackPolicy.shouldStartArmedVehicleTrip(
      origin: origin,
      current: bicycleMovement,
      minimumDisplacement: NativeVehicle.car.automaticTrackingThresholds.vehicleStartDisplacementMeters
    ))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldStartArmedVehicleTrip(
      origin: origin,
      current: bicycleMovement,
      minimumDisplacement: NativeVehicle.bike.automaticTrackingThresholds.vehicleStartDisplacementMeters
    ))

    let initialLocations = NativeAutoTrackPolicy.armedTripInitialLocations(
      bufferedLocations: [movingByDisplacement, parked, origin]
    )
    XCTAssertEqual(initialLocations.count, 3)
    XCTAssertEqual(initialLocations.first?.timestamp, origin.timestamp)
    XCTAssertEqual(initialLocations.last?.timestamp, movingByDisplacement.timestamp)
  }

  func testDiagnosticsDiscardExpiredEventsAndRespectTheMaximumCount() {
    let now = Date()
    let events = [
      NativeAutoTrackDiagnosticEvent(timestamp: now.addingTimeInterval(-10), kind: "new", title: "Newest", detail: ""),
      NativeAutoTrackDiagnosticEvent(timestamp: now.addingTimeInterval(-20), kind: "middle", title: "Middle", detail: ""),
      NativeAutoTrackDiagnosticEvent(timestamp: now.addingTimeInterval(-30), kind: "older", title: "Older", detail: ""),
      NativeAutoTrackDiagnosticEvent(timestamp: now.addingTimeInterval(-8 * 24 * 60 * 60), kind: "expired", title: "Expired", detail: ""),
    ]

    let retained = NativeAutoTrackDiagnostics.retainedEvents(events, now: now, maximumCount: 2)

    XCTAssertEqual(retained.map(\.title), ["Newest", "Middle"])
  }

  func testPersistedDeadlinesKeepTheirAbsoluteFireDates() throws {
    let stationary = Date().addingTimeInterval(120)
    let home = Date().addingTimeInterval(300)
    let disconnect = Date().addingTimeInterval(60)
    let original = NativeAutoTrackDeadlines(
      stationary: stationary,
      homeArrival: home,
      vehicleDisconnect: disconnect
    )

    let restored = try JSONDecoder().decode(
      NativeAutoTrackDeadlines.self,
      from: JSONEncoder().encode(original)
    )

    XCTAssertEqual(restored, original)
  }

  func testSparseSamplesBreakTheRouteInsteadOfDrawingAcrossBlocks() {
    let now = Date()
    let previous = location(latitude: 51.5000, longitude: -0.1200, accuracy: 8, timestamp: now)
    let normal = location(latitude: 51.5002, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(10))
    let sparse = location(latitude: 51.5200, longitude: -0.1100, accuracy: 8, timestamp: now.addingTimeInterval(180))

    XCTAssertFalse(nativeRouteSegmentNeedsBreak(from: previous, to: normal))
    XCTAssertTrue(nativeRouteSegmentNeedsBreak(from: previous, to: sparse))
  }

  private func location(
    latitude: Double,
    longitude: Double,
    accuracy: CLLocationAccuracy,
    timestamp: Date,
    speed: CLLocationSpeed = -1
  ) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      altitude: 0,
      horizontalAccuracy: accuracy,
      verticalAccuracy: -1,
      course: -1,
      speed: speed,
      timestamp: timestamp
    )
  }
}


final class NativeICloudSyncMergeTests: XCTestCase {
  func testFreshLocalOnboardingDoesNotOverwriteRemoteProfile() {
    var localSettings = NativeSettings()
    localSettings.name = "iPad"
    localSettings.platforms = ["Uber Eats"]
    localSettings.hasCompletedOnboarding = true
    localSettings.iCloudSyncEnabled = true

    var remoteSettings = NativeSettings()
    remoteSettings.name = "Henry"
    remoteSettings.platforms = ["Deliveroo"]
    remoteSettings.hasCompletedOnboarding = true
    remoteSettings.iCloudSyncEnabled = true

    let merged = NativeICloudSnapshotMerge.merge(
      local: NativeSnapshot(settings: localSettings, records: [], trips: []),
      remote: NativeSnapshot(settings: remoteSettings, records: [record(amount: 24)], trips: [])
    )

    XCTAssertEqual(merged.settings.name, "Henry")
    XCTAssertEqual(merged.settings.platforms, ["Deliveroo", "Uber Eats"])
    XCTAssertTrue(merged.settings.iCloudSyncEnabled)
    XCTAssertEqual(merged.records.count, 1)
  }

  func testLocalProfileWinsWhenDeviceHasLocalActivity() {
    var localSettings = NativeSettings()
    localSettings.name = "iPad"
    localSettings.platforms = ["Uber Eats"]
    localSettings.hasCompletedOnboarding = true
    localSettings.iCloudSyncEnabled = true

    var remoteSettings = NativeSettings()
    remoteSettings.name = "Henry"
    remoteSettings.platforms = ["Deliveroo"]
    remoteSettings.hasCompletedOnboarding = true
    remoteSettings.iCloudSyncEnabled = true

    let merged = NativeICloudSnapshotMerge.merge(
      local: NativeSnapshot(settings: localSettings, records: [record(amount: 12)], trips: []),
      remote: NativeSnapshot(settings: remoteSettings, records: [record(amount: 24)], trips: [])
    )

    XCTAssertEqual(merged.settings.name, "iPad")
    XCTAssertEqual(merged.records.count, 2)
  }

  func testNewerRemoteRecordEditWins() {
    let changedAt = Date(timeIntervalSince1970: 2_000)
    var localRecord = record(amount: 12)
    localRecord.updatedAt = changedAt
    var remoteRecord = localRecord
    remoteRecord.amount = 24
    remoteRecord.updatedAt = changedAt.addingTimeInterval(60)

    let merged = NativeICloudSnapshotMerge.merge(
      local: NativeSnapshot(settings: NativeSettings(), records: [localRecord], trips: []),
      remote: NativeSnapshot(settings: NativeSettings(), records: [remoteRecord], trips: [])
    )

    XCTAssertEqual(merged.records.count, 1)
    XCTAssertEqual(merged.records.first?.amount, 24)
  }

  func testNewerLocalTripEditWins() {
    let changedAt = Date(timeIntervalSince1970: 3_000)
    var remoteTrip = trip(miles: 4)
    remoteTrip.updatedAt = changedAt
    var localTrip = remoteTrip
    localTrip.miles = 6
    localTrip.updatedAt = changedAt.addingTimeInterval(60)

    let merged = NativeICloudSnapshotMerge.merge(
      local: NativeSnapshot(settings: NativeSettings(), records: [], trips: [localTrip]),
      remote: NativeSnapshot(settings: NativeSettings(), records: [], trips: [remoteTrip])
    )

    XCTAssertEqual(merged.trips.count, 1)
    XCTAssertEqual(merged.trips.first?.miles, 6)
  }

  func testRecordDeletionTombstonePreventsRemoteResurrection() {
    var remoteRecord = record(amount: 24)
    remoteRecord.updatedAt = Date(timeIntervalSince1970: 4_000)
    let deletion = NativeDeletionTombstone(
      id: remoteRecord.id,
      deletedAt: Date(timeIntervalSince1970: 4_060)
    )

    let merged = NativeICloudSnapshotMerge.merge(
      local: NativeSnapshot(
        settings: NativeSettings(),
        records: [],
        trips: [],
        recordTombstones: [deletion]
      ),
      remote: NativeSnapshot(settings: NativeSettings(), records: [remoteRecord], trips: [])
    )

    XCTAssertTrue(merged.records.isEmpty)
    XCTAssertEqual(merged.recordTombstones, [deletion])
  }

  func testRemoteTripDeletionRemovesLocalTrip() {
    var localTrip = trip(miles: 4)
    localTrip.updatedAt = Date(timeIntervalSince1970: 5_000)
    let deletion = NativeDeletionTombstone(
      id: localTrip.id,
      deletedAt: Date(timeIntervalSince1970: 5_060)
    )

    let merged = NativeICloudSnapshotMerge.merge(
      local: NativeSnapshot(settings: NativeSettings(), records: [], trips: [localTrip]),
      remote: NativeSnapshot(
        settings: NativeSettings(),
        records: [],
        trips: [],
        tripTombstones: [deletion]
      )
    )

    XCTAssertTrue(merged.trips.isEmpty)
    XCTAssertEqual(merged.tripTombstones, [deletion])
  }

  func testNewerSettingsReplaceRemovedPlatforms() {
    var localSettings = NativeSettings()
    localSettings.platforms = ["Uber Eats", "Deliveroo"]
    var remoteSettings = localSettings
    remoteSettings.platforms = ["Uber Eats"]

    let merged = NativeICloudSnapshotMerge.merge(
      local: NativeSnapshot(
        settings: localSettings,
        records: [],
        trips: [],
        settingsUpdatedAt: Date(timeIntervalSince1970: 6_000)
      ),
      remote: NativeSnapshot(
        settings: remoteSettings,
        records: [],
        trips: [],
        settingsUpdatedAt: Date(timeIntervalSince1970: 6_060)
      )
    )

    XCTAssertEqual(merged.settings.platforms, ["Uber Eats"])
    XCTAssertEqual(merged.settingsUpdatedAt, Date(timeIntervalSince1970: 6_060))
  }

  func testSnapshotWithoutSyncMetadataStillDecodes() throws {
    let original = NativeSnapshot(
      settings: NativeSettings(),
      records: [record(amount: 10)],
      trips: [trip(miles: 2)]
    )
    let encoded = try JSONEncoder().encode(original)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json.removeValue(forKey: "settingsUpdatedAt")
    json.removeValue(forKey: "recordTombstones")
    json.removeValue(forKey: "tripTombstones")

    let decoded = try JSONDecoder().decode(
      NativeSnapshot.self,
      from: JSONSerialization.data(withJSONObject: json)
    )

    XCTAssertNil(decoded.settingsUpdatedAt)
    XCTAssertTrue(decoded.recordTombstones.isEmpty)
    XCTAssertTrue(decoded.tripTombstones.isEmpty)
    XCTAssertEqual(decoded.records.count, 1)
    XCTAssertEqual(decoded.trips.count, 1)
  }

  private func record(amount: Double) -> NativeRecord {
    NativeRecord(
      kind: .income,
      platform: "Uber Eats",
      vehicle: nil,
      amount: amount,
      miles: nil,
      deduction: nil,
      category: nil,
      date: Date(),
      period: .day,
      receiptImageData: nil
    )
  }

  private func trip(miles: Double) -> NativeTrip {
    let startedAt = Date(timeIntervalSince1970: 1_000)
    return NativeTrip(
      vehicle: .car,
      miles: miles,
      deduction: 0,
      startedAt: startedAt,
      endedAt: startedAt.addingTimeInterval(600),
      points: []
    )
  }
}
