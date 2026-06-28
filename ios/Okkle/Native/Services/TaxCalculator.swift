import Foundation

struct NativeTaxPosition {
  var turnover: Double
  var expenses: Double
  var deductionApplied: Double
  var businessProfit: Double
  var profit: Double
  var incomeTax: Double
  var class4: Double
  var totalDue: Double
  var paymentOnAccount: Double
  var usesTradingAllowance: Bool
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

  static func estimate(turnover: Double, expenses: Double, region: NativeRegion, incomeBracket: NativeIncomeBracket) -> NativeTaxPosition {
    let tradingAllowance = 1_000.0
    let useTradingAllowance = tradingAllowance > expenses
    let deductible = min(turnover, useTradingAllowance ? tradingAllowance : expenses)
    let businessProfit = max(0, turnover - expenses)
    let profit = max(0, turnover - deductible)
    let otherIncome = incomeBracket.assumedOtherIncome(region: region)
    let incomeTax = incomeTax(income: otherIncome + profit, region: region) - incomeTax(income: otherIncome, region: region)
    let class4 = class4(profit: profit)
    let total = incomeTax + class4
    return NativeTaxPosition(
      turnover: turnover,
      expenses: expenses,
      deductionApplied: deductible,
      businessProfit: businessProfit,
      profit: profit,
      incomeTax: incomeTax,
      class4: class4,
      totalDue: total,
      paymentOnAccount: total > 1_000 ? total * 0.5 : 0,
      usesTradingAllowance: useTradingAllowance
    )
  }

  static func incomeTax(income: Double, region: NativeRegion) -> Double {
    let allowance = personalAllowance(for: income)
    let taxable = max(0, income - allowance)
    let bands: [(Double, Double)]
    switch region {
    case .ruk:
      bands = [(37_700, 0.20), (112_570, 0.40), (.infinity, 0.45)]
    case .scotland:
      bands = [(3_967, 0.19), (16_956, 0.20), (31_092, 0.21), (62_430, 0.42), (112_570, 0.45), (.infinity, 0.48)]
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
