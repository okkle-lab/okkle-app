import Foundation
#if canImport(ActivityKit)
import ActivityKit
import UIKit

/// Owns the single Live Activity used for both manual trips and automatic
/// shifts — only one can ever be live at a time (the callers already
/// guarantee that: NativeTripSession.start() concludes any active auto
/// shift first). Deliberately a thin, stateless-from-the-outside wrapper so
/// both trip-tracking engines can call it the same way without knowing
/// about ActivityKit specifics or iOS-version gating.
enum NativeTripLiveActivityController {
  private struct StartRequest {
    var source: String
    var vehicleLabel: String
    var miles: Double
    var elapsed: TimeInterval
    var isDriving: Bool
    var isPausedByUser: Bool
    var automaticStartReason: String?
  }

  private static var activity: Activity<OkkleTripActivityAttributes>?
  private static var pendingStart: StartRequest?
  private static var didConfigureLifecycle = false
  // Avoid spamming ActivityKit with an update on every single GPS tick —
  // it has its own rate limits, and the Lock Screen/Dynamic Island content
  // doesn't need sub-second precision.
  private static var lastUpdateAt: Date = .distantPast
  private static let minimumUpdateInterval: TimeInterval = 15

  /// A local ActivityKit request is rejected while a background location
  /// wake is running. Keep the request alive and retry the moment Okkle is
  /// foreground-visible instead of silently losing the Live Activity.
  static func configureLifecycle() {
    guard !didConfigureLifecycle else { return }
    didConfigureLifecycle = true
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      startPendingIfPossible()
    }
  }

  static func start(
    source: String,
    vehicleLabel: String,
    miles: Double,
    elapsed: TimeInterval,
    isDriving: Bool,
    isPausedByUser: Bool = false,
    automaticStartReason: String? = nil
  ) {
    configureLifecycle()
    let request = StartRequest(
      source: source,
      vehicleLabel: vehicleLabel,
      miles: miles,
      elapsed: elapsed,
      isDriving: isDriving,
      isPausedByUser: isPausedByUser,
      automaticStartReason: automaticStartReason
    )

    guard UIApplication.shared.applicationState == .active else {
      pendingStart = request
      recordDiagnostic(
        kind: "live-activity.deferred.background",
        title: "Live Activity deferred",
        detail: "The \(sourceLabel(source)) trip began while Okkle was in the background. iOS will allow the local Live Activity to start when Okkle next becomes active.",
        deduplicateWithin: 60
      )
      return
    }
    startNow(request)
  }

  private static func startNow(_ request: StartRequest) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      pendingStart = nil
      recordDiagnostic(
        kind: "live-activity.disabled",
        title: "Live Activities unavailable",
        detail: "iOS reports that Live Activities are disabled for Okkle."
      )
      return
    }
    // Guard against a stale Activity surviving a process relaunch mid-trip —
    // starting fresh is safer than updating a handle that may not still be
    // valid.
    end()
    let attributes = OkkleTripActivityAttributes(
      source: request.source,
      automaticStartReason: request.automaticStartReason
    )
    let state = OkkleTripActivityAttributes.ContentState(
      miles: request.miles,
      elapsed: request.elapsed,
      isDriving: request.isDriving,
      isPausedByUser: request.isPausedByUser,
      vehicleLabel: request.vehicleLabel
    )
    do {
      activity = try Activity.request(
        attributes: attributes,
        content: .init(state: state, staleDate: nil)
      )
      pendingStart = nil
      lastUpdateAt = Date()
      recordDiagnostic(
        kind: "live-activity.started",
        title: "Live Activity started",
        detail: "Started for the \(sourceLabel(request.source)) trip."
      )
    } catch {
      activity = nil
      // The app can move out of the active state between the initial check
      // and ActivityKit processing the request. Preserve that race for the
      // next foreground activation; other errors need an explicit log.
      if UIApplication.shared.applicationState != .active {
        pendingStart = request
      } else {
        pendingStart = nil
      }
      recordDiagnostic(
        kind: "live-activity.start-failed",
        title: "Live Activity could not start",
        detail: "ActivityKit error: \(String(describing: error))."
      )
    }
  }

  static func update(
    miles: Double,
    elapsed: TimeInterval,
    isDriving: Bool,
    isPausedByUser: Bool = false,
    vehicleLabel: String,
    force: Bool = false
  ) {
    if activity == nil, pendingStart != nil {
      pendingStart?.miles = miles
      pendingStart?.elapsed = elapsed
      pendingStart?.isDriving = isDriving
      pendingStart?.isPausedByUser = isPausedByUser
      pendingStart?.vehicleLabel = vehicleLabel
      return
    }
    guard let activity else { return }
    guard force || Date().timeIntervalSince(lastUpdateAt) >= minimumUpdateInterval else { return }
    lastUpdateAt = Date()
    let state = OkkleTripActivityAttributes.ContentState(
      miles: miles,
      elapsed: elapsed,
      isDriving: isDriving,
      isPausedByUser: isPausedByUser,
      vehicleLabel: vehicleLabel
    )
    Task { await activity.update(.init(state: state, staleDate: nil)) }
  }

  static func end() {
    pendingStart = nil
    guard let activity else { return }
    self.activity = nil
    Task { await activity.end(nil, dismissalPolicy: .immediate) }
  }

  /// Whether a Live Activity is currently live — lets a LiveActivityIntent
  /// button (running in-process, no app launch) know there's something to
  /// act on.
  static var isActive: Bool { activity != nil }

  private static func startPendingIfPossible() {
    guard UIApplication.shared.applicationState == .active,
          let request = pendingStart else { return }
    startNow(request)
  }

  private static func sourceLabel(_ source: String) -> String {
    source == "auto" ? "automatic" : "manual"
  }

  private static func recordDiagnostic(
    kind: String,
    title: String,
    detail: String,
    deduplicateWithin: TimeInterval = 0
  ) {
    Task { @MainActor in
      NativeAutoTrackDiagnostics.shared.record(
        kind: kind,
        title: title,
        detail: detail,
        deduplicateWithin: deduplicateWithin
      )
    }
  }
}
#else
enum NativeTripLiveActivityController {
  static func configureLifecycle() {}
  static func start(
    source: String,
    vehicleLabel: String,
    miles: Double,
    elapsed: TimeInterval,
    isDriving: Bool,
    isPausedByUser: Bool = false,
    automaticStartReason: String? = nil
  ) {}
  static func update(
    miles: Double,
    elapsed: TimeInterval,
    isDriving: Bool,
    isPausedByUser: Bool = false,
    vehicleLabel: String,
    force: Bool = false
  ) {}
  static func end() {}
  static var isActive: Bool { false }
}
#endif
