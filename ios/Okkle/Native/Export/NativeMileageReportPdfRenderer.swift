import Foundation
import UIKit

/// A standalone mileage report — driver/period details, a summary (grouped
/// by rate band for a UK simplified-mileage driver, matching the "first
/// 10,000 miles" / "remaining miles" split HMRC's flat rate uses; a single
/// per-vehicle line for a US IRS standard-mileage driver; a note instead for
/// a UK actual-cost driver, who doesn't use a mileage rate at all), then the
/// full per-entry log. A lighter companion to the full accountant pack, for
/// when only the mileage evidence is needed.
@MainActor
final class NativeMileageReportPdfRenderer: NativePdfDocumentRenderer {
  private let store: OkkleStore
  private var country: NativeTaxCountry { store.settings.taxCountry }

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

  private var mileageReportSubtitle: String {
    switch country {
    case .uk:
      return store.settings.expenseMethod == .simplified
        ? "HMRC simplified-rate mileage log for Self Assessment"
        : "Business mileage log — vehicle costs claimed as actual expenses"
    case .us:
      return "IRS standard mileage rate log for Schedule C"
    }
  }

  private var mileageReportExplainer: String {
    switch country {
    case .uk:
      return store.settings.expenseMethod == .simplified
        ? "Mileage claimed using HMRC's simplified expenses flat rate — figures are generated on-device from records logged in Okkle."
        : "This log evidences business mileage. Vehicle costs are claimed from expense records rather than a mileage rate — figures are generated on-device from records logged in Okkle."
    case .us:
      return "Mileage claimed using the IRS standard mileage rate — figures are generated on-device from records logged in Okkle."
    }
  }

  private func drawCover() {
    brand.setFill()
    UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: 86, height: 5), cornerRadius: 2.5).fill()
    y += 20

    drawWrapped("Mileage Report", font: .systemFont(ofSize: 27, weight: .heavy), color: ink, spacingAfter: 4)
    drawWrapped(mileageReportSubtitle, font: .systemFont(ofSize: 14, weight: .semibold), color: muted, spacingAfter: 13)

    let clientName = store.settings.name.isEmpty ? "Courier" : store.settings.name
    drawInfoBox([
      ("Driver", clientName),
      ("Vehicle", store.settings.defaultVehicle.label),
      ("Period", "\(nativePeriodDateStamp(store.taxYear.start, country: country)) to \(nativePeriodDateStamp(taxYearEndDate, country: country))"),
      ("Tax year", nativeTaxYearLabel(for: store.taxYear)),
      ("Prepared", nativeLongDate(Date(), country: country))
    ])

    drawWrapped(
      mileageReportExplainer,
      font: .systemFont(ofSize: 10.5, weight: .regular),
      color: muted,
      spacingAfter: 14
    )
  }

  private func drawSummary() {
    drawSectionTitle("Summary")
    switch (country, store.settings.expenseMethod) {
    case (.uk, .simplified):
      drawUkSimplifiedSummaryRows()
    case (.uk, .actualCost):
      drawWrapped(
        "Vehicle costs are claimed as actual expenses on this account, so no mileage rate applies here — see the expense records in the accountant pack for the costs claimed.",
        font: .systemFont(ofSize: 10.5, weight: .regular),
        color: muted,
        spacingAfter: 8
      )
    case (.us, _):
      drawUsSummaryRows()
    }
    drawKeyValue("Total miles", miles(store.yearMiles))
    drawKeyValue("Total deduction", gbp(store.yearMileageDeduction), highlighted: true)
  }

  private func drawUkSimplifiedSummaryRows() {
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
  }

  /// The US IRS standard mileage rate has no UK-style 10,000-mile band, so
  /// this groups by vehicle only, deriving each row's rate from the rows'
  /// own (already country-dispatched) deduction total rather than reading
  /// the UK-only NativeVehicle.rateBand table directly.
  private func drawUsSummaryRows() {
    let rows = store.yearMileageLogRows
    var summaryRows: [[String]] = []
    for vehicle in NativeVehicle.allCases {
      let vehicleRows = rows.filter { $0.vehicle == vehicle }
      let vehicleMiles = vehicleRows.reduce(0.0) { $0 + $1.miles }
      guard vehicleMiles > 0 else { continue }
      let deduction = vehicleRows.reduce(0.0) { $0 + $1.deduction }
      let effectiveRate = vehicleMiles > 0 ? deduction / vehicleMiles : 0
      summaryRows.append(["Business - \(vehicle.label) @ \(gbp(effectiveRate))/mi", miles(vehicleMiles), gbp(deduction)])
    }

    drawTable(
      headers: ["Type", "Distance", "Amount"],
      rows: summaryRows,
      widths: [0.52, 0.24, 0.24],
      rightAligned: [1, 2],
      emptyMessage: "No mileage logged for this tax year."
    )
  }

  private func drawLog() {
    drawSectionTitle("Mileage log")
    drawMileageJournal(store.yearMileageLogRows, country: country)
  }

  private func drawLimitations() {
    drawDisclaimer(
      "Basis and limitations",
      "Prepared by Okkle from records kept on the user's device. Figures are estimates derived from logged data and do not constitute tax advice. Confirm completeness and final figures before submission."
    )
  }
}

@MainActor
func nativeMileageReportPdfData(store: OkkleStore) -> Data {
  NativeMileageReportPdfRenderer(store: store).render()
}
