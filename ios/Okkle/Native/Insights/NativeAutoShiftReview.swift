import CoreLocation
import SwiftUI
import UserNotifications

private struct NativeAutoShiftReviewStop: Identifiable {
  let number: Int
  let visit: NativeVisit

  var id: UUID { visit.id }
}

/// Routes a tapped "Shift logged" notification to the review screen. No
/// UNUserNotificationCenterDelegate existed anywhere in the app before this —
/// set as the centre's delegate once, in AppDelegate.
final class NativeNotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
  static let shared = NativeNotificationRouter()

  @Published var pendingAutoShiftReviewTripID: UUID?
  @Published var pendingManualTripStopPrompt = false

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
    } else if info["type"] as? String == "manualTripStopPrompt" {
      DispatchQueue.main.async { [weak self] in
        self?.pendingManualTripStopPrompt = true
        NativeTripSession.shared.stopPromptRequested = true
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
  @State private var explicitFeedbackGiven = false

  private var trip: NativeTrip? {
    store.trips.first { $0.id == tripID }
  }

  /// The zone that was recommended for this shift's weekday, if the shift's
  /// own route actually passed near it — nil (no prompt shown) when there
  /// was nothing to evaluate, e.g. too little history yet for a
  /// recommendation, or the driver worked somewhere else entirely.
  private var recommendedZoneNearby: CLLocationCoordinate2D? {
    guard let trip else { return nil }
    let weekday = Calendar.current.component(.weekday, from: trip.startedAt) - 1
    guard let zone = NativeShiftInsights.build(visits: autoTrack.visits, store: store)
      .weekdayDetails.first(where: { $0.weekday == weekday })?.coordinate else { return nil }
    let zoneLocation = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
    let wasNear = stops.contains { $0.location.distance(from: zoneLocation) <= 600 }
      || trip.points.contains { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: zoneLocation) <= 600 }
    return wasNear ? zone : nil
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
              DatePicker("Ended", selection: $adjustedEnd, displayedComponents: [.hourAndMinute])
            } header: {
              Text("Shift summary")
            } footer: {
              Text("Adjust \"Ended\" if the shift actually ran longer or shorter than detected — this helps Okkle time future shifts more accurately.")
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

            if !explicitFeedbackGiven, recommendedZoneNearby != nil {
              Section {
                HStack(spacing: 12) {
                  Text("Was this area worth it?")
                    .font(.system(size: 15, weight: .semibold))
                  Spacer()
                  Button("No") { recordZoneFeedback(false) }
                    .buttonStyle(.bordered)
                  Button("Yes") { recordZoneFeedback(true) }
                    .buttonStyle(.borderedProminent)
                }
              } footer: {
                Text("Helps Okkle learn whether a recommended area is actually paying off, not just how busy it looks.")
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

  private func removeStop(_ visit: NativeVisit) {
    autoTrack.discardVisit(visit.id)
  }

  private func recordZoneFeedback(_ wasWorthIt: Bool) {
    NativeZoneOutcomeTracker.shared.recordExplicitFeedback(wasWorthIt: wasWorthIt)
    explicitFeedbackGiven = true
  }

  private func shortTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  private func stopTitle(for visit: NativeVisit) -> String {
    switch visit.kind {
    case .pickup:
      return "Pick-up"
    case .dropoff:
      return "Drop-off"
    case .other:
      return "Stop"
    }
  }

  private func stopSubtitle(for visit: NativeVisit) -> String {
    var text = "\(shortTime(visit.arrival)) – \(shortTime(visit.departure))"
    if let placeName = visit.placeName {
      text += " · \(placeName)"
    }
    return text
  }

  private func routeStopKind(for visit: NativeVisit) -> NativeRouteMapStop.Kind {
    switch visit.kind {
    case .pickup:
      return .pickup
    case .dropoff:
      return .dropoff
    case .other:
      return .other
    }
  }

  private func stopTint(for visit: NativeVisit) -> Color {
    switch visit.kind {
    case .pickup:
      return .indigo
    case .dropoff:
      return .orange
    case .other:
      return .secondary
    }
  }
}
