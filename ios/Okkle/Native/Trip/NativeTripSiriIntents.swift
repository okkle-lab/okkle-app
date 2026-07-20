import AppIntents
import Foundation

struct TrackTripIntent: AppIntent {
  static var title: LocalizedStringResource = "Track Trip"
  static var description = IntentDescription("Start tracking mileage for the current trip.")
  static var openAppWhenRun = true

  @available(iOS 26.0, *)
  static var supportedModes: IntentModes {
    .foreground(.dynamic)
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let store = OkkleStore.shared
    let session = NativeTripSession.shared

    guard store.settings.siriTripTrackingEnabled else {
      return .result(dialog: "Siri trip tracking is off in Okkle.")
    }

    switch session.phase {
    case .live:
      return .result(dialog: "Okkle is already tracking this trip.")
    case .paused:
      session.resume()
      return .result(dialog: "Okkle has resumed tracking this trip.")
    case .setup, .summary:
      session.start(vehicle: store.settings.defaultVehicle)

      if session.phase == .live {
        return .result(dialog: "Okkle is tracking this trip.")
      }

      if session.permissionMessage != nil {
        return .result(dialog: "Location permission is needed to track trip distance.")
      }

      return .result(dialog: "Opening Okkle to start tracking this trip.")
    }
  }
}

struct OkkleTripShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: TrackTripIntent(),
      phrases: [
        "Track this trip with \(.applicationName)",
        "Start tracking this trip with \(.applicationName)",
        "Ask \(.applicationName) to track this trip",
        "Start a trip in \(.applicationName)"
      ],
      shortTitle: "Track Trip",
      systemImageName: "location.north.fill"
    )
  }

  static var shortcutTileColor: ShortcutTileColor {
    .teal
  }
}
