import Foundation

struct NativeMileageLogRow {
  let date: Date
  let vehicle: NativeVehicle
  let source: String
  let miles: Double
  let deduction: Double
  let fromAddress: String?
  let toAddress: String?
}

struct NativeTaxPosition {
  var turnover: Double
  var expenses: Double
  var deductionApplied: Double
  var businessProfit: Double
  var profit: Double
  // UK: income tax on the self-employment profit. US: federal income tax on it.
  var incomeTax: Double
  // UK: Class 4 NIC. US: self-employment (Social Security + Medicare) tax.
  var class4: Double
  var totalDue: Double
  // UK: Payment on Account. US: suggested quarterly (1040-ES) set-aside.
  var paymentOnAccount: Double
  var usesTradingAllowance: Bool
  // US-only, defaulted so the UK path is unchanged.
  var stateTax: Double = 0
  var qbiDeduction: Double = 0
  var standardDeduction: Double = 0
}

enum TaxCalculator {
  static func taxYearInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
    let year = calendar.component(.year, from: date)
    let currentStart = calendar.date(from: DateComponents(year: year, month: 4, day: 6)) ?? date
    let start: Date
    let end: Date
    if date < currentStart {
      start = calendar.date(from: DateComponents(year: year - 1, month: 4, day: 6)) ?? currentStart
      end = currentStart
    } else {
      start = currentStart
      end = calendar.date(from: DateComponents(year: year + 1, month: 4, day: 6)) ?? date
    }
    return DateInterval(start: start, end: end)
  }

  static func periodBounds(for date: Date, period: NativePayPeriod, calendar: Calendar = .current) -> (start: Date, end: Date) {
    let day = calendar.startOfDay(for: date)
    switch period {
    case .day:
      return (day, day)
    case .week:
      let weekday = calendar.component(.weekday, from: day)
      let mondayOffset = weekday == 1 ? -6 : 2 - weekday
      let start = calendar.date(byAdding: .day, value: mondayOffset, to: day) ?? day
      let end = calendar.date(byAdding: .day, value: 6, to: start) ?? day
      return (start, end)
    }
  }

  static func mileageDeduction(miles: Double, vehicle: NativeVehicle, totalBefore: Double = 0, date: Date = Date()) -> Double {
    let threshold = 10_000.0
    let band = vehicle.rateBand(on: date)
    if totalBefore >= threshold { return miles * band.after }
    let first = max(0, min(miles, threshold - totalBefore))
    let second = max(0, miles - first)
    return first * band.first + second * band.after
  }

  static func estimate(turnover: Double, expenses: Double, region: NativeRegion, incomeBracket: NativeIncomeBracket, otherIncome: Double = 0) -> NativeTaxPosition {
    let tradingAllowance = 1_000.0
    let useTradingAllowance = tradingAllowance > expenses
    let deductible = min(turnover, useTradingAllowance ? tradingAllowance : expenses)
    let businessProfit = max(0, turnover - expenses)
    let profit = max(0, turnover - deductible)
    let otherIncome = max(0, otherIncome)
    let incomeTax = incomeTax(income: otherIncome + profit, region: region) - incomeTax(income: otherIncome, region: region)
    let class4 = class4(profit: profit)
    let total = incomeTax + class4
    let totalLiability = self.incomeTax(income: otherIncome + profit, region: region) + class4
    let taxAtSource = self.incomeTax(income: otherIncome, region: region)
    let collectedAtSourceShare = totalLiability > 0 ? taxAtSource / totalLiability : 0
    return NativeTaxPosition(
      turnover: turnover,
      expenses: expenses,
      deductionApplied: deductible,
      businessProfit: businessProfit,
      profit: profit,
      incomeTax: incomeTax,
      class4: class4,
      totalDue: total,
      paymentOnAccount: total > 1_000 && collectedAtSourceShare < 0.8 ? total * 0.5 : 0,
      usesTradingAllowance: useTradingAllowance
    )
  }

  static func incomeTax(income: Double, region: NativeRegion) -> Double {
    let allowance = personalAllowance(for: income)
    let taxable = max(0, income - allowance)
    // The additional-rate band starts at a fixed £125,140 of *gross* income.
    // Expressed in taxable terms that's 125,140 minus whatever allowance
    // actually applied — not a flat 112,570 (125,140 minus the standard,
    // un-tapered £12,570) — because by this income level (over £100,000)
    // the allowance itself is already partway or fully tapered away. Using a
    // fixed taxable cutoff here taxed a slice of income at 45% a little
    // early for anyone still in the £100,000-£125,140 tapering band.
    let additionalRateThreshold = 125_140.0 - allowance
    let bands: [(Double, Double)]
    switch region {
    case .ruk:
      bands = [(37_700, 0.20), (additionalRateThreshold, 0.40), (.infinity, 0.45)]
    case .scotland:
      bands = [(3_967, 0.19), (16_956, 0.20), (31_092, 0.21), (62_430, 0.42), (additionalRateThreshold, 0.45), (.infinity, 0.48)]
    }

    var tax = 0.0
    var previous = 0.0
    for band in bands {
      let slice = min(taxable, band.0) - previous
      if slice > 0 {
        tax += slice * band.1
        previous = min(taxable, band.0)
      }
      if taxable <= band.0 { break }
    }
    return max(0, tax)
  }

  static func personalAllowance(for income: Double) -> Double {
    let allowance = 12_570.0
    guard income > 100_000 else { return allowance }
    return max(0, allowance - ((income - 100_000) / 2))
  }

  static func class4(profit: Double) -> Double {
    guard profit > 12_570 else { return 0 }
    let main = min(profit, 50_270) - 12_570
    let upper = max(0, profit - 50_270)
    return main * 0.06 + upper * 0.02
  }
}

