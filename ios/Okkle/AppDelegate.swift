import SwiftUI
import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = NativeNotificationRouter.shared
    NativeWatchTripConnector.shared.configure()
    return true
  }

  func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard NativeTripWidgetStore.requestFromWidgetURL(url) else { return false }
    NotificationCenter.default.post(name: .nativeTripWidgetActionReceived, object: nil)
    return true
  }
}
