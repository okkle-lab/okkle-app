import Foundation
import UIKit

/// A standalone one-page Self Assessment summary — the same headline
/// figures as the accountant pack's own section, without the rest of the
/// pack, for when only the top-line numbers are needed.
@MainActor
final class NativeSelfAssessmentPdfRenderer: NativePdfDocumentRenderer {
  private let store: OkkleStore

  init(store: OkkleStore) {
    self.store = store
    super.init(footerText: "Okkle Self Assessment summary")
  }

  func render() -> Data {
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = [
      kCGPDFContextTitle as String: "Okkle Self Assessment Summary \(nativeTaxYearLabel(for: store.taxYear))",
      kCGPDFContextCreator as String: "Okkle"
    ]
    let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
    return renderer.pdfData { rendererContext in
      context = rendererContext
      beginPage()
      drawCover()
      drawFigures()
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

    drawWrapped("Self Assessment Summary", font: .systemFont(ofSize: 27, weight: .heavy), color: ink, spacingAfter: 4)
    drawWrapped("Turnover, profit and estimated tax due", font: .systemFont(ofSize: 14, weight: .semibold), color: muted, spacingAfter: 13)

    let clientName = store.settings.name.isEmpty ? "Courier" : store.settings.name
    drawInfoBox([
      ("Driver", clientName),
      ("Period", "\(nativeUkDateStamp(store.taxYear.start)) to \(nativeUkDateStamp(taxYearEndDate))"),
      ("Tax year", nativeTaxYearLabel(for: store.taxYear)),
      ("Prepared", nativeLongDate(Date()))
    ])
  }

  private func drawFigures() {
    let tax = store.taxPosition
    drawSectionTitle("Figures")
    drawKeyValue("Turnover (income)", gbp(tax.turnover))
    drawKeyValue("Logged expenses", gbp(tax.expenses))
    drawKeyValue("Deduction applied", gbp(tax.deductionApplied))
    drawKeyValue("Taxable profit", gbp(tax.profit), highlighted: true)
    drawKeyValue("Income tax band", store.settings.incomeBracket.label)
    drawKeyValue("Other income", gbp(store.settings.otherIncome))
    drawKeyValue("Estimated Income Tax", gbp(tax.incomeTax))
    drawKeyValue("Estimated Class 4 NIC", gbp(tax.class4))
    drawKeyValue("Estimated total due", gbp(tax.totalDue), highlighted: true)
    if tax.paymentOnAccount > 0 {
      drawKeyValue("Payment on account (x2)", "\(gbp(tax.paymentOnAccount)) each")
    }
    drawKeyValue("Business miles", miles(store.yearMiles))
    drawKeyValue("Mileage deduction", gbp(store.yearMileageDeduction))
  }

  private func drawLimitations() {
    drawSectionTitle("Basis and limitations")
    drawWrapped(
      "Prepared by Okkle from records kept on the user's device. Estimates only, not tax advice. Confirm with your accountant.",
      font: .systemFont(ofSize: 10, weight: .regular),
      color: muted,
      spacingAfter: 0
    )
  }
}

@MainActor
func nativeSelfAssessmentPdfData(store: OkkleStore) -> Data {
  NativeSelfAssessmentPdfRenderer(store: store).render()
}
