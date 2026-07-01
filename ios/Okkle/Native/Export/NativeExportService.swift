import SwiftUI
struct NativeExportCard: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var shareItem: NativeShareItem?
  @State private var exportFailed = false

  var body: some View {
    NativeGlassCard(cornerRadius: 30) {
      VStack(alignment: .leading, spacing: 14) {
        Label("Send to your accountant", systemImage: "square.and.arrow.up")
          .font(.system(size: 16, weight: .heavy))
          .foregroundStyle(OkkleColor.brandDark)
        Text("Export & share")
          .font(.system(size: 24, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Generate files on-device and choose where to send or save them.")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(OkkleColor.muted)

        VStack(spacing: 0) {
          ForEach(NativeTaxExportKind.allCases) { kind in
            Button {
              if let item = nativeMakeExport(kind, store: store) {
                shareItem = item
              } else {
                exportFailed = true
              }
            } label: {
              HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                  .font(.system(size: 17, weight: .bold))
                  .foregroundStyle(OkkleColor.brand)
                  .frame(width: 38, height: 38)
                  .background(OkkleColor.brand.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                  Text(kind.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(OkkleColor.ink)
                  Text(kind.subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OkkleColor.muted)
                    .lineLimit(2)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                  .font(.system(size: 15, weight: .bold))
                  .foregroundStyle(OkkleColor.muted)
              }
              .padding(.vertical, 11)
            }
            .buttonStyle(.plain)

            if kind != .allData {
              Divider().padding(.leading, 50)
            }
          }
        }
      }
    }
    .sheet(item: $shareItem) { item in
      NativeShareSheet(items: [item.url])
    }
    .alert("Could not create export", isPresented: $exportFailed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Please try again.")
    }
  }
}

@MainActor
func nativeMakeExport(_ kind: NativeTaxExportKind, store: OkkleStore) -> NativeShareItem? {
  let fileName = "Okkle_\(kind.fileStem)_TaxYear-\(nativeTaxYearLabel(for: store.taxYear))_\(nativeTodayStamp()).\(kind.fileExtension)"
    .replacingOccurrences(of: "/", with: "-")
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
  do {
    if kind == .accountantPack {
      try nativeAccountantPackPdfData(store: store).write(to: url, options: [.atomic])
    } else {
      let content = nativeExportContents(kind, store: store)
      try content.write(to: url, atomically: true, encoding: .utf8)
    }
    return NativeShareItem(url: url)
  } catch {
    return nil
  }
}

@MainActor
func nativeExportContents(_ kind: NativeTaxExportKind, store: OkkleStore) -> String {
  switch kind {
  case .accountantPack:
    return [
      nativeSelfAssessmentText(store: store),
      "",
      "Mileage log",
      nativeMileageCsv(store: store),
      "",
      "All records",
      nativeAllDataCsv(store: store)
    ].joined(separator: "\n")
  case .freeAgent:
    return nativeFreeAgentCsv(store: store)
  case .selfAssessment:
    return nativeSelfAssessmentText(store: store)
  case .mileageLog:
    return nativeMileageCsv(store: store)
  case .allData:
    return nativeAllDataCsv(store: store)
  }
}

@MainActor
func nativeSelfAssessmentText(store: OkkleStore) -> String {
  let tax = store.taxPosition
  let lines = [
    "Okkle - Self Assessment summary \(nativeTaxYearLabel(for: store.taxYear))",
    "",
    "Turnover (income):        \(gbp(tax.turnover))",
    "Logged expenses:          \(gbp(tax.expenses))",
    "Deduction applied:        \(gbp(tax.deductionApplied))",
    "Taxable profit:           \(gbp(tax.profit))",
    "Income tax band:          \(store.settings.incomeBracket.label)",
    "Other income:             \(gbp(store.settings.otherIncome))",
    "",
    "Estimated Income Tax:     \(gbp(tax.incomeTax))",
    "Estimated Class 4 NIC:    \(gbp(tax.class4))",
    "Estimated total due:      \(gbp(tax.totalDue))",
    tax.paymentOnAccount > 0 ? "Payment on account (x2):  \(gbp(tax.paymentOnAccount)) each" : "",
    "",
    "Business miles:           \(miles(store.yearMiles))",
    "Mileage deduction:        \(gbp(store.yearMileageDeduction))",
    "",
    "Estimates only, not tax advice. Confirm with your accountant."
  ]
  return lines.filter { !$0.isEmpty }.joined(separator: "\n")
}

@MainActor
func nativeMileageCsv(store: OkkleStore) -> String {
  let header = "Date,Vehicle,Source,Miles,Basis,Deduction GBP"
  let tripRows = store.trips.sorted { $0.startedAt < $1.startedAt }.map { trip in
    [
      nativeCsvField(nativeDateStamp(trip.startedAt)),
      nativeCsvField(trip.vehicle.label),
      nativeCsvField("GPS"),
      nativeCsvField(nativeDecimal(trip.miles)),
      nativeCsvField("HMRC simplified"),
      nativeCsvField(nativeDecimal(trip.deduction))
    ].joined(separator: ",")
  }
  let manualRows = store.records
    .filter { $0.kind == .mileage }
    .sorted { $0.date < $1.date }
    .map { record in
      [
        nativeCsvField(nativeDateStamp(record.date)),
        nativeCsvField(record.vehicle?.label ?? "Vehicle"),
        nativeCsvField("Manual"),
        nativeCsvField(nativeDecimal(record.miles ?? 0)),
        nativeCsvField("HMRC simplified"),
        nativeCsvField(nativeDecimal(record.deduction ?? 0))
      ].joined(separator: ",")
    }
  return ([header] + tripRows + manualRows).joined(separator: "\n")
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
      return [
        nativeCsvField(nativeUkDateStamp(record.date)),
        nativeCsvField(nativeDecimal(amount)),
        nativeCsvField(description)
      ].joined(separator: ",")
    }
  return (["Date,Amount,Description"] + rows).joined(separator: "\n")
}

@MainActor
func nativeAllDataCsv(store: OkkleStore) -> String {
  let header = "date,type,platform,vehicle,miles,deduction,amount,category,merchant"
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
      nativeCsvField(record.merchant ?? "")
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
