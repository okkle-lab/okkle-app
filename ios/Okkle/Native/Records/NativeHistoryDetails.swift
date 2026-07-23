import CoreLocation
import MapKit
import SwiftUI
import UIKit
struct NativeHistoryDetailSheet: View {
  let item: NativeHistoryItem
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    switch item {
    case .trip(let trip):
      NativeTripDetailSheet(trip: trip, onEdit: onEdit, onDelete: onDelete)
    case .record(let record):
      NativeRecordDetailSheet(record: record, onEdit: onEdit, onDelete: onDelete)
    }
  }
}

struct NativeTripDetailSheet: View {
  let trip: NativeTrip
  let onEdit: () -> Void
  let onDelete: () -> Void
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared
  @State private var startAddress: String?
  @State private var endAddress: String?
  @State private var stopPlaceNames: [UUID: String] = [:]
  @State private var homeCandidate: NativeTripHomeCandidate?
  @State private var didResolveRoute = false
  @State private var selectedRouteStopID: UUID?
  @State private var showingFullScreenRouteMap = false
  @State private var selectedFeedback: NativeTripFeedback?
  @State private var showsFeedbackPrompt = false
  @AppStorage("uk.okkle.native.hasSeenStopPersonalSwipeHint") private var hasSeenStopSwipeHint = false

