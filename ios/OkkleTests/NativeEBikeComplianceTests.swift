import XCTest
@testable import Okkle

/// Electric bikes: a pedal-assist e-bike (250W, assistance cuts out at
/// 15.5 mph, pedals must drive it) is a bicycle; a faster or throttle-only
/// one is a motorcycle (GOV.UK "Electric bike rules"; HMRC EIM31240). HMRC's
/// simplified expenses cover cars, vans and motorcycles but not bicycles
/// (BIM75005), and the IRS standard rate covers cars and vans only
/// (Rev. Proc. 2010-51 §3.01).
final class NativeEBikeComplianceTests: XCTestCase {
  private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    return calendar
  }()

  /// After 6 April 2026, so the 55p car rate applies.
  private var date: Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
  }

  @MainActor
  private func store(_ country: NativeTaxCountry, method: NativeExpenseMethod = .simplified) -> OkkleStore {
    let store = OkkleStore()
    store.settings.taxCountry = country
    store.settings.expenseMethod = method
    return store
  }

  // MARK: UK

  @MainActor
  func testUKSelfEmployedPedalAssistEBikeAndBicycleHaveNoFlatRate() {
    XCTAssertEqual(store(.uk).calcDeduction(miles: 1_000, vehicle: .bike, date: date), 0)
  }

  @MainActor
  func testUKFastOrThrottleEBikeChosenAsMotorbikeUsesTheMotorcycleRate() {
    XCTAssertEqual(store(.uk).calcDeduction(miles: 1_000, vehicle: .motorbike, date: date), 240, accuracy: 0.001)
  }

  @MainActor
  func testUKMotorbikeRateDoesNotDropAfterTenThousandMiles() {
    XCTAssertEqual(store(.uk).calcDeduction(miles: 1_000, vehicle: .motorbike, totalBefore: 20_000, date: date), 240, accuracy: 0.001)
  }

  @MainActor
  func testUKCarAndVanKeepTheSimplifiedRates() {
    XCTAssertEqual(store(.uk).calcDeduction(miles: 1_000, vehicle: .car, date: date), 550, accuracy: 0.001)
    XCTAssertEqual(store(.uk).calcDeduction(miles: 1_000, vehicle: .van, date: date), 550, accuracy: 0.001)
  }

  @MainActor
  func testUKActualCostsMeansNoMileageRateForAnyVehicle() {
    let actual = store(.uk, method: .actualCost)
    for vehicle in NativeVehicle.allCases {
      XCTAssertEqual(actual.calcDeduction(miles: 1_000, vehicle: vehicle, date: date), 0)
    }
  }

  @MainActor
  func testBicycleTripsAddNothingToTheYearDeduction() {
    let carOnly = store(.uk)
    let recent = Date().addingTimeInterval(-3 * 86_400)
    carOnly.trips = [
      NativeTrip(vehicle: .car, miles: 100, deduction: 0, startedAt: recent, endedAt: recent.addingTimeInterval(3_600), points: [])
    ]
    let withBike = store(.uk)
    withBike.trips = carOnly.trips + [
      NativeTrip(vehicle: .bike, miles: 400, deduction: 0, startedAt: recent, endedAt: recent.addingTimeInterval(3_600), points: [])
    ]
    XCTAssertEqual(withBike.yearMileageDeduction, carOnly.yearMileageDeduction, accuracy: 0.001)
  }

  // MARK: US

  @MainActor
  func testUSStandardRateCoversCarsAndVansOnly() {
    let us = store(.us)
    XCTAssertEqual(us.calcDeduction(miles: 1_000, vehicle: .car, date: date), 760, accuracy: 0.001)
    XCTAssertEqual(us.calcDeduction(miles: 1_000, vehicle: .van, date: date), 760, accuracy: 0.001)
    XCTAssertEqual(us.calcDeduction(miles: 1_000, vehicle: .motorbike, date: date), 0)
    XCTAssertEqual(us.calcDeduction(miles: 1_000, vehicle: .bike, date: date), 0)
  }

  // MARK: Labels

  func testVehicleLabelsNameElectricBikes() {
    XCTAssertEqual(NativeVehicle.bike.label, "Bicycle / e-bike")
    XCTAssertEqual(NativeVehicle.motorbike.label, "Motorbike / moped")
  }

  func testUKHintsExplainWhichElectricBikeBelongsWhere() {
    XCTAssertEqual(NativeVehicle.bike.note(for: .uk), "Pedal-assist, up to 15.5 mph")
    XCTAssertEqual(NativeVehicle.motorbike.note(for: .uk), "Includes fast or throttle e-bikes")
    XCTAssertNil(NativeVehicle.car.note(for: .uk))
    XCTAssertNil(NativeVehicle.van.note(for: .uk))
  }

  func testUSHasNoUKSpecificEBikeHints() {
    for vehicle in NativeVehicle.allCases {
      XCTAssertNil(vehicle.note(for: .us))
    }
  }

  // MARK: Tracking still treats e-bikes sensibly

  func testPedalAssistEBikeUsesTheBicycleTrackingProfile() {
    XCTAssertEqual(NativeVehicle.bike.automaticTrackingProfile, .bicycle)
    XCTAssertEqual(NativeVehicle.motorbike.automaticTrackingProfile, .motorized)
  }

  // MARK: No-rate pop-up

  func testUKBicycleWarnsAndOffersTheMotorbikeSwitch() throws {
    let notice = try XCTUnwrap(NativeVehicle.bike.noRateNotice(country: .uk, expenseMethod: .simplified))
    XCTAssertEqual(notice.title, "No mileage rate for bicycles")
    XCTAssertTrue(notice.offersMotorbike)
    XCTAssertTrue(notice.message.contains("throttle"))
  }

  func testNoBicycleWarningWhenClaimingActualCostsAnyway() {
    XCTAssertNil(NativeVehicle.bike.noRateNotice(country: .uk, expenseMethod: .actualCost))
  }

  func testUSWarnsForBicyclesAndMotorbikesWithoutAMotorbikeSwitch() throws {
    let bicycle = try XCTUnwrap(NativeVehicle.bike.noRateNotice(country: .us, expenseMethod: .simplified))
    XCTAssertFalse(bicycle.offersMotorbike)
    let motorbike = try XCTUnwrap(NativeVehicle.motorbike.noRateNotice(country: .us, expenseMethod: .simplified))
    XCTAssertFalse(motorbike.offersMotorbike)
  }

  func testNoWarningForVehiclesThatEarnARate() {
    XCTAssertNil(NativeVehicle.car.noRateNotice(country: .uk, expenseMethod: .simplified))
    XCTAssertNil(NativeVehicle.van.noRateNotice(country: .uk, expenseMethod: .simplified))
    XCTAssertNil(NativeVehicle.motorbike.noRateNotice(country: .uk, expenseMethod: .simplified))
    XCTAssertNil(NativeVehicle.car.noRateNotice(country: .us, expenseMethod: .simplified))
    XCTAssertNil(NativeVehicle.van.noRateNotice(country: .us, expenseMethod: .simplified))
  }

  /// The pop-up and the deduction must never disagree: a vehicle earns no
  /// flat rate exactly when the app warns about it.
  @MainActor
  func testWarningMatchesTheDeductionForEveryVehicle() {
    for country in NativeTaxCountry.allCases {
      let s = store(country)
      for vehicle in NativeVehicle.allCases {
        let earnsNothing = s.calcDeduction(miles: 100, vehicle: vehicle, date: date) == 0
        let warns = vehicle.noRateNotice(country: country, expenseMethod: .simplified) != nil
        XCTAssertEqual(earnsNothing, warns, "\(country) \(vehicle)")
      }
    }
  }
}
