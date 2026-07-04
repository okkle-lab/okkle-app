import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision

struct NativeTaxDetailView: View {
  var onClose: (() -> Void)? = nil
  @EnvironmentObject private var store: OkkleStore
  @State private var detail: NativeTaxOverviewDetail?
  @State private var showsDeadlines = false

  var body: some View {
    NativeScreen(title: "Tax", collapsedTitle: "Tax", subtitle: "Your estimate, deductions and accountant exports.", onClose: onClose) {
      let tax = store.taxPosition
      let savings = NativeProgressSummary.mileageTaxSavings(store: store, period: .yearToDate)

      VStack(alignment: .leading, spacing: 14) {
        if let deadline = upcomingDeadline {
          NativeTaxDeadlineBanner(deadline: deadline.deadline, days: deadline.days) {
            showsDeadlines = true
          }
        }

        Button {
          detail = .bill
        } label: {
          NativeTaxSetAsideCard(tax: tax, taxYear: nativeTaxYearLabel(for: store.taxYear))
        }
        .buttonStyle(.plain)

        if shouldShowMileageBandNudge {
          NativeTaxMileageNudge(miles: savings.miles)
        }

        Text("Tap a card for the detail")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .padding(.top, 2)

        NativeTaxOverviewGroup {
          NativeTaxOverviewRow(
            icon: "chart.line.uptrend.xyaxis",
            title: "Tax saved this year",
            subtitle: "From \(miles(savings.miles)) of mileage",
            value: headlineGbp(savings.taxSaved)
          ) {
            detail = .saved
          }

          NativeTaxOverviewDivider()

          NativeTaxOverviewRow(
            icon: "briefcase.fill",
            title: "This year",
            subtitle: "Turnover, expenses & profit",
            value: headlineGbp(tax.profit)
          ) {
            detail = .year
          }

          NativeTaxOverviewDivider()

          NativeTaxDeadlinesButton {
            showsDeadlines = true
          }
        }

        NativeExportCard()

        Text("Estimates are based on your saved Okkle records and selected tax settings. They are not tax advice.")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .sheet(item: $detail) { detail in
      NativeTaxOverviewDetailSheet(detail: detail)
        .environmentObject(store)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showsDeadlines) {
      NativeKeyTaxDatesSheet()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
  }

  private var shouldShowMileageBandNudge: Bool {
    (store.settings.defaultVehicle == .car || store.settings.defaultVehicle == .van)
      && store.yearMiles > 0
      && store.yearMiles < 10_000
  }

  private var upcomingDeadline: (deadline: NativeTaxDeadline, days: Int)? {
    nativeTaxDeadlines
      .map { deadline in (deadline: deadline, days: nativeDaysUntil(deadline.nextOccurrence())) }
      .filter { $0.days >= 0 && $0.days <= 30 }
      .sorted { $0.days < $1.days }
      .first
  }
}

private enum NativeTaxOverviewDetail: String, Identifiable {
  case bill
  case saved
  case year

  var id: String { rawValue }

  var title: String {
    switch self {
    case .bill:
      return "Tax estimate"
    case .saved:
      return "Tax saved"
    case .year:
      return "This year"
    }
  }
}

private struct NativeTaxDeadlineBanner: View {
  let deadline: NativeTaxDeadline
  let days: Int
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: "calendar")
          .font(.system(size: 14, weight: .bold))
        Text(days == 0 ? "\(deadline.title) is today" : "\(days) days to \(deadline.title.lowercased())")
          .font(.system(size: 14, weight: .bold))
          .lineLimit(2)
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .bold))
      }
      .foregroundStyle(OkkleColor.amber)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(OkkleColor.amber.opacity(0.14), in: Capsule())
    }
    .buttonStyle(.plain)
  }
}

private struct NativeTaxSetAsideCard: View {
  let tax: NativeTaxPosition
  let taxYear: String

  var body: some View {
    NativeGlassCard(cornerRadius: 32) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .center) {
          Label("Set aside for tax", systemImage: "shield.lefthalf.filled")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OkkleColor.brandDark)
          Spacer()
          Text(taxYear)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
        }

        Text(headlineGbp(tax.totalDue))
          .font(.system(size: 54, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.58)

        HStack(alignment: .center, spacing: 8) {
          Text("You’re covered for the current tax year so far")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 8)
          Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
        }
      }
    }
  }
}