  var body: some View {
    ZStack {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if showsFeedbackPrompt {
              NativeTripFeedbackCard(
                feedback: selectedFeedback,
                onSelect: recordTripFeedback
              )
              .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(spacing: 12) {
              NativeTripFlatMetric(title: "Miles", value: miles(trip.miles), symbol: "road.lanes")
              NativeTripFlatMetric(title: "Deduction", value: gbp(trip.deduction, whole: true), symbol: "sterlingsign.circle.fill", color: .green)
            }

            NativeGlassCard {
              VStack(alignment: .leading, spacing: 14) {
                tripDetailRow("Vehicle", value: trip.vehicle.label, symbol: trip.vehicle.symbol)
                Divider()
                tripDetailRow("Duration", value: nativeDurationLabel(trip.endedAt.timeIntervalSince(trip.startedAt)), symbol: "timer")
              }
            }

            if hasMapDetails {
              routeSection
            }

            NativeDetailActionButtons(onEdit: onEdit, onDelete: onDelete)
          }
          .padding(22)
          .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showsFeedbackPrompt)
        }
        .background(NativeBackground())
        .navigationTitle("Trip details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
              .fontWeight(.bold)
          }
        }
      }

      if let homeCandidate {
        NativeTripHomePrompt(
          candidate: homeCandidate,
          onConfirm: saveHomeCandidate,
          onDismiss: dismissHomeCandidate
        )
        .transition(.scale(scale: 0.94).combined(with: .opacity))
        .zIndex(2)
      }
    }
    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: homeCandidate != nil)
    .onAppear {
      selectedFeedback = currentTrip.feedback
      showsFeedbackPrompt = currentTrip.feedback == nil
    }
    .task(id: trip.id) {
      await resolveRouteDetails()
    }
    .fullScreenCover(isPresented: $showingFullScreenRouteMap) {
      NativeTripRouteFullScreenMap(
        points: trip.points,
        stops: routeStops,
        selectedStopID: $selectedRouteStopID
      )
    }
  }

  private var routeSection: some View {
    NativeGlassCard {
      VStack(alignment: .leading, spacing: 14) {
        Label("Route", systemImage: "map.fill")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(OkkleColor.ink)

        NativeRouteMapView(
          points: trip.points,
          stops: routeStops,
          selectedStopID: $selectedRouteStopID
        )
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
          showingFullScreenRouteMap = true
        }

        VStack(alignment: .leading, spacing: 12) {
          if let startPoint {
            routeEndpointLocationRow(
              "Start",
              value: startAddress ?? coordinateLabel(startPoint),
              time: timeLabel(for: startPoint.timestamp ?? trip.startedAt),
              symbol: "location.circle",
              tint: OkkleColor.brand,
              isHome: isKnownHome(startPoint.coordinate)
            )
          }

          if numberedStops.count > 1 && !hasSeenStopSwipeHint {
            stopSwipeHintBanner
          }

          ForEach(numberedStops) { stop in
            NativeVisitSwipeRow(
              isPersonal: stop.visit.isPersonal,
              onSetPersonal: { markStopPersonal(stop.visit, isPersonal: $0) }
            ) {
              Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                  selectedRouteStopID = stop.id
                }
              } label: {
                routeStopLocationRow(stop, isSelected: selectedRouteStopID == stop.id)
              }
              .buttonStyle(.plain)
            }
          }

          if let endPoint {
            routeEndpointLocationRow(
              "End",
              value: endAddress ?? coordinateLabel(endPoint),
              time: timeLabel(for: endPoint.timestamp ?? trip.endedAt),
              symbol: "mappin.circle",
              tint: OkkleColor.blue,
              isHome: isKnownHome(endPoint.coordinate)
            )
          }
        }
      }
    }
  }

  private var hasMapDetails: Bool {
    !trip.points.isEmpty
  }

  private var startPoint: RoutePoint? {
    trip.points.first
  }

  private var endPoint: RoutePoint? {
    trip.points.last
  }

  private var stops: [NativeVisit] {
    NativeRouteStopDetector.routeStops(
      in: trip.points,
      startedAt: trip.startedAt,
      endedAt: trip.endedAt,
      recordedVisits: autoTrack.visits
    )
  }

  private var numberedStops: [NativeTripDetailStop] {
    stops.enumerated().map { index, visit in
      NativeTripDetailStop(number: index + 1, visit: visit)
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
        glyphText: "\(stop.number)",
        isPersonal: stop.visit.isPersonal
      )
    }
  }

  private var currentTrip: NativeTrip {
    store.trips.first { $0.id == trip.id } ?? trip
  }

  private func recordTripFeedback(_ feedback: NativeTripFeedback?) {
    var updated = currentTrip
    updated.feedback = feedback
    selectedFeedback = feedback
    store.updateTrip(updated)
    guard feedback != nil else { return }
    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
      showsFeedbackPrompt = false
    }
  }

  private func coordinateLabel(_ point: RoutePoint) -> String {
    String(format: "%.5f, %.5f", point.latitude, point.longitude)
  }

  private func routeEndpointLocationRow(
    _ title: String,
    value: String,
    time: String,
    symbol: String,
    tint: Color,
    isHome: Bool
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(isHome ? OkkleColor.brand : tint)
        .frame(width: 34, height: 34)
        .background((isHome ? OkkleColor.brand : tint).opacity(0.13), in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          HStack(spacing: 6) {
            Text(title)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
            if isHome {
              Label("Home", systemImage: "house.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OkkleColor.brand)
            }
          }
          Spacer(minLength: 8)
          Text(time)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
            .lineLimit(1)
        }
        Text(value)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var stopSwipeHintBanner: some View {
    HStack(spacing: 10) {
      Image(systemName: "hand.draw.fill")
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(OkkleColor.brand)
      Text("Swipe a stop to mark it personal")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(OkkleColor.ink)
      Spacer(minLength: 8)
      Button {
        withAnimation(.easeInOut(duration: 0.2)) { hasSeenStopSwipeHint = true }
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 16))
          .foregroundStyle(OkkleColor.muted)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(OkkleColor.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .transition(.opacity.combined(with: .move(edge: .top)))
  }

  private func markStopPersonal(_ visit: NativeVisit, isPersonal: Bool) {
    autoTrack.setVisitPersonal(visit, isPersonal: isPersonal)
    withAnimation(.easeInOut(duration: 0.2)) { hasSeenStopSwipeHint = true }
  }

  private func routeStopLocationRow(_ stop: NativeTripDetailStop, isSelected: Bool) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Text("\(stop.number)")
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(stop.visit.isPersonal ? Color.gray : stopTint(for: stop.visit), in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(stopTitle(for: stop.visit))
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OkkleColor.ink)
          if stop.visit.isPersonal {
            Text("Personal")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(.white)
              .padding(.horizontal, 7)
              .padding(.vertical, 2)
              .background(Color.gray, in: Capsule())
          }
          Spacer(minLength: 8)
          Text(stopTimeLabel(for: stop.visit))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
            .lineLimit(1)
        }
        Text(stopSubtitle(for: stop.visit))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 8)
    .opacity(stop.visit.isPersonal ? 0.6 : 1)
    .background(
      isSelected ? stopTint(for: stop.visit).opacity(0.10) : Color.clear,
      in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
  }

  private func tripDetailRow(_ title: String, value: String, symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(OkkleColor.brand)
        .frame(width: 34, height: 34)
        .background(OkkleColor.brand.opacity(0.13), in: Circle())
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      Spacer()
      Text(value)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
        .multilineTextAlignment(.trailing)
    }
  }

  private func stopTitle(for visit: NativeVisit) -> String {
    "Stop"
  }

  private func stopSubtitle(for visit: NativeVisit) -> String {
    let place = stopDisplayName(for: visit)
    let dwellMinutes = max(1, Int((visit.dwell / 60).rounded()))
    return "\(place) • \(dwellMinutes)m"
  }

  private func stopDisplayName(for visit: NativeVisit) -> String {
    stopPlaceNames[visit.id] ?? meaningfulPlaceName(visit.placeName) ?? "Detected from movement"
  }

  private func meaningfulPlaceName(_ name: String?) -> String? {
    guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty,
          trimmed != "Detected from movement" else {
      return nil
    }
    return trimmed
  }

  private func timeLabel(for date: Date) -> String {
    date.formatted(.dateTime.hour().minute())
  }

  private func stopTimeLabel(for visit: NativeVisit) -> String {
    let arrival = timeLabel(for: visit.arrival)
    let departure = timeLabel(for: visit.departure)
    if Calendar.current.isDate(visit.arrival, equalTo: visit.departure, toGranularity: .minute) {
      return arrival
    }
    return "\(arrival) - \(departure)"
  }

  private func stopTint(for visit: NativeVisit) -> Color {
    OkkleColor.amber
  }

  private func routeStopKind(for visit: NativeVisit) -> NativeRouteMapStop.Kind {
    .other
  }

  @MainActor
  private func resolveRouteDetails() async {
    guard !didResolveRoute else { return }
    didResolveRoute = true
    var startResolved: String?
    var endResolved: String?
    if let startPoint {
      if let existingAddress = trip.startAddress {
        startResolved = existingAddress
      } else {
        startResolved = await Self.address(for: startPoint.coordinate)
      }
      startAddress = startResolved
    }
    if let endPoint {
      if let existingAddress = trip.endAddress {
        endResolved = existingAddress
      } else {
        endResolved = await Self.address(for: endPoint.coordinate)
      }
      endAddress = endResolved
    }
    await resolveStopPlaceNames()
    detectHomeCandidate(startAddress: startResolved, endAddress: endResolved)
  }

  @MainActor
  private func resolveStopPlaceNames() async {
    for visit in stops where stopPlaceNames[visit.id] == nil {
      if let name = await Self.placeName(for: visit.coordinate) {
        stopPlaceNames[visit.id] = name
      }
    }
  }

  @MainActor
  private func detectHomeCandidate(startAddress: String?, endAddress: String?) {
    guard homeCandidate == nil else { return }
    let candidates = [
      startPoint.map { ("Start", $0, startAddress) },
      endPoint.map { ("End", $0, endAddress) }
    ].compactMap { $0 }
    for candidate in candidates where shouldSuggestHome(for: candidate.1) {
      let suggestion = NativeTripHomeCandidate(
        title: candidate.0,
        point: candidate.1,
        address: candidate.2,
        dismissalKey: homeDismissalKey(for: candidate.1.coordinate)
      )
      guard !UserDefaults.standard.bool(forKey: suggestion.dismissalKey) else { continue }
      homeCandidate = suggestion
      return
    }
  }

  private func shouldSuggestHome(for point: RoutePoint) -> Bool {
    guard !isKnownHome(point.coordinate) else { return false }
    // Once a Home is saved, a second frequent point elsewhere reads as a
    // regular delivery stop, not a second home — offering it as "maybe
    // home?" is how two different addresses both end up labelled "Home"
    // on different trips. A driver who's genuinely moved can still update
    // Home manually in Settings.
    guard !hasExistingHome else { return false }
    let coordinate = point.coordinate
    let nearbyEndpointCount = store.trips.reduce(0) { count, trip in
      var count = count
      if let first = trip.points.first, distance(from: first.coordinate, to: coordinate) <= 180 {
        count += 1
      }
      if let last = trip.points.last, distance(from: last.coordinate, to: coordinate) <= 180 {
        count += 1
      }
      return count
    }
    let hour = Calendar.current.component(.hour, from: point.timestamp ?? trip.startedAt)
    let edgeOfDay = hour <= 10 || hour >= 20
    return nearbyEndpointCount >= 3 || (nearbyEndpointCount >= 2 && edgeOfDay)
  }

  private func isKnownHome(_ coordinate: CLLocationCoordinate2D) -> Bool {
    store.settings.excludedPlaces.contains { place in
      distance(from: place.coordinate, to: coordinate) <= 200
    }
  }

  private var hasExistingHome: Bool {
    store.settings.excludedPlaces.contains { $0.label.caseInsensitiveCompare("Home") == .orderedSame }
  }

  private func saveHomeCandidate() {
    guard let homeCandidate else { return }
    if !isKnownHome(homeCandidate.point.coordinate) {
      // Defensive dedup, not just the shouldSuggestHome guard above — this
      // is the only place a "Home" place actually gets written, so it's
      // the backstop that guarantees at most one exists no matter which
      // path got here.
      store.settings.excludedPlaces.removeAll { $0.label.caseInsensitiveCompare("Home") == .orderedSame }
      store.settings.excludedPlaces.append(NativeExcludedPlace(
        label: "Home",
        latitude: homeCandidate.point.latitude,
        longitude: homeCandidate.point.longitude,
        address: homeCandidate.address
      ))
    }
    UserDefaults.standard.set(true, forKey: homeCandidate.dismissalKey)
    self.homeCandidate = nil
  }

  private func rememberDismissedHomeCandidate() {
    guard let homeCandidate else { return }
    UserDefaults.standard.set(true, forKey: homeCandidate.dismissalKey)
  }

  private func dismissHomeCandidate() {
    rememberDismissedHomeCandidate()
    homeCandidate = nil
  }

  private func homeDismissalKey(for coordinate: CLLocationCoordinate2D) -> String {
    let lat = Int((coordinate.latitude * 10_000).rounded())
    let lon = Int((coordinate.longitude * 10_000).rounded())
    return "uk.okkle.native.homeCandidateDismissed.\(lat).\(lon)"
  }

  private func distance(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> CLLocationDistance {
    CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
      .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
  }

  private static func address(for coordinate: CLLocationCoordinate2D) async -> String? {
    await withCheckedContinuation { continuation in
      CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
        continuation.resume(returning: placemarks?.first.flatMap(formattedAddress))
      }
    }
  }

  /// Names a stop by street/area rather than guessing which specific
  /// business the driver was at — "nearest POI within N metres" reads
  /// confident but is frequently wrong in dense strips (a few shopfronts
  /// apart is well within GPS drift), and a wrong shop name is worse than
  /// an honest, always-accurate street. Shares the neighbourhood-first
  /// naming used for area suggestions elsewhere (NativeInsightArea.swift).
  private static func placeName(for coordinate: CLLocationCoordinate2D) async -> String? {
    await withCheckedContinuation { continuation in
      CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
        guard let placemark = placemarks?.first else {
          continuation.resume(returning: nil)
          return
        }
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let area = placemark.subLocality ?? placemark.locality
        let name = [street.isEmpty ? nil : street, area]
          .compactMap { $0 }
          .filter { !$0.isEmpty }
          .joined(separator: ", ")
        continuation.resume(returning: name.isEmpty ? nil : name)
      }
    }
  }

  private static func formattedAddress(_ placemark: CLPlacemark) -> String? {
    let line1 = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
    let line2 = [placemark.locality ?? placemark.subLocality, placemark.postalCode].compactMap { $0 }.joined(separator: " ")
    let combined = [line1, line2].filter { !$0.isEmpty }.joined(separator: ", ")
    return combined.isEmpty ? nil : combined
  }
}

