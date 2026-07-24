import AppIntents
import Foundation

extension Notification.Name {
  static let nativeLiveActivityStopTrackingRequested = Notification.Name("uk.okkle.native.liveActivity.stopTracking")
  static let nativeLiveActivityPauseTrackingRequested = Notification.Name("uk.okkle.native.liveActivity.pauseTracking")
  static let nativeLiveActivityResumeTrackingRequested = Notification.Name("uk.okkle.native.liveActivity.resumeTracking")
}

/// The Pause/Resume + End buttons on the trip Live Activity.
/// Conforming to LiveActivityIntent (not plain AppIntent) makes these run
/// in the app's process without launching its UI — matching the
/// Everlance-style buttons this was modelled on.
///
/// This file is compiled into both the main app target and the OkkleWidget
/// extension target (the extension's SwiftUI needs the type to write
/// `Button(intent:)`), but NativeTripSession/NativeAutoTrackEngine — the
/// actual trip-tracking singletons — are main-app-only and far too large a
/// dependency tree to also build into a widget extension. So perform() only
/// posts a plain in-process notification; the real work happens in whichever
/// of those singletons is observing it (see their init()), which always
/// actually runs in the app process regardless of which target's copy of
/// this struct the OS happened to invoke.
@available(iOS 17.0, *)
struct OkkleStopTrackingLiveActivityIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "End trip"
  static var description = IntentDescription("Stop tracking this trip.")

  func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: .nativeLiveActivityStopTrackingRequested, object: nil)
    return .result()
  }
}

@available(iOS 17.0, *)
struct OkklePauseTrackingLiveActivityIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Pause trip"
  static var description = IntentDescription("Pause tracking this trip.")

  func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: .nativeLiveActivityPauseTrackingRequested, object: nil)
    return .result()
  }
}

@available(iOS 17.0, *)
struct OkkleResumeTrackingLiveActivityIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Resume trip"
  static var description = IntentDescription("Resume tracking this trip.")

  func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: .nativeLiveActivityResumeTrackingRequested, object: nil)
    return .result()
  }
}
