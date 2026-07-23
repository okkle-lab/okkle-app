import SwiftUI

struct NativeTaxDetailView: View {
  var onClose: (() -> Void)? = nil
  @EnvironmentObject private var store: OkkleStore
  @State private var detail: NativeTaxOverviewDetail?
  @State private var showsDeadlines = false

  var body: some View {
    NativeScreen(title: "Reports", collapsedTitle: "Reports", subtitle: "Your estimate, deductions and accountant exports.", onClose: onClose) {
      let tax = store.taxPosition
      let savings = NativeProgressSummary.mileageTaxSavings(store: store, period: .yearToDate)

      VStack(alignment: .leading, spacing: 14) {
        priorityBanner(savings: savings)

        NativeTaxOverviewStatsCard(
          due: gbp(tax.totalDue),
          saved: gbp(savings.taxSaved),
          profit: gbp(tax.profit),
          onTapDue: { detail = .bill },
          onTapSaved: { detail = .saved },
          onTapProfit: { detail = .year }
        )

        NativeTaxOverviewGroup {
          NativeTaxDeadlinesButton(authority: store.settings.taxCountry == .us ? "IRS" : "HMRC") {
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
      NativeKeyTaxDatesSheet(country: store.settings.taxCountry, usState: store.settings.usState)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .onAppear {
      NativeTripAddressResolver.backfillMissingAddresses(store: store)
    }
  }

  @ViewBuilder
  private func priorityBanner(savings: NativeMileageTaxSavings) -> some View {
    if shouldShowMileageBandNudge {
      NativeTaxMileageNudge(miles: savings.miles)
    }
  }

  private var shouldShowMileageBandNudge: Bool {
    // The 10,000-mile rate drop is a UK simplified-mileage rule; the US
    // standard rate has no tier, and actual-cost drivers don't use the
    // mileage rate at all.
    store.settings.taxCountry == .uk
      && store.settings.expenseMethod == .simplified
      && (store.settings.defaultVehicle == .car || store.settings.defaultVehicle == .van)
      && store.yearMiles > 0
      && store.yearMiles < 10_000
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

        Text(gbp(tax.totalDue))
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

private struct NativeTaxOverviewStatsCard: View {
  let due: String
  let saved: String
  let profit: String
  let onTapDue: () -> Void
  let onTapSaved: () -> Void
  let onTapProfit: () -> Void

  var body: some View {
    NativeGlassCard(cornerRadius: 28, contentPadding: 18) {
      VStack(alignment: .leading, spacing: 16) {
        Label("Tax overview", systemImage: "shield.lefthalf.filled")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(OkkleColor.brandDark)

        HStack(alignment: .top, spacing: 0) {
          stat(title: "Due", value: due, action: onTapDue)
          Divider().frame(height: 46)
          stat(title: "Saved", value: saved, color: OkkleColor.brand, action: onTapSaved)
          Divider().frame(height: 46)
          stat(title: "Profit", value: profit, action: onTapProfit)
        }
      }
    }
  }

  private func stat(title: String, value: String, color: Color = OkkleColor.ink, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
        Text(value)
          .font(.system(size: 19, weight: .heavy, design: .rounded))
          .foregroundStyle(color)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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

private struct NativeTaxDeadlinesButton: View {
  var authority: String = "HMRC"
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
          Text("View \(authority) deadlines and add to Calendar")
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
        NativeTaxBreakdownHeader(title: "Set aside", value: gbp(tax.totalDue), symbol: "shield.lefthalf.filled")
        NativeTaxDetailRow("Income tax", gbp(tax.incomeTax))
        NativeTaxDetailRow("Class 4 NIC", gbp(tax.class4), info: NativeTaxTerm.class4NIC)
        NativeTaxDetailRow("Payment on account", gbp(tax.paymentOnAccount), info: NativeTaxTerm.paymentOnAccount)
        NativeTaxDetailRow("Taxable profit", gbp(tax.profit), info: NativeTaxTerm.taxableProfit)
        NativeTaxDetailRow("Income tax band", store.settings.incomeBracket.label, info: NativeTaxTerm.incomeTaxBand)
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
        NativeTaxBreakdownHeader(title: "Tax saved this year", value: gbp(savings.taxSaved), symbol: "chart.line.uptrend.xyaxis")
        NativeTaxDetailRow("Business miles", miles(savings.miles))
        NativeTaxDetailRow("Mileage deduction", gbp(savings.mileageDeduction))
        NativeTaxDetailRow("Income tax band", store.settings.incomeBracket.label)
        NativeTaxDetailRow("Estimated saving", gbp(savings.taxSaved), emphasized: true)
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
        NativeTaxBreakdownHeader(title: "This year", value: gbp(tax.profit), symbol: "briefcase.fill")
        NativeTaxDetailRow("Turnover", gbp(tax.turnover))
        NativeTaxDetailRow("Logged expenses", gbp(tax.expenses))
        NativeTaxDetailRow("Business profit", gbp(tax.businessProfit))
        NativeTaxDetailRow("Deduction applied", gbp(tax.deductionApplied), info: NativeTaxTerm.deductionApplied)
        NativeTaxDetailRow("Trading allowance", tax.usesTradingAllowance ? "Used" : "Not used", info: NativeTaxTerm.tradingAllowance)
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
  var info: String? = nil
  @State private var showsInfo = false

  init(_ label: String, _ value: String, emphasized: Bool = false, info: String? = nil) {
    self.label = label
    self.value = value
    self.emphasized = emphasized
    self.info = info
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      HStack(spacing: 4) {
        Text(label)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
        if let info {
          Button {
            showsInfo = true
          } label: {
            Image(systemName: "info.circle")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(OkkleColor.muted.opacity(0.65))
          }
          .buttonStyle(.plain)
          .alert(label, isPresented: $showsInfo) {
            Button("Got it", role: .cancel) {}
          } message: {
            Text(info)
          }
        }
      }
      Spacer(minLength: 12)
      Text(value)
        .font(.system(size: 16, weight: emphasized ? .heavy : .bold, design: .rounded))
        .foregroundStyle(emphasized ? OkkleColor.brandDark : OkkleColor.ink)
        .multilineTextAlignment(.trailing)
    }
  }
}

/// Short, plain-English explanations for the tax jargon shown on this
/// screen — surfaced inline via the (i) buttons above rather than as a
/// separate glossary page, so it stays beginner-friendly without adding
/// another list to scroll through.
private enum NativeTaxTerm {
  static let class4NIC = "A National Insurance charge for self-employed profits above £12,570 a year, on top of income tax."
  static let paymentOnAccount = "An advance instalment HMRC asks for towards next year's bill, paid alongside this year's — only kicks in once your bill passes a threshold."
  static let incomeTaxBand = "The rate HMRC charges on income above your tax-free Personal Allowance. It rises in steps as you earn more."
  static let taxableProfit = "Turnover minus allowable expenses (or the Trading Allowance) — the amount tax is actually calculated on."
  static let deductionApplied = "The mileage or expense deduction subtracted from turnover before working out what's taxed."
  static let tradingAllowance = "The first £1,000 of self-employed income each tax year that's automatically tax-free, no expense logging needed."
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

      Text(gbp(savings.taxSaved))
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
          Text(gbp(tax.totalDue))
            .font(.system(size: 52, weight: .heavy, design: .rounded))
          Text("Estimate only, not tax advice. Built from your logged earnings, expenses, mileage and selected tax band.")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
        }
      }

      HStack(spacing: 12) {
        taxMetricPanel(title: "Turnover", value: gbp(tax.turnover), symbol: "sterlingsign.circle.fill", color: .green)
        taxMetricPanel(title: "Logged expenses", value: gbp(tax.expenses), symbol: "minus.circle.fill", color: OkkleColor.red)
      }

      NativeGlassCard {
        VStack(spacing: 12) {
          taxRow("Business profit", gbp(tax.businessProfit))
          taxRow("Deduction applied", gbp(tax.deductionApplied))
          taxRow("Taxable profit", gbp(tax.profit))
          taxRow("Income tax band", store.settings.incomeBracket.label)
          taxRow("Other income", gbp(store.settings.otherIncome))
          taxRow("Income tax", gbp(tax.incomeTax))
          taxRow("Class 4 NIC", gbp(tax.class4))
          taxRow("Payment on account", gbp(tax.paymentOnAccount))
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
