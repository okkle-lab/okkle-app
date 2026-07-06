import Foundation

enum NativeICloudSyncState: Equatable {
  case disabled
  case unavailable(String)
  case syncing
  case synced(Date)
  case failed(String)

  var title: String {
    switch self {
    case .disabled:
      return "Off"
    case .unavailable:
      return "Unavailable"
    case .syncing:
      return "Syncing..."
    case .synced:
      return "Synced"
    case .failed:
      return "Needs attention"
    }
  }

  var detail: String {
    switch self {
    case .disabled:
      return "Your data is stored on this device."
    case .unavailable(let message):
      return message
    case .syncing:
      return "Updating your iCloud copy."
    case .synced(let date):
      return "Last synced \(date.formatted(date: .omitted, time: .shortened))."
    case .failed(let message):
      return message
    }
  }
}

private struct NativeICloudSnapshotEnvelope: Codable {
  var app: String
  var version: Int
  var updatedAt: Date
  var deviceID: String
  var snapshot: NativeSnapshot
}

@MainActor
final class NativeICloudSyncEngine {
  static let shared = NativeICloudSyncEngine()

  private let fileManager = FileManager.default
  private let defaults = UserDefaults.standard
  private let deviceIDKey = "uk.okkle.native.icloudSync.deviceID"
  private let lastSeenRemoteTimestampKey = "uk.okkle.native.icloudSync.lastSeenRemoteTimestamp"
  private let localChangesPendingKey = "uk.okkle.native.icloudSync.localChangesPending"
  private let containerIdentifier = "iCloud.okklelab.app"
  private let syncFolderName = "Okkle Sync"
  private let syncFileName = "snapshot.json"

  private var isBusy = false
  private var pendingRefresh = false
  private var pendingLocalSnapshot: NativeSnapshot?

  private init() {}

  func refresh(store: OkkleStore, mergeCloudData: Bool = false) {
    guard store.settings.iCloudSyncEnabled else {
      store.setICloudSyncState(.disabled)
      return
    }

    guard !isBusy else {
      pendingRefresh = true
      return
    }
    isBusy = true
    store.setICloudSyncState(.syncing)
    Task { @MainActor in
      do {
        try sync(store: store, mergeCloudData: mergeCloudData)
      } catch let error as NativeICloudSyncError {
        store.setICloudSyncState(error.syncState)
      } catch {
        store.setICloudSyncState(Self.syncState(for: error))
      }
      finishOperation(store: store)
    }
  }

  func uploadLocalSnapshot(_ snapshot: NativeSnapshot, store: OkkleStore) {
    guard snapshot.settings.iCloudSyncEnabled else { return }
    markLocalChangesPending()
    guard !isBusy else {
      pendingLocalSnapshot = snapshot
      return
    }
    isBusy = true
    store.setICloudSyncState(.syncing)
    Task { @MainActor in
      do {
        try upload(snapshot: snapshot, store: store)
      } catch let error as NativeICloudSyncError {
        store.setICloudSyncState(error.syncState)
      } catch {
        store.setICloudSyncState(Self.syncState(for: error))
      }
      finishOperation(store: store)
    }
  }

  private func sync(store: OkkleStore, mergeCloudData: Bool) throws {
    if let remote = try readEnvelopeForSync() {
      if mergeCloudData {
        let merged = NativeICloudSnapshotMerge.merge(local: store.currentSnapshot, remote: remote.snapshot)
        store.applyICloudSnapshot(merged)
        try writeEnvelope(snapshot: merged, store: store)
        return
      }

      if shouldApply(remote) {
        guard !hasLocalChangesPending else {
          let merged = NativeICloudSnapshotMerge.merge(local: store.currentSnapshot, remote: remote.snapshot)
          store.applyICloudSnapshot(merged)
          try writeEnvelope(snapshot: merged, store: store)
          return
        }
        store.applyICloudSnapshot(remote.snapshot)
        markSeen(remote)
        store.setICloudSyncState(.synced(remote.updatedAt))
        return
      }

      if hasLocalChangesPending {
        try writeEnvelope(snapshot: store.currentSnapshot, store: store)
        return
      }

      markSeen(remote)
      store.setICloudSyncState(.synced(remote.updatedAt))
      return
    }

    try writeEnvelope(snapshot: store.currentSnapshot, store: store)
  }

