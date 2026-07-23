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
    // Federal income tax on the business (10% band after $15,750 standard
    // deduction and the QBI deduction).
    XCTAssertEqual(p.incomeTax, 970.45, accuracy: 1.5)
    // Total = federal + SE + state
    XCTAssertEqual(p.totalDue, 5_209.31, accuracy: 2.0)
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
    // CA progressive brackets on $30k profit: 1% to 10,756, 2% to 25,499,
    // 4% above => 107.56 + 294.86 + 180.04 = 582.46
    let ca = USTaxCalculator.estimate(turnover: 40_000, expenses: 10_000, state: .california, otherStateRate: 0)
    XCTAssertEqual(ca.stateTax, 582.46, accuracy: 2.0)
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
    XCTAssertEqual(p.standardDeduction, 15_750, accuracy: 0.01)
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
}
