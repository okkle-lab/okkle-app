import Foundation
import UIKit

@MainActor
final class NativeAccountantPackPdfRenderer {
  private let store: OkkleStore
  private let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
  private let margin: CGFloat = 42
  private let ink = UIColor(red: 0.10, green: 0.16, blue: 0.14, alpha: 1)
  private let muted = UIColor(red: 0.42, green: 0.48, blue: 0.45, alpha: 1)
  private let brand = UIColor(red: 0.03, green: 0.58, blue: 0.49, alpha: 1)
  private let pale = UIColor(red: 0.94, green: 0.98, blue: 0.97, alpha: 1)
  private let line = UIColor(red: 0.84, green: 0.88, blue: 0.86, alpha: 1)
  private var y: CGFloat = 42
  private var page = 0
  private var context: UIGraphicsPDFRendererContext?

  init(store: OkkleStore) {
    self.store = store
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
      drawSelfAssessment()
      drawIncome()
      drawMileage()
      drawExpenses()
      drawReceipts()
      drawLimitations()
    }
  }

  private var contentWidth: CGFloat {
    pageRect.width - (margin * 2)
  }

  private var bottomLimit: CGFloat {
    pageRect.height - margin - 26
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

  private func beginPage() {
    context?.beginPage()
    page += 1
    y = margin
    drawFooter()
  }

  private func drawFooter() {
    let text = "Okkle accountant pack - Page \(page)"
    drawString(
      text,
      in: CGRect(x: margin, y: pageRect.height - margin + 4, width: contentWidth, height: 14),
      font: .systemFont(ofSize: 8, weight: .medium),
      color: muted,
      alignment: .center
    )
  }

  private func ensure(_ height: CGFloat) {
    if y + height > bottomLimit {
      beginPage()
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
    let utr = clean(store.settings.accountantUTR)
    let niNumber = clean(store.settings.accountantNINumber)
    let address = clean(store.settings.accountantAddress).replacingOccurrences(of: "\n", with: ", ")
    if !utr.isEmpty { coverRows.append(("UTR", utr)) }
    if !niNumber.isEmpty { coverRows.append(("National Insurance no.", niNumber)) }
    if !address.isEmpty { coverRows.append(("Address", address)) }
    coverRows.append(contentsOf: [
      ("Accounting period", "\(nativeUkDateStamp(store.taxYear.start)) to \(nativeUkDateStamp(taxYearEndDate))"),
      ("Tax year", nativeTaxYearLabel(for: store.taxYear)),
      ("Prepared", nativeLongDate(Date())),
      ("Tax region", store.settings.region.label),
      ("Income tax band", incomeBracketLine)
    ])
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
    drawKeyValue("Mileage method", "Simplified mileage using HMRC flat rates")
    drawKeyValue("Records source", "Tracked trips and manual entries logged in Okkle")
    drawKeyValue("Income tax band", incomeBracketLine)
    drawKeyValue("Other income", gbp(store.settings.otherIncome))
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
    let tripRows = yearTrips.map { trip in
      [
        nativeUkDateStamp(trip.startedAt),
        trip.vehicle.label,
        "GPS trip",
        miles(trip.miles),
        gbp(trip.deduction)
      ]
    }
    let manualRows = manualMileageRecords.map { record in
      [
        nativeUkDateStamp(record.date),
        record.vehicle?.label ?? "Vehicle",
        "Manual",
        miles(record.miles ?? 0),
        gbp(record.deduction ?? 0)
      ]
    }
    drawWrapped(
      "Tracked trips with saved route points support a contemporaneous mileage log. Your accountant should review the business purpose and completeness.",
      font: .systemFont(ofSize: 10.5, weight: .regular),
      color: muted,
      spacingAfter: 6
    )
    drawTable(
      headers: ["Date", "Vehicle", "Source", "Miles", "Deduction"],
      rows: tripRows + manualRows,
      widths: [0.20, 0.22, 0.20, 0.16, 0.22],
      rightAligned: [3, 4],
      emptyMessage: "No mileage records logged for this tax year."
    )
    drawKeyValue("Business miles", miles(store.yearMiles), highlighted: true)
    drawKeyValue("Mileage deduction", gbp(store.yearMileageDeduction), highlighted: true)
  }

  private func drawExpenses() {
    drawSectionTitle("Expenses")
    let reviewItems = expenseRecords.filter(nativeNeedsAccountantReview)
    let regularItems = expenseRecords.filter { !nativeNeedsAccountantReview($0) }
    drawExpenseTable(regularItems, emptyMessage: "No expense records logged for this tax year.")
    drawKeyValue("Expense total", gbp(expenseRecords.reduce(0) { $0 + ($1.amount ?? 0) }))

    if !reviewItems.isEmpty {
      drawSectionTitle("Items flagged for review")
      drawWrapped(
        "These look like vehicle running costs. If simplified mileage is used, they may already be covered by the mileage rate.",
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
        nativeUkDateStamp(record.date),
        nativeExpenseDescription(record),
        gbp(record.amount ?? 0),
        record.receiptImageData == nil ? "No" : "Attached"
      ]
    }
    drawTable(
      headers: ["Date", "Description", "Amount", "Receipt"],
      rows: rows,
      widths: [0.20, 0.44, 0.20, 0.16],
      rightAligned: [2],
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
      let caption = "\(nativeUkDateStamp(record.date)) - \(nativeExpenseDescription(record)) - \(gbp(record.amount ?? 0))"
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

  private func drawInfoBox(_ rows: [(String, String)]) {
    let labelFont = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
    let valueFont = UIFont.systemFont(ofSize: 10.5, weight: .bold)
    let labelWidth: CGFloat = 150
    let valueWidth = contentWidth - 194
    let rowHeights = rows.map { label, value in
      max(
        24,
        measuredHeight(label, font: labelFont, width: labelWidth),
        measuredHeight(value, font: valueFont, width: valueWidth)
      ) + 7
    }
    let boxHeight = rowHeights.reduce(18, +)
    ensure(boxHeight)
    let rect = CGRect(x: margin, y: y, width: contentWidth, height: boxHeight)
    pale.setFill()
    UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
    line.setStroke()
    UIBezierPath(roundedRect: rect, cornerRadius: 10).stroke()
    y += 9
    for (index, row) in rows.enumerated() {
      let rowHeight = rowHeights[index]
      drawString(row.0, in: CGRect(x: margin + 12, y: y, width: labelWidth, height: rowHeight), font: labelFont, color: muted)
      drawString(row.1, in: CGRect(x: margin + 170, y: y, width: valueWidth, height: rowHeight), font: valueFont, color: ink, alignment: .right)
      y += rowHeight
    }
    y += 13
  }

  private func drawSectionTitle(_ title: String) {
    ensure(42)
    y += y > margin + 2 ? 14 : 0
    drawWrapped(title, font: .systemFont(ofSize: 15, weight: .heavy), color: brand, spacingAfter: 5)
    brand.withAlphaComponent(0.22).setFill()
    UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: contentWidth, height: 2), cornerRadius: 1).fill()
    y += 9
  }

  private func drawKeyValue(_ label: String, _ value: String, highlighted: Bool = false) {
    let labelWidth = contentWidth * 0.48
    let valueWidth = contentWidth - labelWidth
    let labelFont = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
    let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 10.5, weight: highlighted ? .bold : .semibold)
    let height = max(
      measuredHeight(label, font: labelFont, width: labelWidth),
      measuredHeight(value, font: valueFont, width: valueWidth)
    ) + 10
    ensure(height)
    if highlighted {
      pale.setFill()
      UIBezierPath(roundedRect: CGRect(x: margin - 6, y: y - 2, width: contentWidth + 12, height: height), cornerRadius: 6).fill()
    }
    drawString(label, in: CGRect(x: margin, y: y + 4, width: labelWidth, height: height), font: labelFont, color: muted)
    drawString(value, in: CGRect(x: margin + labelWidth, y: y + 4, width: valueWidth, height: height), font: valueFont, color: highlighted ? brand : ink, alignment: .right)
    y += height
    drawHairline()
  }

  private func drawTable(
    headers: [String],
    rows: [[String]],
    widths: [CGFloat],
    rightAligned: Set<Int> = [],
    emptyMessage: String = "None recorded."
  ) {
    let total = widths.reduce(0, +)
    let columnWidths = widths.map { contentWidth * ($0 / total) }
    drawTableRow(headers, widths: columnWidths, rightAligned: rightAligned, font: .systemFont(ofSize: 9.4, weight: .bold), textColor: ink, background: UIColor(red: 0.94, green: 0.94, blue: 0.92, alpha: 1))

    if rows.isEmpty {
      drawTableRow([emptyMessage], widths: [contentWidth], rightAligned: [], font: .systemFont(ofSize: 9.4, weight: .regular), textColor: muted, background: nil)
    } else {
      rows.forEach { row in
        drawTableRow(row, widths: columnWidths, rightAligned: rightAligned, font: .systemFont(ofSize: 9.2, weight: .regular), textColor: ink, background: nil)
      }
    }
    y += 5
  }

  private func drawTableRow(_ values: [String], widths: [CGFloat], rightAligned: Set<Int>, font: UIFont, textColor: UIColor, background: UIColor?) {
    let padding: CGFloat = 6
    let cellHeights = values.enumerated().map { index, value in
      measuredHeight(value, font: font, width: max(1, widths[index] - padding * 2))
    }
    let rowHeight = max(24, (cellHeights.max() ?? 12) + padding * 2)
    ensure(rowHeight)
    if let background {
      background.setFill()
      UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)).fill()
    }

    var x = margin
    for (index, value) in values.enumerated() {
      let width = widths[index]
      let rect = CGRect(x: x + padding, y: y + padding, width: width - padding * 2, height: rowHeight - padding)
      drawString(value, in: rect, font: font, color: textColor, alignment: rightAligned.contains(index) ? .right : .left)
      x += width
    }
    y += rowHeight
    drawHairline()
  }

  private func drawHairline() {
    line.setStroke()
    let path = UIBezierPath()
    path.move(to: CGPoint(x: margin, y: y))
    path.addLine(to: CGPoint(x: margin + contentWidth, y: y))
    path.lineWidth = 0.5
    path.stroke()
  }

  @discardableResult
  private func drawWrapped(_ value: String, font: UIFont, color: UIColor, spacingAfter: CGFloat) -> CGFloat {
    let height = measuredHeight(value, font: font, width: contentWidth)
    ensure(height + spacingAfter)
    drawString(value, in: CGRect(x: margin, y: y, width: contentWidth, height: height), font: font, color: color)
    y += height + spacingAfter
    return height
  }

  private func drawString(_ value: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraph
    ]
    (value as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
  }

  private func measuredHeight(_ value: String, font: UIFont, width: CGFloat) -> CGFloat {
    let rect = (value as NSString).boundingRect(
      with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font],
      context: nil
    )
    return ceil(rect.height)
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

func nativeLongDate(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_GB")
  formatter.dateStyle = .long
  return formatter.string(from: date)
}
