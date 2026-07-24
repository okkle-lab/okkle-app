import Foundation
import UIKit

/// Shared low-level drawing primitives for on-device PDF reports (pagination,
/// tables, key/value rows, wrapped text) — pulled out so every Okkle PDF
/// export (accountant pack, mileage report, ...) shares one layout engine
/// instead of each reimplementing pagination and table-drawing separately.
@MainActor
class NativePdfDocumentRenderer {
  let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
  let margin: CGFloat = 42
  let ink = UIColor(red: 0.10, green: 0.16, blue: 0.14, alpha: 1)
  let muted = UIColor(red: 0.42, green: 0.48, blue: 0.45, alpha: 1)
  let brand = UIColor(red: 0.03, green: 0.58, blue: 0.49, alpha: 1)
  let pale = UIColor(red: 0.94, green: 0.98, blue: 0.97, alpha: 1)
  let line = UIColor(red: 0.84, green: 0.88, blue: 0.86, alpha: 1)
  var y: CGFloat = 42
  var page = 0
  var context: UIGraphicsPDFRendererContext?
  private let footerText: String

  init(footerText: String) {
    self.footerText = footerText
  }

  var contentWidth: CGFloat {
    pageRect.width - (margin * 2)
  }

  var bottomLimit: CGFloat {
    pageRect.height - margin - 26
  }

  func beginPage() {
    context?.beginPage()
    page += 1
    y = margin
    drawFooter()
  }

  private func drawFooter() {
    let text = "\(footerText) - Page \(page)"
    drawString(
      text,
      in: CGRect(x: margin, y: pageRect.height - margin + 4, width: contentWidth, height: 14),
      font: .systemFont(ofSize: 8, weight: .medium),
      color: muted,
      alignment: .center
    )
  }

  func ensure(_ height: CGFloat) {
    if y + height > bottomLimit {
      beginPage()
    }
  }

