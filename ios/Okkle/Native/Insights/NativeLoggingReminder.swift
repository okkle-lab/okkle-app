import Foundation
@preconcurrency import UserNotifications

// MARK: - Weekly/monthly logging reminder (local notification)

/// Nudges drivers who log trips manually. Automatic tracking owns mileage
/// capture when enabled, so it suppresses this reminder entirely. The saved
/// reminder preference is retained and becomes active again if automatic
/// tracking is later turned off.
@MainActor
enum NativeLoggingReminder {
  private static let identifier = "uk.okkle.native.loggingreminder"
  private static let fireHour = 18

  static func refresh(store: OkkleStore) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    let canSchedule = shouldSchedule(settings: store.settings)
    if !canSchedule {
      center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    // Requests notification permission below if none of this has run
    // before — that ask needs to wait for onboarding's own explanation
    // screen, not fire the moment a fresh install's default settings
    // happen to already satisfy every other guard here.
    guard canSchedule else { return }

    let calendar = Calendar.current
    let monthly = store.settings.logFrequency == .monthly

    guard var fireDate = nextOccurrence(reminderDay: store.settings.reminderDay, monthly: monthly, after: Date(), calendar: calendar) else { return }

    // Don't nag the same day a shift already got logged (auto or manual) —
    // push to the following occurrence instead of firing today.
    if calendar.isDateInToday(fireDate), hasLoggedToday(store: store, calendar: calendar) {
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)
      guard let pushed = nextOccurrence(reminderDay: store.settings.reminderDay, monthly: monthly, after: tomorrow, calendar: calendar) else { return }
      fireDate = pushed
    }

    guard fireDate > Date().addingTimeInterval(120) else { return }

    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
    let requestIdentifier = identifier
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      Task { @MainActor in
        // Permission prompts can outlive the settings state that initiated
        // them. Recheck here so enabling automatic tracking while the prompt
        // is open cannot re-add a reminder after refresh cancelled it.
        guard granted, shouldSchedule(settings: store.settings) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Weekly logging reminder"
        content.body = "Log this week's miles and pay so nothing slips through."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger))
      }
    }
  }

  static func shouldSchedule(settings: NativeSettings) -> Bool {
    settings.hasCompletedOnboarding &&
      settings.loggingReminder &&
      !settings.autoTrackTrips
  }

  /// Whether a shift or manual entry already exists today, or one is currently
  /// in progress — either way, today already has something logged.
  static func hasLoggedToday(store: OkkleStore, calendar: Calendar) -> Bool {
    if NativeAutoTrackEngine.shared.shiftPhase != .idle { return true }
    let today = Date()
    return store.trips.contains { calendar.isDate($0.endedAt, inSameDayAs: today) }
      || store.records.contains { calendar.isDate($0.date, inSameDayAs: today) }
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
