import EventKit
import SwiftUI

struct NativeTaxDeadline: Identifiable {
  let title: String
  let month: Int
  let day: Int
  let note: String
  var authority: String = "HMRC"   // calendar-event prefix / owning tax body

  // Includes the date, not just the title — two deadlines can legitimately
  // share a title (e.g. two California instalments both worth 30%); title
  // alone as the id let SwiftUI's list conflate them and render one row
  // twice instead of each on its own real date.
  var id: String { "\(title)-\(month)-\(day)" }

  func nextOccurrence(from reference: Date = Date()) -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: reference)
    let year = calendar.component(.year, from: reference)
    var components = DateComponents(year: year, month: month, day: day, hour: 9, minute: 0)
    var date = calendar.date(from: components) ?? reference
    if date < today {
      components.year = year + 1
      date = calendar.date(from: components) ?? reference
    }
    return date
  }
}

/// Key tax dates by jurisdiction. UK = HMRC Self Assessment calendar; US =
/// the IRS 1040-ES quarterly estimated-tax schedule plus the annual return,
/// plus (when the state levies its own income tax) that state's own
/// estimated-tax deadlines — which are a SEPARATE payment from the federal
/// one even when the dates coincide. US dates verified against irs.gov
/// (Form 1040-ES) and each state's own tax authority; review annually.
///
/// California is the one built-in state with a genuinely different
/// schedule: FTB requires 30% / 40% / 0% / 30% (no September instalment —
/// that share is rolled into January) rather than four equal payments, per
/// ftb.ca.gov/pay/estimated-tax-payments.html. New York, Illinois,
/// Pennsylvania and Georgia all use the same four dates and equal 25%
/// split as the IRS, but still require their own separate voucher/payment.
func nativeTaxDeadlines(
  for country: NativeTaxCountry,
  usState: NativeUSState = .california,
  status: NativeWorkStatus = .selfEmployed,
  companyYearEndMonth: Int = 3,
  companyYearEndDay: Int = 31
) -> [NativeTaxDeadline] {
  if status == .company {
    return nativeCompanyDeadlines(for: country, yearEndMonth: companyYearEndMonth, yearEndDay: companyYearEndDay)
  }
  switch country {
  case .uk:
    return [
      NativeTaxDeadline(title: "Register for Self Assessment", month: 10, day: 5, note: "Only if this was your first year self-employed.", authority: "HMRC"),
      NativeTaxDeadline(title: "File your return & pay your tax", month: 1, day: 31, note: "Online Self Assessment deadline for the previous tax year.", authority: "HMRC"),
      NativeTaxDeadline(title: "Second payment on account", month: 7, day: 31, note: "Only if HMRC asked you for payments on account.", authority: "HMRC"),
    ] + nativeMakingTaxDigitalDeadlines()
  case .us:
    var deadlines: [NativeTaxDeadline] = [
      NativeTaxDeadline(title: "Q1 federal estimated tax (1040-ES)", month: 4, day: 15, note: "25% of your estimated federal tax for the year.", authority: "IRS"),
      NativeTaxDeadline(title: "Q2 federal estimated tax (1040-ES)", month: 6, day: 15, note: "25% of your estimated federal tax for the year.", authority: "IRS"),
      NativeTaxDeadline(title: "Q3 federal estimated tax (1040-ES)", month: 9, day: 15, note: "25% of your estimated federal tax for the year.", authority: "IRS"),
      NativeTaxDeadline(title: "Q4 federal estimated tax (1040-ES)", month: 1, day: 15, note: "25% of your estimated federal tax for the year (covers Sep-Dec of the prior year).", authority: "IRS"),
      NativeTaxDeadline(title: "File your federal return (Form 1040)", month: 4, day: 15, note: "Annual return; Schedule C + Schedule SE for self-employment.", authority: "IRS"),
    ]
    switch usState {
    case .california:
      deadlines.append(contentsOf: [
        NativeTaxDeadline(title: "CA estimated tax - Q1 30% (Form 540-ES)", month: 4, day: 15, note: "California's own schedule - a separate payment from the IRS one due the same day.", authority: "FTB"),
        NativeTaxDeadline(title: "CA estimated tax - Q2 40% (Form 540-ES)", month: 6, day: 15, note: "No California payment is due in September - that share is rolled into January instead.", authority: "FTB"),
        NativeTaxDeadline(title: "CA estimated tax - Q4 30% (Form 540-ES)", month: 1, day: 15, note: "Final California instalment - a separate payment from the IRS one due the same day.", authority: "FTB"),
      ])
    case .newYork:
      deadlines.append(contentsOf: nativeQuarterlyStateDeadlines(state: "New York", form: "IT-2105", authority: "NY Tax Dept"))
    case .illinois:
      deadlines.append(contentsOf: nativeQuarterlyStateDeadlines(state: "Illinois", form: "IL-1040-ES", authority: "IL Dept of Revenue"))
    case .pennsylvania:
      deadlines.append(contentsOf: nativeQuarterlyStateDeadlines(state: "Pennsylvania", form: "PA-40 ESI", authority: "PA Dept of Revenue"))
    case .georgia:
      deadlines.append(contentsOf: nativeQuarterlyStateDeadlines(state: "Georgia", form: "500-ES", authority: "GA Dept of Revenue"))
    default:
      break // No-income-tax states, and states Okkle doesn't yet model by name, get federal dates only.
    }
    return deadlines
  }
}