private struct NativeTaxMileageNudge: View {
  let miles: Double

  private var remaining: Double {
    max(0, 10_000 - miles)
  }

  private var progress: Double {
    min(max(miles / 10_000, 0), 1)
  }

  var body: some View {
    NativeGlassCard(cornerRadius: 24, contentPadding: 16) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          Image(systemName: "gauge.with.dots.needle.bottom.50percent")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(OkkleColor.brand)
          Text("\(Okkle.miles(remaining)) before your rate drops at 10,000 miles")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OkkleColor.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
        ProgressView(value: progress)
          .tint(OkkleColor.brand)
      }
    }
  }
}

private struct NativeTaxOverviewGroup<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .shadow(color: .black.opacity(0.07), radius: 22, y: 12)
  }
}

private struct NativeTaxOverviewDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 64)
  }
}

private struct NativeTaxOverviewRow: View {
  let icon: String
  let title: String
  let subtitle: String
  let value: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: icon)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(OkkleColor.brand)
          .frame(width: 38, height: 38)
          .background(OkkleColor.mint, in: Circle())

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(OkkleColor.ink)
          Text(subtitle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .lineLimit(2)
        }

        Spacer(minLength: 10)

        Text(value)
          .font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.68)

        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(OkkleColor.muted.opacity(0.7))
      }
      .padding(16)
    }
    .buttonStyle(.plain)
  }
}

private struct NativeTaxDeadlinesButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: "calendar.badge.clock")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(OkkleColor.amber)
          .frame(width: 38, height: 38)
          .background(OkkleColor.amber.opacity(0.14), in: Circle())

        VStack(alignment: .leading, spacing: 3) {
          Text("Key tax dates")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(OkkleColor.ink)
          Text("View HMRC deadlines and add to Calendar")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .lineLimit(2)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(OkkleColor.muted.opacity(0.7))
      }
      .padding(16)
    }
    .buttonStyle(.plain)
  }
}

private struct NativeTaxOverviewDetailSheet: View {
  @EnvironmentObject private var store: OkkleStore
  @Environment(\.dismiss) private var dismiss
  let detail: NativeTaxOverviewDetail

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          switch detail {
          case .bill:
            NativeTaxBillBreakdown()
          case .saved:
            NativeTaxSavedBreakdown()
          case .year:
            NativeTaxYearBreakdown()
          }
        }
        .padding(20)
      }
      .background(NativeBackground())
      .navigationTitle(detail.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .fontWeight(.bold)
        }
      }
    }
  }
}

private struct NativeTaxBillBreakdown: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    let tax = store.taxPosition
    NativeGlassCard {
      VStack(spacing: 12) {
        NativeTaxBreakdownHeader(title: "Set aside", value: headlineGbp(tax.totalDue), symbol: "shield.lefthalf.filled")
        NativeTaxDetailRow("Income tax", headlineGbp(tax.incomeTax))
        NativeTaxDetailRow("Class 4 NIC", headlineGbp(tax.class4))
        NativeTaxDetailRow("Payment on account", headlineGbp(tax.paymentOnAccount))
        NativeTaxDetailRow("Taxable profit", headlineGbp(tax.profit))
        NativeTaxDetailRow("Income tax band", store.settings.incomeBracket.label)
      }
    }
  }
}

private struct NativeTaxSavedBreakdown: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    let savings = NativeProgressSummary.mileageTaxSavings(store: store, period: .yearToDate)
    NativeGlassCard {
      VStack(spacing: 12) {
        NativeTaxBreakdownHeader(title: "Tax saved this year", value: headlineGbp(savings.taxSaved), symbol: "chart.line.uptrend.xyaxis")
        NativeTaxDetailRow("Business miles", miles(savings.miles))
        NativeTaxDetailRow("Mileage deduction", headlineGbp(savings.mileageDeduction))
        NativeTaxDetailRow("Income tax band", store.settings.incomeBracket.label)
        NativeTaxDetailRow("Estimated saving", headlineGbp(savings.taxSaved), emphasized: true)
      }
    }
  }
}

