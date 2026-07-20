import Foundation
import UIKit

/// A standalone HMRC-style mileage report — driver/period details, a
/// summary grouped by rate band (matching the "first 10,000 miles" /
/// "remaining miles" split HMRC's simplified mileage rate uses), then the
/// full per-entry log. A lighter companion to the full accountant pack, for
/// when only the mileage evidence is needed.
@MainActor
final class NativeMileageReportPdfRenderer: NativePdfDocumentRenderer {
  private let store: OkkleStore

  init(store: OkkleStore) {
    self.store = store
    super.init(footerText: "Okkle mileage report")
  }

  func render() -> Data {
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = [
      kCGPDFContextTitle as String: "Okkle Mileage Report \(nativeTaxYearLabel(for: store.taxYear))",
      kCGPDFContextCreator as String: "Okkle"
    ]
    let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
    return renderer.pdfData { rendererContext in
      context = rendererContext
      beginPage()
      drawCover()
      drawSummary()
      drawLog()
      drawLimitations()
    }
  }

  private var taxYearEndDate: Date {
    Calendar.current.date(byAdding: .day, value: -1, to: store.taxYear.end) ?? store.taxYear.end
  }

  private func drawCover() {
    brand.setFill()
    UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: 86, height: 5), cornerRadius: 2.5).fill()
    y += 20

    drawWrapped("Mileage Report", font: .systemFont(ofSize: 27, weight: .heavy), color: ink, spacingAfter: 4)
    drawWrapped("HMRC simplified-rate mileage log for Self Assessment", font: .systemFont(ofSize: 14, weight: .semibold), color: muted, spacingAfter: 13)

    let clientName = store.settings.name.isEmpty ? "Courier" : store.settings.name
    drawInfoBox([
      ("Driver", clientName),
      ("Vehicle", store.settings.defaultVehicle.label),
      ("Period", "\(nativeUkDateStamp(store.taxYear.start)) to \(nativeUkDateStamp(taxYearEndDate))"),
      ("Tax year", nativeTaxYearLabel(for: store.taxYear)),
      ("Prepared", nativeLongDate(Date()))
    ])

    drawWrapped(
      "Mileage claimed using HMRC's simplified expenses flat rate — figures are generated on-device from records logged in Okkle.",
      font: .systemFont(ofSize: 10.5, weight: .regular),
      color: muted,
      spacingAfter: 14
    )
  }

  private func drawSummary() {
    drawSectionTitle("Summary")
    let rows = store.yearMileageLogRows
    let referenceDate = store.taxYear.start

    var summaryRows: [[String]] = []
    let carVanMiles = rows.filter { $0.vehicle == .car || $0.vehicle == .van }.reduce(0.0) { $0 + $1.miles }
    if carVanMiles > 0 {
      // Car and van share one combined 10,000-mile band under HMRC's rules,
      // regardless of which of the two was actually driven for any given
      // entry — the label uses whichever the driver has set as default.
      let rate = store.settings.defaultVehicle.rateBand(on: referenceDate)
      let firstBandMiles = min(carVanMiles, 10_000)
      let afterBandMiles = max(0, carVanMiles - 10_000)
      summaryRows.append(["Business - first 10,000 mi @ \(gbp(rate.first))/mi", miles(firstBandMiles), gbp(firstBandMiles * rate.first)])
      if afterBandMiles > 0 {
        summaryRows.append(["Business - over 10,000 mi @ \(gbp(rate.after))/mi", miles(afterBandMiles), gbp(afterBandMiles * rate.after)])
      }
    }
    for vehicle in [NativeVehicle.motorbike, .bike] {
      let vehicleMiles = rows.filter { $0.vehicle == vehicle }.reduce(0.0) { $0 + $1.miles }
      guard vehicleMiles > 0 else { continue }
      let rate = vehicle.rateBand(on: referenceDate).first
      summaryRows.append(["Business - \(vehicle.label) @ \(gbp(rate))/mi", miles(vehicleMiles), gbp(vehicleMiles * rate)])
    }

    drawTable(
      headers: ["Type", "Distance", "Amount"],
      rows: summaryRows,
      widths: [0.52, 0.24, 0.24],
      rightAligned: [1, 2],
      emptyMessage: "No mileage logged for this tax year."
    )
    drawKeyValue("Total miles", miles(store.yearMiles))
    drawKeyValue("Total deduction", gbp(store.yearMileageDeduction), highlighted: true)
  }

  private func drawLog() {
    drawSectionTitle("Mileage log")
    let rows = store.yearMileageLogRows
    guard !rows.isEmpty else {
      drawWrapped("No mileage logged for this tax year.", font: .systemFont(ofSize: 10, weight: .regular), color: muted, spacingAfter: 0)
      return
    }

    var lastDateKey: String?
    for row in rows {
      let dateKey = nativeDateStamp(row.date)
      drawJourneyEntry(row, showDate: dateKey != lastDateKey)
      lastDateKey = dateKey
    }
  }

  /// One journey — a from/to address pair (when resolved) plus its
  /// business/distance/rate/amount line, in the style of a standard HMRC
  /// mileage log rather than a bare summary table. Falls back to a plain
  /// one-line entry for manual records or trips whose address hasn't been
  /// resolved yet (no network at the time, or logged before this existed).
  private func drawJourneyEntry(_ row: NativeMileageLogRow, showDate: Bool) {
    if showDate {
      ensure(24)
      drawWrapped(nativeLongDate(row.date), font: .systemFont(ofSize: 11.5, weight: .heavy), color: ink, spacingAfter: 6)
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
    drawString("Business", in: CGRect(x: margin, y: y, width: contentWidth * 0.5, height: 16), font: .systemFont(ofSize: 10.5, weight: .semibold), color: ink)
    drawString(gbp(row.deduction), in: CGRect(x: margin + contentWidth * 0.5, y: y, width: contentWidth * 0.5, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: ink, alignment: .right)
    y += 16
    drawString(miles(row.miles), in: CGRect(x: margin, y: y, width: contentWidth * 0.5, height: 14), font: .systemFont(ofSize: 9.5, weight: .regular), color: muted)
    drawString("\(gbp(rate)) / mi", in: CGRect(x: margin + contentWidth * 0.5, y: y, width: contentWidth * 0.5, height: 14), font: .systemFont(ofSize: 9.5, weight: .regular), color: muted, alignment: .right)
    y += 18
    drawHairline()
    y += 8
  }

  private func drawLimitations() {
    drawSectionTitle("Basis and limitations")
    drawWrapped(
      "Prepared by Okkle from records kept on the user's device. Figures are estimates derived from logged data and do not constitute tax advice. Confirm completeness and final figures before submission.",
      font: .systemFont(ofSize: 10, weight: .regular),
      color: muted,
      spacingAfter: 0
    )
  }
}

@MainActor
func nativeMileageReportPdfData(store: OkkleStore) -> Data {
  NativeMileageReportPdfRenderer(store: store).render()
}