private struct NativeTripHomeCandidate {
  let title: String
  let point: RoutePoint
  let address: String?
  let dismissalKey: String
}

private struct NativeTripFlatMetric: View {
  let title: String
  let value: String
  let symbol: String
  var color: Color = OkkleColor.brand

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(color)
        .frame(width: 28, height: 28)
        .background(color.opacity(0.12), in: Circle())

      VStack(alignment: .leading, spacing: 1) {
        Text(value)
          .font(.system(size: 18, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Text(title)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(OkkleColor.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(OkkleColor.muted.opacity(0.10), lineWidth: 1)
    }
  }
}

private struct NativeTripFeedbackCard: View {
  let feedback: NativeTripFeedback?
  let onSelect: (NativeTripFeedback?) -> Void

  var body: some View {
    NativeGlassCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text("How was this trip?")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(OkkleColor.ink)
            Text("Optional feedback helps Okkle learn which areas are actually worth recommending.")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 8)
          if feedback != nil {
            Button("Clear") { onSelect(nil) }
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(OkkleColor.muted)
              .buttonStyle(.plain)
          }
        }

        HStack(spacing: 10) {
          feedbackButton(.good, tint: OkkleColor.brand)
          feedbackButton(.bad, tint: OkkleColor.amber)
        }
      }
    }
  }

  private func feedbackButton(_ value: NativeTripFeedback, tint: Color) -> some View {
    let selected = feedback == value
    return Button {
      onSelect(selected ? nil : value)
    } label: {
      HStack(spacing: 8) {
        Image(systemName: value.symbol)
          .font(.system(size: 14, weight: .bold))
        Text(value.label)
          .font(.system(size: 14, weight: .bold))
      }
      .foregroundStyle(selected ? .white : tint)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 11)
      .background(selected ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Mark trip as \(value.label.lowercased())")
  }
}

private struct NativeTripEditFeedbackPicker: View {
  @Binding var feedback: NativeTripFeedback?

  var body: some View {
    HStack(spacing: 10) {
      feedbackButton(nil, label: "Not set", symbol: "minus.circle.fill", tint: OkkleColor.muted)
      feedbackButton(.good, label: NativeTripFeedback.good.label, symbol: NativeTripFeedback.good.symbol, tint: OkkleColor.brand)
      feedbackButton(.bad, label: NativeTripFeedback.bad.label, symbol: NativeTripFeedback.bad.symbol, tint: OkkleColor.amber)
    }
    .padding(.vertical, 4)
  }

  private func feedbackButton(
    _ value: NativeTripFeedback?,
    label: String,
    symbol: String,
    tint: Color
  ) -> some View {
    let selected = feedback == value
    return Button {
      feedback = value
    } label: {
      VStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 15, weight: .bold))
        Text(label)
          .font(.system(size: 12, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.76)
      }
      .foregroundStyle(selected ? .white : tint)
      .frame(maxWidth: .infinity)
      .frame(height: 58)
      .background(selected ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label == "Not set" ? "Clear trip feedback" : "Mark trip as \(label.lowercased())")
  }
}

private struct NativeTripHomePrompt: View {
  let candidate: NativeTripHomeCandidate
  let onConfirm: () -> Void
  let onDismiss: () -> Void

  private let rainbow = [
    Color(red: 1.00, green: 0.23, blue: 0.39),
    Color(red: 1.00, green: 0.67, blue: 0.20),
    Color(red: 0.32, green: 0.82, blue: 0.39),
    Color(red: 0.16, green: 0.72, blue: 1.00),
    Color(red: 0.52, green: 0.35, blue: 1.00),
    Color(red: 1.00, green: 0.24, blue: 0.76),
    Color(red: 1.00, green: 0.23, blue: 0.39)
  ]

  var body: some View {
    ZStack {
      Color.black.opacity(0.18)
        .ignoresSafeArea()
        .onTapGesture(perform: onDismiss)

      VStack(spacing: 16) {
        ZStack {
          Circle()
            .fill(AngularGradient(colors: rainbow, center: .center))
            .frame(width: 92, height: 92)
            .blur(radius: 18)
            .opacity(0.45)

          Circle()
            .stroke(AngularGradient(colors: rainbow, center: .center), lineWidth: 2)
            .frame(width: 62, height: 62)
            .opacity(0.72)

          Image(systemName: "sparkles")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(OkkleColor.brand, in: Circle())
            .shadow(color: OkkleColor.brand.opacity(0.22), radius: 14, y: 8)
        }
        .padding(.top, 2)

        VStack(spacing: 8) {
          Text("Maybe home?")
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(OkkleColor.ink)

          Text("\(candidate.title) looks like a regular home location. Save it so Okkle can leave it out of future work suggestions?")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let address = candidate.address {
          Text(address)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(OkkleColor.brandDark)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(OkkleColor.mint.opacity(0.55), in: Capsule())
        }

        HStack(spacing: 10) {
          Button(action: onDismiss) {
            Text("Not now")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(OkkleColor.muted)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 13)
              .background(Color.black.opacity(0.06), in: Capsule())
          }

          Button(action: onConfirm) {
            Text("Yes")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(.white)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 13)
              .background(OkkleColor.brand, in: Capsule())
          }
        }
        .padding(.top, 2)
      }
      .padding(20)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
          .stroke(AngularGradient(colors: rainbow, center: .center), lineWidth: 1.2)
          .opacity(0.62)
      }
      .shadow(color: Color(red: 0.58, green: 0.36, blue: 1.0).opacity(0.18), radius: 34, y: 16)
      .padding(.horizontal, 28)
    }
  }
}

private struct NativeTripDetailStop: Identifiable {
  let number: Int
  let visit: NativeVisit

  var id: UUID { visit.id }
}

/// Swipe a single stop within a multi-stop trip to flag it personal or
/// business — two fixed edges, not one dynamic toggle: swiping right
/// (leading edge) always reveals Business, swiping left (trailing edge)
/// always reveals Personal, matching the Data tab's whole-trip row. Full
/// swipe on either side commits immediately since this is reversible.
private struct NativeVisitSwipeRow<Content: View>: View {
  let isPersonal: Bool
  let onSetPersonal: (Bool) -> Void
  @ViewBuilder var content: () -> Content

  @State private var dragOffset: CGFloat = 0
  @State private var isOpen = false

  private let revealWidth: CGFloat = 92
  private let fullSwipeCommitDistance: CGFloat = 150
  // Matches routeStopLocationRow's own selected-state highlight radius
  // (14pt) so the row's resting and selected shapes agree — 20 read as
  // too round, a plain rectangle (0) as the chopped-off look this
  // replaced.
  private let cornerRadius: CGFloat = 14

