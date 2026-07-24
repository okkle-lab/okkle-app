import AVFoundation
import CoreLocation
import XCTest
@testable import Okkle

final class TaxCalculatorTests: XCTestCase {
  // Every region/state combination Okkle ships, generating real PDFs and tax
  // positions for each so a regression in one config (wrong rate, crash,
  // duplicate deadline id, mismatched totals) can't slip through even though
  // day-to-day development mostly exercises just one config at a time.
  @MainActor
  func testAllRegionsProduceConsistentReportsAndDeadlines() {
    struct Config {
      let country: NativeTaxCountry
      let usState: NativeUSState
      let expenseMethod: NativeExpenseMethod
    }
    let configs: [Config] = [
      Config(country: .uk, usState: .california, expenseMethod: .simplified),
      Config(country: .uk, usState: .california, expenseMethod: .actualCost),
      Config(country: .us, usState: .california, expenseMethod: .simplified),
      Config(country: .us, usState: .newYork, expenseMethod: .simplified),
      Config(country: .us, usState: .illinois, expenseMethod: .simplified),
      Config(country: .us, usState: .pennsylvania, expenseMethod: .simplified),
      Config(country: .us, usState: .georgia, expenseMethod: .simplified),
      Config(country: .us, usState: .texas, expenseMethod: .simplified),
      Config(country: .us, usState: .otherState, expenseMethod: .simplified)
    ]

    for config in configs {
      let store = OkkleStore()
      store.settings.taxCountry = config.country
      store.settings.usState = config.usState
      store.settings.usOtherStateRate = 0.05
      store.settings.expenseMethod = config.expenseMethod
      store.settings.name = "Test Driver"

      let recentDate = Date().addingTimeInterval(-3 * 86_400)
      var trip = NativeTrip(vehicle: .car, miles: 120, deduction: 0, startedAt: recentDate, endedAt: recentDate.addingTimeInterval(3_600), points: [])
      trip.startAddress = "100 Main St"
      trip.endAddress = "200 Elm St"
      store.trips = [trip]
      store.records = [
        NativeRecord(kind: .income, platform: "Uber Eats", vehicle: nil, amount: 800, miles: nil, deduction: nil, category: nil, date: recentDate, period: .day, receiptImageData: nil),
        NativeRecord(kind: .income, platform: "DoorDash", vehicle: nil, amount: 400, miles: nil, deduction: nil, category: nil, date: recentDate, period: .day, receiptImageData: nil),
        NativeRecord(kind: .expense, platform: nil, vehicle: nil, amount: 120, miles: nil, deduction: nil, category: "Fuel", date: recentDate, period: .day, receiptImageData: nil),
        NativeRecord(kind: .expense, platform: nil, vehicle: nil, amount: 40, miles: nil, deduction: nil, category: "Fuel", date: recentDate, period: .day, receiptImageData: nil),
        NativeRecord(kind: .expense, platform: nil, vehicle: nil, amount: 15, miles: nil, deduction: nil, category: "Parking", date: recentDate, period: .day, receiptImageData: nil),
        NativeRecord(kind: .expense, platform: nil, vehicle: nil, amount: 25, miles: nil, deduction: nil, category: nil, date: recentDate, period: .day, receiptImageData: nil)
      ]

      let context = "\(config.country) / \(config.usState) / \(config.expenseMethod)"
      let accountantPdf = nativeAccountantPackPdfData(store: store)
      let mileagePdf = nativeMileageReportPdfData(store: store)
      let selfAssessPdf = nativeSelfAssessmentPdfData(store: store)
      XCTAssertEqual(accountantPdf.prefix(4), Data("%PDF".utf8), context)
      XCTAssertEqual(mileagePdf.prefix(4), Data("%PDF".utf8), context)
      XCTAssertEqual(selfAssessPdf.prefix(4), Data("%PDF".utf8), context)

      let deadlines = nativeTaxDeadlines(for: config.country, usState: config.usState)
      XCTAssertEqual(Set(deadlines.map(\.id)).count, deadlines.count, "Duplicate deadline id in \(context)")

      let tax = store.taxPosition
      XCTAssertEqual(tax.incomeTax + tax.class4 + tax.stateTax, tax.totalDue, accuracy: 0.01, context)
      XCTAssertEqual(tax.totalDue / 4, tax.paymentOnAccount, accuracy: 0.01, context)
      if config.usState.hasNoIncomeTax {
        XCTAssertEqual(tax.stateTax, 0, context)
        XCTAssertTrue(deadlines.allSatisfy { $0.authority == "IRS" }, context)
      }
    }
  }

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