private struct NativeTaxYearBreakdown: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    let tax = store.taxPosition
    NativeGlassCard {
      VStack(spacing: 12) {
        NativeTaxBreakdownHeader(title: "This year", value: headlineGbp(tax.profit), symbol: "briefcase.fill")
        NativeTaxDetailRow("Turnover", headlineGbp(tax.turnover))
        NativeTaxDetailRow("Logged expenses", headlineGbp(tax.expenses))
        NativeTaxDetailRow("Business profit", headlineGbp(tax.businessProfit))
        NativeTaxDetailRow("Deduction applied", headlineGbp(tax.deductionApplied))
        NativeTaxDetailRow("Trading allowance", tax.usesTradingAllowance ? "Used" : "Not used")
      }
    }
  }
}

private struct NativeTaxBreakdownHeader: View {
  let title: String
  let value: String
  let symbol: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: symbol)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(OkkleColor.brandDark)
      Text(value)
        .font(.system(size: 42, weight: .heavy, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.58)
      Divider()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct NativeTaxDetailRow: View {
  let label: String
  let value: String
  var emphasized = false

  init(_ label: String, _ value: String, emphasized: Bool = false) {
    self.label = label
    self.value = value
    self.emphasized = emphasized
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      Spacer(minLength: 12)
      Text(value)
        .font(.system(size: 16, weight: emphasized ? .heavy : .bold, design: .rounded))
        .foregroundStyle(emphasized ? OkkleColor.brandDark : OkkleColor.ink)
        .multilineTextAlignment(.trailing)
    }
  }
}

struct NativeTaxSavedPanel: View {
  @EnvironmentObject private var store: OkkleStore
  let period: NativeProgressPeriod

  private var savings: NativeMileageTaxSavings {
    NativeProgressSummary.mileageTaxSavings(store: store, period: period)
  }

  var body: some View {
    let savings = savings
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Image(systemName: "chart.line.uptrend.xyaxis")
          .font(.system(size: 14, weight: .bold))
        Text(title)
          .font(.system(size: 13, weight: .semibold))
      }
      .foregroundStyle(OkkleColor.muted)

      Text(headlineGbp(savings.taxSaved))
        .font(.system(size: 40, weight: .heavy, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.52)

      Text("from \(miles(savings.miles)) · \(gbp(savings.mileageDeduction)) mileage deduction")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
        .fixedSize(horizontal: false, vertical: true)

      Text(periodLabel)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(OkkleColor.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.76), in: Capsule())
        .overlay {
          Capsule()
            .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
        }
        .padding(.top, 2)
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
    .background(OkkleColor.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
  }

  private var title: String {
    switch period {
    case .weekly:
      return "Tax saved this week"
    case .yearToDate:
      return "Tax saved this year"
    case .allTime:
      return "Tax saved all time"
    }
  }

  private var periodLabel: String {
    switch period {
    case .weekly:
      return "This week"
    case .yearToDate:
      return "Tax year \(nativeTaxYearLabel(for: store.taxYear))"
    case .allTime:
      return "All time"
    }
  }
}

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
        taxMetricPanel(title: "Turnover", value: headlineGbp(tax.turnover), symbol: "sterlingsign.circle.fill", color: .green)
        taxMetricPanel(title: "Logged expenses", value: headlineGbp(tax.expenses), symbol: "minus.circle.fill", color: OkkleColor.amber)
      }

      NativeGlassCard {
        VStack(spacing: 12) {
          taxRow("Business profit", headlineGbp(tax.businessProfit))
          taxRow("Deduction applied", headlineGbp(tax.deductionApplied))
          taxRow("Taxable profit", headlineGbp(tax.profit))
          taxRow("Income tax band", store.settings.incomeBracket.label)
          taxRow("Other income", headlineGbp(store.settings.otherIncome))
          taxRow("Income tax", headlineGbp(tax.incomeTax))
          taxRow("Class 4 NIC", headlineGbp(tax.class4))
          taxRow("Payment on account", headlineGbp(tax.paymentOnAccount))
          taxRow("Trading allowance", tax.usesTradingAllowance ? "Used" : "Not used")
        }
      }

      NativeExportCard()
    }
  }

  private func taxMetricPanel(title: String, value: String, symbol: String, color: Color) -> some View {
    NativeGlassCard(contentPadding: 16) {
      VStack(alignment: .leading, spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(color)
        Text(value)
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
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
