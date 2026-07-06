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
        store.setICloudSyncState(.failed(error.localizedDescription))
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
        store.setICloudSyncState(.failed(error.localizedDescription))
      }
      finishOperation(store: store)
    }
  }

  private func sync(store: OkkleStore, mergeCloudData: Bool) throws {
    if let remote = try readEnvelope() {
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
    if let remote = try readEnvelope(),
       shouldApply(remote) {
      snapshotToUpload = NativeICloudSnapshotMerge.merge(local: snapshot, remote: remote.snapshot)
      store.applyICloudSnapshot(snapshotToUpload)
    } else {
      snapshotToUpload = snapshot
    }
    try writeEnvelope(snapshot: snapshotToUpload, store: store)
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
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

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
    try data.write(to: url, options: [.atomic])
    markSeen(envelope)
    markLocalChangesSynced()
    store.setICloudSyncState(.synced(updatedAt))
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
    guard nsError.domain == NSCocoaErrorDomain else { return false }
    return nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError
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
