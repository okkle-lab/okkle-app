import SwiftUI

private struct NativeExportRequest {
  let document: NativeExportDocument
  let formats: [NativeExportFormat]
}

struct NativeExportCard: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var shareItem: NativeShareItem?
  @State private var exportFailed = false
  @State private var pendingGroup: NativeTaxExportGroup?
  @State private var queuedExport: NativeExportRequest?

  var body: some View {
    NativeGlassCard(cornerRadius: 30) {
      VStack(alignment: .leading, spacing: 14) {
        Text("Export & share")
          .font(.system(size: 24, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)

        VStack(spacing: 0) {
          ForEach(NativeTaxExportGroup.allCases, id: \.self) { group in
            groupRow(group)
            if group != NativeTaxExportGroup.allCases.last {
              Divider().padding(.leading, 50)
            }
          }
        }
      }
    }
    .sheet(item: $pendingGroup, onDismiss: performQueuedExport) { group in
      NativeExportSelectionPanel(group: group, country: store.settings.taxCountry) { request in
        queuedExport = request
      }
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
      .presentationBackground(.ultraThinMaterial)
      .presentationCornerRadius(36)
      .nativeIPadPagePresentation()
    }
    .sheet(item: $shareItem) { item in
      NativeShareSheet(items: item.urls)
    }
    .alert("Could not create export", isPresented: $exportFailed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Please try again.")
    }
  }

  private func groupRow(_ group: NativeTaxExportGroup) -> some View {
    let documents = NativeExportDocument.available(for: store.settings.taxCountry).filter { $0.group == group }
    return Button {
      pendingGroup = group
    } label: {
      HStack(spacing: 12) {
        Image(systemName: documents.first?.symbol ?? "doc.fill")
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(OkkleColor.brand)
          .frame(width: 38, height: 38)
          .background(OkkleColor.brand.opacity(0.12), in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(group.title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OkkleColor.ink)
          Text(documents.map { $0.title(for: store.settings.taxCountry) }.joined(separator: " · "))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: "square.and.arrow.up")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(OkkleColor.muted)
      }
      .padding(.vertical, 11)
    }
    .buttonStyle(.plain)
  }

  private func performQueuedExport() {
    guard let request = queuedExport else { return }
    queuedExport = nil
    export(request.document, formats: request.formats)
  }

  private func export(_ document: NativeExportDocument, formats: [NativeExportFormat]) {
    let kinds = formats.map { document.kind(for: $0) }
    if let item = nativeMakeExport(kinds, store: store) {
      shareItem = item
    } else {
      exportFailed = true
    }
  }
}

/// A material-backed bottom sheet matching the Add Record type selector. It
/// keeps document and format selection in one native panel so iPad never
/// turns either step into an anchored confirmation popover.
private struct NativeExportSelectionPanel: View {
  let group: NativeTaxExportGroup
  let country: NativeTaxCountry
  let onSelect: (NativeExportRequest) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var selectedDocument: NativeExportDocument?

  private var documents: [NativeExportDocument] {
    NativeExportDocument.available(for: country).filter { $0.group == group }
  }

