import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Owns the single Live Activity used for both manual trips and automatic
/// shifts — only one can ever be live at a time (the callers already
/// guarantee that: NativeTripSession.start() concludes any active auto
/// shift first). Deliberately a thin, stateless-from-the-outside wrapper so
/// both trip-tracking engines can call it the same way without knowing
/// about ActivityKit specifics or iOS-version gating.
enum NativeTripLiveActivityController {
  private static var activity: Activity<OkkleTripActivityAttributes>?
  // Avoid spamming ActivityKit with an update on every single GPS tick —
  // it has its own rate limits, and the Lock Screen/Dynamic Island content
  // doesn't need sub-second precision.
  private static var lastUpdateAt: Date = .distantPast
  private static let minimumUpdateInterval: TimeInterval = 15

  static func start(source: String, vehicleLabel: String, miles: Double, elapsed: TimeInterval, isDriving: Bool) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    // Guard against a stale Activity surviving a process relaunch mid-trip —
    // starting fresh is safer than updating a handle that may not still be
    // valid.
    end()
    let attributes = OkkleTripActivityAttributes(source: source)
    let state = OkkleTripActivityAttributes.ContentState(
      miles: miles, elapsed: elapsed, isDriving: isDriving, vehicleLabel: vehicleLabel
    )
    activity = try? Activity.request(
      attributes: attributes,
      content: .init(state: state, staleDate: nil)
    )
    lastUpdateAt = Date()
  }

  static func update(miles: Double, elapsed: TimeInterval, isDriving: Bool, vehicleLabel: String, force: Bool = false) {
    guard let activity else { return }
    guard force || Date().timeIntervalSince(lastUpdateAt) >= minimumUpdateInterval else { return }
    lastUpdateAt = Date()
    let state = OkkleTripActivityAttributes.ContentState(
      miles: miles, elapsed: elapsed, isDriving: isDriving, vehicleLabel: vehicleLabel
    )
    Task { await activity.update(.init(state: state, staleDate: nil)) }
  }

  static func end() {
    guard let activity else { return }
    self.activity = nil
    Task { await activity.end(nil, dismissalPolicy: .immediate) }
  }

  /// Whether a Live Activity is currently live — lets a LiveActivityIntent
  /// button (running in-process, no app launch) know there's something to
  /// act on.
  static var isActive: Bool { activity != nil }
}
#else
enum NativeTripLiveActivityController {
  static func start(source: String, vehicleLabel: String, miles: Double, elapsed: TimeInterval, isDriving: Bool) {}
  static func update(miles: Double, elapsed: TimeInterval, isDriving: Bool, vehicleLabel: String, force: Bool = false) {}
  static func end() {}
  static var isActive: Bool { false }
}
#endif
