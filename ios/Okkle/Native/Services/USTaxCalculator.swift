import Foundation

/// US self-employment tax engine — the American counterpart to `TaxCalculator`.
///
/// Scope (2.2 foundation): federal income tax, self-employment (SE) tax, the
/// standard deduction and the 20% QBI deduction, plus state income tax for the
/// five biggest gig markets (CA, NY, IL, PA, GA), the nine no-income-tax states
/// as a hard zero, and a manual flat rate for every other state.
///
/// Like the UK engine, figures are reported *incrementally*: the tax owed on the
/// driver's self-employment profit, stacked on top of any W-2 wages
/// (`otherIncome`) — so the driver sees what their gig work adds to their bill.
///
/// IMPORTANT: every rate table below is for the **2025 tax year, single filing
/// status**, and must be reviewed against official IRS / state sources before
/// each release. These are estimates to keep the driver organised, not tax
/// advice, and Okkle never files a return.
enum USTaxCalculator {
  // The US federal tax year is the calendar year.
  static func taxYearInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
    let year = calendar.component(.year, from: date)
    let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? date
    let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? date
    return DateInterval(start: start, end: end)
  }

  /// IRS standard mileage rate — a single rate per business mile with no
  /// UK-style 10,000-mile second tier. 2025: 70¢/mi.
  static let standardMileageRate = 0.70

  static func mileageDeduction(miles: Double) -> Double {
    max(0, miles) * standardMileageRate
  }

  // MARK: - Top-level estimate

  static func estimate(
    turnover: Double,
    expenses: Double,
    state: NativeUSState,
    otherStateRate: Double,
    wages: Double = 0
  ) -> NativeTaxPosition {
    let netProfit = max(0, turnover - expenses)
    let wages = max(0, wages)

    // 1. Self-employment tax (on 92.35% of net profit).
    let seTax = selfEmploymentTax(netProfit: netProfit)
    let seDeduction = seTax * 0.5   // half of SE tax is deductible from income

    // 2. Adjusted gross income, then taxable income after the standard
    //    deduction and the QBI deduction.
    let agiWithBusiness = wages + netProfit - seDeduction
    let taxableBeforeQBIWith = max(0, agiWithBusiness - standardDeduction)
    let qbiBase = max(0, netProfit - seDeduction)
    let qbiDeduction = min(0.20 * qbiBase, 0.20 * taxableBeforeQBIWith)
    let taxableWith = max(0, taxableBeforeQBIWith - qbiDeduction)

    // 3. Federal income tax attributable to the business — the increment over
    //    taxing wages alone (wages get no QBI deduction).
    let taxableWagesOnly = max(0, wages - standardDeduction)
    let federalWith = federalIncomeTax(taxable: taxableWith)
    let federalWithout = federalIncomeTax(taxable: taxableWagesOnly)
    let federalOnBusiness = max(0, federalWith - federalWithout)

    // 4. State income tax on the business profit (also incremental over wages).
    let stateWith = stateIncomeTax(taxable: max(0, wages + netProfit), state: state, otherStateRate: otherStateRate)
    let stateWithout = stateIncomeTax(taxable: wages, state: state, otherStateRate: otherStateRate)
    let stateOnBusiness = max(0, stateWith - stateWithout)

    let totalDue = federalOnBusiness + seTax + stateOnBusiness

    return NativeTaxPosition(
      turnover: turnover,
      expenses: expenses,
      deductionApplied: expenses,
      businessProfit: netProfit,
      profit: netProfit,
      incomeTax: federalOnBusiness,
      class4: seTax,
      totalDue: totalDue,
      // The IRS expects quarterly estimated payments; a quarter of the year's
      // liability is the simplest "set aside this each quarter" figure.
      paymentOnAccount: totalDue / 4,
      usesTradingAllowance: false,
      stateTax: stateOnBusiness,
      qbiDeduction: qbiDeduction,
      standardDeduction: standardDeduction
    )
  }

  // MARK: - Federal

  /// 2025 standard deduction, single filer.
  static let standardDeduction = 15_000.0

  /// 2025 federal self-employment tax: 12.4% Social Security up to the wage
  /// base, 2.9% Medicare on everything, plus the 0.9% Additional Medicare on
  /// net earnings over $200,000 (single) — all on 92.35% of net profit.
  static func selfEmploymentTax(netProfit: Double) -> Double {
    let netEarnings = max(0, netProfit) * 0.9235
    guard netEarnings > 0 else { return 0 }
    let socialSecurityWageBase = 176_100.0
    let socialSecurity = min(netEarnings, socialSecurityWageBase) * 0.124
    let medicare = netEarnings * 0.029
    let additionalMedicare = max(0, netEarnings - 200_000) * 0.009
    return socialSecurity + medicare + additionalMedicare
  }

  /// 2025 federal income tax, single filer, applied to taxable income.
  static func federalIncomeTax(taxable: Double) -> Double {
    let bands: [(upTo: Double, rate: Double)] = [
      (11_925, 0.10),
      (48_475, 0.12),
      (103_350, 0.22),
      (197_300, 0.24),
      (250_525, 0.32),
      (626_350, 0.35),
      (.infinity, 0.37),
    ]
    return progressiveTax(on: taxable, bands: bands)
  }

  // MARK: - State

  static func stateIncomeTax(taxable: Double, state: NativeUSState, otherStateRate: Double) -> Double {
    let income = max(0, taxable)
    guard income > 0 else { return 0 }
    if state.hasNoIncomeTax { return 0 }

    switch state {
    case .california:
      // 2025 single brackets (approximate — verify annually).
      return progressiveTax(on: income, bands: [
        (10_756, 0.01), (25_499, 0.02), (40_245, 0.04), (55_866, 0.06),
        (70_606, 0.08), (360_659, 0.093), (432_787, 0.103), (721_314, 0.113),
        (.infinity, 0.123),
      ])
    case .newYork:
      return progressiveTax(on: income, bands: [
        (8_500, 0.04), (11_700, 0.045), (13_900, 0.0525), (80_650, 0.055),
        (215_400, 0.06), (1_077_550, 0.0685), (5_000_000, 0.0965),
        (25_000_000, 0.103), (.infinity, 0.109),
      ])
    case .illinois:
      return income * 0.0495   // flat
    case .pennsylvania:
      return income * 0.0307   // flat
    case .georgia:
      return income * 0.0539   // 2024 flat rate; verify current year
    case .otherState:
      return income * max(0, min(otherStateRate, 0.15))
    default:
      return 0
    }
  }

  // MARK: - Shared

  private static func progressiveTax(on taxable: Double, bands: [(upTo: Double, rate: Double)]) -> Double {
    guard taxable > 0 else { return 0 }
    var tax = 0.0
    var previous = 0.0
    for band in bands {
      let slice = min(taxable, band.upTo) - previous
      if slice > 0 {
        tax += slice * band.rate
        previous = min(taxable, band.upTo)
      }
      if taxable <= band.upTo { break }
    }
    return max(0, tax)
  }
}