  private var activeDocument: NativeExportDocument? {
    selectedDocument ?? (documents.count == 1 ? documents.first : nil)
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          if let document = activeDocument {
            formatRows(for: document)
          } else {
            documentRows
          }
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if selectedDocument != nil, documents.count > 1 {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              withAnimation(.easeInOut(duration: 0.18)) {
                selectedDocument = nil
              }
            } label: {
              Label("Back", systemImage: "chevron.left")
            }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.semibold)
        }
      }
    }
  }

  private var navigationTitle: String {
    guard let document = activeDocument else { return group.title }
    return document.formats.count > 1 ? "Export \(document.title(for: country))" : group.title
  }

  @ViewBuilder private var documentRows: some View {
    ForEach(documents) { document in
      exportOptionRow(
        title: document.title(for: country),
        subtitle: document.subtitle(for: country),
        symbol: document.symbol
      ) {
        if document.formats.count > 1 {
          withAnimation(.easeInOut(duration: 0.18)) {
            selectedDocument = document
          }
        } else if let format = document.formats.first {
          choose(document, formats: [format])
        }
      }
    }
  }

  @ViewBuilder private func formatRows(for document: NativeExportDocument) -> some View {
    ForEach(document.formats) { format in
      exportOptionRow(
        title: format.label,
        subtitle: format == .pdf ? "A formatted document ready to share" : "Spreadsheet-ready raw data",
        symbol: format == .pdf ? "doc.richtext.fill" : "tablecells.fill"
      ) {
        choose(document, formats: [format])
      }
    }
    if document.formats.count > 1 {
      exportOptionRow(
        title: "PDF & CSV",
        subtitle: "Create both files together",
        symbol: "doc.on.doc.fill"
      ) {
        choose(document, formats: document.formats)
      }
    }
  }

  private func exportOptionRow(
    title: String,
    subtitle: String,
    symbol: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: symbol)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(OkkleColor.brand)
          .frame(width: 38, height: 38)
          .background(OkkleColor.brand.opacity(0.13), in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(OkkleColor.ink)
          Text(subtitle)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 10)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    .listRowBackground(Color.white.opacity(0.20))
  }

  private func choose(_ document: NativeExportDocument, formats: [NativeExportFormat]) {
    onSelect(NativeExportRequest(document: document, formats: formats))
    dismiss()
  }
}

@MainActor
func nativeMakeExport(_ kinds: [NativeTaxExportKind], store: OkkleStore) -> NativeShareItem? {
  let urls = kinds.compactMap { nativeMakeExportFile($0, store: store) }
  guard !urls.isEmpty else { return nil }
  return NativeShareItem(urls: urls)
}

@MainActor
private func nativeMakeExportFile(_ kind: NativeTaxExportKind, store: OkkleStore) -> URL? {
  let fileName = "Okkle_\(kind.fileStem(for: store.settings.taxCountry))_TaxYear-\(nativeTaxYearLabel(for: store.taxYear))_\(nativeTodayStamp()).\(kind.fileExtension)"
    .replacingOccurrences(of: "/", with: "-")
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
  do {
    switch kind {
    case .accountantPackPdf:
      try nativeAccountantPackPdfData(store: store).write(to: url, options: [.atomic])
    case .mileageReportPdf:
      try nativeMileageReportPdfData(store: store).write(to: url, options: [.atomic])
    case .selfAssessmentPdf:
      try nativeSelfAssessmentPdfData(store: store).write(to: url, options: [.atomic])
    case .accountantPackCsv:
      try nativeAccountantPackCsv(store: store).write(to: url, atomically: true, encoding: .utf8)
    case .selfAssessmentCsv:
      try nativeSelfAssessmentCsv(store: store).write(to: url, atomically: true, encoding: .utf8)
    case .mileageLogCsv:
      try nativeMileageCsv(store: store).write(to: url, atomically: true, encoding: .utf8)
    case .freeAgent:
      try nativeFreeAgentCsv(store: store).write(to: url, atomically: true, encoding: .utf8)
    case .sage:
      try nativeSageCsv(store: store).write(to: url, atomically: true, encoding: .utf8)
    case .quickBooks:
      try nativeQuickBooksCsv(store: store).write(to: url, atomically: true, encoding: .utf8)
    case .xero:
      try nativeXeroCsv(store: store).write(to: url, atomically: true, encoding: .utf8)
    case .wave:
      try nativeWaveCsv(store: store).write(to: url, atomically: true, encoding: .utf8)
    case .allData:
      try nativeAllDataCsv(store: store).write(to: url, atomically: true, encoding: .utf8)
    }
    return url
  } catch {
    return nil
  }
}