  private func upload(snapshot: NativeSnapshot, store: OkkleStore) throws {
    let snapshotToUpload: NativeSnapshot
    if let remote = try readEnvelopeForSync(),
       shouldApply(remote) {
      snapshotToUpload = NativeICloudSnapshotMerge.merge(local: snapshot, remote: remote.snapshot)
      store.applyICloudSnapshot(snapshotToUpload)
    } else {
      snapshotToUpload = snapshot
    }
    try writeEnvelope(snapshot: snapshotToUpload, store: store)
  }

  private func readEnvelopeForSync() throws -> NativeICloudSnapshotEnvelope? {
    do {
      return try readEnvelope()
    } catch NativeICloudSyncError.remoteDownloadPending {
      return nil
    }
  }

  private func readEnvelope() throws -> NativeICloudSnapshotEnvelope? {
    guard let url = syncFileURL() else {
      throw NativeICloudSyncError.unavailable
    }
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    try? fileManager.startDownloadingUbiquitousItem(at: url)
    let data = try readSnapshotData(at: url)
    guard !data.isEmpty else { return nil }
    let envelope = try JSONDecoder().decode(NativeICloudSnapshotEnvelope.self, from: data)
    guard envelope.app == "okkle", envelope.version == 1 else { return nil }
    return envelope
  }

  private func readSnapshotData(at url: URL) throws -> Data {
    do {
      return try Data(contentsOf: url)
    } catch {
      if Self.isMissingICloudData(error) {
        throw NativeICloudSyncError.remoteDownloadPending
      }
      throw error
    }
  }

