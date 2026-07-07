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
    drawTable(
      headers: ["Date", "Vehicle", "Source", "Miles", "Deduction"],
      rows: nativeMileageLogTableRows(store.yearMileageLogRows),
      widths: [0.20, 0.22, 0.20, 0.16, 0.22],
      rightAligned: [3, 4],
      emptyMessage: "No mileage logged for this tax year."
    )
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
