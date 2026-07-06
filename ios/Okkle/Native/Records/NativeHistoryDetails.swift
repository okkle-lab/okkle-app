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
  @State private var homeCandidate: NativeTripHomeCandidate?
  @State private var didResolveRoute = false

  var body: some View {
    ZStack {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
              NativeMetricTile(title: "Miles", value: miles(trip.miles), symbol: "road.lanes")
              NativeMetricTile(title: "Deduction", value: gbp(trip.deduction, whole: true), symbol: "sterlingsign.circle.fill", color: .green)
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
    .task(id: trip.id) {
      await resolveRouteDetails()
    }
  }

  private var routeSection: some View {
    NativeGlassCard {
      VStack(alignment: .leading, spacing: 14) {
        Label("Route", systemImage: "map.fill")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(OkkleColor.ink)

        NativeRouteMapView(points: trip.points, stops: routeStops)
          .frame(height: 250)
          .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

        tripDetailRow("Route points", value: "\(trip.points.count)", symbol: "point.3.connected.trianglepath.dotted")

        Divider()

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

          ForEach(numberedStops) { stop in
            routeStopLocationRow(stop)
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
    autoTrack.visits
      .filter { $0.arrival >= trip.startedAt && $0.departure <= trip.endedAt }
      .sorted { $0.arrival < $1.arrival }
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
        glyphText: "\(stop.number)"
      )
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

  private func routeStopLocationRow(_ stop: NativeTripDetailStop) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text("\(stop.number)")
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(stopTint(for: stop.visit), in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(stopTitle(for: stop.visit))
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OkkleColor.ink)
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
    let place = visit.placeName ?? "Detected from movement"
    let dwellMinutes = max(1, Int((visit.dwell / 60).rounded()))
    return "\(place) • \(dwellMinutes)m"
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
    switch visit.kind {
    case .pickup:
      return OkkleColor.brand
    case .dropoff:
      return OkkleColor.blue
    case .other:
      return OkkleColor.amber
    }
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

  @MainActor
  private func resolveRouteDetails() async {
    guard !didResolveRoute else { return }
    didResolveRoute = true
    var startResolved: String?
    var endResolved: String?
    if let startPoint {
      startResolved = await Self.address(for: startPoint.coordinate)
      startAddress = startResolved
    }
    if let endPoint {
      endResolved = await Self.address(for: endPoint.coordinate)
      endAddress = endResolved
    }
    detectHomeCandidate(startAddress: startResolved, endAddress: endResolved)
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

  private func saveHomeCandidate() {
    guard let homeCandidate else { return }
    if !isKnownHome(homeCandidate.point.coordinate) {
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
            NativeFreeTextDropdown(
              title: "Merchant",
              placeholder: "Choose or type a merchant",
              options: merchantOptions,
              text: $merchant
            )
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
    return uniqueStrings(store.settings.platforms + nativeDeliveryServiceOptions + recent + [platform])
  }

  private var categoryOptions: [String] {
    let recent = store.records
      .filter { $0.kind == .expense }
      .compactMap { $0.category }
    return uniqueStrings([category] + recent + nativeExpenseCategories)
  }

  private var merchantOptions: [String] {
    let recent = store.records
      .filter { $0.kind == .expense }
      .compactMap { $0.merchant }
    return uniqueStrings([merchant] + recent)
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
      return amountValue > 0 && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
      updated.amount = amountValue
      updated.category = cleanCategory
      updated.merchant = cleanMerchant.isEmpty ? nil : cleanMerchant
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

  init(trip: NativeTrip, onSave: @escaping (NativeTrip) -> Void) {
    self.trip = trip
    self.onSave = onSave
    _vehicle = State(initialValue: trip.vehicle)
    _milesText = State(initialValue: String(format: "%.1f", trip.miles))
    _startedAt = State(initialValue: trip.startedAt)
    _endedAt = State(initialValue: trip.endedAt)
    _routePoints = State(initialValue: trip.points)
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

        if !routeSegments.isEmpty {
          Section("Route") {
            NativeRouteMapView(points: routePoints, showsEndMarker: true)
              .frame(height: 180)
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
              Label("\(routePoints.count) points", systemImage: "point.3.connected.trianglepath.dotted")
              Spacer()
              Text(miles(routeMiles(from: routePoints)))
                .fontWeight(.bold)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

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
    autoTrack.visits
      .filter { $0.arrival >= startedAt && $0.departure <= endedAt }
      .sorted { $0.arrival < $1.arrival }
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
    onSave(updated)
    dismiss()
  }

  private func routeSegmentTitle(_ segment: NativeTripRouteEditSegment) -> String {
    let start = routeEndpointNames[segment.startIndex] ?? routeFallbackName(for: segment.startIndex, segment: segment)
    let end = routeEndpointNames[segment.endIndex] ?? routeFallbackName(for: segment.endIndex, segment: segment)
    return "\(start) to \(end)"
  }

  private func routeSegmentSubtitle(_ segment: NativeTripRouteEditSegment) -> String {
    "\(miles(segment.miles)) • \(segment.pointCount) route points"
  }

  private func routeFallbackName(for index: Int, segment: NativeTripRouteEditSegment) -> String {
    if index == routePoints.indices.first { return "Start" }
    if index == routePoints.indices.last { return "End" }
    return "Point \(index + 1)"
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
    await withCheckedContinuation { continuation in
      CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
        guard let placemark = placemarks?.first else {
          continuation.resume(returning: nil)
          return
        }
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
          .compactMap { $0 }
          .joined(separator: " ")
        let area = placemark.subLocality ?? placemark.locality ?? placemark.name
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

    if indexes.count == 2 && run.count > 18 {
      let segmentCount = min(6, max(2, run.count / 14))
      for step in 1..<segmentCount {
        indexes.insert(runStart + ((run.count - 1) * step / segmentCount))
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
}

struct NativeRouteMapView: UIViewRepresentable {
  let points: [RoutePoint]
  var stops: [NativeRouteMapStop] = []
  var showsEndMarker = true
  var isInteractive = false

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator
    mapView.isUserInteractionEnabled = isInteractive
    mapView.pointOfInterestFilter = .excludingAll
    mapView.showsCompass = false
    mapView.showsScale = isInteractive
    return mapView
  }

  func updateUIView(_ mapView: MKMapView, context: Context) {
    mapView.isUserInteractionEnabled = isInteractive
    mapView.showsScale = isInteractive
    mapView.removeOverlays(mapView.overlays)
    mapView.removeAnnotations(mapView.annotations)

    let coordinates = points.map(\.coordinate)
    guard let first = coordinates.first else {
      mapView.setRegion(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
        span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
      ), animated: false)
      return
    }

    mapView.addAnnotation(NativeRouteMapAnnotation(
      coordinate: first,
      title: "Start",
      subtitle: nil,
      kind: .start,
      glyphText: nil
    ))

    stops.forEach { stop in
      mapView.addAnnotation(NativeRouteMapAnnotation(
        coordinate: stop.coordinate,
        title: stop.title,
        subtitle: stop.subtitle,
        kind: NativeRouteMapAnnotation.Kind(stop.kind),
        glyphText: stop.glyphText
      ))
    }

    if let last = coordinates.last, coordinates.count > 1 {
      if showsEndMarker {
        mapView.addAnnotation(NativeRouteMapAnnotation(
          coordinate: last,
          title: "End",
          subtitle: nil,
          kind: .end,
          glyphText: nil
        ))
      }

      routeCoordinateRuns(from: points).forEach { run in
        guard run.count > 1 else { return }
        let polyline = MKPolyline(coordinates: run, count: run.count)
        mapView.addOverlay(polyline)
      }
      mapView.setVisibleMapRect(
        visibleMapRect(routeCoordinates: coordinates, stopCoordinates: stops.map(\.coordinate)),
        edgePadding: UIEdgeInsets(top: 38, left: 30, bottom: 38, right: 30),
        animated: false
      )
    } else {
      mapView.setRegion(MKCoordinateRegion(center: first, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)), animated: false)
    }
  }

  private func visibleMapRect(routeCoordinates: [CLLocationCoordinate2D], stopCoordinates: [CLLocationCoordinate2D]) -> MKMapRect {
    let coordinates = routeCoordinates + stopCoordinates
    return coordinates.reduce(MKMapRect.null) { rect, coordinate in
      let point = MKMapPoint(coordinate)
      let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
      return rect.union(pointRect)
    }
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

  final class Coordinator: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      guard let polyline = overlay as? MKPolyline else {
        return MKOverlayRenderer(overlay: overlay)
      }
      let renderer = MKPolylineRenderer(polyline: polyline)
      renderer.strokeColor = UIColor(red: 0.03, green: 0.58, blue: 0.49, alpha: 1)
      renderer.lineWidth = 5
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

  init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?, kind: Kind, glyphText: String?) {
    self.coordinate = coordinate
    self.title = title
    self.subtitle = subtitle
    self.kind = kind
    self.glyphText = glyphText
  }

  var markerTintColor: UIColor {
    switch kind {
    case .start:
      return UIColor(red: 0.03, green: 0.58, blue: 0.49, alpha: 1)
    case .end:
      return UIColor.systemRed
    case .pickup:
      return UIColor.systemIndigo
    case .dropoff:
      return UIColor.systemOrange
    case .other:
      return UIColor.systemGray
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
