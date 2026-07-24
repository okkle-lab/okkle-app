import XCTest
@testable import Okkle

final class USTaxCalculatorTests: XCTestCase {
  // A typical full-time gig driver: $40k gross, $10k expenses => $30k profit,
  // no W-2 wages, in a no-income-tax state (Texas).
  func testTypicalDriverNoStateTax() {
    let p = USTaxCalculator.estimate(turnover: 40_000, expenses: 10_000, state: .texas, otherStateRate: 0)
    XCTAssertEqual(p.businessProfit, 30_000, accuracy: 0.01)
    // SE tax = 30,000 * 0.9235 * 0.153 = 4,238.87
    XCTAssertEqual(p.class4, 4_238.87, accuracy: 1.0)
    XCTAssertEqual(p.stateTax, 0, accuracy: 0.01)
    // Federal income tax on the business (10% band after $16,100 standard
    // deduction and the QBI deduction).
    XCTAssertEqual(p.incomeTax, 942.45, accuracy: 1.5)
    // Total = federal + SE + state
    XCTAssertEqual(p.totalDue, 5_181.32, accuracy: 2.0)
    // Quarterly 1040-ES set-aside = total / 4
    XCTAssertEqual(p.paymentOnAccount, p.totalDue / 4, accuracy: 0.01)
    XCTAssertFalse(p.usesTradingAllowance)
  }

  func testSelfEmploymentTaxBasis() {
    // SE tax is on 92.35% of net profit at 15.3% below the SS wage base.
    XCTAssertEqual(USTaxCalculator.selfEmploymentTax(netProfit: 30_000), 4_238.865, accuracy: 0.5)
    XCTAssertEqual(USTaxCalculator.selfEmploymentTax(netProfit: 0), 0, accuracy: 0.01)
  }

  func testSocialSecurityWageBaseCaps() {
    // Above the 2025 SS wage base, only the 2.9% Medicare keeps applying to the
    // extra earnings — so the marginal SE rate drops.
    let low = USTaxCalculator.selfEmploymentTax(netProfit: 150_000)
    let high = USTaxCalculator.selfEmploymentTax(netProfit: 250_000)
    // The extra $100k of profit shouldn't add a full 15.3%.
    XCTAssertLessThan(high - low, 100_000 * 0.9235 * 0.153)
  }

  func testFlatStateTax() {
    // Illinois flat 4.95% on the profit (no wages).
    let il = USTaxCalculator.estimate(turnover: 40_000, expenses: 10_000, state: .illinois, otherStateRate: 0)
    XCTAssertEqual(il.stateTax, 30_000 * 0.0495, accuracy: 1.0)
  }

  func testCaliforniaBrackets() {
    // CA progressive brackets on $30k profit: 1% to 11,079, 2% to 26,264,
    // 4% above => 110.79 + 303.70 + 149.44 = 563.93
    let ca = USTaxCalculator.estimate(turnover: 40_000, expenses: 10_000, state: .california, otherStateRate: 0)
    XCTAssertEqual(ca.stateTax, 563.93, accuracy: 2.0)
  }

  func testManualStateRateForUnmodelledState() {
    // A state Okkle doesn't model yet: the driver's own flat rate is applied.
    let p = USTaxCalculator.estimate(turnover: 40_000, expenses: 10_000, state: .otherState, otherStateRate: 0.05)
    XCTAssertEqual(p.stateTax, 30_000 * 0.05, accuracy: 1.0)
  }

  func testQBIDeductionReducesFederalTax() {
    // With QBI the taxable income is lower, so federal tax is lower than a naive
    // (profit - standard deduction) * rate would give.
    let p = USTaxCalculator.estimate(turnover: 40_000, expenses: 10_000, state: .texas, otherStateRate: 0)
    XCTAssertGreaterThan(p.qbiDeduction, 0)
    XCTAssertEqual(p.standardDeduction, 16_100, accuracy: 0.01)
  }

  func testUSTaxYearIsCalendarYear() {
    let cal = Calendar(identifier: .gregorian)
    let july = cal.date(from: DateComponents(year: 2026, month: 7, day: 21))!
    let interval = USTaxCalculator.taxYearInterval(containing: july, calendar: cal)
    XCTAssertEqual(cal.component(.year, from: interval.start), 2026)
    XCTAssertEqual(cal.component(.month, from: interval.start), 1)
    XCTAssertEqual(cal.component(.day, from: interval.start), 1)
  }

