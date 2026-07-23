import Foundation
import UIKit

@MainActor
final class NativeAccountantPackPdfRenderer: NativePdfDocumentRenderer {
  private let store: OkkleStore
  private var country: NativeTaxCountry { store.settings.taxCountry }

  init(store: OkkleStore) {
    self.store = store
    super.init(footerText: "Okkle accountant pack")
  }

  func render() -> Data {
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = [
      kCGPDFContextTitle as String: "Okkle Accountant Pack \(nativeTaxYearLabel(for: store.taxYear))",
      kCGPDFContextCreator as String: "Okkle"
    ]
    let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
    return renderer.pdfData { rendererContext in
      context = rendererContext
      beginPage()
      drawCover()
      drawBasis()
      switch country {
      case .uk: drawSelfAssessment()
      case .us: drawUsTaxSummary()
      }
      drawIncome()
      drawMileage()
      drawExpenses()
      drawReceipts()
      drawLimitations()
    }
  }

  private var taxYearEndDate: Date {
    Calendar.current.date(byAdding: .day, value: -1, to: store.taxYear.end) ?? store.taxYear.end
  }

  private var yearTrips: [NativeTrip] {
    store.yearTrips.sorted { $0.startedAt < $1.startedAt }
  }

  private var yearRecords: [NativeRecord] {
    store.yearRecords.sorted { $0.date < $1.date }
  }

  private var incomeRecords: [NativeRecord] {
    yearRecords.filter { $0.kind == .income }
  }

  private var expenseRecords: [NativeRecord] {
    yearRecords.filter { $0.kind == .expense }
  }

  private var manualMileageRecords: [NativeRecord] {
    yearRecords.filter { $0.kind == .mileage }
  }

  private var incomeBracketLine: String {
    "\(store.settings.incomeBracket.label) (\(Int(store.settings.incomeBracket.marginalRate(region: store.settings.region) * 100))% tax-saved estimate)"
  }

  private var mileageMethodLine: String {
    switch country {
    case .uk:
      return store.settings.expenseMethod == .simplified
        ? "Simplified mileage using HMRC flat rates"
        : "Actual vehicle costs claimed — no mileage rate applied"
    case .us:
      return "IRS standard mileage rate"
    }
  }

  private func drawCover() {
    func clean(_ value: String) -> String {
      value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    brand.setFill()
    UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: 86, height: 5), cornerRadius: 2.5).fill()
    y += 20

    drawWrapped("Accountant Review Pack", font: .systemFont(ofSize: 27, weight: .heavy), color: ink, spacingAfter: 4)
    drawWrapped("Income, expenses, mileage and receipt evidence", font: .systemFont(ofSize: 14, weight: .semibold), color: muted, spacingAfter: 13)

    let clientName = store.settings.name.isEmpty ? "Courier" : store.settings.name
    let business = clean(store.settings.accountantBusinessDescription)
    let businessLine = business.isEmpty ? "Sole trader delivery records" : "Sole trader (\(business))"
    drawWrapped("\(clientName) - \(businessLine)", font: .systemFont(ofSize: 12, weight: .medium), color: ink, spacingAfter: 18)

    var coverRows: [(String, String)] = []
    if country == .uk {
      let utr = clean(store.settings.accountantUTR)
      let niNumber = clean(store.settings.accountantNINumber)
      let address = clean(store.settings.accountantAddress).replacingOccurrences(of: "\n", with: ", ")
      if !utr.isEmpty { coverRows.append(("UTR", utr)) }
      if !niNumber.isEmpty { coverRows.append(("National Insurance no.", niNumber)) }
      if !address.isEmpty { coverRows.append(("Address", address)) }
    }
    coverRows.append(contentsOf: [
      ("Accounting period", "\(nativePeriodDateStamp(store.taxYear.start, country: country)) to \(nativePeriodDateStamp(taxYearEndDate, country: country))"),
      ("Tax year", nativeTaxYearLabel(for: store.taxYear)),
      ("Prepared", nativeLongDate(Date(), country: country))
    ])
    switch country {
    case .uk:
      coverRows.append(("Tax region", store.settings.region.label))
      coverRows.append(("Income tax band", incomeBracketLine))
    case .us:
      coverRows.append(("Tax state", store.settings.usState.label))
    }
    drawInfoBox(coverRows)

