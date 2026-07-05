import Combine
import Foundation
import WatchConnectivity

final class NativeWatchTripConnector: NSObject, WCSessionDelegate {
  static let shared = NativeWatchTripConnector()

  private let watchSession: WCSession?
  private let tripSession = NativeTripSession.shared
  private let store = OkkleStore.shared
  private var cancellable: AnyCancellable?

  private override init() {
    watchSession = WCSession.isSupported() ? WCSession.default : nil
    super.init()
  }

  func configure() {
    guard let watchSession else { return }
    watchSession.delegate = self
    watchSession.activate()
    cancellable = tripSession.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
          self?.publishState()
        }
      }
    publishState()
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    publishState()
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    publishState()
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    Task { @MainActor in
      handle(message)
      replyHandler(statePayload())
    }
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    Task { @MainActor in
      handle(message)
    }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    Task { @MainActor in
      handle(applicationContext)
    }
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    Task { @MainActor in
      handle(userInfo)
    }
  }

  private func publishState() {
    Task { @MainActor in
      guard let watchSession, watchSession.activationState == .activated else { return }
      let payload = statePayload()
      try? watchSession.updateApplicationContext(payload)
      if watchSession.isReachable {
        watchSession.sendMessage(payload, replyHandler: nil, errorHandler: nil)
      }
    }
  }

  @MainActor
  private func handle(_ message: [String: Any]) {
    guard let command = message["command"] as? String else { return }
    switch command {
    case "start":
      guard tripSession.phase == .setup || tripSession.phase == .summary else { break }
      if tripSession.phase == .summary {
        tripSession.discard()
      }
      tripSession.start(vehicle: store.settings.defaultVehicle)
    case "stop":
      guard tripSession.phase == .live || tripSession.phase == .paused else { break }
      if let trip = tripSession.end(store: store) {
        store.addTrip(trip)
      }
      tripSession.discard()
    default:
      break
    }
    publishState()
  }

  @MainActor
  private func statePayload() -> [String: Any] {
    [
      "phase": tripSession.watchPhaseName,
      "miles": tripSession.miles,
      "elapsed": tripSession.elapsed,
      "vehicle": tripSession.vehicle.label,
      "permissionMessage": tripSession.permissionMessage ?? "",
    ]
  }
}

private extension NativeTripSession {
  var watchPhaseName: String {
    switch phase {
    case .setup:
      return "setup"
    case .live:
      return "live"
    case .paused:
      return "paused"
    case .summary:
      return "summary"
    }
  }
}
