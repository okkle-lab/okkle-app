import SwiftUI

@main
struct OkkleWatchApp: App {
  @StateObject private var connector = WatchTripConnector.shared

  var body: some Scene {
    WindowGroup {
      WatchTripView()
        .environmentObject(connector)
    }
  }
}