/// Deadlines for a driver working through their own company.
///
/// UK limited company: all three depend on the accounting period end —
/// Corporation Tax is due 9 months and 1 day after it, accounts go to
/// Companies House within 9 months, and the CT600 return is due 12 months
/// after. US: calendar-year S-corps file Form 1120-S by 15 March and C-corps
/// Form 1120 by 15 April; the owner's personal return is also due 15 April.
func nativeCompanyDeadlines(for country: NativeTaxCountry, yearEndMonth: Int = 3, yearEndDay: Int = 31) -> [NativeTaxDeadline] {
  switch country {
  case .uk:
    let calendar = Calendar(identifier: .gregorian)
    // A non-leap reference year keeps 29 Feb year-ends well defined.
    let month = min(max(yearEndMonth, 1), 12)
    let range = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: 2027, month: month, day: 1))!)!
    let day = min(max(yearEndDay, 1), range.count)
    let yearEnd = calendar.date(from: DateComponents(year: 2027, month: month, day: day))!
    let accounts = calendar.date(byAdding: .month, value: 9, to: yearEnd)!
    let payment = calendar.date(byAdding: .day, value: 1, to: accounts)!
    let returnDue = calendar.date(byAdding: .month, value: 12, to: yearEnd)!
    func deadline(_ title: String, _ date: Date, _ note: String, authority: String = "HMRC") -> NativeTaxDeadline {
      NativeTaxDeadline(
        title: title,
        month: calendar.component(.month, from: date),
        day: calendar.component(.day, from: date),
        note: note,
        authority: authority
      )
    }
    return [
      deadline("Pay Corporation Tax", payment, "9 months and 1 day after your accounting period ends."),
      deadline("File company accounts", accounts, "To Companies House, 9 months after your accounting period ends.", authority: "Companies House"),
      deadline("File Company Tax Return (CT600)", returnDue, "12 months after your accounting period ends."),
      NativeTaxDeadline(title: "File your personal return & pay", month: 1, day: 31, note: "Only if HMRC requires one, for example for dividends.", authority: "HMRC"),
    ]
  case .us:
    return [
      NativeTaxDeadline(title: "S-corp return (Form 1120-S)", month: 3, day: 15, note: "Calendar-year S-corps. Extension via Form 7004.", authority: "IRS"),
      NativeTaxDeadline(title: "C-corp return (Form 1120)", month: 4, day: 15, note: "Calendar-year C-corps. Tax is still due by this date.", authority: "IRS"),
      NativeTaxDeadline(title: "Personal return (Form 1040)", month: 4, day: 15, note: "Your accountant will confirm any estimated payments.", authority: "IRS"),
    ]
  }
}

