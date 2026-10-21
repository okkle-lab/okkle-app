import Foundation
import UIKit

/// A standalone one-page tax summary — the same headline figures as the
/// accountant pack's own section, without the rest of the pack, for when
/// only the top-line numbers are needed. UK: Self Assessment Summary. US:
/// Schedule C Summary.
@MainActor
final class NativeSelfAssessmentPdfRenderer: NativePdfDocumentRenderer {
  private let store: OkkleStore
  private var country: NativeTaxCountry { store.settings.taxCountry }

  private var documentTitle: String {
    if store.settings.workStatus == .company { return "Company Summary" }
    return country == .uk ? "Self Assessment Summary" : "Schedule C Summary"
  }

  init(store: OkkleStore) {
    self.store = store
    let footer: String
    if store.settings.workStatus == .company {
      footer = "Okkle company summary"
    } else {
      footer = store.settings.taxCountry == .uk ? "Okkle Self Assessment summary" : "Okkle Schedule C summary"
    }
    super.init(footerText: footer)
  }

  func render() -> Data {
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = [
      kCGPDFContextTitle as String: "Okkle \(documentTitle) \(nativeTaxYearLabel(for: store.taxYear))",
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

    drawWrapped(documentTitle, font: .systemFont(ofSize: 27, weight: .heavy), color: ink, spacingAfter: 4)
    drawWrapped("Turnover, profit and estimated tax due", font: .systemFont(ofSize: 14, weight: .semibold), color: muted, spacingAfter: 13)

    let clientName = store.settings.name.isEmpty ? "Courier" : store.settings.name
    drawInfoBox([
      ("Driver", clientName),
      ("Period", "\(nativePeriodDateStamp(store.taxYear.start, country: country)) to \(nativePeriodDateStamp(taxYearEndDate, country: country))"),
      ("Tax year", nativeTaxYearLabel(for: store.taxYear)),
      ("Prepared", nativeLongDate(Date(), country: country))
    ])
  }

  private func drawFigures() {
    let tax = store.taxPosition
    drawSectionTitle("Figures")
    drawKeyValue("Turnover (income)", gbp(tax.turnover))
    drawKeyValue("Logged expenses", gbp(tax.expenses))
    drawKeyValue("Deduction applied", gbp(tax.deductionApplied))
    drawKeyValue(store.settings.workStatus == .company ? "Profit before tax" : "Taxable profit", gbp(tax.profit), highlighted: true)
    if store.settings.workStatus == .company {
      if country == .uk {
        drawKeyValue("Estimated Corporation Tax", gbp(tax.totalDue), highlighted: true)
      }
      drawKeyValue("Business miles", miles(store.yearMiles))
      drawKeyValue("Mileage reimbursed", gbp(store.yearMileageDeduction))
      return
    }
    switch country {
    case .uk:
      drawKeyValue("Income tax band", store.settings.incomeBracket.label)
      drawKeyValue("Other income", gbp(store.settings.otherIncome))
      drawKeyValue("Estimated Income Tax", gbp(tax.incomeTax))
      drawKeyValue("Estimated Class 4 NIC", gbp(tax.class4))
    case .us:
      drawKeyValue("Standard deduction", gbp(tax.standardDeduction))
      drawKeyValue("QBI deduction (20%)", gbp(tax.qbiDeduction))
      drawKeyValue("Other W-2 wages", gbp(store.settings.otherIncome))
      drawKeyValue("Estimated federal income tax", gbp(tax.incomeTax))
      drawKeyValue("Estimated self-employment tax", gbp(tax.class4))
      if tax.stateTax > 0 {
        drawKeyValue("Estimated state tax (\(store.settings.usState.label))", gbp(tax.stateTax))
      }
    }
    drawKeyValue("Estimated total due", gbp(tax.totalDue), highlighted: true)
    if tax.paymentOnAccount > 0 {
      switch country {
      case .uk:
        drawKeyValue("Payment on account (x2)", "\(gbp(tax.paymentOnAccount)) each")
      case .us:
        drawKeyValue("Suggested quarterly set-aside (1040-ES)", gbp(tax.paymentOnAccount))
      }
    }
    drawKeyValue("Business miles", miles(store.yearMiles))
    drawKeyValue("Mileage deduction", gbp(store.yearMileageDeduction))
  }

  private func drawLimitations() {
    drawDisclaimer(
      "Basis and limitations",
      "Prepared by Okkle from records kept on the user's device. Estimates only, not tax advice. Confirm with your accountant."
    )
  }
}

@MainActor
func nativeSelfAssessmentPdfData(store: OkkleStore) -> Data {
  NativeSelfAssessmentPdfRenderer(store: store).render()
}
