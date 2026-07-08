import CoreLocation
import Foundation
@preconcurrency import UserNotifications

// MARK: - Pre-shift heads-up (local notification)

/// Schedules one local notification ahead of today's busy window, plus a
/// follow-up if that window arrives and the driver still hasn't gone out —
/// on-device, no server, and silently no-ops if permission is denied or
/// there is nothing useful to say.
@MainActor
enum NativePreShiftNotifier {
  private static let identifier = "uk.okkle.native.preshift"
  private static let followUpIdentifier = "uk.okkle.native.preshift.followup"
  private static var lastScheduledKey = ""

  static func refresh(store: OkkleStore) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier, followUpIdentifier])

    // Same reasoning as NativeLoggingReminder.refresh: this can request
    // notification permission below, which needs to wait for onboarding's
    // own explanation screen rather than firing cold before it.
    guard store.settings.hasCompletedOnboarding,
          store.settings.insightsEnabled,
          store.settings.autoTrackTrips,
          store.settings.preShiftAlerts,
          nativeIsWorkingDay(Date(), settings: store.settings) else { return }

    let shift = NativeShiftInsights.build(visits: NativeAutoTrackEngine.shared.visits, store: store)
    guard let plan = shift.todayPlan, plan.isToday, let peak = plan.peakWindow else { return }

    let calendar = Calendar.current
    let areaName = NativeAreaNamer.shared.name(for: plan.zone ?? CLLocationCoordinate2D())
    let areaSuffix = areaName.map { " near \($0)" } ?? ""

    scheduleHeadsUp(store: store, plan: plan, peak: peak, shift: shift, areaSuffix: areaSuffix, calendar: calendar, center: center)
    scheduleFollowUpIfNeeded(store: store, peak: peak, areaSuffix: areaSuffix, calendar: calendar, center: center)
  }

  private static func scheduleHeadsUp(store: OkkleStore, plan: NativeDayPlan, peak: NativeHourWindow, shift: NativeShiftInsights, areaSuffix: String, calendar: Calendar, center: UNUserNotificationCenter) {
    guard let fireDate = calendar.date(bySettingHour: max(0, peak.startHour - 1), minute: 30, second: 0, of: Date()),
          fireDate > Date().addingTimeInterval(120) else { return }

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

  /// A second, more direct nudge for ~1hr into the peak window — but only
  /// ever scheduled while the driver is still idle with nothing logged today.
  /// Every refresh() call (app becomes active, shift phase changes, relevant
  /// settings change) re-evaluates this from scratch: the moment a shift
  /// actually starts or one's already logged today, the next refresh removes
  /// the pending request above and this guard stops it being rescheduled —
  /// so it only ever actually fires if the driver genuinely never went out.
  private static func scheduleFollowUpIfNeeded(store: OkkleStore, peak: NativeHourWindow, areaSuffix: String, calendar: Calendar, center: UNUserNotificationCenter) {
    guard !NativeLoggingReminder.hasLoggedToday(store: store, calendar: calendar) else { return }
    guard let followUpDate = calendar.date(bySettingHour: min(23, peak.startHour + 1), minute: 0, second: 0, of: Date()),
          followUpDate > Date().addingTimeInterval(120) else { return }

    let title = "You haven't gone out yet"
    let body = "Tonight's usually strong for you around \(peak.label)\(areaSuffix) — worth heading out."
    let requestIdentifier = followUpIdentifier

    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: followUpDate)
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      center.add(UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger))
    }
  }
}
