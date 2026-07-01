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