  var body: some View {
    ZStack {
      HStack(spacing: 0) {
        if dragOffset > 0 {
          swipeButton(label: "Business", symbol: "briefcase.fill", tint: OkkleColor.brand) { commit(setPersonal: false) }
            .frame(width: max(dragOffset, revealWidth), alignment: .leading)
          Spacer(minLength: 0)
        } else if dragOffset < 0 {
          Spacer(minLength: 0)
          swipeButton(label: "Personal", symbol: "person.fill", tint: .gray) { commit(setPersonal: true) }
            .frame(width: max(-dragOffset, revealWidth), alignment: .trailing)
        }
      }

      content()
        .background(Color(.systemBackground))
        .offset(x: dragOffset)
        .contentShape(Rectangle())
        .onTapGesture {
          if isOpen { close() }
        }
        .highPriorityGesture(
          DragGesture(minimumDistance: 14)
            .onChanged { value in
              guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
              let base: CGFloat = isOpen ? (dragOffset >= 0 ? revealWidth : -revealWidth) : 0
              let proposed = base + value.translation.width
              dragOffset = max(-fullSwipeCommitDistance - 30, min(fullSwipeCommitDistance + 30, proposed))
            }
            .onEnded { value in
              handleDragEnd(value.translation.width)
            }
        )
    }
    // Rounds both the content and the reveal buttons underneath it as one
    // shape — .clipped() alone only clips to the rectangular bounds, which
    // is why these panels read as square before this.
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  private func swipeButton(label: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: symbol)
          .font(.system(size: 16, weight: .bold))
        Text(label)
          .font(.system(size: 11, weight: .bold))
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .buttonStyle(.plain)
    .background(tint)
  }

  private func handleDragEnd(_ translation: CGFloat) {
    if translation <= -fullSwipeCommitDistance {
      commit(setPersonal: true)
      return
    }
    if translation >= fullSwipeCommitDistance {
      commit(setPersonal: false)
      return
    }
    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
      if dragOffset > revealWidth / 2 {
        dragOffset = revealWidth
        isOpen = true
      } else if dragOffset < -revealWidth / 2 {
        dragOffset = -revealWidth
        isOpen = true
      } else {
        dragOffset = 0
        isOpen = false
      }
    }
  }

  private func commit(setPersonal: Bool) {
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
    onSetPersonal(setPersonal)
    close()
  }

  private func close() {
    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
      dragOffset = 0
      isOpen = false
    }
  }
}

private struct NativeTripRouteFullScreenMap: View {
  let points: [RoutePoint]
  let stops: [NativeRouteMapStop]
  @Binding var selectedStopID: UUID?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack(alignment: .topTrailing) {
      NativeRouteMapView(
        points: points,
        stops: stops,
        showsEndMarker: true,
        isInteractive: true,
        selectedStopID: $selectedStopID
      )
      .ignoresSafeArea()

      Button {
        dismiss()
      } label: {
        Text("Done")
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(OkkleColor.brand)
          .padding(.horizontal, 18)
          .padding(.vertical, 12)
          .background(.regularMaterial, in: Capsule())
      }
      .buttonStyle(.plain)
      .padding(.top, 18)
      .padding(.trailing, 18)
    }
  }
}

struct NativeRecordDetailSheet: View {
  let record: NativeRecord
  let onEdit: () -> Void
  let onDelete: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var showingFullScreenReceipt = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          NativeGlassCard(cornerRadius: 30) {
            HStack(alignment: .center, spacing: 14) {
              Image(systemName: record.kind.symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(tint.opacity(0.14), in: Circle())
              VStack(alignment: .leading, spacing: 4) {
                Text(title)
                  .font(.system(size: 24, weight: .bold, design: .rounded))
                  .foregroundStyle(OkkleColor.ink)
                Text(subtitle)
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(OkkleColor.muted)
              }
              Spacer(minLength: 10)
              Text(primaryValue)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(OkkleColor.ink)
                .minimumScaleFactor(0.7)
            }
          }

          NativeGlassCard {
            VStack(alignment: .leading, spacing: 14) {
              recordDetailRow("Date", value: record.date.formatted(.dateTime.weekday(.abbreviated).day().month().year()), symbol: "calendar")
              recordDetailRow("Period", value: record.period.label, symbol: "calendar.badge.clock")
              Divider()
              detailRows
            }
          }

          if let image = receiptImage {
            NativeGlassCard {
              VStack(alignment: .leading, spacing: 12) {
                Label("Receipt", systemImage: "photo")
                  .font(.system(size: 16, weight: .bold))
                  .foregroundStyle(OkkleColor.ink)
                Button {
                  showingFullScreenReceipt = true
                } label: {
                  Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                      Label("View", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.52), in: Capsule())
                        .padding(12)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View receipt full screen")
              }
            }
          }

          NativeDetailActionButtons(onEdit: onEdit, onDelete: onDelete)
        }
        .padding(22)
      }
      .background(NativeBackground())
      .navigationTitle("Log details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
    }
    .fullScreenCover(isPresented: $showingFullScreenReceipt) {
      if let image = receiptImage {
        NativeReceiptFullScreenView(image: image)
      }
    }
  }

  @ViewBuilder
  private var detailRows: some View {
    switch record.kind {
    case .income:
      recordDetailRow("Platform", value: record.platform ?? "Earnings", symbol: "app.badge")
      recordDetailRow("Amount", value: gbp(record.amount ?? 0), symbol: "sterlingsign.circle")
    case .expense:
      recordDetailRow("Category", value: record.category ?? "Expense", symbol: "tag")
      if let merchant = record.merchant, !merchant.isEmpty {
        recordDetailRow("Merchant", value: merchant, symbol: "building.2")
      }
      if let note = record.note, !note.isEmpty {
        recordDetailRow("Note", value: note, symbol: "note.text")
      }
      recordDetailRow("Amount", value: gbp(record.amount ?? 0), symbol: "receipt")
    case .mileage:
      recordDetailRow("Vehicle", value: record.vehicle?.label ?? "Vehicle", symbol: record.vehicle?.symbol ?? "car.fill")
      recordDetailRow("Miles", value: miles(record.miles ?? 0), symbol: "road.lanes")
      recordDetailRow("Deduction", value: gbp(record.deduction ?? 0, whole: true), symbol: "sterlingsign.circle")
    }
  }

  private var title: String {
    switch record.kind {
    case .income: return record.platform ?? "Earnings"
    case .expense: return record.category ?? "Expense"
    case .mileage: return "Mileage"
    }
  }

  private var subtitle: String {
    switch record.kind {
    case .income: return "Earnings"
    case .expense:
      if let merchant = record.merchant, !merchant.isEmpty {
        return merchant
      }
      return "Expense"
    case .mileage:
      return record.vehicle?.label ?? "Vehicle"
    }
  }

  private var primaryValue: String {
    switch record.kind {
    case .income, .expense:
      return gbp(record.amount ?? 0)
    case .mileage:
      return miles(record.miles ?? 0)
    }
  }

  private var tint: Color {
    switch record.kind {
    case .income: return .green
    case .expense: return OkkleColor.amber
    case .mileage: return OkkleColor.brand
    }
  }

  private var receiptImage: UIImage? {
    guard let data = record.receiptImageData else { return nil }
    return UIImage(data: data)
  }

  private func recordDetailRow(_ title: String, value: String, symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 34, height: 34)
        .background(tint.opacity(0.13), in: Circle())
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      Spacer()
      Text(value)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
        .multilineTextAlignment(.trailing)
    }
  }
}

struct NativeReceiptFullScreenView: View {
  let image: UIImage
  @Environment(\.dismiss) private var dismiss
  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black
          .ignoresSafeArea()

