import SwiftUI
import UserNotifications

/// Routes a tapped "Shift logged" notification to the review screen. No
/// UNUserNotificationCenterDelegate existed anywhere in the app before this —
/// set as the centre's delegate once, in AppDelegate.
final class NativeNotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
  static let shared = NativeNotificationRouter()

  @Published var pendingAutoShiftReviewTripID: UUID?

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .list])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    if info["type"] as? String == "autoShiftReview",
       let raw = info["tripID"] as? String,
       let tripID = UUID(uuidString: raw) {
      DispatchQueue.main.async { [weak self] in
        self?.pendingAutoShiftReviewTripID = tripID
      }
    }
    completionHandler()
  }
}

/// Lets the driver confirm or correct an automatically-detected shift: check
/// the miles look right, drop a stop that got misclassified, or nudge the
/// end time if it cut off too early/late. Corrections feed straight back
/// into the calibration that tunes future detection — this is the whole
/// point of showing it, not just a receipt.
struct NativeAutoShiftReviewView: View {
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared
  @Environment(\.dismiss) private var dismiss
  let tripID: UUID

  @State private var adjustedEnd: Date = Date()

  private var trip: NativeTrip? {
    store.trips.first { $0.id == tripID }
  }

  private var stops: [NativeVisit] {
    guard let trip else { return [] }
    return autoTrack.visits
      .filter { $0.arrival >= trip.startedAt && $0.departure <= trip.endedAt }
      .sorted { $0.arrival < $1.arrival }
  }

  var body: some View {
    NavigationStack {
      Group {
        if let trip {
          List {
            Section {
              LabeledContent("Miles", value: miles(trip.miles))
              LabeledContent("Started", value: shortTime(trip.startedAt))
              DatePicker("Ended", selection: $adjustedEnd, displayedComponents: [.hourAndMinute])
            } header: {
              Text("Shift summary")
            } footer: {
              Text("Adjust \"Ended\" if the shift actually ran longer or shorter than detected — this helps Okkle time future shifts more accurately.")
            }

            if !stops.isEmpty {
              Section {
                ForEach(stops) { visit in
                  HStack {
                    VStack(alignment: .leading, spacing: 2) {
                      Text(visit.kind == .pickup ? "Pick-up" : "Drop-off")
                        .font(.system(size: 15, weight: .bold))
                      Text(stopSubtitle(for: visit))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                  }
                }
                .onDelete { offsets in
                  for index in offsets { autoTrack.discardVisit(stops[index].id) }
                }
              } header: {
                Text("Detected stops (\(stops.count))")
              } footer: {
                Text("Swipe to remove a stop that isn't actually work.")
              }
            }
          }
          .onAppear { adjustedEnd = trip.endedAt }
        } else {
          VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
              .font(.system(size: 34, weight: .bold))
              .foregroundStyle(.secondary)
            Text("Shift no longer available")
              .font(.system(size: 17, weight: .bold))
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .navigationTitle("Check your shift")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            applyCorrections()
            dismiss()
          }
        }
      }
    }
  }

  private func applyCorrections() {
    guard var trip = self.trip else { return }
    let delta = adjustedEnd.timeIntervalSince(trip.endedAt)
    // A few seconds' difference from opening the DatePicker isn't a real
    // correction — only treat a deliberate change as calibration signal.
    guard abs(delta) > 60 else { return }
    let suggestedTimeout = store.settings.autoTrackCalibration.stationaryTimeoutSeconds + delta
    store.settings.autoTrackCalibration.nudgeStationaryTimeout(toward: suggestedTimeout)
    trip.endedAt = adjustedEnd
    store.updateTrip(trip)
  }

  private func shortTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  private func stopSubtitle(for visit: NativeVisit) -> String {
    var text = "\(shortTime(visit.arrival)) – \(shortTime(visit.departure))"
    if let placeName = visit.placeName {
      text += " · \(placeName)"
    }
    return text
  }
}
