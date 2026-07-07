import SwiftUI
import UIKit
import UniformTypeIdentifiers
struct NativeRecordsView: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var mode: RecordsMode
  @State private var filter: RecordsFilter = .all
  // nil = All time. Defaults to the current month — day-to-day you're
  // checking what's recent, not everything you've ever logged; All time is
  // one tap away via the month picker below.
  @State private var selectedMonth: Date? = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))
  @State private var itemPendingDeletion: NativeHistoryItem?
  @State private var selectedHistoryItem: NativeHistoryItem?
  @State private var tripPendingEdit: NativeTrip?
  @State private var recordPendingEdit: NativeRecord?
  @State private var showsAddRecordPanel = false
  var onClose: (() -> Void)? = nil

  enum RecordsMode: String, CaseIterable, Identifiable {
    case history
    case tax

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
  }

  enum RecordsFilter: String, CaseIterable, Identifiable {
    case all
    case journeys
    case income
    case expense

    var id: String { rawValue }
    var label: String {
      switch self {
      case .all:
        return "All"
      case .journeys:
        return "Trips"
      case .income:
        return "Income"
      case .expense:
        return "Expense"
      }
    }
  }

  init(initialMode: RecordsMode = .history, onClose: (() -> Void)? = nil) {
    _mode = State(initialValue: initialMode)
    self.onClose = onClose
  }

  var body: some View {
    NativeScreen(
      title: "Data",
      collapsedTitle: "Data",
      subtitle: "Log trip mileage, income and expenses - all export-ready.",
      onClose: onClose
    ) {
      if mode == .tax {
        NativeTaxSummaryView()
      } else {
        recordsOverview
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      bottomAddRecordMenu
    }
    .alert("Delete this entry?", isPresented: Binding(
      get: { itemPendingDeletion != nil },
      set: { if !$0 { itemPendingDeletion = nil } }
    )) {
      Button("Cancel", role: .cancel) {
        itemPendingDeletion = nil
      }
      Button("Delete", role: .destructive) {
        if let item = itemPendingDeletion {
          delete(item)
        }
        itemPendingDeletion = nil
      }
    } message: {
      Text(pendingDeletionMessage)
    }
    .sheet(item: $selectedHistoryItem) { item in
      let current = currentItem(matching: item) ?? item
      NativeHistoryDetailSheet(
        item: current,
        onEdit: { requestEdit(current) },
        onDelete: { requestDelete(current) }
      )
    }
    .sheet(item: $tripPendingEdit) { trip in
      NativeTripEditSheet(trip: currentTrip(matching: trip) ?? trip) { updatedTrip in
        store.updateTrip(updatedTrip)
        tripPendingEdit = nil
      }
    }
    .sheet(item: $recordPendingEdit) { record in
      NativeRecordEditSheet(record: currentRecord(matching: record) ?? record) { updatedRecord in
        store.updateRecord(updatedRecord)
        recordPendingEdit = nil
      }
    }
    .sheet(isPresented: $showsAddRecordPanel) {
      NativeAddRecordPanel(
        title: { logTitle(for: $0) },
        subtitle: { logSubtitle(for: $0) },
        onViewRecords: {
          showsAddRecordPanel = false
        }
      )
      .environmentObject(store)
      .presentationDetents([.medium])
      .presentationDragIndicator(.visible)
    }
  }

  private var recordsOverview: some View {
    historyContent
  }

  private var addRecordButton: some View {
    Button {
      showsAddRecordPanel = true
    } label: {
      Label("Add record", systemImage: "plus")
        .font(.system(size: 17, weight: .heavy))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Add record")
  }

  private var bottomAddRecordMenu: some View {
    HStack {
      Spacer()
      addRecordButton
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(OkkleColor.brand, in: Capsule())
        .overlay {
          Capsule()
            .stroke(.white.opacity(0.22), lineWidth: 0.8)
        }
        .shadow(color: OkkleColor.brand.opacity(0.32), radius: 22, y: 10)
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .padding(.bottom, 10)
  }

  private func logTitle(for kind: NativeLogKind) -> String {
    switch kind {
    case .income:
      return "Log earnings"
    case .expense:
      return "Log expense"
    case .mileage:
      return "Log mileage"
    }
  }

  private func logSubtitle(for kind: NativeLogKind) -> String {
    switch kind {
    case .income:
      return "Add delivery pay, tips or bonuses."
    case .expense:
      return "Add a deductible cost."
    case .mileage:
      return "Add mileage from a previous journey."
    }
  }

  private var historyContent: some View {
    VStack(spacing: 20) {
      HStack(spacing: 10) {
        Picker("History filter", selection: $filter) {
          ForEach(RecordsFilter.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        Menu {
          Button {
            selectedMonth = nil
          } label: {
            if selectedMonth == nil {
              Label("All time", systemImage: "checkmark")
            } else {
              Text("All time")
            }
          }

          ForEach(availableMonths, id: \.self) { month in
            Button {
              selectedMonth = month
            } label: {
              if selectedMonth == month {
                Label(monthLabel(for: month), systemImage: "checkmark")
              } else {
                Text(monthLabel(for: month))
              }
            }
          }
        } label: {
          Label(monthButtonLabel, systemImage: "line.3.horizontal.decrease")
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(OkkleColor.brand)
            .padding(10)
            .background(OkkleColor.brand.opacity(selectedMonth != nil ? 0.22 : 0.14), in: Circle())
            .overlay {
              Circle()
                .stroke(OkkleColor.brand.opacity(selectedMonth != nil ? 0.38 : 0), lineWidth: 1)
            }
        }
        .accessibilityLabel(selectedMonth != nil ? "Showing \(monthButtonLabel)" : "Showing all time")
      }

      if filteredHistory.isEmpty {
        NativeEmptyState(symbol: "archivebox", title: "Nothing here yet", message: "Mileage, earnings and expenses appear here after you save them.")
      } else {
        NativeGlassCard {
          VStack(spacing: 0) {
            ForEach(filteredHistory) { item in
              NativeSelectableHistoryRow(
                item: item,
                onSelect: { selectFromAllHistory(item) }
              )
              if item.id != filteredHistory.last?.id {
                Divider().padding(.leading, 52)
              }
            }
          }
        }
      }
    }
  }

  private func selectFromAllHistory(_ item: NativeHistoryItem) {
    selectedHistoryItem = currentItem(matching: item) ?? item
  }

  private var filteredHistory: [NativeHistoryItem] {
    store.history.filter { item in
      let typeOk: Bool
      switch filter {
      case .all:
        typeOk = true
      case .journeys:
        if case .trip = item { typeOk = true }
        else if case .record(let record) = item { typeOk = record.kind == .mileage }
        else { typeOk = false }
      case .income:
        if case .record(let record) = item { typeOk = record.kind == .income } else { typeOk = false }
      case .expense:
        if case .record(let record) = item { typeOk = record.kind == .expense } else { typeOk = false }
      }
      guard typeOk else { return false }
      guard let selectedMonth else { return true }
      return Calendar.current.isDate(item.date, equalTo: selectedMonth, toGranularity: .month)
    }
  }

  /// Distinct months present anywhere in history (not just the current type
  /// filter), newest first — what the month picker offers.
  private var availableMonths: [Date] {
    let calendar = Calendar.current
    let months = Set(store.history.map { calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date)) ?? $0.date })
    return months.sorted(by: >)
  }

  private func monthLabel(for month: Date) -> String {
    month.formatted(.dateTime.month(.abbreviated).year())
  }

  private var monthButtonLabel: String {
    selectedMonth.map(monthLabel) ?? "All time"
  }

  private func delete(_ item: NativeHistoryItem) {
    switch item {
    case .trip(let trip):
      store.deleteTrip(trip)
      if tripPendingEdit?.id == trip.id {
        tripPendingEdit = nil
      }
    case .record(let record):
      store.deleteRecord(record)
      if recordPendingEdit?.id == record.id {
        recordPendingEdit = nil
      }
    }
    if selectedHistoryItem?.id == item.id {
      selectedHistoryItem = nil
    }
  }

  private func edit(_ item: NativeHistoryItem) {
    switch item {
    case .trip(let trip):
      tripPendingEdit = currentTrip(matching: trip) ?? trip
    case .record(let record):
      recordPendingEdit = currentRecord(matching: record) ?? record
    }
  }

  private func requestEdit(_ item: NativeHistoryItem) {
    selectedHistoryItem = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      edit(currentItem(matching: item) ?? item)
    }
  }

  private func requestDelete(_ item: NativeHistoryItem) {
    selectedHistoryItem = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      itemPendingDeletion = currentItem(matching: item) ?? item
    }
  }

  private func currentTrip(matching trip: NativeTrip) -> NativeTrip? {
    store.trips.first { $0.id == trip.id }
  }

  private func currentRecord(matching record: NativeRecord) -> NativeRecord? {
    store.records.first { $0.id == record.id }
  }

  private func currentItem(matching item: NativeHistoryItem) -> NativeHistoryItem? {
    switch item {
    case .trip(let trip):
      return store.trips.first { $0.id == trip.id }.map(NativeHistoryItem.trip)
    case .record(let record):
      return store.records.first { $0.id == record.id }.map(NativeHistoryItem.record)
    }
  }

  private var pendingDeletionMessage: String {
    guard let item = itemPendingDeletion else {
      return "This cannot be undone."
    }
    switch item {
    case .trip:
      return "This trip, route and mileage deduction will be removed from Records. This cannot be undone."
    case .record(let record):
      return "This \(record.kind.label.lowercased()) entry will be removed from Records and tax totals. This cannot be undone."
    }
  }
}

