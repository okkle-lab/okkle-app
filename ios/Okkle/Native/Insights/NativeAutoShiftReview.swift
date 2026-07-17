import CoreLocation
import SwiftUI
import UserNotifications

private struct NativeAutoShiftReviewStop: Identifiable {
  let number: Int
  let visit: NativeVisit

  var id: UUID { visit.id }
}

private struct NativeTripFeedbackReviewRow: View {
  let feedback: NativeTripFeedback?
  let onSelect: (NativeTripFeedback?) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("How was this trip?")
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        if feedback != nil {
          Button("Clear") { onSelect(nil) }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
        }
      }
      HStack(spacing: 10) {
        feedbackButton(.good, tint: OkkleColor.brand)
        feedbackButton(.bad, tint: OkkleColor.amber)
      }
    }
    .padding(.vertical, 4)
  }

  private func feedbackButton(_ value: NativeTripFeedback, tint: Color) -> some View {
    let selected = feedback == value
    return Button {
      onSelect(selected ? nil : value)
    } label: {
      Label(value.label, systemImage: value.symbol)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(selected ? .white : tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(selected ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

/// Routes a tapped "Shift logged" notification to the review screen. No
/// UNUserNotificationCenterDelegate existed anywhere in the app before this —
/// set as the centre's delegate once, in AppDelegate.
final class NativeNotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
  static let shared = NativeNotificationRouter()

  @Published var pendingAutoShiftReviewTripID: UUID?
  @Published var pendingAutoShiftStarted = false
  @Published var pendingManualTripStopPrompt = false
  @Published var pendingManualTripAutoCompleted = false

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
    switch response.actionIdentifier {
    case NativeManualTripStopNotification.endActionIdentifier:
      Task { @MainActor in
        NativeTripSession.shared.completeStoppedManualTrip(store: OkkleStore.shared, notify: false)
      }
      completionHandler()
      return
    case NativeManualTripStopNotification.continueActionIdentifier:
      DispatchQueue.main.async {
        NativeTripSession.shared.dismissStopPrompt()
      }
      completionHandler()
      return
    case NativeManualTripStopNotification.autoCompleteActionIdentifier:
      Task { @MainActor in
        OkkleStore.shared.settings.manualTripAutoComplete = true
        NativeTripSession.shared.completeStoppedManualTrip(store: OkkleStore.shared, notify: false)
      }
      completionHandler()
      return
    default:
      break
    }

    if info["type"] as? String == "autoShiftReview",
       let raw = info["tripID"] as? String,
       let tripID = UUID(uuidString: raw) {
      DispatchQueue.main.async { [weak self] in
        self?.pendingAutoShiftReviewTripID = tripID
      }
    } else if info["type"] as? String == "autoShiftStarted" {
      DispatchQueue.main.async { [weak self] in
        self?.pendingAutoShiftStarted = true
      }
    } else if info["type"] as? String == "manualTripStopPrompt" {
      DispatchQueue.main.async { [weak self] in
        self?.pendingManualTripStopPrompt = true
        NativeTripSession.shared.requestStopPrompt()
      }
    } else if info["type"] as? String == "manualTripAutoCompleted" {
      DispatchQueue.main.async { [weak self] in
        self?.pendingManualTripAutoCompleted = true
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
  @State private var selectedFeedback: NativeTripFeedback?
  @State private var showsFeedbackPrompt = false

  private var trip: NativeTrip? {
    store.trips.first { $0.id == tripID }
  }

  private var stops: [NativeVisit] {
    guard let trip else { return [] }
    return autoTrack.visits
      .filter { $0.arrival >= trip.startedAt && $0.departure <= trip.endedAt }
      .sorted { $0.arrival < $1.arrival }
  }

  private var numberedStops: [NativeAutoShiftReviewStop] {
    stops.enumerated().map { index, visit in
      NativeAutoShiftReviewStop(number: index + 1, visit: visit)
    }
  }

  private var routeStops: [NativeRouteMapStop] {
    numberedStops.map { stop in
      NativeRouteMapStop(
        id: stop.visit.id,
        coordinate: stop.visit.coordinate,
        title: "\(stop.number). \(stopTitle(for: stop.visit))",
        subtitle: stopSubtitle(for: stop.visit),
        kind: routeStopKind(for: stop.visit),
        glyphText: "\(stop.number)"
      )
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if let trip {
          List {
            Section {
              NativeRouteMapView(
                points: trip.points,
                stops: routeStops,
                showsEndMarker: true,
                isInteractive: true
              )
              .frame(height: 260)
              .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                  .stroke(Color.white.opacity(0.16), lineWidth: 1)
              }
            } header: {
              Text("Route")
            } footer: {
              Text("Numbered pins are the detected stops. Remove any stop that does not belong; the map and future insights update straight away.")
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)

            Section {
              LabeledContent("Miles", value: miles(trip.miles))
              LabeledContent("Started", value: shortTime(trip.startedAt))
              DatePicker(
                "Ended",
                selection: $adjustedEnd,
                in: trip.startedAt...Date(),
                displayedComponents: [.date, .hourAndMinute]
              )
            } header: {
              Text("Shift summary")
            } footer: {
              Text("Adjust \"Ended\" if the shift actually ran longer or shorter than detected — this helps Okkle time future shifts more accurately.")
            }

            if showsFeedbackPrompt {
              Section {
                NativeTripFeedbackReviewRow(
                  feedback: selectedFeedback,
                  onSelect: recordTripFeedback
                )
                .transition(.move(edge: .top).combined(with: .opacity))
              } footer: {
                Text("Optional. This helps Okkle learn which areas are genuinely worth recommending, not just where stops happen often.")
              }
            }

            if !stops.isEmpty {
              Section {
                ForEach(numberedStops) { stop in
                  HStack(spacing: 12) {
                    Text("\(stop.number)")
                      .font(.system(size: 13, weight: .heavy, design: .rounded))
                      .foregroundStyle(.white)
                      .frame(width: 30, height: 30)
                      .background(stopTint(for: stop.visit), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                      Text(stopTitle(for: stop.visit))
                        .font(.system(size: 15, weight: .bold))
                      Text(stopSubtitle(for: stop.visit))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button(role: .destructive) {
                      removeStop(stop.visit)
                    } label: {
                      Image(systemName: "trash")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(stopTitle(for: stop.visit))")
                  }
                }
                .onDelete { offsets in
                  let currentStops = numberedStops
                  for index in offsets {
                    removeStop(currentStops[index].visit)
                  }
                }
              } header: {
                Text("Detected stops (\(stops.count))")
              } footer: {
                Text("Use the remove button or swipe left to remove a stop that is not actually work.")
              }
            }
          }
          .onAppear {
            adjustedEnd = trip.endedAt
            selectedFeedback = trip.feedback
            showsFeedbackPrompt = trip.feedback == nil
          }
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
    // Guards against a corrected end time that would make the shift's
    // duration negative or nonsensical — the DatePicker's own `in:` range
    // already prevents this in the UI, but this is the last line of
    // defense before it's saved.
    guard adjustedEnd > trip.startedAt else { return }
    let delta = adjustedEnd.timeIntervalSince(trip.endedAt)
    // A few seconds' difference from opening the DatePicker isn't a real
    // correction — only treat a deliberate change as calibration signal.
    guard abs(delta) > 60 else { return }
    let suggestedTimeout = store.settings.autoTrackCalibration.stationaryTimeoutSeconds + delta
    store.settings.autoTrackCalibration.nudgeStationaryTimeout(toward: suggestedTimeout)
    trip.endedAt = adjustedEnd
    store.updateTrip(trip)
  }

  private func removeStop(_ visit: NativeVisit) {
    autoTrack.discardVisit(visit.id)
  }

  private func recordTripFeedback(_ feedback: NativeTripFeedback?) {
    guard var trip else { return }
    trip.feedback = feedback
    selectedFeedback = feedback
    store.updateTrip(trip)
    guard feedback != nil else { return }
    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
      showsFeedbackPrompt = false
    }
  }

  private func shortTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  private func stopTitle(for visit: NativeVisit) -> String {
    "Stop"
  }

  private func stopSubtitle(for visit: NativeVisit) -> String {
    var text = "\(shortTime(visit.arrival)) – \(shortTime(visit.departure))"
    if let placeName = visit.placeName {
      text += " · \(placeName)"
    }
    return text
  }

  private func routeStopKind(for visit: NativeVisit) -> NativeRouteMapStop.Kind {
    .other
  }

  private func stopTint(for visit: NativeVisit) -> Color {
    .secondary
  }
}
