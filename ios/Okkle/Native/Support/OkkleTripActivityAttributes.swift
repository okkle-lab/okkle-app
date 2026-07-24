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
    // Distinguishes a driver-requested pause from automatic tracking's
    // stationary end-check; both can be resumed, but their status copy differs.
    // Optional keeps an in-flight Activity from an older build decodable.
    var isPausedByUser: Bool?
    var vehicleLabel: String
  }

  // "manual" or "auto" — lets the shared presentation explain whether the
  // driver started the trip or Okkle detected it automatically.
  var source: String
  // User-facing explanation of the signal that started an automatic trip,
  // for example "Driving motion detected" or "CarPlay or Car Audio detected".
  // Manual trips leave this nil.
  var automaticStartReason: String?

  var isAutomatic: Bool { source == "auto" }
}
#endif