private struct NativeAddRecordPanel: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: OkkleStore
  @State private var logKind: NativeLogKind?
  let title: (NativeLogKind) -> String
  let subtitle: (NativeLogKind) -> String
  let onViewRecords: () -> Void

  private let options: [NativeLogKind] = [.income, .expense, .mileage]

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(options) { kind in
            Button {
              logKind = kind
            } label: {
              HStack(spacing: 14) {
                Image(systemName: kind.symbol)
                  .font(.system(size: 18, weight: .bold))
                  .foregroundStyle(optionTint(for: kind))
                  .frame(width: 36, height: 36)
                  .background(optionTint(for: kind).opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                  Text(optionTitle(for: kind))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OkkleColor.ink)
                  Text(optionSubtitle(for: kind))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(.tertiary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
          }
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.visible)
      .navigationTitle("Add record")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .fontWeight(.semibold)
        }
      }
      .sheet(item: $logKind) { kind in
        NativeLogView(
          initialKind: kind,
          allowedKinds: [kind],
          title: title(kind),
          subtitle: subtitle(kind),
          onClose: {
            logKind = nil
          },
          onViewRecords: {
            logKind = nil
            onViewRecords()
          }
        )
        .environmentObject(store)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
    }
  }

  private func optionTitle(for kind: NativeLogKind) -> String {
    switch kind {
    case .income:
      return "Earnings"
    case .expense:
      return "Expense"
    case .mileage:
      return "Mileage"
    }
  }

  private func optionSubtitle(for kind: NativeLogKind) -> String {
    switch kind {
    case .income:
      return "Pay, tips or bonuses"
    case .expense:
      return "Deductible cost"
    case .mileage:
      return "Previous journey"
    }
  }

  private func optionTint(for kind: NativeLogKind) -> Color {
    switch kind {
    case .income:
      return .green
    case .expense:
      return OkkleColor.amber
    case .mileage:
      return OkkleColor.brand
    }
  }
}

