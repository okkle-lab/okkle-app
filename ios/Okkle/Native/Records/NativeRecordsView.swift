import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision
struct NativeRecordsView: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var mode: RecordsMode
  @State private var filter: RecordsFilter = .all
  @State private var itemPendingDeletion: NativeHistoryItem?
  @State private var selectedHistoryItem: NativeHistoryItem?
  @State private var tripPendingEdit: NativeTrip?
  @State private var recordPendingEdit: NativeRecord?
  var onClose: (() -> Void)? = nil

  enum RecordsMode: String, CaseIterable, Identifiable {
    case history
    case tax

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
  }

  enum RecordsFilter: String, CaseIterable, Identifiable {
    case all
    case trips
    case income
    case expense

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
  }

  init(initialMode: RecordsMode = .history, onClose: (() -> Void)? = nil) {
    _mode = State(initialValue: initialMode)
    self.onClose = onClose
  }

  var body: some View {
    NativeScreen(title: "Records", collapsedTitle: "Records", subtitle: "Your logs, tax estimate and export-ready history.", onClose: onClose) {
      Picker("Records", selection: $mode) {
        ForEach(RecordsMode.allCases) { Text($0.label).tag($0) }
      }
      .pickerStyle(.segmented)

      if mode == .tax {
        NativeTaxSummaryView()
      } else {
        historyContent
      }
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
  }

  private var historyContent: some View {
    VStack(spacing: 20) {
      Picker("History filter", selection: $filter) {
        ForEach(RecordsFilter.allCases) { Text($0.label).tag($0) }
      }
      .pickerStyle(.segmented)

      if filteredHistory.isEmpty {
        NativeEmptyState(symbol: "archivebox", title: "Nothing here yet", message: "Trips, earnings and expenses appear here after you save them.")
      } else {
        NativeGlassCard {
          VStack(spacing: 0) {
            ForEach(filteredHistory) { item in
              NativeSelectableHistoryRow(
                item: item,
                onSelect: { selectedHistoryItem = item }
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

  private var filteredHistory: [NativeHistoryItem] {
    store.history.filter { item in
      switch filter {
      case .all:
        return true
      case .trips:
        if case .trip = item { return true }
        if case .record(let record) = item { return record.kind == .mileage }
        return false
      case .income:
        if case .record(let record) = item { return record.kind == .income }
        return false
      case .expense:
        if case .record(let record) = item { return record.kind == .expense }
        return false
      }
    }
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
  case mileageLog
  case allData

  var id: String { rawValue }

  var title: String {
    switch self {
    case .accountantPack: return "Accountant pack PDF"
    case .freeAgent: return "FreeAgent CSV"
    case .selfAssessment: return "Self Assessment summary"
    case .mileageLog: return "HMRC mileage log"
    case .allData: return "All data CSV"
    }
  }

  var subtitle: String {
    switch self {
    case .accountantPack: return "Summary, mileage, expenses, receipts and records"
    case .freeAgent: return "Income and expenses for bank import"
    case .selfAssessment: return "Turnover, expenses, profit and tax estimate"
    case .mileageLog: return "GPS and manual mileage claims"
    case .allData: return "Trips, earnings, mileage and expenses"
    }
  }

  var symbol: String {
    switch self {
    case .accountantPack: return "doc.richtext.fill"
    case .freeAgent: return "arrow.up.doc.fill"
    case .selfAssessment: return "doc.text.fill"
    case .mileageLog: return "map.fill"
    case .allData: return "externaldrive.fill"
    }
  }

  var fileStem: String {
    switch self {
    case .accountantPack: return "Accountant-Pack"
    case .freeAgent: return "FreeAgent-Import"
    case .selfAssessment: return "SelfAssessment-Summary"
    case .mileageLog: return "HMRC-Mileage-Log"
    case .allData: return "All-Data"
    }
  }

  var fileExtension: String {
    switch self {
    case .accountantPack: return "pdf"
    case .selfAssessment: return "txt"
    case .freeAgent, .mileageLog, .allData: return "csv"
    }
  }
}
