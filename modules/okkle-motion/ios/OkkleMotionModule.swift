import ExpoModulesCore
import CoreMotion

// Wraps CMMotionActivityManager so JS can ask "is the user driving/cycling right
// now?" — far more accurate than GPS speed (no false positives from buses, etc.).
public class OkkleMotionModule: Module {
  private let activityManager = CMMotionActivityManager()
  private let queue = OperationQueue()

  public func definition() -> ModuleDefinition {
    Name("OkkleMotion")

    Function("isAvailable") { () -> Bool in
      return CMMotionActivityManager.isActivityAvailable()
    }

    // Resolve the dominant motion activity over the last `seconds`.
    AsyncFunction("recentActivity") { (seconds: Double, promise: Promise) in
      guard CMMotionActivityManager.isActivityAvailable() else {
        promise.resolve(["available": false])
        return
      }
      let end = Date()
      let start = end.addingTimeInterval(-max(30.0, seconds))
      self.activityManager.queryActivityStarting(from: start, to: end, to: self.queue) { activities, error in
        guard error == nil, let activities = activities, !activities.isEmpty else {
          promise.resolve([
            "available": true, "automotive": false, "cycling": false,
            "walking": false, "stationary": false, "confidence": 0,
          ])
          return
        }
        // Prefer the most recent non-low-confidence sample.
        let latest = activities.last(where: { $0.confidence != .low }) ?? activities.last!
        promise.resolve([
          "available": true,
          "automotive": latest.automotive,
          "cycling": latest.cycling,
          "walking": latest.walking,
          "stationary": latest.stationary,
          "confidence": latest.confidence.rawValue,
        ])
      }
    }
  }
}