        ScrollView([.horizontal, .vertical], showsIndicators: false) {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .frame(
              width: UIScreen.main.bounds.width,
              height: UIScreen.main.bounds.height * 0.82
            )
            .padding(.vertical, 32)
            .gesture(
              MagnificationGesture()
                .onChanged { value in
                  scale = min(4, max(1, lastScale * value))
                }
                .onEnded { _ in
                  lastScale = scale
                }
            )
            .onTapGesture(count: 2) {
              withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                scale = scale > 1 ? 1 : 2
                lastScale = scale
              }
            }
        }
      }
      .navigationTitle("Receipt")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .fontWeight(.bold)
          .foregroundStyle(.white)
        }
      }
    }
  }
}

struct NativeDetailActionButtons: View {
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onEdit) {
        Label("Edit", systemImage: "pencil")
          .font(.system(size: 16, weight: .bold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white)
      .background(OkkleColor.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

      Button(role: .destructive, action: onDelete) {
        Label("Delete", systemImage: "trash")
          .font(.system(size: 16, weight: .bold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white)
      .background(OkkleColor.red, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .padding(.top, 2)
  }
}

struct NativeRecordEditSheet: View {
  let record: NativeRecord
  let onSave: (NativeRecord) -> Void
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: OkkleStore
  @State private var amountText: String
  @State private var milesText: String
  @State private var platform: String
  @State private var vehicle: NativeVehicle
  @State private var category: String
  @State private var merchant: String
  @State private var note: String
  @State private var date: Date
  @State private var period: NativePayPeriod

  init(record: NativeRecord, onSave: @escaping (NativeRecord) -> Void) {
    self.record = record
    self.onSave = onSave
    _amountText = State(initialValue: record.amount.map { String(format: "%.2f", $0) } ?? "")
    _milesText = State(initialValue: record.miles.map { String(format: "%.1f", $0) } ?? "")
    _platform = State(initialValue: record.platform ?? "Uber Eats")
    _vehicle = State(initialValue: record.vehicle ?? .car)
    _category = State(initialValue: record.category ?? "")
    _merchant = State(initialValue: record.merchant ?? "")
    _note = State(initialValue: record.note ?? "")
    _date = State(initialValue: record.date)
    _period = State(initialValue: record.period)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(record.kind.label) {
          switch record.kind {
          case .income:
            NativeNumberDoneTextField(text: $amountText, placeholder: "Amount")
              .frame(height: 34)
            NativeFreeTextDropdown(
              title: "Platform",
              placeholder: "Choose or type a delivery service",
              options: platformOptions,
              text: $platform
            )
          case .expense:
            NativeNumberDoneTextField(text: $amountText, placeholder: "Amount")
              .frame(height: 34)
            NativeFreeTextDropdown(
              title: "Category",
              placeholder: "Choose or type a category",
              options: categoryOptions,
              text: $category
            )
            TextField("Merchant", text: $merchant)
              .textInputAutocapitalization(.words)
            TextField("Note for accountant", text: $note, axis: .vertical)
              .lineLimit(2...4)
          case .mileage:
            NativeNumberDoneTextField(text: $milesText, placeholder: "Miles")
              .frame(height: 34)
            Picker("Vehicle", selection: $vehicle) {
              ForEach(NativeVehicle.allCases) { item in
                Label(item.label, systemImage: item.symbol).tag(item)
              }
            }
          }
        }

        Section("Date") {
          DatePicker("Date", selection: $date, displayedComponents: .date)
          Picker("Period", selection: $period) {
            ForEach(NativePayPeriod.allCases) { item in
              Text(item.label).tag(item)
            }
          }
        }

        if record.kind == .mileage {
          Section("Preview") {
            HStack {
              Text("Deduction")
              Spacer()
              Text(gbp(previewDeduction, whole: true))
                .fontWeight(.bold)
            }
          }
        }

        if let receiptImage {
          Section("Receipt") {
            Image(uiImage: receiptImage)
              .resizable()
              .scaledToFill()
              .frame(height: 170)
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          }
        }
      }
      .navigationTitle("Edit log")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") {
            save()
          }
          .fontWeight(.bold)
          .disabled(!canSave)
        }
      }
      .nativeKeyboardDoneToolbar()
    }
  }

  private var platformOptions: [String] {
    let recent = store.records
      .filter { $0.kind == .income }
      .compactMap { $0.platform }
    return uniqueStrings(store.settings.platforms + nativeAllKnownPlatforms + recent + [platform])
  }

  private var categoryOptions: [String] {
    let recent = store.records
      .filter { $0.kind == .expense }
      .compactMap { $0.category }
    return uniqueStrings([category] + recent + nativeExpenseCategories)
  }

  private var amountValue: Double {
    Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
  }

  private var milesValue: Double {
    Double(milesText.replacingOccurrences(of: ",", with: ".")) ?? 0
  }

  private var previewDeduction: Double {
    store.calcDeduction(miles: milesValue, vehicle: vehicle, date: date)
  }

  private var canSave: Bool {
    switch record.kind {
    case .income:
      return amountValue > 0 && !platform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .expense:
      return amountValue > 0
        && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .mileage:
      return milesValue > 0
    }
  }

  private var receiptImage: UIImage? {
    guard let data = record.receiptImageData else { return nil }
    return UIImage(data: data)
  }

  private func save() {
    guard canSave else { return }
    var updated = record
    let bounds = store.periodBounds(for: date, period: period)
    updated.date = date
    updated.period = period
    updated.periodStart = bounds.start
    updated.periodEnd = bounds.end

    switch record.kind {
    case .income:
      let cleanPlatform = platform.trimmingCharacters(in: .whitespacesAndNewlines)
      updated.platform = cleanPlatform
      updated.amount = amountValue
      store.settings.platforms = uniqueStrings(store.settings.platforms + [cleanPlatform])
    case .expense:
      let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
      let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
      let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
      updated.amount = amountValue
      updated.category = cleanCategory.isEmpty ? nil : cleanCategory
      updated.merchant = cleanMerchant.isEmpty ? nil : cleanMerchant
      updated.note = cleanNote
    case .mileage:
      updated.vehicle = vehicle
      updated.miles = milesValue
      updated.deduction = previewDeduction
    }

    onSave(updated)
    dismiss()
  }
}

struct NativeTripEditSheet: View {
  let trip: NativeTrip
  let onSave: (NativeTrip) -> Void
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared
  @State private var vehicle: NativeVehicle
  @State private var milesText: String
  @State private var startedAt: Date
  @State private var endedAt: Date
  @State private var routePoints: [RoutePoint]
  @State private var routeEndpointNames: [Int: String] = [:]
  @State private var feedback: NativeTripFeedback?

  init(trip: NativeTrip, onSave: @escaping (NativeTrip) -> Void) {
    self.trip = trip
    self.onSave = onSave
    _vehicle = State(initialValue: trip.vehicle)
    _milesText = State(initialValue: String(format: "%.1f", trip.miles))
    _startedAt = State(initialValue: trip.startedAt)
    _endedAt = State(initialValue: trip.endedAt)
    _routePoints = State(initialValue: trip.points)
    _feedback = State(initialValue: trip.feedback)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Trip") {
          Picker("Vehicle", selection: $vehicle) {
            ForEach(NativeVehicle.allCases) { item in
              Label(item.label, systemImage: item.symbol).tag(item)
            }
          }

          NativeNumberDoneTextField(text: $milesText, placeholder: "Miles")
            .frame(height: 34)
        }

        Section("Time") {
          DatePicker("Started", selection: $startedAt)
          DatePicker("Ended", selection: $endedAt)
        }

        Section {
          NativeTripEditFeedbackPicker(feedback: $feedback)
        } header: {
          Text("Trip feedback")
        } footer: {
          Text("This updates the Good/Bad signal used by Insights recommendations.")
        }