  func testStandardMileageIsSingleFlatRateByDate() {
    let cal = Calendar(identifier: .gregorian)
    let in2025 = cal.date(from: DateComponents(year: 2025, month: 6, day: 1))!
    let early2026 = cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!
    let late2026 = cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!
    // No UK-style two-tier threshold, but the flat rate changes by date.
    XCTAssertEqual(USTaxCalculator.mileageDeduction(miles: 1_000, on: in2025), 700, accuracy: 0.01)     // 70¢
    XCTAssertEqual(USTaxCalculator.mileageDeduction(miles: 1_000, on: early2026), 725, accuracy: 0.01)  // 72.5¢
    XCTAssertEqual(USTaxCalculator.mileageDeduction(miles: 1_000, on: late2026), 760, accuracy: 0.01)   // 76¢
    // Still a single tier — 20k miles is just rate × miles, no threshold break.
    XCTAssertEqual(USTaxCalculator.mileageDeduction(miles: 20_000, on: in2025), 14_000, accuracy: 0.01)
  }

  // California's own estimated-tax schedule is 30/40/0/30, not four equal
  // 25% payments — confirmed against ftb.ca.gov/pay/estimated-tax-payments.html.
  // A California driver needs both the federal deadlines AND these.
  func testCaliforniaHasNonStandardEstimatedTaxDeadlines() {
    let deadlines = nativeTaxDeadlines(for: .us, usState: .california)
    let caDeadlines = deadlines.filter { $0.authority == "FTB" }
    XCTAssertEqual(caDeadlines.count, 3, "No September FTB payment — that share rolls into January.")
    XCTAssertTrue(caDeadlines.contains { $0.month == 4 && $0.day == 15 })
    XCTAssertTrue(caDeadlines.contains { $0.month == 6 && $0.day == 15 })
    XCTAssertTrue(caDeadlines.contains { $0.month == 1 && $0.day == 15 })
    XCTAssertFalse(caDeadlines.contains { $0.month == 9 })
    // Federal deadlines are still present and unaffected — CA owes both.
    XCTAssertTrue(deadlines.contains { $0.authority == "IRS" && $0.month == 9 && $0.day == 15 })
    // Two CA instalments share the same 30% headline — `id` must still be
    // unique per date, or SwiftUI's ForEach renders one row for both dates
    // (this exact bug shipped once already: the January entry displayed
    // April's date because both entries' `id` was `title` alone).
    XCTAssertEqual(Set(caDeadlines.map(\.id)).count, caDeadlines.count)
  }

  // New York (and Illinois/Pennsylvania/Georgia) follow the same four dates
  // and equal split as the IRS, but still need their own separate voucher.
  func testNewYorkAddsSeparateStateDeadlinesOnFederalDates() {
    let deadlines = nativeTaxDeadlines(for: .us, usState: .newYork)
    let nyDeadlines = deadlines.filter { $0.authority == "NY Tax Dept" }
    XCTAssertEqual(nyDeadlines.count, 4)
    let federalDates = Set(deadlines.filter { $0.authority == "IRS" && $0.title.hasPrefix("Q") }.map { "\($0.month)-\($0.day)" })
    let nyDates = Set(nyDeadlines.map { "\($0.month)-\($0.day)" })
    XCTAssertEqual(federalDates, nyDates)
  }

  // A no-income-tax state adds nothing beyond the federal calendar.
  func testNoIncomeTaxStateAddsNoExtraDeadlines() {
    let deadlines = nativeTaxDeadlines(for: .us, usState: .texas)
    XCTAssertTrue(deadlines.allSatisfy { $0.authority == "IRS" })
  }

  func testUSStateMatchingFromGeocodedPlacemark() {
    XCTAssertEqual(NativeUSState.matching(administrativeArea: "California"), .california)
    XCTAssertEqual(NativeUSState.matching(administrativeArea: "new york"), .newYork)
    XCTAssertEqual(NativeUSState.matching(administrativeArea: "CA"), .california)
    XCTAssertEqual(NativeUSState.matching(administrativeArea: " ny "), .newYork)
    XCTAssertEqual(NativeUSState.matching(administrativeArea: "Ohio"), .otherState)
    XCTAssertEqual(NativeUSState.matching(administrativeArea: nil), .otherState)
  }

  func testOnboardingLocationDetectionSelectsCountryAndLocalTaxArea() {
    let us = nativeOnboardingDetectedTaxLocation(
      isoCountryCode: "US",
      countryName: "United States",
      administrativeArea: "CA",
      subAdministrativeArea: "Santa Clara County"
    )
    XCTAssertEqual(us?.country, .us)
    XCTAssertEqual(us?.usState, .california)
    XCTAssertNil(us?.region)

    let scotland = nativeOnboardingDetectedTaxLocation(
      isoCountryCode: "GB",
      countryName: "United Kingdom",
      administrativeArea: "Scotland",
      subAdministrativeArea: "Glasgow City"
    )
    XCTAssertEqual(scotland?.country, .uk)
    XCTAssertEqual(scotland?.region, .scotland)
    XCTAssertNil(scotland?.usState)

    XCTAssertNil(nativeOnboardingDetectedTaxLocation(
      isoCountryCode: "CA",
      countryName: "Canada",
      administrativeArea: "Ontario",
      subAdministrativeArea: nil
    ))
  }
}