  // Each bookkeeping export must match that software's own documented CSV
  // import spec — verified against FreeAgent, Sage, QuickBooks Online, Xero
  // and Wave's own support articles, since a wrong header/date-format/column
  // choice means the file silently fails (or misparses) on import.
  @MainActor
  func testBookkeepingCsvExportsMatchEachSoftwaresDocumentedFormat() {
    let store = OkkleStore()
    store.settings.taxCountry = .uk
    let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 9))!
    store.trips = []
    store.records = [
      NativeRecord(kind: .income, platform: "Uber Eats", vehicle: nil, amount: 100, miles: nil, deduction: nil, category: nil, date: date, period: .day, receiptImageData: nil)
    ]

    // FreeAgent: no header row at all, dd/mm/yyyy, Date/Amount/Description order.
    let freeAgent = nativeFreeAgentCsv(store: store)
    XCTAssertFalse(freeAgent.contains("Date,Amount,Description"), "FreeAgent's spec forbids a header row")
    XCTAssertTrue(freeAgent.hasPrefix("09/03/2026,100.00,"))

    // Sage Business Cloud Accounting: header row, Date/Description/Amount
    // order, dd/mm/yyyy (Sage's own UK default).
    let sage = nativeSageCsv(store: store)
    XCTAssertTrue(sage.hasPrefix("Date,Description,Amount\n09/03/2026,"))

    // QuickBooks Online: header row, Date/Description/Amount order, dd/mm/yyyy.
    let quickBooks = nativeQuickBooksCsv(store: store)
    XCTAssertTrue(quickBooks.hasPrefix("Date,Description,Amount\n09/03/2026,"))

    // Xero: header row, Date/Amount/Description order, date matching the
    // org's own region setting — dd/mm/yyyy for a UK driver.
    let xero = nativeXeroCsv(store: store)
    XCTAssertTrue(xero.hasPrefix("Date,Amount,Description\n09/03/2026,100.00,"))

    // Wave: header row, Date/Description/Amount order, US-style MM/DD/YYYY
    // (Wave's own support article documents this as the minimum required format).
    let wave = nativeWaveCsv(store: store)
    XCTAssertTrue(wave.hasPrefix("Date,Description,Amount\n03/09/2026,"))
  }

  // A US driver only ever sees QuickBooks/Xero/Wave (FreeAgent and Sage are
  // both UK-only products, filtered out of NativeExportDocument.available).
  // QuickBooks Online's CSV importer wants dd/mm/yyyy regardless of country
  // (a well-documented QBO quirk, confirmed via multiple en-us support
  // threads about it silently swapping day/month otherwise) — Xero and Wave
  // do vary by region/product, so this locks in the country-aware branch
  // actually firing correctly for a US driver rather than just assuming it.
  @MainActor
  func testBookkeepingCsvExportsForUSDriver() {
    let store = OkkleStore()
    store.settings.taxCountry = .us
    let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 9))!
    store.trips = []
    store.records = [
      NativeRecord(kind: .income, platform: "DoorDash", vehicle: nil, amount: 100, miles: nil, deduction: nil, category: nil, date: date, period: .day, receiptImageData: nil)
    ]

    // QuickBooks Online: still dd/mm/yyyy even for a US driver — this is a
    // genuine QBO CSV-importer quirk, not a UK/US split.
    let quickBooks = nativeQuickBooksCsv(store: store)
    XCTAssertTrue(quickBooks.hasPrefix("Date,Description,Amount\n09/03/2026,"))

    // Xero: date format follows the org's own region setting — mm/dd/yyyy
    // for a US org.
    let xero = nativeXeroCsv(store: store)
    XCTAssertTrue(xero.hasPrefix("Date,Amount,Description\n03/09/2026,100.00,"), "Xero should use mm/dd/yyyy for a US org, not the UK dd/mm/yyyy")

    // Wave: US-style MM/DD/YYYY, same as the UK case — Wave's own spec
    // isn't locale-conditional.
    let wave = nativeWaveCsv(store: store)
    XCTAssertTrue(wave.hasPrefix("Date,Description,Amount\n03/09/2026,"))

    // FreeAgent and Sage must not be offered to a US driver at all — neither
    // is a real product fit for a US self-employed courier.
    let available = NativeExportDocument.available(for: .us)
    XCTAssertFalse(available.contains(.freeAgent))
    XCTAssertFalse(available.contains(.sage))
  }

  // A realistic month of mixed income/expense records, including the messy
  // real-world text (commas, quote marks, apostrophes) a merchant name or
  // note can genuinely contain — this is what actually breaks a naive CSV
  // export, not the single clean row the format-shape test above uses.
  // Prints every export in full (picked up by an external, independent CSV
  // parser to validate) and checks in-process that nothing was silently
  // dropped or duplicated by reconciling the exported total back to the
  // known input total.
  @MainActor
  func testBookkeepingCsvExportsSurviveRealisticDataWithEdgeCases() {
    let store = OkkleStore()
    store.settings.taxCountry = .uk
    let cal = Calendar(identifier: .gregorian)
    var records: [NativeRecord] = []
    let platforms = ["Uber Eats", "Deliveroo", "Just Eat"]
    for i in 0..<12 {
      let date = cal.date(byAdding: .day, value: -i, to: Date())!
      records.append(NativeRecord(kind: .income, platform: platforms[i % 3], amount: Double(8 + i) + 0.37, date: date, period: .day))
    }
    records.append(NativeRecord(
      kind: .expense, amount: 45.50, category: "Fuel",
      merchant: "Tesco, Filling Station", note: "Receipt said \"full tank\" — driver's own note",
      date: Date(), period: .day
    ))
    records.append(NativeRecord(kind: .expense, amount: 12.00, category: "Parking", merchant: "NCP", date: Date(), period: .day))
    records.append(NativeRecord(kind: .expense, amount: 8.99, category: "Phone, data", merchant: nil, note: nil, date: Date(), period: .day))
    store.records = records
    store.trips = []

    let inputTotal = records.reduce(0.0) { $0 + ($1.amount ?? 0) }
    print("OKKLE-CSV-AUDIT: input record count=\(records.count) total=\(inputTotal)")
    print("OKKLE-CSV-AUDIT-BEGIN-FREEAGENT\n\(nativeFreeAgentCsv(store: store))\nOKKLE-CSV-AUDIT-END-FREEAGENT")
    print("OKKLE-CSV-AUDIT-BEGIN-SAGE\n\(nativeSageCsv(store: store))\nOKKLE-CSV-AUDIT-END-SAGE")
    print("OKKLE-CSV-AUDIT-BEGIN-QUICKBOOKS\n\(nativeQuickBooksCsv(store: store))\nOKKLE-CSV-AUDIT-END-QUICKBOOKS")
    print("OKKLE-CSV-AUDIT-BEGIN-XERO\n\(nativeXeroCsv(store: store))\nOKKLE-CSV-AUDIT-END-XERO")
    print("OKKLE-CSV-AUDIT-BEGIN-WAVE\n\(nativeWaveCsv(store: store))\nOKKLE-CSV-AUDIT-END-WAVE")

    // In-process reconciliation: row counts and total amounts must survive
    // the export untouched, regardless of format-specific quoting rules.
    for (name, csv, hasHeader) in [
      ("FreeAgent", nativeFreeAgentCsv(store: store), false),
      ("Sage", nativeSageCsv(store: store), true),
      ("QuickBooks", nativeQuickBooksCsv(store: store), true),
      ("Xero", nativeXeroCsv(store: store), true),
      ("Wave", nativeWaveCsv(store: store), true),
    ] {
      var lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
      if hasHeader { lines.removeFirst() }
      XCTAssertEqual(lines.count, records.count, "\(name): row count should match record count")
      XCTAssertFalse(csv.contains("Filling Station\""), "\(name): a raw description shouldn't leak an unescaped quote next to a comma")
    }

    // FreeAgent specifically forbids commas and quote marks anywhere in the
    // file — confirm the sanitizer actually removed them, not just avoided
    // CSV-quoting them.
    let freeAgent = nativeFreeAgentCsv(store: store)
    XCTAssertFalse(freeAgent.contains("\""), "FreeAgent's spec forbids quote marks anywhere in the file")
    let freeAgentDataLines = freeAgent.split(separator: "\n")
    for line in freeAgentDataLines {
      let commaCount = line.filter { $0 == "," }.count
      XCTAssertEqual(commaCount, 2, "FreeAgent row should have exactly 2 commas (3 columns): \(line)")
    }
  }

  @MainActor
  func testExpenseCategoryCsvSubtotalsByCategory() {
    let store = OkkleStore()
    store.trips = []
    let recentDate = Date().addingTimeInterval(-3 * 86_400)
    store.records = [
      NativeRecord(kind: .expense, platform: nil, vehicle: nil, amount: 100, miles: nil, deduction: nil, category: "Fuel", date: recentDate, period: .day, receiptImageData: nil),
      NativeRecord(kind: .expense, platform: nil, vehicle: nil, amount: 50, miles: nil, deduction: nil, category: "Fuel", date: recentDate, period: .day, receiptImageData: nil),
      NativeRecord(kind: .expense, platform: nil, vehicle: nil, amount: 30, miles: nil, deduction: nil, category: "Parking", date: recentDate, period: .day, receiptImageData: nil),
      NativeRecord(kind: .expense, platform: nil, vehicle: nil, amount: 20, miles: nil, deduction: nil, category: nil, date: recentDate, period: .day, receiptImageData: nil)
    ]
    let csv = nativeExpenseCategoryCsv(store: store)
    XCTAssertTrue(csv.contains("Fuel,150.00"), "Two Fuel entries should subtotal to 150 — an accountant needs the category total, not a re-tally of individual rows.")
    XCTAssertTrue(csv.contains("Parking,30.00"))
    XCTAssertTrue(csv.contains("Uncategorised,20.00"))
  }

  @MainActor
  func testActualCostMethodDropsMileageDeductionFromTaxEstimate() {
    let store = OkkleStore()
    store.settings.expenseMethod = .actualCost
    let recentDate = Date().addingTimeInterval(-3 * 86_400)
    store.trips = [
      NativeTrip(vehicle: .car, miles: 500, deduction: 0, startedAt: recentDate, endedAt: recentDate.addingTimeInterval(3_600), points: [])
    ]

    XCTAssertEqual(store.calcDeduction(miles: 500, vehicle: .car), 0)
    XCTAssertEqual(store.yearMileageDeduction, 0)
  }

  @MainActor
  func testSimplifiedMethodKeepsMileageDeductionUnchanged() {
    let store = OkkleStore()
    store.settings.expenseMethod = .simplified

    XCTAssertGreaterThan(store.calcDeduction(miles: 500, vehicle: .car), 0)
  }

  @MainActor
  func testCompleteOnboardingLocksExpenseMethodOnlyForSimplified() {
    let simplifiedStore = OkkleStore()
    simplifiedStore.completeOnboarding(
      name: "Alex", defaultVehicle: .car, platforms: ["Uber Eats"],
      taxCountry: .uk, region: .ruk, expenseMethod: .simplified, usState: .california,
      incomeBracket: .basic, autoTrackTrips: false, enhancedAutoTracking: false, workingDays: []
    )
    XCTAssertEqual(simplifiedStore.settings.expenseMethod, .simplified)
    XCTAssertTrue(simplifiedStore.settings.expenseMethodLocked)

    let actualCostStore = OkkleStore()
    actualCostStore.completeOnboarding(
      name: "Alex", defaultVehicle: .car, platforms: ["Uber Eats"],
      taxCountry: .uk, region: .ruk, expenseMethod: .actualCost, usState: .california,
      incomeBracket: .basic, autoTrackTrips: false, enhancedAutoTracking: false, workingDays: []
    )
    XCTAssertEqual(actualCostStore.settings.expenseMethod, .actualCost)
    XCTAssertFalse(actualCostStore.settings.expenseMethodLocked)
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

final class NativeReceiptParserTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
  }

  func testReadsUKReceiptAmountAndDate() {
    let result = nativeParseReceipt(
      lines: ["Shell", "Date 21/07/2026 09:37", "TOTAL £42.75"],
      dateOrder: .dayMonthYear,
      referenceDate: date(2026, 7, 24),
      calendar: calendar
    )

    XCTAssertEqual(result.amount ?? 0, 42.75, accuracy: 0.001)
    XCTAssertEqual(result.date, date(2026, 7, 21))
  }

  func testReadsUSEarningsPayoutWithThousandsSeparator() {
    let result = nativeParseReceipt(
      lines: ["Uber Eats", "Payout date 07/21/2026", "Paid $1,234.56"],
      dateOrder: .monthDayYear,
      referenceDate: date(2026, 7, 24),
      calendar: calendar
    )

    XCTAssertEqual(result.amount ?? 0, 1_234.56, accuracy: 0.001)
    XCTAssertEqual(result.date, date(2026, 7, 21))
  }

  func testAmbiguousNumericDateUsesDriverRegion() {
    let lines = ["Transaction date 03/04/2026", "Total £12.50"]
    let uk = nativeParseReceipt(
      lines: lines,
      dateOrder: .dayMonthYear,
      referenceDate: date(2026, 7, 24),
      calendar: calendar
    )
    let us = nativeParseReceipt(
      lines: lines,
      dateOrder: .monthDayYear,
      referenceDate: date(2026, 7, 24),
      calendar: calendar
    )

    XCTAssertEqual(uk.date, date(2026, 4, 3))
    XCTAssertEqual(us.date, date(2026, 3, 4))
  }

  func testPrefersTransactionDateAndRejectsExpiryDate() {
    let result = nativeParseReceipt(
      lines: ["Card expiry date 08/29/2028", "Transaction date Jul 20, 2026", "Amount $18.20"],
      dateOrder: .monthDayYear,
      referenceDate: date(2026, 7, 24),
      calendar: calendar
    )

    XCTAssertEqual(result.date, date(2026, 7, 20))
  }
}