@MainActor
func nativeSelfAssessmentCsv(store: OkkleStore) -> String {
  let tax = store.taxPosition
  let country = store.settings.taxCountry
  var rows: [[String]] = [
    ["Field", "Value"],
    ["Tax year", nativeTaxYearLabel(for: store.taxYear)],
    ["Turnover (income)", nativeDecimal(tax.turnover)],
    ["Logged expenses", nativeDecimal(tax.expenses)],
    ["Deduction applied", nativeDecimal(tax.deductionApplied)],
    ["Taxable profit", nativeDecimal(tax.profit)]
  ]
  switch country {
  case .uk:
    rows.append(["Income tax band", store.settings.incomeBracket.label])
    rows.append(["Other income", nativeDecimal(store.settings.otherIncome)])
    rows.append(["Estimated Income Tax", nativeDecimal(tax.incomeTax)])
    rows.append(["Estimated Class 4 NIC", nativeDecimal(tax.class4)])
  case .us:
    rows.append(["Standard deduction", nativeDecimal(tax.standardDeduction)])
    rows.append(["QBI deduction (20%)", nativeDecimal(tax.qbiDeduction)])
    rows.append(["Other W-2 wages", nativeDecimal(store.settings.otherIncome)])
    rows.append(["Estimated federal income tax", nativeDecimal(tax.incomeTax)])
    rows.append(["Estimated self-employment tax", nativeDecimal(tax.class4)])
    if tax.stateTax > 0 {
      rows.append(["Estimated state tax (\(store.settings.usState.label))", nativeDecimal(tax.stateTax)])
    }
  }
  rows.append(["Estimated total due", nativeDecimal(tax.totalDue)])
  if tax.paymentOnAccount > 0 {
    let label = country == .uk ? "Payment on account (each)" : "Suggested quarterly set-aside (1040-ES)"
    rows.append([label, nativeDecimal(tax.paymentOnAccount)])
  }
  rows.append(["Business miles", nativeDecimal(store.yearMiles)])
  rows.append(["Mileage deduction", nativeDecimal(store.yearMileageDeduction)])
  return rows.map { $0.map(nativeCsvField).joined(separator: ",") }.joined(separator: "\n")
}

@MainActor
func nativeExpenseCategoryCsv(store: OkkleStore) -> String {
  var totals: [String: Double] = [:]
  store.yearRecords
    .filter { $0.kind == .expense }
    .forEach { record in
      let category = record.category?.isEmpty == false ? record.category! : "Uncategorised"
      totals[category, default: 0] += record.amount ?? 0
    }
  let rows = totals
    .sorted { $0.value > $1.value }
    .map { [nativeCsvField($0.key), nativeCsvField(nativeDecimal($0.value))].joined(separator: ",") }
  return (["Category,Amount"] + rows).joined(separator: "\n")
}

@MainActor
func nativeAccountantPackCsv(store: OkkleStore) -> String {
  [
    nativeSelfAssessmentCsv(store: store),
    "",
    "Expenses by category",
    nativeExpenseCategoryCsv(store: store),
    "",
    "Mileage log",
    nativeMileageCsv(store: store),
    "",
    "All records",
    nativeAllDataCsv(store: store)
  ].joined(separator: "\n")
}

@MainActor
func nativeMileageCsv(store: OkkleStore) -> String {
  // Scoped to the current tax year, with each row's deduction recomputed
  // against a running car/van total — a trip's own stored `deduction` is
  // set at logging time against a running total of zero, so it's only
  // right below the 10,000-mile HMRC simplified-rate threshold; this way
  // the exported total always matches the tax-year figure shown in Reports.
  let country = store.settings.taxCountry
  let basis: String
  switch (country, store.settings.expenseMethod) {
  case (.uk, .simplified): basis = "HMRC simplified"
  case (.uk, .actualCost): basis = "Actual cost (no mileage rate)"
  case (.us, _): basis = "IRS standard mileage"
  }
  let header = "Date,Vehicle,Source,Miles,Basis,Deduction \(country.currencyCode),From,To"
  let rows = store.yearMileageLogRows.map { row in
    [
      nativeCsvField(nativeDateStamp(row.date)),
      nativeCsvField(row.vehicle.label),
      nativeCsvField(row.source),
      nativeCsvField(nativeDecimal(row.miles)),
      nativeCsvField(basis),
      nativeCsvField(nativeDecimal(row.deduction)),
      nativeCsvField(row.fromAddress ?? ""),
      nativeCsvField(row.toAddress ?? "")
    ].joined(separator: ",")
  }
  return ([header] + rows).joined(separator: "\n")
}