// MARK: - Work status (self-employed vs company)

/// Which flat mileage rate applies to a driver, by country and work status.
///
/// UK self-employed: HMRC simplified expenses covers cars, goods vehicles and
/// motorcycles only (GOV.UK, BIM75005) — there is no flat rate for bicycles, so
/// a self-employed cyclist claims actual costs. UK company: the company pays
/// the director Approved Mileage Allowance Payments (EIM31240), which do
/// include 20p for cycles. US: the IRS standard rate is defined for
/// "automobiles (including vans, pickups, or panel trucks)" only (Rev. Proc.
/// 2010-51 §3.01), so motorcycles and bicycles have no standard rate. A US
/// company reimburses at the same rate through an accountable plan.
enum NativeMileageRules {
  static func deduction(
    miles: Double,
    vehicle: NativeVehicle,
    totalBefore: Double = 0,
    date: Date,
    country: NativeTaxCountry,
    status: NativeWorkStatus,
    expenseMethod: NativeExpenseMethod
  ) -> Double {
    switch (country, status) {
    case (.uk, .selfEmployed):
      // Actual-cost drivers claim real receipts, and bicycles aren't covered
      // by the simplified rates at all.
      guard expenseMethod == .simplified, vehicle != .bike else { return 0 }
      return TaxCalculator.mileageDeduction(miles: miles, vehicle: vehicle, totalBefore: totalBefore, date: date)
    case (.uk, .company):
      // The expense method is a sole-trader choice; company mileage is always
      // paid at the approved rates.
      return TaxCalculator.mileageDeduction(miles: miles, vehicle: vehicle, totalBefore: totalBefore, date: date)
    case (.us, _):
      guard vehicle == .car || vehicle == .van else { return 0 }
      return USTaxCalculator.mileageDeduction(miles: miles, on: date)
    }
  }

  /// Whether a flat per-mile rate applies to this driver at all (as opposed to
  /// claiming actual costs).
  static func usesFlatRate(country: NativeTaxCountry, status: NativeWorkStatus, expenseMethod: NativeExpenseMethod) -> Bool {
    switch (country, status) {
    case (.uk, .selfEmployed): return expenseMethod == .simplified
    case (.uk, .company), (.us, _): return true
    }
  }