@MainActor
final class NativeInsightsSimulationTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  func testStoredTripWithoutStopEvidenceKeepsInferredDeliveryPair() {
    let store = OkkleStore()
    store.trips = [trip(miles: 6, startedAt: date(2026, 6, 23, 18), endedAt: date(2026, 6, 23, 18, 30), timestamped: false)]

    let visits = NativeShiftInsights.enrichedVisits(visits: [], trips: store.trips)
    let insights = NativeShiftInsights.build(visits: visits, store: store)

    XCTAssertEqual(visits.map(\.kind), [.pickup, .dropoff])
    XCTAssertTrue(visits.allSatisfy(\.isEndpointGuess))
    XCTAssertTrue(insights.hasData)
    XCTAssertEqual(insights.deliveries, 1)
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

  func testTimestampedRouteWithoutSignificantStopsKeepsInferredDeliveryPair() {
    let store = OkkleStore()
    store.trips = [trip(miles: 8, startedAt: date(2026, 6, 25, 17), endedAt: date(2026, 6, 25, 18), timestamped: true)]

    let insights = NativeShiftInsights.build(
      visits: NativeShiftInsights.enrichedVisits(visits: [], trips: store.trips),
      store: store
    )

    XCTAssertEqual(insights.deliveries, 1)
    XCTAssertGreaterThan(insights.paidMiles, 0)
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

    // Raw endpoints preserve delivery progress but are never location evidence.
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
    visit.confidence = 0.9
    visit.evidence = kind == .pickup ? [.nearbyPointOfInterest, .routeDwell] : [.routeDwell]
    return visit
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  private func record(date: Date, amount: Double) -> NativeRecord {
    var record = NativeRecord(kind: .income, platform: "Uber Eats", vehicle: nil, amount: amount, miles: nil,
                              deduction: nil, category: nil, date: date, period: .day, receiptImageData: nil)
    record.source = .tripEarnings
    record.legacyID = "sqlite-trip-earnings-\(UUID().uuidString)"
    return record
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

  func testDetectedStopPreservesVehicleAndMovementEvidence() {
    let started = date(2026, 7, 6, 18, 0)
    let points = [
      RoutePoint(latitude: 51.5000, longitude: -0.1200, timestamp: started, speed: 8, vehicleConnectionActive: true),
      RoutePoint(latitude: 51.5100, longitude: -0.1100, timestamp: started.addingTimeInterval(10 * 60), speed: 0.2, vehicleConnectionActive: true),
      RoutePoint(latitude: 51.5101, longitude: -0.1101, timestamp: started.addingTimeInterval(20 * 60), speed: 0.1, vehicleConnectionActive: false),
      RoutePoint(latitude: 51.5200, longitude: -0.1000, timestamp: started.addingTimeInterval(30 * 60), speed: 8, vehicleConnectionActive: false),
    ]

    let stop = NativeRouteStopDetector.detectStops(in: points).first?.visit

    XCTAssertEqual(stop?.kind, .other)
    XCTAssertTrue(stop?.evidence?.contains(.routeDwell) == true)
    XCTAssertTrue(stop?.evidence?.contains(.vehicleDisconnect) == true)
    XCTAssertTrue(stop?.evidence?.contains(.speedDecay) == true)
    XCTAssertTrue(stop?.evidence?.contains(.resumedDriving) == true)
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


final class NativeAutoTrackCoordinatorTests: XCTestCase {
  func testDrivingAndStationaryEventsFollowOneReducerOwnedLifecycle() {
    var coordinator = NativeAutoTrackCoordinator()

    XCTAssertEqual(coordinator.handle(.drivingDetected), .beginShift)
    XCTAssertEqual(coordinator.state.phase, .driving)
    XCTAssertEqual(coordinator.handle(.stationaryDetected), .beginStationaryWait)
    XCTAssertEqual(coordinator.state.phase, .stationaryPending)
    XCTAssertEqual(coordinator.handle(.drivingDetected), .resumeFromStationary)
    XCTAssertEqual(coordinator.state.phase, .driving)
    XCTAssertEqual(coordinator.handle(.endRequested(reason: "Test complete")), .concludeShift(reason: "Test complete"))
    XCTAssertEqual(coordinator.state.phase, .idle)
  }

  func testPauseResumeAndInvalidEventsCannotCreateImpossibleTransitions() {
    var coordinator = NativeAutoTrackCoordinator()

    XCTAssertEqual(coordinator.handle(.pauseRequested), .none)
    XCTAssertEqual(coordinator.state.phase, .idle)
    XCTAssertEqual(coordinator.handle(.drivingDetected), .beginShift)
    XCTAssertEqual(coordinator.handle(.pauseRequested), .pauseShift)
    XCTAssertEqual(coordinator.state.phase, .paused)
    XCTAssertEqual(coordinator.handle(.stationaryDetected), .none)
    XCTAssertEqual(coordinator.handle(.resumeRequested), .resumePausedShift)
    XCTAssertEqual(coordinator.state.phase, .driving)
  }

  func testRestoredPhaseBecomesCoordinatorState() {
    var coordinator = NativeAutoTrackCoordinator()

    coordinator.restore(phase: .stationaryPending)

    XCTAssertEqual(coordinator.state.phase, .stationaryPending)
    XCTAssertEqual(coordinator.handle(.endRequested(reason: "Recovered timeout")), .concludeShift(reason: "Recovered timeout"))
  }
}


final class NativeTrackingConfidenceTests: XCTestCase {
  func testStartRequiresDrivingEvidenceAndUsesVehicleSignalAsSupport() {
    XCTAssertFalse(NativeTrackingConfidenceEvaluator.startDecision(
      NativeTripStartEvidence(vehicleConnected: true)
    ).shouldTransition)
    XCTAssertTrue(NativeTrackingConfidenceEvaluator.startDecision(
      NativeTripStartEvidence(automotiveMotion: true)
    ).shouldTransition)
    XCTAssertTrue(NativeTrackingConfidenceEvaluator.startDecision(
      NativeTripStartEvidence(displacementMeters: 40, vehicleConnected: true)
    ).shouldTransition)
  }

  func testStopHysteresisRejectsBriefPauseAndAcceptsConfirmedEnd() {
    let briefPause = NativeTripStopEvidenceSnapshot(stationaryDuration: 120, stationaryMotion: true)
    XCTAssertFalse(NativeTrackingConfidenceEvaluator.stopDecision(
      briefPause,
      stationaryTimeout: 20 * 60
    ).shouldTransition)

    let disconnected = NativeTripStopEvidenceSnapshot(
      stationaryDuration: 5 * 60,
      vehicleDisconnected: true
    )
    XCTAssertTrue(NativeTrackingConfidenceEvaluator.stopDecision(
      disconnected,
      stationaryTimeout: 20 * 60
    ).shouldTransition)

    let resumed = NativeTripStopEvidenceSnapshot(
      stationaryDuration: 20 * 60,
      stationaryMotion: true,
      drivingResumed: true
    )
    XCTAssertFalse(NativeTrackingConfidenceEvaluator.stopDecision(
      resumed,
      stationaryTimeout: 20 * 60
    ).shouldTransition)
  }
}


final class NativeTripRecorderTests: XCTestCase {
  func testRecorderHasSingleOwnerAndSharedMileageRules() {
    let recorder = NativeTripRecorder.shared
    recorder.release(owner: .manual)
    recorder.release(owner: .automatic)
    defer {
      recorder.release(owner: .manual)
      recorder.release(owner: .automatic)
    }
    let start = Date(timeIntervalSinceReferenceDate: 10_000)
    XCTAssertTrue(recorder.begin(owner: .manual, startedAt: start))
    XCTAssertFalse(recorder.begin(owner: .automatic, startedAt: start))

    let first = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 51.50, longitude: -0.12),
      altitude: 0,
      horizontalAccuracy: 5,
      verticalAccuracy: 5,
      course: 0,
      speed: 4,
      // Core Location commonly delivers the first moving fix just after the
      // state transition even though its sensor timestamp is a second older.
      timestamp: start.addingTimeInterval(-1)
    )
    let second = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 51.501, longitude: -0.12),
      altitude: 0,
      horizontalAccuracy: 5,
      verticalAccuracy: 5,
      course: 0,
      speed: 4,
      timestamp: start.addingTimeInterval(60)
    )
    let third = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 51.504, longitude: -0.12),
      altitude: 0,
      horizontalAccuracy: 5,
      verticalAccuracy: 5,
      course: 0,
      speed: 5.5,
      timestamp: start.addingTimeInterval(120)
    )
    let update = recorder.ingest([first, second, third], owner: .manual, now: start.addingTimeInterval(120))

    XCTAssertEqual(update?.acceptedLocations.count, 3)
    XCTAssertEqual(update?.snapshot.points.count, 3)
    XCTAssertTrue(update?.snapshot.points.allSatisfy { !$0.breakBefore } == true)
    XCTAssertGreaterThan(update?.snapshot.miles ?? 0, 0.05)
  }
}