/// One bank-statement-style transaction line, shared by every bookkeeping-
/// software export below — each just formats the same underlying records
/// differently, per that software's own documented CSV import rules.
private struct NativeBookkeepingTransaction {
  let date: Date
  let amount: Double
  let description: String
}

@MainActor
private func nativeBookkeepingTransactions(store: OkkleStore) -> [NativeBookkeepingTransaction] {
  store.records
    .filter { ($0.kind == .income || $0.kind == .expense) && (($0.amount ?? 0) > 0) }
    .sorted { $0.date < $1.date }
    .map { record in
      let amount = record.kind == .expense ? -abs(record.amount ?? 0) : (record.amount ?? 0)
      let description: String
      if record.kind == .income {
        description = "\(record.platform ?? "Platform") earnings"
      } else {
        description = [record.merchant, record.category ?? "Expense"].compactMap { value in
          guard let value, !value.isEmpty else { return nil }
          return value
        }.joined(separator: " - ")
      }
      let cleanNote = record.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let exportDescription = cleanNote.isEmpty ? description : "\(description) - \(cleanNote)"
      return NativeBookkeepingTransaction(date: record.date, amount: amount, description: exportDescription)
    }
}

/// FreeAgent's own CSV spec (support.freeagent.com "Format a CSV file to
/// upload a bank statement"): exactly Date, Amount, Description in that
/// order, dd/mm/yyyy always (not locale-dependent), a single signed Amount
/// column, and — unlike most importers — NO header row at all. FreeAgent's
/// spec also explicitly forbids commas and quote marks anywhere in the file
/// (there's no quote-escaping convention it recognises), so descriptions are
/// sanitised here rather than CSV-quoted the normal way.
@MainActor
func nativeFreeAgentCsv(store: OkkleStore) -> String {
  nativeBookkeepingTransactions(store: store)
    .map { tx in
      [
        nativeUkDateStamp(tx.date),
        nativeDecimal(tx.amount),
        nativeFreeAgentSafeText(tx.description)
      ].joined(separator: ",")
    }
    .joined(separator: "\n")
}

/// FreeAgent has no comma/quote-escaping convention, so those characters are
/// stripped (rather than quoted) to keep the column count intact.
private func nativeFreeAgentSafeText(_ value: String) -> String {
  value
    .replacingOccurrences(of: ",", with: ";")
    .replacingOccurrences(of: "\"", with: "'")
    .replacingOccurrences(of: "\n", with: " ")
}

/// Sage Business Cloud Accounting's CSV bank-statement import (Sage
/// Knowledgebase "Formatting CSV bank statements"): a required header row of
/// Date, Description, Amount, a single signed Amount column (negative =
/// payment/expense, positive = receipt/income — same convention already used
/// for the transactions below), and Sage's own UK default of dd/mm/yyyy.
@MainActor
func nativeSageCsv(store: OkkleStore) -> String {
  let rows = nativeBookkeepingTransactions(store: store).map { tx in
    [
      nativeCsvField(nativeUkDateStamp(tx.date)),
      nativeCsvField(tx.description),
      nativeCsvField(nativeDecimal(tx.amount))
    ].joined(separator: ",")
  }
  return (["Date,Description,Amount"] + rows).joined(separator: "\n")
}

/// QuickBooks Online's 3-column CSV import (Date, Description, Amount) —
/// Intuit's own guidance asks for one consistent date format per file and
/// recommends dd/mm/yyyy specifically, so that's used regardless of the
/// driver's own country.
@MainActor
func nativeQuickBooksCsv(store: OkkleStore) -> String {
  let rows = nativeBookkeepingTransactions(store: store).map { tx in
    [
      nativeCsvField(nativeUkDateStamp(tx.date)),
      nativeCsvField(tx.description),
      nativeCsvField(nativeDecimal(tx.amount))
    ].joined(separator: ",")
  }
  return (["Date,Description,Amount"] + rows).joined(separator: "\n")
}