        if !routeSegments.isEmpty {
          Section("Route") {
            NativeRouteMapView(points: routePoints, stops: routeStops, showsEndMarker: true)
              .frame(height: 180)
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            ForEach(routeSegments) { segment in
              HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(routeSegmentTitle(segment))
                    .font(.subheadline.weight(.semibold))
                  Text(routeSegmentSubtitle(segment))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button(role: .destructive) {
                  removeRouteSegment(segment)
                } label: {
                  Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!canRemoveRouteSegment(segment))
              }
            }
          }
        }

        Section("Preview") {
          HStack {
            Text("Deduction")
            Spacer()
            Text(gbp(previewDeduction, whole: true))
              .fontWeight(.bold)
          }
          Text("Removing route segments updates the saved route, mileage and mileage deduction.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Edit trip")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") {
            save()
          }
          .fontWeight(.bold)
          .disabled(!canSave)
        }
      }
      .nativeKeyboardDoneToolbar()
    }
    .task(id: routeNameSignature) {
      await resolveRouteEndpointNames()
    }
  }

  private var milesValue: Double {
    Double(milesText.replacingOccurrences(of: ",", with: ".")) ?? 0
  }

  private var canSave: Bool {
    milesValue > 0 && endedAt >= startedAt
  }

  private var previewDeduction: Double {
    store.calcDeduction(miles: milesValue, vehicle: vehicle, date: startedAt)
  }

  private var routeVisits: [NativeVisit] {
    NativeRouteStopDetector.routeStops(
      in: routePoints,
      startedAt: startedAt,
      endedAt: endedAt,
      recordedVisits: autoTrack.visits
    )
  }

  private var numberedRouteStops: [(number: Int, visit: NativeVisit)] {
    routeVisits.enumerated().map { (number: $0.offset + 1, visit: $0.element) }
  }

  private var routeStops: [NativeRouteMapStop] {
    numberedRouteStops.map { stop in
      NativeRouteMapStop(
        id: stop.visit.id,
        coordinate: stop.visit.coordinate,
        title: "\(stop.number). \(editStopTitle(for: stop.visit))",
        subtitle: editStopSubtitle(for: stop.visit),
        kind: editRouteStopKind(for: stop.visit),
        glyphText: "\(stop.number)",
        isPersonal: stop.visit.isPersonal
      )
    }
  }

  private var routeSegments: [NativeTripRouteEditSegment] {
    NativeTripRouteEditSegment.build(points: routePoints, visits: routeVisits)
  }

  private var routeNameSignature: String {
    routeSegments
      .flatMap { [$0.startIndex, $0.endIndex] }
      .map(String.init)
      .joined(separator: "-")
  }

  private func save() {
    guard canSave else { return }
    var updated = trip
    updated.vehicle = vehicle
    updated.miles = milesValue
    updated.startedAt = startedAt
    updated.endedAt = endedAt
    updated.deduction = previewDeduction
    updated.points = routePoints
    updated.feedback = feedback
    onSave(updated)
    dismiss()
  }

  private func routeSegmentTitle(_ segment: NativeTripRouteEditSegment) -> String {
    let start = routeEndpointNames[segment.startIndex] ?? routeFallbackName(for: segment.startIndex, segment: segment)
    let end = routeEndpointNames[segment.endIndex] ?? routeFallbackName(for: segment.endIndex, segment: segment)
    return "\(start) to \(end)"
  }

  private func routeSegmentSubtitle(_ segment: NativeTripRouteEditSegment) -> String {
    miles(segment.miles)
  }

  private func routeFallbackName(for index: Int, segment: NativeTripRouteEditSegment) -> String {
    if index == routePoints.indices.first { return "Start" }
    if index == routePoints.indices.last { return "End" }
    if let stopNumber = nearestStopNumber(to: index) { return "Stop \(stopNumber)" }
    return "Point \(index + 1)"
  }

  private func nearestStopNumber(to routePointIndex: Int) -> Int? {
    guard routePoints.indices.contains(routePointIndex) else { return nil }
    let routePoint = routePoints[routePointIndex]
    let routeLocation = CLLocation(latitude: routePoint.latitude, longitude: routePoint.longitude)
    return numberedRouteStops.first { stop in
      routeLocation.distance(from: stop.visit.location) <= 140
    }?.number
  }

  private func editStopTitle(for visit: NativeVisit) -> String {
    "Stop"
  }

  private func editStopSubtitle(for visit: NativeVisit) -> String {
    let place = visit.placeName ?? "Detected from movement"
    let dwellMinutes = max(1, Int((visit.dwell / 60).rounded()))
    return "\(place) • \(dwellMinutes)m"
  }

  private func editRouteStopKind(for visit: NativeVisit) -> NativeRouteMapStop.Kind {
    .other
  }

  private func canRemoveRouteSegment(_ segment: NativeTripRouteEditSegment) -> Bool {
    routePoints.count - segment.pointCount >= 2
  }

  private func removeRouteSegment(_ segment: NativeTripRouteEditSegment) {
    guard canRemoveRouteSegment(segment),
          routePoints.indices.contains(segment.startIndex),
          routePoints.indices.contains(segment.endIndex),
          segment.startIndex <= segment.endIndex else {
      return
    }

    routePoints.removeSubrange(segment.startIndex...segment.endIndex)
    if routePoints.indices.contains(segment.startIndex) {
      routePoints[segment.startIndex].breakBefore = true
    }
    if !routePoints.isEmpty {
      routePoints[0].breakBefore = false
    }
    routeEndpointNames = [:]

    let recalculatedMiles = routeMiles(from: routePoints)
    if recalculatedMiles > 0 {
      milesText = String(format: "%.1f", recalculatedMiles)
    }
  }

  @MainActor
  private func resolveRouteEndpointNames() async {
    let indexes = Array(Set(routeSegments.flatMap { [$0.startIndex, $0.endIndex] })).sorted()
    for index in indexes where routeEndpointNames[index] == nil && routePoints.indices.contains(index) {
      if let name = await Self.placeName(for: routePoints[index].coordinate) {
        routeEndpointNames[index] = name
      }
    }
  }

  private func routeMiles(from points: [RoutePoint]) -> Double {
    guard points.count > 1 else { return 0 }
    var meters: CLLocationDistance = 0
    for index in points.indices.dropFirst() where !points[index].breakBefore {
      let previous = CLLocation(latitude: points[index - 1].latitude, longitude: points[index - 1].longitude)
      let current = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
      meters += current.distance(from: previous)
    }
    return meters / 1_609.344
  }

  private static func placeName(for coordinate: CLLocationCoordinate2D) async -> String? {
    await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
      CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
        guard let placemark = placemarks?.first else {
          continuation.resume(returning: nil)
          return
        }
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
          .compactMap { $0 }
          .joined(separator: " ")
        let area = placemark.subLocality ?? placemark.locality
        let name = [street.isEmpty ? nil : street, area]
          .compactMap { $0 }
          .filter { !$0.isEmpty }
          .joined(separator: ", ")
        continuation.resume(returning: name.isEmpty ? nil : name)
      }
    }
  }
}

private struct NativeTripRouteEditSegment: Identifiable {
  let number: Int
  let startIndex: Int
  let endIndex: Int
  let miles: Double

  var id: String { "\(number)-\(startIndex)-\(endIndex)" }
  var pointCount: Int { endIndex - startIndex + 1 }

  static func build(points: [RoutePoint], visits: [NativeVisit]) -> [NativeTripRouteEditSegment] {
    guard points.count > 1 else { return [] }

    var segments: [NativeTripRouteEditSegment] = []
    var runStart = 0

    while runStart < points.count {
      var runEnd = runStart
      while runEnd + 1 < points.count && !points[runEnd + 1].breakBefore {
        runEnd += 1
      }

      if runEnd > runStart {
        let indexes = boundaryIndexes(points: points, runStart: runStart, runEnd: runEnd, visits: visits)
        for pair in zip(indexes, indexes.dropFirst()) where pair.0 < pair.1 {
          segments.append(NativeTripRouteEditSegment(
            number: segments.count + 1,
            startIndex: pair.0,
            endIndex: pair.1,
            miles: miles(points: Array(points[pair.0...pair.1]))
          ))
        }
      }

      runStart = runEnd + 1
    }

    return segments
  }