/// Making Tax Digital for Income Tax quarterly updates. Mandatory from
/// 6 April 2026 for sole traders whose qualifying income (gross turnover) was
/// over £50,000, over £30,000 from April 2027 and over £20,000 from April 2028.
/// Each update is a summary sent through MTD-compatible software, not a tax
/// payment. Deadlines assume the standard 5 April year end. Review annually.
private func nativeMakingTaxDigitalDeadlines() -> [NativeTaxDeadline] {
  let note = "Making Tax Digital only: applies if your turnover is over £50,000 (from April 2026) or £30,000 (from April 2027). A summary update, not a tax payment."
  return [
    (quarter: "Q1", period: "6 Apr-5 Jul", month: 8, day: 7),
    (quarter: "Q2", period: "6 Jul-5 Oct", month: 11, day: 7),
    (quarter: "Q3", period: "6 Oct-5 Jan", month: 2, day: 7),
    (quarter: "Q4", period: "6 Jan-5 Apr", month: 5, day: 7),
  ].map { entry in
    NativeTaxDeadline(
      title: "MTD quarterly update \(entry.quarter) (\(entry.period))",
      month: entry.month,
      day: entry.day,
      note: note,
      authority: "HMRC"
    )
  }
}

/// A state whose estimated-tax schedule matches the IRS's four equal 25%
/// instalments on the same four dates, but which still requires its own
/// separate voucher/payment rather than being covered by the federal one.
private func nativeQuarterlyStateDeadlines(state: String, form: String, authority: String) -> [NativeTaxDeadline] {
  [
    (quarter: "Q1", month: 4, day: 15),
    (quarter: "Q2", month: 6, day: 15),
    (quarter: "Q3", month: 9, day: 15),
    (quarter: "Q4", month: 1, day: 15),
  ].map { entry in
    NativeTaxDeadline(
      title: "\(state) \(entry.quarter) estimated tax (\(form))",
      month: entry.month,
      day: entry.day,
      note: "Separate \(state) payment, same date as the IRS \(entry.quarter) payment.",
      authority: authority
    )
  }
}

func nativeDaysUntil(_ date: Date) -> Int {
  let calendar = Calendar.current
  let today = calendar.startOfDay(for: Date())
  let target = calendar.startOfDay(for: date)
  return calendar.dateComponents([.day], from: today, to: target).day ?? 0
}

func nativeTaxDateLabel(_ date: Date) -> String {
  date.formatted(.dateTime.day().month(.wide).year())
}

@MainActor
func nativeAddDeadlineToCalendar(_ deadline: NativeTaxDeadline) async -> Bool {
  let eventStore = EKEventStore()
  do {
    let granted: Bool
    if #available(iOS 17.0, *) {
      granted = try await eventStore.requestFullAccessToEvents()
    } else {
      granted = try await withCheckedThrowingContinuation { continuation in
        eventStore.requestAccess(to: .event) { granted, error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: granted)
          }
        }
      }
    }
    guard granted, let calendar = eventStore.defaultCalendarForNewEvents else { return false }

    let start = deadline.nextOccurrence()
    let end = Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? start.addingTimeInterval(1800)
    let event = EKEvent(eventStore: eventStore)
    event.calendar = calendar
    event.title = "\(deadline.authority): \(deadline.title)"
    event.startDate = start
    event.endDate = end
    event.notes = deadline.note
    event.addAlarm(EKAlarm(relativeOffset: -60 * 60 * 24 * 7))
    try eventStore.save(event, span: .thisEvent)
    return true
  } catch {
    return false
  }
}

