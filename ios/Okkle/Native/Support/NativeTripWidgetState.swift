import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum NativeTripWidgetAction: String, Codable {
  case start
  case end
}

struct NativeTripWidgetState: Codable, Equatable {
  var isTripActive: Bool
  var startedAt: Date?
  var pendingAction: NativeTripWidgetAction?
  var pendingActionID: UUID?
  var updatedAt: Date

  static var inactive: NativeTripWidgetState {
    NativeTripWidgetState(
      isTripActive: false,
      startedAt: nil,
      pendingAction: nil,
      pendingActionID: nil,
      updatedAt: Date()
    )
  }
}

enum NativeTripWidgetStore {
  static let appGroupID = "group.okklelab.app"

  private static let stateKey = "nativeTripWidgetState"

  static func read() -> NativeTripWidgetState {
    guard
      let data = defaults.data(forKey: stateKey),
      let state = try? JSONDecoder().decode(NativeTripWidgetState.self, from: data)
    else {
      return .inactive
    }
    return state
  }

  static func markTripStarted(startedAt: Date = Date()) {
    write(NativeTripWidgetState(
      isTripActive: true,
      startedAt: startedAt,
      pendingAction: nil,
      pendingActionID: nil,
      updatedAt: Date()
    ))
  }

  static func markTripEnded() {
    write(.inactive)
  }

  static func requestStartFromWidget() {
    write(NativeTripWidgetState(
      isTripActive: true,
      startedAt: Date(),
      pendingAction: .start,
      pendingActionID: UUID(),
      updatedAt: Date()
    ))
  }

  static func requestEndFromWidget() {
    var state = read()
    state.isTripActive = false
    state.pendingAction = .end
    state.pendingActionID = UUID()
    state.updatedAt = Date()
    write(state)
  }

  static func consumePendingAction() -> NativeTripWidgetAction? {
    var state = read()
    guard let action = state.pendingAction else { return nil }
    state.pendingAction = nil
    state.pendingActionID = nil
    state.updatedAt = Date()
    write(state, reloadWidgets: false)
    return action
  }

  static var hasPendingAction: Bool {
    read().pendingAction != nil
  }

  private static var defaults: UserDefaults {
    UserDefaults(suiteName: appGroupID) ?? .standard
  }

  private static func write(_ state: NativeTripWidgetState, reloadWidgets: Bool = true) {
    if let data = try? JSONEncoder().encode(state) {
      defaults.set(data, forKey: stateKey)
      defaults.synchronize()
    }

    guard reloadWidgets else { return }
    #if canImport(WidgetKit)
    WidgetCenter.shared.reloadAllTimelines()
    #endif
  }
}
