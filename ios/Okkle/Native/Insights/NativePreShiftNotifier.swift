import CoreLocation
import Foundation
@preconcurrency import UserNotifications

// MARK: - Pre-shift heads-up (local notification)

/// Schedules one local notification ahead of today's busy window. On-device,
/// no server, and silently no-ops if permission is denied or there is nothing
/// useful to say.
@MainActor
enum NativePreShiftNotifier {
  private static let identifier = "uk.okkle.native.preshift"
  private static var lastScheduledKey = ""

  static func refresh(store: OkkleStore) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])

    guard store.settings.autoTrackTrips,
          store.settings.preShiftAlerts,
          nativeIsWorkingDay(Date(), settings: store.settings) else { return }

    let shift = NativeShiftInsights.build(visits: NativeAutoTrackEngine.shared.visits, store: store)
    guard let plan = shift.todayPlan, plan.isToday, let peak = plan.peakWindow else { return }

    let calendar = Calendar.current
    guard let fireDate = calendar.date(bySettingHour: max(0, peak.startHour - 1), minute: 30, second: 0, of: Date()),
          fireDate > Date().addingTimeInterval(120) else { return }

    let areaName = NativeAreaNamer.shared.name(for: plan.zone ?? CLLocationCoordinate2D())
    let areaSuffix = areaName.map { " near \($0)" } ?? ""
    let boost = NativeWeatherService.shared.today?.hours.contains { (10...23).contains($0.hour) && $0.boostsDemand } ?? false
    let strongDay = shift.weekdayDetails.prefix(3).contains { $0.weekday == plan.weekday }

    let title: String
    let body: String
    if boost && strongDay {
      title = "Don't skip tonight"
      body = "Bad weather on a busy night. Be out for \(peak.label)\(areaSuffix)."
    } else {
      title = "Your busy window's coming up"
      body = "Be out for \(peak.label)\(areaSuffix). Usually your strongest stretch today."
    }

    let key = "\(calendar.startOfDay(for: Date()).timeIntervalSince1970)-\(peak.startHour)-\(body.hashValue)"
    guard key != lastScheduledKey else { return }

    let requestIdentifier = identifier
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      center.add(UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger))
      Task { @MainActor in lastScheduledKey = key }
    }
  }
}
