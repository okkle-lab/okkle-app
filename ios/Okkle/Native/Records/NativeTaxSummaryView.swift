import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
struct NativeTaxSummaryView: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    let tax = store.taxPosition
    VStack(spacing: 14) {
      NativeGlassCard(cornerRadius: 32) {
        VStack(alignment: .leading, spacing: 14) {
          Label("Estimated tax due", systemImage: "shield.lefthalf.filled")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OkkleColor.brandDark)
          Text(headlineGbp(tax.totalDue))
            .font(.system(size: 52, weight: .heavy, design: .rounded))
          Text("Estimate only, not tax advice. Built from your logged earnings, expenses, mileage and selected tax band.")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
        }
      }

      HStack(spacing: 12) {
        NativeMetricTile(title: "Turnover", value: headlineGbp(tax.turnover), symbol: "sterlingsign.circle.fill", color: .green)
        NativeMetricTile(title: "Logged expenses", value: headlineGbp(tax.expenses), symbol: "minus.circle.fill", color: OkkleColor.amber)
      }

      NativeGlassCard {
        VStack(spacing: 12) {
          taxRow("Business profit", headlineGbp(tax.businessProfit))
          taxRow("Deduction applied", headlineGbp(tax.deductionApplied))
          taxRow("Taxable profit", headlineGbp(tax.profit))
          taxRow("Income tax band", store.settings.incomeBracket.label)
          taxRow("Income tax", headlineGbp(tax.incomeTax))
          taxRow("Class 4 NIC", headlineGbp(tax.class4))
          taxRow("Payment on account", headlineGbp(tax.paymentOnAccount))
          taxRow("Trading allowance", tax.usesTradingAllowance ? "Used" : "Not used")
        }
      }

      NativeExportCard()
    }
  }

  private func taxRow(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      Spacer()
      Text(value)
        .font(.system(size: 16, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
    }
  }
}