  private static func boundaryIndexes(
    points: [RoutePoint],
    runStart: Int,
    runEnd: Int,
    visits: [NativeVisit]
  ) -> [Int] {
    var indexes = Set([runStart, runEnd])
    let run = Array(points[runStart...runEnd])

    for visit in visits {
      let nearest = nearestIndex(to: visit, in: run, offset: runStart)
      if nearest > runStart && nearest < runEnd {
        indexes.insert(nearest)
      }
    }

    for stop in NativeRouteStopDetector.detectStops(in: points, runStart: runStart, runEnd: runEnd) {
      if stop.boundaryIndex > runStart && stop.boundaryIndex < runEnd {
        indexes.insert(stop.boundaryIndex)
      }
    }

    return indexes.sorted()
  }

  private static func nearestIndex(to visit: NativeVisit, in points: [RoutePoint], offset: Int) -> Int {
    if points.contains(where: { $0.timestamp != nil }) {
      let target = visit.arrival.timeIntervalSinceReferenceDate
      let localIndex = points.indices.min { lhs, rhs in
        abs((points[lhs].timestamp?.timeIntervalSinceReferenceDate ?? target) - target) <
          abs((points[rhs].timestamp?.timeIntervalSinceReferenceDate ?? target) - target)
      } ?? points.startIndex
      return offset + localIndex
    }

    let location = visit.location
    let localIndex = points.indices.min { lhs, rhs in
      let lhsLocation = CLLocation(latitude: points[lhs].latitude, longitude: points[lhs].longitude)
      let rhsLocation = CLLocation(latitude: points[rhs].latitude, longitude: points[rhs].longitude)
      return lhsLocation.distance(from: location) < rhsLocation.distance(from: location)
    } ?? points.startIndex
    return offset + localIndex
  }

  private static func miles(points: [RoutePoint]) -> Double {
    guard points.count > 1 else { return 0 }
    var meters: CLLocationDistance = 0
    for index in points.indices.dropFirst() {
      let previous = CLLocation(latitude: points[index - 1].latitude, longitude: points[index - 1].longitude)
      let current = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
      meters += current.distance(from: previous)
    }
    return meters / 1_609.344
  }
}

struct NativeRouteMapStop: Identifiable {
  enum Kind {
    case pickup
    case dropoff
    case other
  }

  let id: UUID
  let coordinate: CLLocationCoordinate2D
  let title: String
  let subtitle: String?
  let kind: Kind
  let glyphText: String?
  var isPersonal: Bool = false
}

private extension MKCoordinateRegion {
  var toMapRect: MKMapRect {
    let halfLat = span.latitudeDelta / 2
    let halfLon = span.longitudeDelta / 2
    let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: center.latitude + halfLat, longitude: center.longitude - halfLon))
    let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: center.latitude - halfLat, longitude: center.longitude + halfLon))
    return MKMapRect(
      x: min(topLeft.x, bottomRight.x),
      y: min(topLeft.y, bottomRight.y),
      width: abs(topLeft.x - bottomRight.x),
      height: abs(topLeft.y - bottomRight.y)
    )
  }
}

struct NativeRouteMapView: UIViewRepresentable {
  let points: [RoutePoint]
  var stops: [NativeRouteMapStop] = []
  var showsEndMarker = true
  var isInteractive = false
  // When false (the live-tracking map), interaction is limited to
  // pinch/double-tap zoom — no drag-to-pan or rotate/tilt, since the map
  // auto-follows the current position and free panning would fight that.
  // Review/full-screen maps leave this true for unrestricted exploration.
  var allowsPanning = true
  var selectedStopID: Binding<UUID?>
  // Extra bottom padding for callers with an overlaid bottom panel (the
  // live-tracking screen) — without it, the auto-fit region centres on the
  // full view including the area a bottom sheet actually covers, so the
  // current/start position can end up rendered right at or under the
  // panel's top edge.
  var bottomInset: CGFloat = 0

  init(
    points: [RoutePoint],
    stops: [NativeRouteMapStop] = [],
    showsEndMarker: Bool = true,
    isInteractive: Bool = false,
    allowsPanning: Bool = true,
    selectedStopID: Binding<UUID?> = .constant(nil),
    bottomInset: CGFloat = 0
  ) {
    self.points = points
    self.stops = stops
    self.showsEndMarker = showsEndMarker
    self.isInteractive = isInteractive
    self.allowsPanning = allowsPanning
    self.selectedStopID = selectedStopID
    self.bottomInset = bottomInset
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator
    mapView.isUserInteractionEnabled = isInteractive
    mapView.isScrollEnabled = isInteractive && allowsPanning
    mapView.isZoomEnabled = isInteractive
    mapView.isRotateEnabled = isInteractive && allowsPanning
    mapView.isPitchEnabled = isInteractive && allowsPanning
    mapView.pointOfInterestFilter = .excludingAll
    mapView.showsCompass = false
    mapView.showsScale = isInteractive
    return mapView
  }

  func updateUIView(_ mapView: MKMapView, context: Context) {
    context.coordinator.parent = self
    mapView.isUserInteractionEnabled = isInteractive
    mapView.isScrollEnabled = isInteractive && allowsPanning
    mapView.isZoomEnabled = isInteractive
    mapView.isRotateEnabled = isInteractive && allowsPanning
    mapView.isPitchEnabled = isInteractive && allowsPanning
    mapView.showsScale = isInteractive

    let coordinates = points.map(\.coordinate)
    guard let first = coordinates.first else {
      mapView.setRegion(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
        span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
      ), animated: false)
      context.coordinator.hasSetInitialRegion = true
      return
    }

    let signature = dataSignature(coordinates: coordinates)
    let shouldRebuildMap = context.coordinator.dataSignature != signature
    if shouldRebuildMap {
      context.coordinator.dataSignature = signature
      context.coordinator.hasSetInitialRegion = false
      mapView.removeOverlays(mapView.overlays)
      mapView.removeAnnotations(mapView.annotations)

      mapView.addAnnotation(NativeRouteMapAnnotation(
        coordinate: first,
        title: "Start",
        subtitle: nil,
        kind: .start,
        glyphText: nil,
        stopID: nil
      ))

      stops.forEach { stop in
        mapView.addAnnotation(NativeRouteMapAnnotation(
          coordinate: stop.coordinate,
          title: stop.title,
          subtitle: stop.subtitle,
          kind: NativeRouteMapAnnotation.Kind(stop.kind),
          glyphText: stop.glyphText,
          stopID: stop.id,
          isPersonal: stop.isPersonal
        ))
      }

      if let last = coordinates.last, coordinates.count > 1, showsEndMarker {
        mapView.addAnnotation(NativeRouteMapAnnotation(
          coordinate: last,
          title: "End",
          subtitle: nil,
          kind: .end,
          glyphText: nil,
          stopID: nil
        ))
      }

      routeCoordinateRuns(from: points).forEach { run in
        guard run.count > 1 else { return }
        let polyline = MKPolyline(coordinates: run, count: run.count)
        mapView.addOverlay(polyline)
      }

      routeGapCoordinatePairs(from: points).forEach { pair in
        let gap = MKGeodesicPolyline(coordinates: pair, count: pair.count)
        mapView.addOverlay(gap)
      }
    }

