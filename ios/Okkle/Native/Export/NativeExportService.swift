import SwiftUI
struct NativeExportCard: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var shareItem: NativeShareItem?
  @State private var exportFailed = false
  // Group row -> document (when a group holds more than one) -> format,
  // rather than a fixed row per file kind — same underlying exports, far
  // less to scan, and PDF/CSV/both is only asked where more than one exists.
  @State private var pendingGroup: NativeTaxExportGroup?
  @State private var pendingDocument: NativeExportDocument?

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
    .confirmationDialog(
      pendingGroup?.title ?? "",
      isPresented: Binding(get: { pendingGroup != nil }, set: { if !$0 { pendingGroup = nil } }),
      titleVisibility: .visible
    ) {
      ForEach(NativeExportDocument.allCases.filter { $0.group == pendingGroup }) { document in
        Button(document.title) { selectDocument(document) }
      }
      Button("Cancel", role: .cancel) {}
    }
    .confirmationDialog(
      "Export \(pendingDocument?.title ?? "") as",
      isPresented: Binding(get: { pendingDocument != nil }, set: { if !$0 { pendingDocument = nil } }),
      titleVisibility: .visible
    ) {
      if let document = pendingDocument {
        ForEach(document.formats) { format in
          Button(format.label) { export(document, formats: [format]) }
        }
        if document.formats.count > 1 {
          Button("Both") { export(document, formats: document.formats) }
        }
      }
      Button("Cancel", role: .cancel) {}
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
    let documents = NativeExportDocument.allCases.filter { $0.group == group }
    return Button {
      if documents.count == 1, let only = documents.first {
        selectDocument(only)
      } else {
        pendingGroup = group
      }
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
          Text(documents.map(\.title).joined(separator: " · "))
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

  private func selectDocument(_ document: NativeExportDocument) {
    if document.formats.count > 1 {
      pendingDocument = document
    } else if let format = document.formats.first {
      export(document, formats: [format])
    }
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

@MainActor
func nativeMakeExport(_ kinds: [NativeTaxExportKind], store: OkkleStore) -> NativeShareItem? {
  let urls = kinds.compactMap { nativeMakeExportFile($0, store: store) }
  guard !urls.isEmpty else { return nil }
  return NativeShareItem(urls: urls)
}

@MainActor
private func nativeMakeExportFile(_ kind: NativeTaxExportKind, store: OkkleStore) -> URL? {
  let fileName = "Okkle_\(kind.fileStem)_TaxYear-\(nativeTaxYearLabel(for: store.taxYear))_\(nativeTodayStamp()).\(kind.fileExtension)"
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
  var rows: [[String]] = [
    ["Field", "Value"],
    ["Tax year", nativeTaxYearLabel(for: store.taxYear)],
    ["Turnover (income)", nativeDecimal(tax.turnover)],
    ["Logged expenses", nativeDecimal(tax.expenses)],
    ["Deduction applied", nativeDecimal(tax.deductionApplied)],
    ["Taxable profit", nativeDecimal(tax.profit)],
    ["Income tax band", store.settings.incomeBracket.label],
    ["Other income", nativeDecimal(store.settings.otherIncome)],
    ["Estimated Income Tax", nativeDecimal(tax.incomeTax)],
    ["Estimated Class 4 NIC", nativeDecimal(tax.class4)],
    ["Estimated total due", nativeDecimal(tax.totalDue)]
  ]
  if tax.paymentOnAccount > 0 {
    rows.append(["Payment on account (each)", nativeDecimal(tax.paymentOnAccount)])
  }
  rows.append(["Business miles", nativeDecimal(store.yearMiles)])
  rows.append(["Mileage deduction", nativeDecimal(store.yearMileageDeduction)])
  return rows.map { $0.map(nativeCsvField).joined(separator: ",") }.joined(separator: "\n")
}

@MainActor
func nativeAccountantPackCsv(store: OkkleStore) -> String {
  [
    nativeSelfAssessmentCsv(store: store),
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
  let header = "Date,Vehicle,Source,Miles,Basis,Deduction GBP,From,To"
  let rows = store.yearMileageLogRows.map { row in
    [
      nativeCsvField(nativeDateStamp(row.date)),
      nativeCsvField(row.vehicle.label),
      nativeCsvField(row.source),
      nativeCsvField(nativeDecimal(row.miles)),
      nativeCsvField("HMRC simplified"),
      nativeCsvField(nativeDecimal(row.deduction)),
      nativeCsvField(row.fromAddress ?? ""),
      nativeCsvField(row.toAddress ?? "")
    ].joined(separator: ",")
  }
  return ([header] + rows).joined(separator: "\n")
}

@MainActor
func nativeFreeAgentCsv(store: OkkleStore) -> String {
  let rows = store.records
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
      return [
        nativeCsvField(nativeUkDateStamp(record.date)),
        nativeCsvField(nativeDecimal(amount)),
        nativeCsvField(exportDescription)
      ].joined(separator: ",")
    }
  return (["Date,Amount,Description"] + rows).joined(separator: "\n")
}

@MainActor
func nativeAllDataCsv(store: OkkleStore) -> String {
  let header = "date,type,platform,vehicle,miles,deduction,amount,category,merchant,note"
  let tripRows = store.trips.map { trip in
    [
      nativeCsvField(nativeDateStamp(trip.startedAt)),
      nativeCsvField("trip"),
      nativeCsvField(""),
      nativeCsvField(trip.vehicle.label),
      nativeCsvField(nativeDecimal(trip.miles)),
      nativeCsvField(nativeDecimal(trip.deduction)),
      nativeCsvField(""),
      nativeCsvField(""),
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

@MainActor
func nativeAccountantPackPdfData(store: OkkleStore) -> Data {
  NativeAccountantPackPdfRenderer(store: store).render()
}
