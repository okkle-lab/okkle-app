import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Shared between the main app (which starts/updates/ends the Activity) and
/// the OkkleWidget extension (which renders it) — must stay a member of both
/// targets. Backs the Lock Screen / Dynamic Island live-tracking banner for
/// both manual trips and automatic shifts.
@available(iOS 16.1, *)
struct OkkleTripActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var miles: Double
    var elapsed: TimeInterval
    // true while actively recording a route; false during a stationary/
    // finalizing window (e.g. an automatic shift's stop-or-end dwell), so
    // the banner can read "Finalizing trip" instead of "Tracking trip".
    var isDriving: Bool
    var vehicleLabel: String
  }

  // "manual" or "auto" — display/debug only, doesn't affect behavior.
  var source: String
}
#endif
