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
  static let urlScheme = "okkle"
  static let widgetURLHost = "widget-trip"

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

  static func request(_ action: NativeTripWidgetAction) {
    switch action {
    case .start:
      requestStartFromWidget()
    case .end:
      requestEndFromWidget()
    }
  }

  static func widgetURL(for action: NativeTripWidgetAction) -> URL {
    URL(string: "\(urlScheme)://\(widgetURLHost)/\(action.rawValue)")!
  }

  static func requestFromWidgetURL(_ url: URL) -> Bool {
    guard let action = action(from: url) else { return false }
    request(action)
    return true
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

  private static func action(from url: URL) -> NativeTripWidgetAction? {
    guard url.scheme?.caseInsensitiveCompare(urlScheme) == .orderedSame,
          url.host?.caseInsensitiveCompare(widgetURLHost) == .orderedSame else {
      return nil
    }
    let actionName = url.pathComponents.dropFirst().first
    return actionName.flatMap(NativeTripWidgetAction.init(rawValue:))
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

extension Notification.Name {
  static let nativeTripWidgetActionReceived = Notification.Name("nativeTripWidgetActionReceived")
  static let nativeShowRecords = Notification.Name("nativeShowRecords")
  static let nativeShowTaxRecords = Notification.Name("nativeShowTaxRecords")
}