struct NativeSelectableHistoryRow: View {
  let item: NativeHistoryItem
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      NativeHistoryRow(item: item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isButton)
    .accessibilityHint("Opens details.")
  }
}

struct NativeHistoryRow: View {
  let item: NativeHistoryItem

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 40, height: 40)
        .background(tint.opacity(0.13), in: Circle())
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
        Text(subtitle)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .lineLimit(1)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        Text(value)
          .font(.system(size: 16, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        if let detail {
          Text(detail)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
        }
      }
    }
    .padding(.vertical, 12)
  }

  private var symbol: String {
    switch item {
    case .trip: return "location.north.fill"
    case .record(let record): return record.kind.symbol
    }
  }

  private var tint: Color {
    switch item {
    case .trip: return OkkleColor.blue
    case .record(let record):
      switch record.kind {
      case .income: return .green
      case .expense: return OkkleColor.amber
      case .mileage: return OkkleColor.brand
      }
    }
  }

  private var title: String {
    switch item {
    case .trip(let trip): return "Trip - \(trip.vehicle.label)"
    case .record(let record):
      switch record.kind {
      case .income: return record.platform ?? "Earnings"
      case .expense: return record.category ?? "Expense"
      case .mileage: return "Mileage - \(record.vehicle?.label ?? "Vehicle")"
      }
    }
  }

  private var subtitle: String {
    switch item {
    case .trip(let trip): return "GPS - \(shortDate(trip.startedAt))"
    case .record(let record):
      if record.kind == .expense, let merchant = record.merchant, !merchant.isEmpty {
        return "\(merchant) - \(shortDate(record.date))"
      }
      return "\(record.kind.label) - \(shortDate(record.date))"
    }
  }

  private var value: String {
    switch item {
    case .trip(let trip): return miles(trip.miles)
    case .record(let record):
      if record.kind == .mileage { return miles(record.miles ?? 0) }
      return gbp(record.amount ?? 0)
    }
  }

  private var detail: String? {
    switch item {
    case .trip(let trip): return gbp(trip.deduction, whole: true)
    case .record(let record):
      if let deduction = record.deduction { return gbp(deduction, whole: true) }
      return record.period.label
    }
  }
}