  func drawInfoBox(_ rows: [(String, String)]) {
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

  func drawSectionTitle(_ title: String) {
    ensure(42)
    y += y > margin + 2 ? 14 : 0
    drawWrapped(title, font: .systemFont(ofSize: 15, weight: .heavy), color: brand, spacingAfter: 5)
    brand.withAlphaComponent(0.22).setFill()
    UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: contentWidth, height: 2), cornerRadius: 1).fill()
    y += 9
  }

  /// A closing caveat ("basis and limitations", "not tax advice", etc.) —
  /// deliberately styled much quieter than `drawSectionTitle`'s bold brand
  /// heading. It still needs to be legible (this is the line doing the
  /// compliance work of not letting an estimate read as an official filing),
  /// but visually it should read as a footnote next to the actual figures,
  /// not compete with them for attention the way a same-weight heading would.
  func drawDisclaimer(_ title: String, _ body: String) {
    ensure(30)
    y += y > margin + 2 ? 14 : 0
    drawWrapped(title, font: .systemFont(ofSize: 10.5, weight: .semibold), color: muted, spacingAfter: 4)
    drawWrapped(body, font: .systemFont(ofSize: 9.5, weight: .regular), color: muted, spacingAfter: 0)
  }

  func drawKeyValue(_ label: String, _ value: String, highlighted: Bool = false) {
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

  func drawTable(
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

  func drawHairline() {
    line.setStroke()
    let path = UIBezierPath()
    path.move(to: CGPoint(x: margin, y: y))
    path.addLine(to: CGPoint(x: margin + contentWidth, y: y))
    path.lineWidth = 0.5
    path.stroke()
  }

  @discardableResult
  func drawWrapped(_ value: String, font: UIFont, color: UIColor, spacingAfter: CGFloat) -> CGFloat {
    let height = measuredHeight(value, font: font, width: contentWidth)
    ensure(height + spacingAfter)
    drawString(value, in: CGRect(x: margin, y: y, width: contentWidth, height: height), font: font, color: color)
    y += height + spacingAfter
    return height
  }

  func drawString(_ value: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
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

  func measuredHeight(_ value: String, font: UIFont, width: CGFloat) -> CGFloat {
    let rect = (value as NSString).boundingRect(
      with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font],
      context: nil
    )
    return ceil(rect.height)
  }

  /// The full per-journey mileage log — date, from/to addresses (or a plain
  /// fallback), stated business purpose, distance and deduction. Shared by
  /// the accountant pack and the standalone mileage report so both PDFs
  /// present the exact same record for the same trip, at the level of detail
  /// (date, start/destination, purpose, miles) IRS Publication 463 requires
  /// and HMRC expects to be able to reconstruct a journey during an enquiry —
  /// a bare date/vehicle/miles/deduction table falls short of both.
  func drawMileageJournal(_ rows: [NativeMileageLogRow], country: NativeTaxCountry) {
    guard !rows.isEmpty else {
      drawWrapped("No mileage logged for this tax year.", font: .systemFont(ofSize: 10, weight: .regular), color: muted, spacingAfter: 0)
      return
    }

    var lastDateKey: String?
    for row in rows {
      let dateKey = nativeDateStamp(row.date)
      drawMileageJournalEntry(row, showDate: dateKey != lastDateKey, country: country)
      lastDateKey = dateKey
    }
  }

  private func drawMileageJournalEntry(_ row: NativeMileageLogRow, showDate: Bool, country: NativeTaxCountry) {
    if showDate {
      ensure(24)
      drawWrapped(nativeLongDate(row.date, country: country), font: .systemFont(ofSize: 11.5, weight: .heavy), color: ink, spacingAfter: 6)
    }

    let addressFont = UIFont.systemFont(ofSize: 10, weight: .medium)
    let dotColumn: CGFloat = 16
    let addressWidth = contentWidth - dotColumn

    if let from = row.fromAddress, let to = row.toAddress {
      let rowGap: CGFloat = 5
      let fromHeight = measuredHeight(from, font: addressFont, width: addressWidth)
      let toHeight = measuredHeight(to, font: addressFont, width: addressWidth)
      ensure(fromHeight + toHeight + rowGap + 4)

      let topDotY = y + fromHeight / 2
      let bottomDotY = y + fromHeight + rowGap + toHeight / 2
      let dotX = margin + 4

      line.setStroke()
      let connector = UIBezierPath()
      connector.move(to: CGPoint(x: dotX, y: topDotY + 4))
      connector.addLine(to: CGPoint(x: dotX, y: bottomDotY - 4))
      connector.lineWidth = 1
      connector.setLineDash([1.5, 1.8], count: 2, phase: 0)
      connector.stroke()

      muted.setStroke()
      [topDotY, bottomDotY].forEach { dotY in
        let dot = UIBezierPath(ovalIn: CGRect(x: dotX - 2.5, y: dotY - 2.5, width: 5, height: 5))
        dot.lineWidth = 1.1
        dot.stroke()
      }

      drawString(from, in: CGRect(x: margin + dotColumn, y: y, width: addressWidth, height: fromHeight), font: addressFont, color: ink)
      drawString(to, in: CGRect(x: margin + dotColumn, y: y + fromHeight + rowGap, width: addressWidth, height: toHeight), font: addressFont, color: ink)
      y += fromHeight + rowGap + toHeight + 8
    } else {
      let label = row.source == "GPS" ? "\(row.vehicle.label) trip" : "Manual entry - \(row.vehicle.label)"
      drawWrapped(label, font: addressFont, color: muted, spacingAfter: 8)
    }

    let rate = row.miles > 0 ? row.deduction / row.miles : 0
    ensure(34)
    drawString("Business - delivery driving (\(row.vehicle.label))", in: CGRect(x: margin, y: y, width: contentWidth * 0.5, height: 16), font: .systemFont(ofSize: 10.5, weight: .semibold), color: ink)
    drawString(gbp(row.deduction), in: CGRect(x: margin + contentWidth * 0.5, y: y, width: contentWidth * 0.5, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: ink, alignment: .right)
    y += 16
    drawString(miles(row.miles), in: CGRect(x: margin, y: y, width: contentWidth * 0.5, height: 14), font: .systemFont(ofSize: 9.5, weight: .regular), color: muted)
    drawString("\(gbp(rate)) / mi", in: CGRect(x: margin + contentWidth * 0.5, y: y, width: contentWidth * 0.5, height: 14), font: .systemFont(ofSize: 9.5, weight: .regular), color: muted, alignment: .right)
    y += 18
    drawHairline()
    y += 8
  }
}