  /// Short plain-English reason a vehicle earns no mileage deduction, or nil
  /// when it does.
  static func noRateReason(
    vehicle: NativeVehicle,
    country: NativeTaxCountry,
    status: NativeWorkStatus,
    expenseMethod: NativeExpenseMethod
  ) -> String? {
    switch (country, status, vehicle) {
    case (.uk, .selfEmployed, .bike):
      return "No mileage rate for bicycles when self-employed. Claim actual costs instead."
    case (.us, _, .bike):
      return "The IRS has no mileage rate for bicycles."
    case (.us, _, .motorbike):
      return "The IRS standard rate only covers cars, vans and trucks. Claim actual costs instead."
    default:
      return nil
    }
  }
}

extension NativeSettings {
  var usesFlatMileageRate: Bool {
    NativeMileageRules.usesFlatRate(country: taxCountry, status: workStatus, expenseMethod: expenseMethod)
  }
}

extension TaxCalculator {
  /// UK corporation tax: 19% up to £50,000 of profit, 25% from £250,000, and
  /// marginal relief (3/200 of the gap below £250,000) in between. Assumes no
  /// associated companies and a 12-month accounting period.
  static func corporationTax(profit: Double) -> Double {
    guard profit > 0 else { return 0 }
    let smallLimit = 50_000.0
    let mainLimit = 250_000.0
    if profit <= smallLimit { return profit * 0.19 }
    if profit >= mainLimit { return profit * 0.25 }
    return profit * 0.25 - (mainLimit - profit) * 3 / 200
  }

  /// A limited company's position: corporation tax on profit after expenses
  /// (including mileage the company pays the director). Salary and dividends
  /// the director takes are not modelled.
  static func estimateCompany(turnover: Double, expenses: Double) -> NativeTaxPosition {
    let profit = max(0, turnover - expenses)
    let tax = corporationTax(profit: profit)
    return NativeTaxPosition(
      turnover: turnover,
      expenses: expenses,
      deductionApplied: min(turnover, expenses),
      businessProfit: profit,
      profit: profit,
      incomeTax: tax,
      class4: 0,
      totalDue: tax,
      paymentOnAccount: 0,
      usesTradingAllowance: false
    )
  }
}

/// What the Reports screens call each tax line, and which lines apply, for a
/// given country and work status.
struct NativeTaxPresentation: Equatable {
  var estimatesTax: Bool
  var headline: String
  var taxLabel: String
  var secondLabel: String?
  var paymentLabel: String?
  var otherIncomeLabel: String?
  var showsTradingAllowance: Bool
  var showsIncomeBand: Bool

  init(country: NativeTaxCountry, status: NativeWorkStatus) {
    switch (country, status) {
    case (.uk, .selfEmployed):
      estimatesTax = true
      headline = "Estimated tax due"
      taxLabel = "Income tax"
      secondLabel = "Class 4 NIC"
      paymentLabel = "Payment on account"
      otherIncomeLabel = "Other income"
      showsTradingAllowance = true
      showsIncomeBand = true
    case (.uk, .company):
      estimatesTax = true
      headline = "Estimated Corporation Tax"
      taxLabel = "Corporation tax"
      secondLabel = nil
      paymentLabel = nil
      otherIncomeLabel = nil
      showsTradingAllowance = false
      showsIncomeBand = false
    case (.us, .selfEmployed):
      estimatesTax = true
      headline = "Estimated tax due"
      taxLabel = "Federal income tax"
      secondLabel = "Self-employment tax"
      paymentLabel = "Quarterly set-aside"
      otherIncomeLabel = "W-2 wages"
      showsTradingAllowance = false
      showsIncomeBand = false
    case (.us, .company):
      estimatesTax = false
      headline = "Company tax not estimated"
      taxLabel = "Company tax"
      secondLabel = nil
      paymentLabel = nil
      otherIncomeLabel = nil
      showsTradingAllowance = false
      showsIncomeBand = false
    }
  }
}

extension OkkleStore {
  var taxPresentation: NativeTaxPresentation {
    NativeTaxPresentation(country: settings.taxCountry, status: settings.workStatus)
  }

  /// "Due" as shown on the Reports screen: the figure, or a plain word when
  /// the app doesn't estimate tax for this setup.
  var taxDueText: String {
    taxPresentation.estimatesTax ? gbp(taxPosition.totalDue) : "Not estimated"
  }
}
