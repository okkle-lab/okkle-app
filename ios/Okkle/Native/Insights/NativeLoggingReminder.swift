import Foundation
@preconcurrency import UserNotifications

// MARK: - Weekly/monthly logging reminder (local notification)

/// Nudges the driver to log the one thing automatic tracking can't do for
/// them — earnings and expenses. Mileage is handled by NativeAutoTrackEngine
/// when automatic tracking is on, so this reminder's copy and cadence adapt:
/// with automatic tracking on it's always weekly and only about pay/expenses;
/// with it off it respects the driver's own weekly/monthly choice and covers
/// miles too. Either way it skips today if a shift already got logged today,
/// so a driver never gets "don't forget to log" the same day something was
/// already logged automatically.
@MainActor
enum NativeLoggingReminder {
  private static let identifier = "uk.okkle.native.loggingreminder"
  private static let fireHour = 18

  static func refresh(store: OkkleStore) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])

    guard store.settings.loggingReminder else { return }

    let calendar = Calendar.current
    let autoTracking = store.settings.autoTrackTrips
    let monthly = !autoTracking && store.settings.logFrequency == .monthly

    guard var fireDate = nextOccurrence(reminderDay: store.settings.reminderDay, monthly: monthly, after: Date(), calendar: calendar) else { return }

    // Don't nag the same day a shift already got logged (auto or manual) —
    // push to the following occurrence instead of firing today.
    if calendar.isDateInToday(fireDate), hasLoggedToday(store: store, calendar: calendar) {
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)
      guard let pushed = nextOccurrence(reminderDay: store.settings.reminderDay, monthly: monthly, after: tomorrow, calendar: calendar) else { return }
      fireDate = pushed
    }

    guard fireDate > Date().addingTimeInterval(120) else { return }

    let title: String
    let body: String
    if autoTracking {
      title = "Log this week's earnings"
      body = "Miles are already logged automatically — pop in this week's earnings and expenses for accurate totals."
    } else {
      title = "Weekly logging reminder"
      body = "Log this week's miles and pay so nothing slips through."
    }

    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
  }

  /// Whether a shift already ended today, or one is currently in progress —
  /// either way, today already has (or will have) something logged.
  private static func hasLoggedToday(store: OkkleStore, calendar: Calendar) -> Bool {
    if NativeAutoTrackEngine.shared.shiftPhase != .idle { return true }
    return store.trips.contains { calendar.isDate($0.endedAt, inSameDayAs: Date()) }
  }

  /// Weekly: the next occurrence of `reminderDay` (0 = Sunday … 6 = Saturday,
  /// matching `nativeIsWorkingDay`'s convention) at a fixed hour. Monthly:
  /// the next 1st-of-month at the same hour, independent of `reminderDay`.
  private static func nextOccurrence(reminderDay: Int, monthly: Bool, after date: Date, calendar: Calendar) -> Date? {
    var components = DateComponents()
    components.hour = fireHour
    components.minute = 0
    if monthly {
      components.day = 1
    } else {
      components.weekday = reminderDay + 1   // Calendar.weekday is 1-based (1 = Sunday)
    }
    return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents)
  }
}