struct NativeKeyTaxDatesPanel: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var showSheet = false

  var body: some View {
    NativeAiCard(banner: "KEY TAX DATES") {
      VStack(alignment: .leading, spacing: 18) {
        Text("Keep HMRC deadlines close")
          .font(.title2.bold())
          .foregroundStyle(.primary)
        Text("Review Self Assessment dates and add reminders to your calendar.")
          .font(.body)
          .foregroundStyle(.secondary)
        Toggle("Tax deadline reminders", isOn: Binding(
          get: { store.settings.taxDeadlineReminders },
          set: { value in
            withAnimation(nativeInsightPromptAnimation) {
              store.settings.taxDeadlineReminders = value
            }
          }
        ))
        .font(.headline)
        .tint(OkkleColor.brand)
        Button {
          showSheet = true
        } label: {
          Label("View dates", systemImage: "calendar")
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .controlSize(.large)
        .tint(OkkleColor.brand)
      }
    }
    .sheet(isPresented: $showSheet) {
      NativeKeyTaxDatesSheet(
        country: store.settings.taxCountry,
        usState: store.settings.usState,
        status: store.settings.workStatus,
        yearEndMonth: store.settings.companyYearEndMonth,
        yearEndDay: store.settings.companyYearEndDay
      )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
  }
}

struct NativeKeyTaxDatesSheet: View {
  var country: NativeTaxCountry = .uk
  var usState: NativeUSState = .california
  var status: NativeWorkStatus = .selfEmployed
  var yearEndMonth = 3
  var yearEndDay = 31
  @Environment(\.dismiss) private var dismiss
  @State private var alertMessage: String?

  private var deadlines: [NativeTaxDeadline] {
    nativeTaxDeadlines(
      for: country,
      usState: usState,
      status: status,
      companyYearEndMonth: yearEndMonth,
      companyYearEndDay: yearEndDay
    )
  }

  private var recordsFootnote: String {
    if status == .company {
      return country == .uk
        ? "Keep company records for at least 6 years from the end of each accounting period."
        : "Keep your mileage log and reimbursement records for at least 3 years."
    }
    switch country {
    case .uk:
      return "Keep your records for at least 5 years after the 31 January deadline. MTD for Income Tax adds quarterly updates once your income passes the threshold."
    case .us:
      return "Keep your mileage log and records for at least 3 years. Pay estimated tax each quarter if you expect to owe $1,000 or more, to avoid an underpayment penalty."
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Text("Add these dates to Calendar with a reminder one week before.")
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          NativeAiCard {
            VStack(spacing: 0) {
              ForEach(deadlines) { deadline in
                NativeTaxDeadlineRow(deadline: deadline) { message in
                  alertMessage = message
                }
                if deadline.id != deadlines.last?.id {
                  Divider().padding(.leading, 0)
                }
              }
            }
          }

          Button {
            Task {
              var added = 0
              for deadline in deadlines {
                if await nativeAddDeadlineToCalendar(deadline) {
                  added += 1
                }
              }
              alertMessage = added == deadlines.count
                ? "All key tax dates were added to your calendar."
                : "Added \(added) of \(deadlines.count) dates. Please allow calendar access and try again for the rest."
            }
          } label: {
            Label("Add all dates", systemImage: "calendar.badge.plus")
              .font(.headline)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.roundedRectangle(radius: 10))
          .controlSize(.large)
          .tint(OkkleColor.brand)

          Text(recordsFootnote)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
      }
      .background(NativeBackground())
      .navigationTitle("Key tax dates")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .fontWeight(.bold)
        }
      }
      .alert("Calendar", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(alertMessage ?? "")
      }
    }
  }
}

struct NativeTaxDeadlineRow: View {
  let deadline: NativeTaxDeadline
  let onResult: (String) -> Void
  @State private var busy = false

  var body: some View {
    let next = deadline.nextOccurrence()
    let days = nativeDaysUntil(next)
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(deadline.title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
        Text("\(nativeTaxDateLabel(next)) - \(daysLabel(days))")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.brand)
        Text(deadline.note)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Button {
        busy = true
        Task {
          let ok = await nativeAddDeadlineToCalendar(deadline)
          busy = false
          onResult(ok
            ? "\(deadline.title) was added to your calendar with a reminder one week before."
            : "Could not add \(deadline.title). Please allow calendar access and try again.")
        }
      } label: {
        Label(busy ? "Adding" : "Add", systemImage: "calendar.badge.plus")
          .font(.subheadline.weight(.semibold))
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
      .tint(OkkleColor.brand)
      .disabled(busy)
    }
    .padding(.vertical, 15)
  }

  private func daysLabel(_ days: Int) -> String {
    if days == 0 { return "today" }
    if days == 1 { return "tomorrow" }
    return "in \(days) days"
  }
}

// MARK: - Analysis

/// One weekday + time-of-day bucket, ranked by how many deliveries land in it.