/// Xero's CSV bank statement import (central.xero.com "Import a bank
/// statement in CSV format") requires the date format to match the Xero
/// organisation's own region setting — dd/mm/yyyy for a UK org, mm/dd/yyyy
/// for a US one — not a fixed ISO stamp, which risks Xero's ambiguous-date
/// prompt or a misread date. Amount is a single signed column; Description
/// is optional but worth including.
@MainActor
func nativeXeroCsv(store: OkkleStore) -> String {
  let country = store.settings.taxCountry
  let rows = nativeBookkeepingTransactions(store: store).map { tx in
    [
      nativeCsvField(nativePeriodDateStamp(tx.date, country: country)),
      nativeCsvField(nativeDecimal(tx.amount)),
      nativeCsvField(tx.description)
    ].joined(separator: ",")
  }
  return (["Date,Amount,Description"] + rows).joined(separator: "\n")
}

/// Wave's statement import (support.waveapps.com "Upload a bank or credit
/// card statement in .csv format") documents its minimum required columns as
/// Date (MM/DD/YYYY), Description, Amount — US-style, not year-first.
@MainActor
func nativeWaveCsv(store: OkkleStore) -> String {
  let rows = nativeBookkeepingTransactions(store: store).map { tx in
    [
      nativeCsvField(nativeUsDateStamp(tx.date)),
      nativeCsvField(tx.description),
      nativeCsvField(nativeDecimal(tx.amount))
    ].joined(separator: ",")
  }
  return (["Date,Description,Amount"] + rows).joined(separator: "\n")
}

@MainActor
func nativeAllDataCsv(store: OkkleStore) -> String {
  let header = "date,type,platform,vehicle,miles,deduction,amount,category,deliveries,merchant,note"
  let tripRows = store.trips.map { trip in
    [
      nativeCsvField(nativeDateStamp(trip.startedAt)),
      nativeCsvField("trip"),
      nativeCsvField(""),
      nativeCsvField(trip.vehicle.label),
      nativeCsvField(nativeDecimal(trip.miles)),
      nativeCsvField(nativeDecimal(trip.deduction)),
      nativeCsvField(""),
      nativeCsvField(trip.category.label),
      nativeCsvField(String(store.deliveryCount(for: trip))),
      nativeCsvField(""),
      nativeCsvField("")
    ].joined(separator: ",")
  }
  let recordRows = store.records.map { record in
    [
      nativeCsvField(nativeDateStamp(record.date)),
      nativeCsvField(record.kind.rawValue),
      nativeCsvField(record.platform ?? ""),
      nativeCsvField(record.vehicle?.label ?? ""),
      nativeCsvField(record.miles.map(nativeDecimal) ?? ""),
      nativeCsvField(record.deduction.map(nativeDecimal) ?? ""),
      nativeCsvField(record.amount.map(nativeDecimal) ?? ""),
      nativeCsvField(record.category ?? ""),
      nativeCsvField(""),
      nativeCsvField(record.merchant ?? ""),
      nativeCsvField(record.note ?? "")
    ].joined(separator: ",")
  }
  return ([header] + tripRows + recordRows).joined(separator: "\n")
}

func nativeCsvField(_ value: String) -> String {
  if value.contains(",") || value.contains("\"") || value.contains("\n") {
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
  return value
}

func nativeDecimal(_ value: Double) -> String {
  String(format: "%.2f", value)
}

func nativeTodayStamp() -> String {
  nativeDateStamp(Date())
}

func nativeDateStamp(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.string(from: date)
}

func nativeUkDateStamp(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_GB")
  formatter.dateFormat = "dd/MM/yyyy"
  return formatter.string(from: date)
}

func nativeUsDateStamp(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US")
  formatter.dateFormat = "MM/dd/yyyy"
  return formatter.string(from: date)
}

/// Display date stamp for the jurisdiction the export is for — dd/MM/yyyy
/// for the UK, MM/dd/yyyy for the US. `nativeDateStamp` (ISO yyyy-MM-dd)
/// stays the one used for filenames and raw-data CSVs, which want an
/// unambiguous, locale-independent format regardless of country.
func nativePeriodDateStamp(_ date: Date, country: NativeTaxCountry) -> String {
  country == .uk ? nativeUkDateStamp(date) : nativeUsDateStamp(date)
}

@MainActor
func nativeAccountantPackPdfData(store: OkkleStore) -> Data {
  NativeAccountantPackPdfRenderer(store: store).render()
}