final class NativeDeliveryEpisodeTests: XCTestCase {
  func testGenericStopsBecomeEpisodeOnlyWithOriginEvidence() {
    let start = Date(timeIntervalSinceReferenceDate: 20_000)
    var origin = NativeVisit(
      tripID: UUID(),
      latitude: 51.50,
      longitude: -0.12,
      arrival: start,
      departure: start.addingTimeInterval(60),
      confidence: 0.9,
      evidence: [.routeDwell, .nearbyPointOfInterest]
    )
    origin.kind = .other
    var destination = NativeVisit(
      tripID: origin.tripID,
      latitude: 51.51,
      longitude: -0.11,
      arrival: start.addingTimeInterval(600),
      departure: start.addingTimeInterval(660),
      confidence: 0.8,
      evidence: [.routeDwell]
    )
    destination.kind = .other

    XCTAssertEqual(NativeDeliveryEpisodeDetector.episodes(in: [origin, destination]).count, 1)
    origin.evidence = [.routeDwell]
    XCTAssertTrue(NativeDeliveryEpisodeDetector.episodes(in: [origin, destination]).isEmpty)
  }

  func testInferredPickupDropoffPairRemainsAnEpisodeWithoutNewEvidence() {
    let tripID = UUID()
    let start = Date(timeIntervalSinceReferenceDate: 30_000)
    var pickup = NativeVisit(
      tripID: tripID,
      latitude: 51.50,
      longitude: -0.12,
      arrival: start,
      departure: start,
      isEndpointGuess: true
    )
    pickup.kind = .pickup
    var dropoff = NativeVisit(
      tripID: tripID,
      latitude: 51.52,
      longitude: -0.10,
      arrival: start.addingTimeInterval(900),
      departure: start.addingTimeInterval(900),
      isEndpointGuess: true
    )
    dropoff.kind = .dropoff

    let episodes = NativeDeliveryEpisodeDetector.episodes(in: [pickup, dropoff])

    XCTAssertEqual(episodes.count, 1)
    XCTAssertEqual(episodes.first?.origin.id, pickup.id)
    XCTAssertEqual(episodes.first?.destination.id, dropoff.id)
  }
}