struct NativeShareItem: Identifiable {
  let id = UUID()
  let url: URL
}

struct NativeShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct NativeBackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }

  var data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

enum NativeBackupResult {
  case iCloud(URL)
  case share(NativeShareItem)
  case failed(String)
}

@MainActor
func nativeCreateBackup(store: OkkleStore) -> NativeBackupResult {
  let fileManager = FileManager.default
  if let container = nativeICloudContainerURL(fileManager: fileManager) {
    do {
      let folder = container
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("Okkle Backups", isDirectory: true)
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

      let fileName = nativeBackupFileName()
      let cloudURL = folder.appendingPathComponent(fileName)
      let localURL = fileManager.temporaryDirectory.appendingPathComponent(fileName)
      try store.backupData().write(to: localURL, options: [.atomic])
      if fileManager.fileExists(atPath: cloudURL.path) {
        try fileManager.removeItem(at: cloudURL)
      }

      do {
        try fileManager.setUbiquitous(true, itemAt: localURL, destinationURL: cloudURL)
      } catch {
        try store.backupData().write(to: cloudURL, options: [.atomic])
        try? fileManager.removeItem(at: localURL)
      }

      return .iCloud(cloudURL)
    } catch {
      if let item = nativeCreateShareBackup(store: store) {
        return .share(item)
      }
      return .failed("Could not write to iCloud Drive. \(error.localizedDescription)")
    }
  }

  if let item = nativeCreateShareBackup(store: store) {
    return .share(item)
  }
  return .failed("iCloud Drive is not available on this device.")
}

let nativeICloudContainerIdentifier = "iCloud.okklelab.app"

func nativeICloudContainerURL(fileManager: FileManager = .default) -> URL? {
  fileManager.url(forUbiquityContainerIdentifier: nativeICloudContainerIdentifier)
    ?? fileManager.url(forUbiquityContainerIdentifier: nil)
}

@MainActor
func nativeCreateShareBackup(store: OkkleStore) -> NativeShareItem? {
  do {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(nativeBackupFileName())
    try store.backupData().write(to: url, options: [.atomic])
    return NativeShareItem(url: url)
  } catch {
    return nil
  }
}

func nativeBackupFileName() -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
  return "Okkle_Backup_\(formatter.string(from: Date())).json"
}

enum NativeTaxExportKind: String, CaseIterable, Identifiable {
  case accountantPack
  case freeAgent
  case selfAssessment
  case mileageReportPdf
  case mileageLog
  case allData

  var id: String { rawValue }

  var title: String {
    switch self {
    case .accountantPack: return "Accountant pack PDF"
    case .freeAgent: return "FreeAgent CSV"
    case .selfAssessment: return "Self Assessment summary"
    case .mileageReportPdf: return "Mileage report PDF"
    case .mileageLog: return "HMRC mileage log (CSV)"
    case .allData: return "All data CSV"
    }
  }

  var subtitle: String {
    switch self {
    case .accountantPack: return "Summary, mileage, expenses, receipts and records"
    case .freeAgent: return "Income and expenses for bank import"
    case .selfAssessment: return "Turnover, expenses, profit and tax estimate"
    case .mileageReportPdf: return "Summary by rate band, plus full per-trip log"
    case .mileageLog: return "GPS and manual mileage claims, for a spreadsheet"
    case .allData: return "Trips, earnings and expenses"
    }
  }

  var symbol: String {
    switch self {
    case .accountantPack: return "doc.richtext.fill"
    case .freeAgent: return "arrow.up.doc.fill"
    case .selfAssessment: return "doc.text.fill"
    case .mileageReportPdf: return "chart.bar.doc.horizontal.fill"
    case .mileageLog: return "map.fill"
    case .allData: return "externaldrive.fill"
    }
  }

  var fileStem: String {
    switch self {
    case .accountantPack: return "Accountant-Pack"
    case .freeAgent: return "FreeAgent-Import"
    case .selfAssessment: return "SelfAssessment-Summary"
    case .mileageReportPdf: return "Mileage-Report"
    case .mileageLog: return "HMRC-Mileage-Log"
    case .allData: return "All-Data"
    }
  }

  var fileExtension: String {
    switch self {
    case .accountantPack, .mileageReportPdf: return "pdf"
    case .selfAssessment: return "txt"
    case .freeAgent, .mileageLog, .allData: return "csv"
    }
  }
}