    if let selectedStopID = selectedStopID.wrappedValue,
       let stop = stops.first(where: { $0.id == selectedStopID }) {
      let selectedChanged = context.coordinator.selectedStopID != selectedStopID
      context.coordinator.selectedStopID = selectedStopID
      focus(mapView, on: stop, animated: selectedChanged)
    } else if shouldRebuildMap || !context.coordinator.hasSetInitialRegion {
      // Always goes through setVisibleMapRect, even for a single point —
      // unlike setRegion, it honours edgePadding, which is what keeps a
      // fresh "just started" trip's Start pin from landing under a bottom
      // panel (see bottomInset). visibleMapRect pads a lone/tight cluster
      // out to a sane minimum span itself, rather than zooming to MapKit's
      // maximum for a near-zero-size rect.
      context.coordinator.selectedStopID = nil
      mapView.setVisibleMapRect(
        visibleMapRect(routeCoordinates: coordinates, stopCoordinates: stops.map(\.coordinate)),
        edgePadding: UIEdgeInsets(top: 38, left: 30, bottom: 38 + bottomInset, right: 30),
        animated: false
      )
      context.coordinator.hasSetInitialRegion = true
    }
  }

  private func dataSignature(coordinates: [CLLocationCoordinate2D]) -> String {
    let first = coordinates.first.map { "\($0.latitude),\($0.longitude)" } ?? "none"
    let last = coordinates.last.map { "\($0.latitude),\($0.longitude)" } ?? "none"
    // Includes isPersonal so swiping a stop's category while this same map
    // is on screen rebuilds the pin colour immediately, instead of only
    // picking it up the next time the screen appears.
    let stopIDs = stops.map { "\($0.id.uuidString):\($0.isPersonal)" }.joined(separator: ",")
    let breakIndices = points.enumerated().compactMap { $0.element.breakBefore ? String($0.offset) : nil }.joined(separator: ",")
    return "\(coordinates.count)|\(first)|\(last)|\(breakIndices)|\(showsEndMarker)|\(stopIDs)"
  }

  private func focus(_ mapView: MKMapView, on stop: NativeRouteMapStop, animated: Bool) {
    mapView.setRegion(
      MKCoordinateRegion(
        center: stop.coordinate,
        latitudinalMeters: 650,
        longitudinalMeters: 650
      ),
      animated: animated
    )
    if let annotation = mapView.annotations.compactMap({ $0 as? NativeRouteMapAnnotation }).first(where: { $0.stopID == stop.id }) {
      mapView.selectAnnotation(annotation, animated: animated)
    }
  }

  private func visibleMapRect(routeCoordinates: [CLLocationCoordinate2D], stopCoordinates: [CLLocationCoordinate2D]) -> MKMapRect {
    let coordinates = routeCoordinates + stopCoordinates
    var rect = coordinates.reduce(MKMapRect.null) { rect, coordinate in
      let point = MKMapPoint(coordinate)
      let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
      return rect.union(pointRect)
    }
    // A single point (or a tight cluster right at a trip's start) unions
    // down to a near-zero-size rect, which setVisibleMapRect would zoom to
    // MapKit's maximum for — pad it out to a sane minimum span so a
    // fresh trip shows real surrounding streets, not a featureless close-up.
    if let anchor = coordinates.first {
      let minimumRegion = MKCoordinateRegion(center: anchor, latitudinalMeters: 1800, longitudinalMeters: 1800)
      rect = rect.union(minimumRegion.toMapRect)
    }
    return rect
  }

  private func routeCoordinateRuns(from points: [RoutePoint]) -> [[CLLocationCoordinate2D]] {
    points.reduce(into: [[CLLocationCoordinate2D]]()) { runs, point in
      if runs.isEmpty || point.breakBefore {
        runs.append([point.coordinate])
      } else {
        runs[runs.count - 1].append(point.coordinate)
      }
    }
  }

  private func routeGapCoordinatePairs(from points: [RoutePoint]) -> [[CLLocationCoordinate2D]] {
    guard points.count > 1 else { return [] }
    return points.indices.dropFirst().compactMap { index in
      guard points[index].breakBefore else { return nil }
      return [points[index - 1].coordinate, points[index].coordinate]
    }
  }

  final class Coordinator: NSObject, MKMapViewDelegate {
    var parent: NativeRouteMapView
    var dataSignature: String?
    var selectedStopID: UUID?
    var hasSetInitialRegion = false

    init(_ parent: NativeRouteMapView) {
      self.parent = parent
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      guard let polyline = overlay as? MKPolyline else {
        return MKOverlayRenderer(overlay: overlay)
      }
      let renderer = MKPolylineRenderer(polyline: polyline)
      renderer.strokeColor = UIColor(red: 0.03, green: 0.58, blue: 0.49, alpha: 1)
      if overlay is MKGeodesicPolyline {
        renderer.strokeColor = renderer.strokeColor?.withAlphaComponent(0.55)
        renderer.lineDashPattern = [4, 8]
        renderer.lineWidth = 4
      } else {
        renderer.lineWidth = 5
      }
      renderer.lineCap = .round
      renderer.lineJoin = .round
      return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
      guard let annotation = annotation as? NativeRouteMapAnnotation else { return nil }
      let identifier = "NativeRouteMapAnnotation"
      let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
        ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
      view.annotation = annotation
      view.canShowCallout = true
      view.markerTintColor = annotation.markerTintColor
      view.glyphTintColor = .white
      view.glyphText = annotation.glyphText
      view.glyphImage = annotation.glyphImage
      view.displayPriority = annotation.displayPriority
      return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
      guard let annotation = view.annotation as? NativeRouteMapAnnotation,
            let stopID = annotation.stopID else { return }
      parent.selectedStopID.wrappedValue = stopID
    }
  }
}

private final class NativeRouteMapAnnotation: NSObject, MKAnnotation {
  enum Kind {
    case start
    case end
    case pickup
    case dropoff
    case other

    init(_ stopKind: NativeRouteMapStop.Kind) {
      switch stopKind {
      case .pickup:
        self = .pickup
      case .dropoff:
        self = .dropoff
      case .other:
        self = .other
      }
    }
  }

  let coordinate: CLLocationCoordinate2D
  let title: String?
  let subtitle: String?
  let kind: Kind
  let glyphText: String?
  let stopID: UUID?
  let isPersonal: Bool

  init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?, kind: Kind, glyphText: String?, stopID: UUID?, isPersonal: Bool = false) {
    self.coordinate = coordinate
    self.title = title
    self.subtitle = subtitle
    self.kind = kind
    self.glyphText = glyphText
    self.stopID = stopID
    self.isPersonal = isPersonal
  }

  // Same business/personal convention as the stop list and the Data tab's
  // trip rows (orange for business, gray for personal) — a stop is either
  // one or the other, so pickup/dropoff no longer gets its own colour here.
  var markerTintColor: UIColor {
    switch kind {
    case .start:
      return UIColor(red: 0.03, green: 0.58, blue: 0.49, alpha: 1)
    case .end:
      return UIColor.systemRed
    case .pickup, .dropoff, .other:
      return isPersonal ? .systemGray : UIColor(red: 0.86, green: 0.50, blue: 0.08, alpha: 1)
    }
  }

  var glyphImage: UIImage? {
    guard glyphText == nil else { return nil }
    switch kind {
    case .start:
      return UIImage(systemName: "play.fill")
    case .end:
      return UIImage(systemName: "stop.fill")
    case .pickup:
      return UIImage(systemName: "bag.fill")
    case .dropoff:
      return UIImage(systemName: "mappin")
    case .other:
      return UIImage(systemName: "circle.fill")
    }
  }

  var displayPriority: MKFeatureDisplayPriority {
    switch kind {
    case .start, .end:
      return .required
    case .pickup, .dropoff, .other:
      return .defaultHigh
    }
  }
}

func nativeDurationLabel(_ seconds: TimeInterval) -> String {
  let total = max(0, Int(seconds))
  let hours = total / 3600
  let minutes = (total % 3600) / 60
  if hours > 0 { return "\(hours)h \(minutes)m" }
  return "\(minutes)m"
}