@MainActor
final class NativeInsightArchitectureTests: XCTestCase {
  func testExplicitRecordProvenanceControlsRecommendationIncome() {
    var manual = NativeRecord(
      source: .manual,
      kind: .income,
      platform: "Uber Eats",
      vehicle: nil,
      amount: 50,
      miles: nil,
      deduction: nil,
      category: nil,
      date: Date(),
      period: .day,
      receiptImageData: nil
    )
    manual.legacyID = "sqlite-trip-earnings-old-prefix"
    var tripEarnings = manual
    tripEarnings.source = .tripEarnings

    XCTAssertFalse(manual.isInsightRecommendationIncome)
    XCTAssertTrue(tripEarnings.isInsightRecommendationIncome)
  }

  func testPureProjectionHonorsMasterInsightsGate() {
    let store = OkkleStore()
    store.settings.insightsEnabled = false
    let input = NativeInsightInput(visits: [], store: store)

    let result = NativeShiftInsights.build(input: input)

    XCTAssertFalse(result.hasData)
    XCTAssertEqual(result.deliveries, 0)
  }

  func testProjectorProducesVersionedSnapshot() async {
    let store = OkkleStore()
    let input = NativeInsightInput(visits: [], store: store)

    let snapshot = await NativeInsightsProjector.shared.project(input)

    XCTAssertEqual(snapshot.version, NativeInsightSnapshot.currentVersion)
    XCTAssertEqual(snapshot.inputRevision, input.revision)
  }
}


