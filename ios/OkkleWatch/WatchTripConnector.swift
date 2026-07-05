import Foundation
import WatchConnectivity

final class WatchTripConnector: NSObject, ObservableObject, WCSessionDelegate {
  static let shared = WatchTripConnector()

  @Published private(set) var phase = "setup"
  @Published private(set) var miles: Double = 0
  @Published private(set) var elapsed: TimeInterval = 0
  @Published private(set) var vehicle = "Car"
  @Published private(set) var permissionMessage = ""
  @Published private(set) var isReachable = false
  @Published private(set) var pendingCommand: String?

  private let session: WCSession?
  private var pendingDelivery: [String: String]?

  private override init() {
    session = WCSession.isSupported() ? WCSession.default : nil
    super.init()
  }

  var isTracking: Bool {
    phase == "live" || phase == "paused"
  }

  var title: String {
    if pendingCommand == "start" {
      return "Starting trip"
    }
    if pendingCommand == "stop" {
      return "Saving trip"
    }
    switch phase {
    case "live":
      return "Tracking trip"
    case "paused":
      return "Trip paused"
    default:
      return "Ready to record"
    }
  }

  var subtitle: String {
    if pendingCommand != nil {
      return isReachable ? "Sending to iPhone" : "Will sync with iPhone"
    }
    return isTracking ? vehicle : "Uses your iPhone for GPS"
  }

  var milesLabel: String {
    String(format: "%.1f mi", miles)
  }

  var elapsedLabel: String {
    let total = max(0, Int(elapsed.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 {
      return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
  }

  var buttonTitle: String {
    if pendingCommand == "start" {
      return "Starting..."
    }
    if pendingCommand == "stop" {
      return "Saving..."
    }
    return isTracking ? "Stop" : "Record"
  }

  var buttonSymbol: String {
    isTracking ? "stop.fill" : "location.north.fill"
  }

  func configure() {
    guard let session else { return }
    session.delegate = self
    if session.activationState == .notActivated {
      session.activate()
    }
    isReachable = session.isReachable
  }

  func primaryAction() {
    guard pendingCommand == nil else { return }
    send(command: isTracking ? "stop" : "start")
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    DispatchQueue.main.async {
      self.isReachable = session.isReachable
      if activationState == .activated, let pendingDelivery = self.pendingDelivery {
        self.deliver(pendingDelivery)
      }
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async {
      self.isReachable = session.isReachable
    }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    apply(applicationContext)
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    apply(message)
  }

  private func send(command: String) {
    guard let session else { return }
    let message = ["command": command]
    pendingCommand = command
    permissionMessage = ""
    if command == "start" {
      phase = "starting"
    } else if command == "stop" {
      phase = "stopping"
    }

    guard session.activationState == .activated else {
      pendingDelivery = message
      if session.activationState == .notActivated {
        session.activate()
      }
      return
    }

    deliver(message)
  }

  private func deliver(_ message: [String: String]) {
    guard let session else { return }
    pendingDelivery = nil
    if session.isReachable {
      session.sendMessage(message) { [weak self] reply in
        self?.apply(reply)
      } errorHandler: { _ in
        session.transferUserInfo(message)
      }
    } else {
      session.transferUserInfo(message)
    }
  }

  private func apply(_ payload: [String: Any]) {
    DispatchQueue.main.async {
      self.phase = payload["phase"] as? String ?? self.phase
      self.miles = payload["miles"] as? Double ?? self.miles
      self.elapsed = payload["elapsed"] as? TimeInterval ?? self.elapsed
      self.vehicle = payload["vehicle"] as? String ?? self.vehicle
      self.permissionMessage = payload["permissionMessage"] as? String ?? self.permissionMessage
      self.pendingCommand = nil
    }
  }
}