  private func writeEnvelope(snapshot: NativeSnapshot, store: OkkleStore) throws {
    guard let url = syncFileURL() else {
      throw NativeICloudSyncError.unavailable
    }
    try createSyncDirectory(at: url.deletingLastPathComponent())

    let updatedAt = Date()
    let envelope = NativeICloudSnapshotEnvelope(
      app: "okkle",
      version: 1,
      updatedAt: updatedAt,
      deviceID: deviceID,
      snapshot: snapshot
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(envelope)
    try writeSnapshotData(data, to: url)
    markSeen(envelope)
    markLocalChangesSynced()
    store.setICloudSyncState(.synced(updatedAt))
  }

  private func writeSnapshotData(_ data: Data, to url: URL) throws {
    do {
      try data.write(to: url, options: [.atomic])
    } catch {
      guard Self.isMissingICloudData(error) else { throw error }
      try replaceMissingCloudSnapshot(data, at: url)
    }
  }

  private func replaceMissingCloudSnapshot(_ data: Data, at url: URL) throws {
    try? fileManager.removeItem(at: url)
    try createSyncDirectory(at: url.deletingLastPathComponent())

    do {
      try data.write(to: url, options: [.atomic])
    } catch {
      guard Self.isMissingICloudData(error) else { throw error }
      try uploadSnapshotFromTemporaryFile(data, to: url)
    }
  }

  private func uploadSnapshotFromTemporaryFile(_ data: Data, to url: URL) throws {
    let temporaryURL = fileManager.temporaryDirectory
      .appendingPathComponent("OkkleSync-\(UUID().uuidString)")
      .appendingPathExtension("json")
    try data.write(to: temporaryURL, options: [.atomic])
    do {
      try? fileManager.removeItem(at: url)
      try fileManager.setUbiquitous(true, itemAt: temporaryURL, destinationURL: url)
    } catch {
      try? fileManager.removeItem(at: temporaryURL)
      throw error
    }
  }

  private func createSyncDirectory(at directoryURL: URL) throws {
    do {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    } catch {
      guard Self.isMissingICloudData(error) else { throw error }
      try? fileManager.removeItem(at: directoryURL)
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
  }

  private func syncFileURL() -> URL? {
    let container = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier)
      ?? fileManager.url(forUbiquityContainerIdentifier: nil)
    return container?
      .appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent(syncFolderName, isDirectory: true)
      .appendingPathComponent(syncFileName)
  }

  private func shouldApply(_ envelope: NativeICloudSnapshotEnvelope) -> Bool {
    envelope.deviceID != deviceID &&
      envelope.updatedAt.timeIntervalSince1970 > defaults.double(forKey: lastSeenRemoteTimestampKey) + 0.5
  }

  private func markSeen(_ envelope: NativeICloudSnapshotEnvelope) {
    defaults.set(envelope.updatedAt.timeIntervalSince1970, forKey: lastSeenRemoteTimestampKey)
  }

  private var hasLocalChangesPending: Bool {
    defaults.bool(forKey: localChangesPendingKey)
  }

  private func markLocalChangesPending() {
    defaults.set(true, forKey: localChangesPendingKey)
  }

  private func markLocalChangesSynced() {
    defaults.set(false, forKey: localChangesPendingKey)
  }

  private func finishOperation(store: OkkleStore) {
    isBusy = false
    guard store.settings.iCloudSyncEnabled else {
      pendingLocalSnapshot = nil
      pendingRefresh = false
      store.setICloudSyncState(.disabled)
      return
    }
    if let snapshot = pendingLocalSnapshot {
      pendingLocalSnapshot = nil
      uploadLocalSnapshot(snapshot, store: store)
    } else if pendingRefresh {
      pendingRefresh = false
      refresh(store: store)
    }
  }

  private var deviceID: String {
    if let existing = defaults.string(forKey: deviceIDKey) {
      return existing
    }
    let id = UUID().uuidString
    defaults.set(id, forKey: deviceIDKey)
    return id
  }

  private static func isMissingICloudData(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain,
       nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError {
      return true
    }
    if nsError.domain == NSPOSIXErrorDomain, nsError.code == 2 {
      return true
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
       isMissingICloudData(underlying) {
      return true
    }
    let description = nsError.localizedDescription.lowercased()
    return description.contains("data") &&
      description.contains("read") &&
      description.contains("missing")
  }

  private static func syncState(for error: Error) -> NativeICloudSyncState {
    if isMissingICloudData(error) {
      return .syncing
    }
    return .failed(error.localizedDescription)
  }
}

private enum NativeICloudSyncError: LocalizedError {
  case unavailable
  case remoteDownloadPending

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "iCloud Drive is not available on this device."
    case .remoteDownloadPending:
      return "Waiting for iCloud Drive to download your Okkle data."
    }
  }

  var syncState: NativeICloudSyncState {
    switch self {
    case .unavailable:
      return .unavailable(errorDescription ?? "iCloud Drive is not available on this device.")
    case .remoteDownloadPending:
      return .syncing
    }
  }
}

private enum NativeICloudSnapshotMerge {
  static func merge(local: NativeSnapshot, remote: NativeSnapshot) -> NativeSnapshot {
    NativeSnapshot(
      settings: mergeSettings(local: local.settings, remote: remote.settings),
      records: mergeRecords(local.records, remote.records),
      trips: mergeTrips(local.trips, remote.trips)
    )
  }

  private static func mergeSettings(local: NativeSettings, remote: NativeSettings) -> NativeSettings {
    var settings = local.hasCompletedOnboarding ? local : remote
    settings.platforms = uniqueStrings(remote.platforms + local.platforms)
    settings.iCloudSyncEnabled = true
    return settings
  }

  private static func mergeRecords(_ local: [NativeRecord], _ remote: [NativeRecord]) -> [NativeRecord] {
    var byID: [UUID: NativeRecord] = [:]
    for record in remote {
      byID[record.id] = record
    }
    for record in local {
      byID[record.id] = record
    }
    return byID.values.sorted { $0.date > $1.date }
  }

  private static func mergeTrips(_ local: [NativeTrip], _ remote: [NativeTrip]) -> [NativeTrip] {
    var byID: [UUID: NativeTrip] = [:]
    for trip in remote {
      byID[trip.id] = trip
    }
    for trip in local {
      byID[trip.id] = trip
    }
    return byID.values.sorted { $0.startedAt > $1.startedAt }
  }
}