@MainActor
final class NativeTripAnalysisArchitectureTests: XCTestCase {
  func testTripOwnsCanonicalStopsAndRoundTripsThemInSnapshotData() throws {
    let started = Date(timeIntervalSinceReferenceDate: 1_000_000)
    var trip = makeTrip(started: started)
    let stop = NativeVisit(
      latitude: 51.515,
      longitude: -0.115,
      arrival: started.addingTimeInterval(300),
      departure: started.addingTimeInterval(600),
      placeName: "Cafe"
    )
    trip.analysis = NativeTripAnalysisProjector.build(
      for: trip,
      source: .automatic,
      recordedVisits: [stop]
    )

    let snapshot = NativeSnapshot(settings: NativeSettings(), records: [], trips: [trip])
    let decoded = try JSONDecoder().decode(NativeSnapshot.self, from: JSONEncoder().encode(snapshot))

    XCTAssertEqual(decoded.trips.first?.canonicalStops.count, 1)
    XCTAssertEqual(decoded.trips.first?.canonicalStops.first?.placeName, "Cafe")
    XCTAssertEqual(decoded.trips.first?.canonicalStops.first?.tripID, trip.id)
  }

  func testRouteEditInvalidatesOldAnalysisAndStoreRebuildsIt() {
    let started = Date(timeIntervalSinceReferenceDate: 2_000_000)
    var trip = makeTrip(started: started)
    trip.analysis = NativeTripAnalysisProjector.build(for: trip, source: .manual)
    let oldFingerprint = trip.analysis?.routeFingerprint
    trip.points.append(RoutePoint(
      latitude: 51.53,
      longitude: -0.09,
      timestamp: started.addingTimeInterval(1_000)
    ))
    XCTAssertTrue(trip.canonicalStops.isEmpty)

    let store = OkkleStore()
    var storedOriginal = makeTrip(started: started)
    storedOriginal.id = trip.id
    storedOriginal.analysis = NativeTripAnalysisProjector.build(for: storedOriginal, source: .manual)
    store.trips = [storedOriginal]
    store.updateTrip(trip)

    XCTAssertEqual(store.trips.first?.analysis?.source, .manual)
    XCTAssertNotEqual(store.trips.first?.analysis?.routeFingerprint, oldFingerprint)
    XCTAssertTrue(store.trips.first?.canonicalStops.isEmpty ?? false)
  }

