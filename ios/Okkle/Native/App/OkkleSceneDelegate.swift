import SwiftUI
import UIKit

final class OkkleSceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = UIHostingController(rootView: OkkleNativeRootView())
    self.window = window
    window.makeKeyAndVisible()

    connectionOptions.urlContexts.forEach { handle(url: $0.url) }
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    URLContexts.forEach { handle(url: $0.url) }
  }

  private func handle(url: URL) {
    guard NativeTripWidgetStore.requestFromWidgetURL(url) else { return }
    NotificationCenter.default.post(name: .nativeTripWidgetActionReceived, object: nil)
  }
}