    drawWrapped(
      "A review pack to support your accountant. Figures are generated on-device from records logged in Okkle and should be confirmed before filing.",
      font: .systemFont(ofSize: 10.5, weight: .regular),
      color: muted,
      spacingAfter: 14
    )
  }

  private func drawBasis() {
    drawSectionTitle("Basis of preparation")
    drawKeyValue("Accounting basis", "Cash basis")
    drawKeyValue("Mileage method", mileageMethodLine)
    drawKeyValue("Records source", "Tracked trips and manual entries logged in Okkle")
    if country == .uk {
      drawKeyValue("Income tax band", incomeBracketLine)
    }
    drawKeyValue(country == .uk ? "Other income" : "Other W-2 wages", gbp(store.settings.otherIncome))
    drawKeyValue("Income entries", "\(incomeRecords.count)")
    drawKeyValue("Expense entries", "\(expenseRecords.count) (\(expenseRecords.filter { $0.receiptImageData != nil }.count) with receipts)")
    drawKeyValue("Mileage entries", "\(yearTrips.count) tracked trips, \(manualMileageRecords.count) manual entries")
  }

  private func drawSelfAssessment() {
    let tax = store.taxPosition
    drawSectionTitle("Self Assessment summary")
    drawTable(
      headers: ["SA103S box", "Description", "Amount"],
      rows: [
        ["9", "Turnover - business income", gbp(tax.turnover)],
        ["20", "Allowable business expenses, including mileage deduction", gbp(tax.deductionApplied)],
        ["31", "Taxable profit", gbp(tax.profit)]
      ],
      widths: [0.18, 0.54, 0.28],
      rightAligned: [2]
    )
    drawKeyValue("Income Tax estimate", gbp(tax.incomeTax))
    drawKeyValue("Class 4 NIC estimate", gbp(tax.class4))
    drawKeyValue("Estimated total due", gbp(tax.totalDue), highlighted: true)
    if tax.paymentOnAccount > 0 {
      drawKeyValue("Payment on account", "\(gbp(tax.paymentOnAccount)) each")
    }
    drawKeyValue("Trading allowance", tax.usesTradingAllowance ? "Used" : "Not used")
  }

  private func drawUsTaxSummary() {
    let tax = store.taxPosition
    drawSectionTitle("Schedule C / SE tax summary")
    drawTable(
      headers: ["Description", "Amount"],
      rows: [
        ["Turnover - business income", gbp(tax.turnover)],
        ["Allowable business expenses, including mileage/actual costs", gbp(tax.deductionApplied)],
        ["Taxable profit", gbp(tax.profit)]
      ],
      widths: [0.72, 0.28],
      rightAligned: [1]
    )
    drawKeyValue("Standard deduction", gbp(tax.standardDeduction))
    drawKeyValue("QBI deduction (20%)", gbp(tax.qbiDeduction))
    drawKeyValue("Estimated federal income tax", gbp(tax.incomeTax))
    drawKeyValue("Estimated self-employment tax", gbp(tax.class4))
    if tax.stateTax > 0 {
      drawKeyValue("Estimated state tax (\(store.settings.usState.label))", gbp(tax.stateTax))
    }
    drawKeyValue("Estimated total due", gbp(tax.totalDue), highlighted: true)
    if tax.paymentOnAccount > 0 {
      drawKeyValue("Suggested quarterly set-aside (1040-ES)", gbp(tax.paymentOnAccount))
    }
  }

  private func drawIncome() {
    drawSectionTitle("Income by platform")
    var totals: [String: Double] = [:]
    incomeRecords.forEach { record in
      totals[record.platform ?? "Other", default: 0] += record.amount ?? 0
    }
    let rows = totals
      .sorted { $0.value > $1.value }
      .map { [$0.key, gbp($0.value)] }
    drawTable(
      headers: ["Platform", "Amount"],
      rows: rows,
      widths: [0.66, 0.34],
      rightAligned: [1],
      emptyMessage: "No income records logged for this tax year."
    )
    drawKeyValue("Total turnover", gbp(store.taxPosition.turnover), highlighted: true)
  }

  private func drawMileage() {
    drawSectionTitle("Mileage log")
    // Each row's deduction comes from yearMileageLogRows, which recomputes
    // it against a running car/van total for the tax year — a trip or
    // manual record's own stored `deduction` field is set at logging time
    // against a running total of zero, so the rows below would silently
    // stop summing to the "Mileage deduction" total once combined car/van
    // mileage crosses the 10,000-mile HMRC simplified-rate threshold.
    let usesActualCost = country == .uk && store.settings.expenseMethod == .actualCost
    drawWrapped(
      usesActualCost
        ? "Actual-cost driver: this log evidences business mileage, but vehicle costs are claimed from the expense records below rather than a mileage rate."
        : "Tracked trips with saved route points support a contemporaneous mileage log. Your accountant should review the business purpose and completeness.",
      font: .systemFont(ofSize: 10.5, weight: .regular),
      color: muted,
      spacingAfter: 6
    )
    drawMileageJournal(store.yearMileageLogRows, country: country)
    drawKeyValue("Business miles", miles(store.yearMiles), highlighted: true)
    drawKeyValue("Mileage deduction", gbp(store.yearMileageDeduction), highlighted: true)
  }

  private func drawExpenses() {
    drawSectionTitle("Expenses")
    // The "may already be covered by mileage" flag applies to anyone using a
    // flat mileage rate — UK simplified expenses or the US IRS standard
    // mileage rate both bundle fuel/insurance/repairs into the per-mile
    // figure — so it only drops out for a UK actual-cost driver, who claims
    // these receipts directly instead.
    let usesFlatMileageRate = country != .uk || store.settings.expenseMethod == .simplified
    let reviewItems = usesFlatMileageRate ? expenseRecords.filter(nativeNeedsAccountantReview) : []
    let regularItems = usesFlatMileageRate ? expenseRecords.filter { !nativeNeedsAccountantReview($0) } : expenseRecords
    drawExpenseTable(regularItems, emptyMessage: "No expense records logged for this tax year.")
    drawKeyValue("Expense total", gbp(expenseRecords.reduce(0) { $0 + ($1.amount ?? 0) }))

    if !reviewItems.isEmpty {
      drawSectionTitle("Items flagged for review")
      drawWrapped(
        country == .uk
          ? "These look like vehicle running costs. If simplified mileage is used, they may already be covered by the mileage rate."
          : "These look like vehicle running costs. The IRS standard mileage rate already covers them, so check you're not claiming them twice.",
        font: .systemFont(ofSize: 10.5, weight: .regular),
        color: muted,
        spacingAfter: 6
      )
      drawExpenseTable(reviewItems)
    }
  }

  private func drawExpenseTable(_ records: [NativeRecord], emptyMessage: String = "None.") {
    let rows = records.map { record in
      [
        nativePeriodDateStamp(record.date, country: country),
        nativeExpenseDescription(record),
        record.note ?? "",
        gbp(record.amount ?? 0),
        record.receiptImageData == nil ? "No" : "Attached"
      ]
    }
    drawTable(
      headers: ["Date", "Description", "Note", "Amount", "Receipt"],
      rows: rows,
      widths: [0.16, 0.30, 0.26, 0.14, 0.14],
      rightAligned: [3],
      emptyMessage: emptyMessage
    )
  }

  private func drawReceipts() {
    let receipts = expenseRecords.compactMap { record -> (NativeRecord, UIImage)? in
      guard let data = record.receiptImageData, let image = UIImage(data: data) else { return nil }
      return (record, image)
    }
    guard !receipts.isEmpty else { return }

    drawSectionTitle("Receipt images")
    for (record, image) in receipts {
      let caption = "\(nativePeriodDateStamp(record.date, country: country)) - \(nativeExpenseDescription(record)) - \(gbp(record.amount ?? 0))"
      let captionHeight = measuredHeight(caption, font: .systemFont(ofSize: 9.5, weight: .semibold), width: contentWidth)
      let maxImageWidth = contentWidth
      let maxImageHeight: CGFloat = 270
      let scale = min(maxImageWidth / max(image.size.width, 1), maxImageHeight / max(image.size.height, 1), 1)
      let imageSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      ensure(captionHeight + imageSize.height + 20)
      drawWrapped(caption, font: .systemFont(ofSize: 9.5, weight: .semibold), color: muted, spacingAfter: 5)
      let imageRect = CGRect(x: margin, y: y, width: imageSize.width, height: imageSize.height)
      image.draw(in: imageRect)
      line.setStroke()
      UIBezierPath(roundedRect: imageRect, cornerRadius: 5).stroke()
      y += imageSize.height + 16
    }
  }

  private func drawLimitations() {
    drawSectionTitle("Basis and limitations")
    drawWrapped(
      "Prepared by Okkle from records kept on the user's device. Figures are estimates derived from logged data, have not been independently verified or reconciled to bank records, and do not constitute tax advice. Confirm completeness, categorisation and final figures before submission.",
      font: .systemFont(ofSize: 10, weight: .regular),
      color: muted,
      spacingAfter: 0
    )
  }
}

func nativeExpenseDescription(_ record: NativeRecord) -> String {
  [record.merchant, record.category ?? "Expense"]
    .compactMap { value in
      guard let value, !value.isEmpty else { return nil }
      return value
    }
    .joined(separator: " - ")
}

func nativeNeedsAccountantReview(_ record: NativeRecord) -> Bool {
  let text = "\(record.category ?? "") \(record.merchant ?? "")".lowercased()
  let terms = ["fuel", "petrol", "diesel", "tyre", "tire", "mot", "service", "servicing", "repair", "insurance", "road tax", "breakdown", "oil", "brake", "battery"]
  return terms.contains { text.contains($0) }
}

func nativeLongDate(_ date: Date, country: NativeTaxCountry = .uk) -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: country == .uk ? "en_GB" : "en_US")
  formatter.dateStyle = .long
  return formatter.string(from: date)
}