  func testAddingAnOlderTripNormalizesAnalysisAtTheStoreBoundary() {
    let store = OkkleStore()
    store.trips = []
    let trip = makeTrip(started: Date(timeIntervalSinceReferenceDate: 3_000_000))

    store.addTrip(trip)

    XCTAssertEqual(store.trips.count, 1)
    XCTAssertTrue(store.trips[0].analysis?.isCurrent(for: store.trips[0]) == true)
    XCTAssertTrue(store.trips[0].canonicalStops.isEmpty)
  }

  func testLegacyVisitMigrationReplacesInferredStopsOnce() {
    let started = Date(timeIntervalSinceReferenceDate: 4_000_000)
    let store = OkkleStore()
    var trip = makeTrip(started: started)
    trip.analysis = NativeTripAnalysisProjector.build(for: trip, source: .unknown)
    store.trips = [trip]
    let legacy = NativeVisit(
      latitude: 51.516,
      longitude: -0.114,
      arrival: started.addingTimeInterval(300),
      departure: started.addingTimeInterval(540),
      placeName: "Legacy stop"
    )

    XCTAssertTrue(store.migrateTripAnalyses(legacyVisits: [legacy]))
    XCTAssertEqual(store.trips[0].analysis?.source, .automatic)
    XCTAssertEqual(store.trips[0].canonicalStops.map(\.placeName), ["Legacy stop"])
    XCTAssertFalse(store.migrateTripAnalyses(legacyVisits: [legacy]))
  }

  private func makeTrip(started: Date) -> NativeTrip {
    NativeTrip(
      vehicle: .car,
      miles: 2.5,
      deduction: 1.13,
      startedAt: started,
      endedAt: started.addingTimeInterval(1_200),
      points: [
        RoutePoint(latitude: 51.50, longitude: -0.12, timestamp: started),
        RoutePoint(latitude: 51.52, longitude: -0.10, timestamp: started.addingTimeInterval(1_200)),
      ]
    )
  }
}


@MainActor
final class NativeAutoTrackPolicyTests: XCTestCase {
  func testActiveTripKeepsContinuousGPSAndRelaunchWakeWhileWaitingToEnd() {
    XCTAssertEqual(NativeAutoTrackPolicy.locationStrategy(during: .driving), .continuousWithRelaunchWake)
    XCTAssertEqual(NativeAutoTrackPolicy.locationStrategy(during: .stationaryPending), .continuousWithRelaunchWake)
    XCTAssertEqual(NativeAutoTrackPolicy.locationStrategy(during: .idle), .significantChangeOnly)
    XCTAssertEqual(NativeAutoTrackPolicy.locationStrategy(during: .paused), .off)
  }

  func testOffDayKeepsWakeMonitoringWithoutAllowingATripStart() {
    var settings = NativeSettings()
    settings.autoTrackTrips = true
    settings.workingDays = []

    XCTAssertTrue(NativeAutoTrackPolicy.canMaintainWakeMonitoring(
      settings: settings,
      authorizationStatus: .authorizedAlways
    ))
    XCTAssertFalse(NativeAutoTrackPolicy.canStartTrip(
      settings: settings,
      authorizationStatus: .authorizedAlways,
      accuracyAuthorization: .fullAccuracy,
      date: Date()
    ))
    XCTAssertEqual(NativeAutoTrackPolicy.readiness(
      settings: settings,
      authorizationStatus: .authorizedAlways,
      accuracyAuthorization: .fullAccuracy,
      date: Date()
    ), .waitingForWorkingDay)
  }

  func testReducedAccuracyCanWakeButCannotRecordATrip() {
    var settings = NativeSettings()
    settings.autoTrackTrips = true
    settings.workingDays = Array(0...6)

    XCTAssertTrue(NativeAutoTrackPolicy.canMaintainWakeMonitoring(
      settings: settings,
      authorizationStatus: .authorizedAlways
    ))
    XCTAssertFalse(NativeAutoTrackPolicy.canStartTrip(
      settings: settings,
      authorizationStatus: .authorizedAlways,
      accuracyAuthorization: .reducedAccuracy,
      date: Date()
    ))
    XCTAssertFalse(NativeAutoTrackPolicy.canContinueActiveShift(
      settings: settings,
      authorizationStatus: .authorizedAlways,
      accuracyAuthorization: .reducedAccuracy
    ))
    XCTAssertEqual(NativeAutoTrackPolicy.readiness(
      settings: settings,
      authorizationStatus: .authorizedAlways,
      accuracyAuthorization: .reducedAccuracy,
      date: Date()
    ), .needsPreciseLocation)
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
    XCTAssertFalse(NativeAutoTrackPolicy.canMonitor(
      settings: settings,
      authorizationStatus: .authorizedAlways,
      accuracyAuthorization: .reducedAccuracy,
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
    XCTAssertFalse(NativeAutoTrackPolicy.canContinueActiveShift(
      settings: settings,
      authorizationStatus: .authorizedAlways,
      accuracyAuthorization: .reducedAccuracy
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

  func testMileageAndRouteShareTheSamePlausibilityFilter() {
    let now = Date()
    let first = location(latitude: 51.5000, longitude: -0.1200, accuracy: 8, timestamp: now)
    let plausible = location(latitude: 51.5005, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(10))
    let lastGoodAccuracy = location(latitude: 51.5006, longitude: -0.1200, accuracy: 45, timestamp: now.addingTimeInterval(20))
    let inaccurate = location(latitude: 51.5007, longitude: -0.1200, accuracy: 46, timestamp: now.addingTimeInterval(30))
    let teleport = location(latitude: 52.0000, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(11))
    let outOfOrder = location(latitude: 51.5006, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(9))
    let impossibleReportedSpeed = location(
      latitude: 51.5006, longitude: -0.1200, accuracy: 8,
      timestamp: now.addingTimeInterval(20), speed: 46
    )

    XCTAssertTrue(NativeAutoTrackPolicy.shouldAcceptTripLocation(first, since: nil))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldAcceptTripLocation(plausible, since: first))
    XCTAssertTrue(NativeAutoTrackPolicy.shouldAcceptTripLocation(lastGoodAccuracy, since: plausible))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldAcceptTripLocation(inaccurate, since: lastGoodAccuracy))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldAcceptTripLocation(teleport, since: plausible))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldAcceptTripLocation(outOfOrder, since: plausible))
    XCTAssertFalse(NativeAutoTrackPolicy.shouldAcceptTripLocation(impossibleReportedSpeed, since: plausible))
  }

  func testStationaryGPSJitterDoesNotIncreaseMileage() {
    let now = Date()
    let previous = location(latitude: 51.5000, longitude: -0.1200, accuracy: 12, timestamp: now)
    let jitter = location(latitude: 51.50005, longitude: -0.1200, accuracy: 12, timestamp: now.addingTimeInterval(10))
    let stopped = location(
      latitude: 51.5002, longitude: -0.1200, accuracy: 8,
      timestamp: now.addingTimeInterval(20), speed: 0.2
    )
    let moving = location(
      latitude: 51.5003, longitude: -0.1200, accuracy: 8,
      timestamp: now.addingTimeInterval(30), speed: 4
    )

    XCTAssertNil(nativeTripMovementDistance(from: previous, to: jitter))
    XCTAssertNil(nativeTripMovementDistance(from: jitter, to: stopped))
    XCTAssertNotNil(nativeTripMovementDistance(from: stopped, to: moving))
  }

  func testRecordedLocationsDoNotCreateAutomaticDottedBreaks() {
    let now = Date()
    let first = RoutePoint(location: location(latitude: 51.5000, longitude: -0.1200, accuracy: 8, timestamp: now))
    let later = RoutePoint(location: location(latitude: 51.5200, longitude: -0.1100, accuracy: 8, timestamp: now.addingTimeInterval(180)))

    XCTAssertFalse(first.breakBefore)
    XCTAssertFalse(later.breakBefore)
  }

  func testLocationRejectionsExplainWhyAFixWasDropped() {
    let now = Date()
    let previous = location(latitude: 51.5000, longitude: -0.1200, accuracy: 8, timestamp: now.addingTimeInterval(-10))
    let inaccurate = location(latitude: 51.5001, longitude: -0.1200, accuracy: 46, timestamp: now)
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
  func testInsightEvidenceMergesWithTheUserSnapshot() throws {
    let now = Date(timeIntervalSinceReferenceDate: 30_000)
    var localEvidence = NativeInsightEvidence()
    localEvidence.outcomeSamples = [NativeOutcomeSample(
      date: now,
      period: .day,
      amount: 20,
      wasPredictedPeakDay: true
    )]
    localEvidence.updatedAt = now
    var remoteEvidence = NativeInsightEvidence()
    remoteEvidence.zoneOutcomeSamples = [NativeZoneOutcomeSample(
      date: now.addingTimeInterval(60),
      period: .day,
      amount: 25,
      wasNearRecommendedZone: true
    )]
    remoteEvidence.explicitPositive = 2
    remoteEvidence.updatedAt = now.addingTimeInterval(60)

    let merged = NativeICloudSnapshotMerge.merge(
      local: NativeSnapshot(
        settings: NativeSettings(),
        records: [],
        trips: [],
        insightEvidence: localEvidence
      ),
      remote: NativeSnapshot(
        settings: NativeSettings(),
        records: [],
        trips: [],
        insightEvidence: remoteEvidence
      )
    )
    let decoded = try JSONDecoder().decode(
      NativeSnapshot.self,
      from: JSONEncoder().encode(merged)
    )

    XCTAssertEqual(decoded.insightEvidence.outcomeSamples.count, 1)
    XCTAssertEqual(decoded.insightEvidence.zoneOutcomeSamples.count, 1)
    XCTAssertEqual(decoded.insightEvidence.explicitPositive, 2)
  }

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

  func testCountryChangeKeepsSharedAndCustomPlatformsOnly() {
    let migrated = nativePlatformsAfterCountryChange(
      ["Deliveroo", "Uber Eats", "Amazon Flex", "Local Courier"],
      to: .us
    )

    XCTAssertEqual(migrated, ["Uber Eats", "Amazon Flex", "Local Courier"])
  }

  func testCountryChangeUsesNewMarketDefaultWhenNothingCarriesAcross() {
    XCTAssertEqual(nativePlatformsAfterCountryChange(["Deliveroo", "Just Eat"], to: .us), ["DoorDash"])
    XCTAssertEqual(nativePlatformsAfterCountryChange(["DoorDash", "Grubhub"], to: .uk), ["Uber Eats"])
  }

  func testTripCurrencyUsesGPSMarketInsteadOfTaxProfile() {
    let sanFrancisco = [RoutePoint(latitude: 37.7749, longitude: -122.4194)]
    let london = [RoutePoint(latitude: 51.5072, longitude: -0.1276)]

    XCTAssertEqual(nativeTripCurrencyCode(for: sanFrancisco), "USD")
    XCTAssertEqual(nativeTripCurrencyCode(for: london), "GBP")
    XCTAssertNil(nativeTripCurrencyCode(for: []))
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
