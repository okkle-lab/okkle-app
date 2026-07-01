import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
enum NativeTimeFilter: String, CaseIterable, Identifiable {
  case all
  case morning
  case lunch
  case afternoon
  case dinner
  case late

  var id: String { rawValue }

  var label: String {
    switch self {
    case .all: return "All day"
    case .morning: return "Morning"
    case .lunch: return "Lunch"
    case .afternoon: return "Afternoon"
    case .dinner: return "Dinner"
    case .late: return "Late"
    }
  }

  func includes(_ date: Date) -> Bool {
    if self == .all { return true }
    let hour = Calendar.current.component(.hour, from: date)
    switch self {
    case .all:
      return true
    case .morning:
      return hour >= 6 && hour < 11
    case .lunch:
      return hour >= 11 && hour < 14
    case .afternoon:
      return hour >= 14 && hour < 17
    case .dinner:
      return hour >= 17 && hour < 21
    case .late:
      return hour >= 21 || hour < 6
    }
  }
}

struct NativeHeatSummary {
  let tripCount: Int
  let miles: Double
  let deduction: Double

  var hasData: Bool {
    tripCount > 0
  }
}

func nativeHeatTrips(from trips: [NativeTrip], filter: NativeTimeFilter) -> [NativeTrip] {
  trips.filter { trip in
    filter.includes(trip.startedAt) && trip.points.count > 1
  }
}

func nativeHeatSummary(from trips: [NativeTrip], filter: NativeTimeFilter) -> NativeHeatSummary {
  let filteredTrips = nativeHeatTrips(from: trips, filter: filter)
  return NativeHeatSummary(
    tripCount: filteredTrips.count,
    miles: filteredTrips.reduce(0) { $0 + $1.miles },
    deduction: filteredTrips.reduce(0) { $0 + $1.deduction }
  )
}

func nativeStrongestHeatFilter(from trips: [NativeTrip]) -> NativeTimeFilter? {
  NativeTimeFilter.allCases
    .filter { $0 != .all }
    .map { filter in
      (filter: filter, summary: nativeHeatSummary(from: trips, filter: filter))
    }
    .filter { $0.summary.hasData }
    .max {
      if $0.summary.miles == $1.summary.miles {
        return $0.summary.tripCount < $1.summary.tripCount
      }
      return $0.summary.miles < $1.summary.miles
    }?
    .filter
}

struct NativeHeatMapCard: View {
  let trips: [NativeTrip]
  let summary: NativeHeatSummary
  let strongestFilter: NativeTimeFilter?
  let showsFilters: Bool
  @Binding var filter: NativeTimeFilter

  var body: some View {
    NativeAiCard(banner: "HOTSPOT MAP") {
      VStack(alignment: .leading, spacing: 16) {
        Text("See where your work clusters")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Okkle shows the routes you have actually tracked. Repeated routes become stronger, while the map stays readable.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
        if summary.hasData {
          NativeHeatStatsRow(summary: summary)
          if filter == .all, let strongestFilter {
            Label("Most tracked mileage is currently around \(strongestFilter.label.lowercased()).", systemImage: "clock.fill")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(OkkleColor.brandDark)
              .padding(.horizontal, 12)
              .padding(.vertical, 10)
              .background(OkkleColor.brand.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
        }
        if showsFilters {
          NativeHeatFilterBar(selection: $filter)
        }
        NativeHeatRouteMapView(trips: trips)
        NativeHeatLegend()
        Text("Built on-device from your tracked routes.")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

struct NativeHeatStatsRow: View {
  let summary: NativeHeatSummary

  var body: some View {
    HStack(spacing: 10) {
      NativeHeatStatChip(title: "Trips", value: "\(summary.tripCount)", symbol: "location.north.line.fill", color: OkkleColor.brand)
      NativeHeatStatChip(title: "Miles", value: miles(summary.miles), symbol: "road.lanes", color: OkkleColor.blue)
      NativeHeatStatChip(title: "Deduction", value: gbp(summary.deduction, whole: true), symbol: "sterlingsign.circle.fill", color: .green)
    }
  }
}

struct NativeHeatStatChip: View {
  let title: String
  let value: String
  let symbol: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(color)
      Text(value)
        .font(.system(size: 17, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
    .padding(12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

struct NativeHeatFilterBar: View {
  @Binding var selection: NativeTimeFilter

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(NativeTimeFilter.allCases) { filter in
          Button {
            selection = filter
          } label: {
            Text(filter.label)
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(selection == filter ? Color.white : OkkleColor.muted)
              .padding(.horizontal, 14)
              .padding(.vertical, 9)
              .background(selection == filter ? OkkleColor.brand : OkkleColor.fieldBackground, in: Capsule())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

struct NativeHeatMapEmpty: View {
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "map")
        .font(.system(size: 30, weight: .bold))
        .foregroundStyle(OkkleColor.brand)
      Text("Track a few GPS trips and your routes will appear here.")
        .font(.system(size: 15, weight: .semibold))
        .multilineTextAlignment(.center)
        .foregroundStyle(OkkleColor.muted)
        .padding(.horizontal, 18)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 220)
    .background(Color(uiColor: .secondarySystemBackground).opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
  }
}

struct NativeHeatRouteMapView: View {
  let trips: [NativeTrip]

  private var hasEnoughRoutes: Bool {
    trips.contains { $0.points.count > 1 }
  }

  var body: some View {
    Group {
      if hasEnoughRoutes {
        NativeHeatRouteMapRepresentable(trips: trips)
          .frame(height: 240)
          .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      } else {
        NativeHeatMapEmpty()
      }
    }
  }
}

struct NativeHeatRouteMapRepresentable: UIViewRepresentable {
  let trips: [NativeTrip]

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator
    mapView.isUserInteractionEnabled = false
    mapView.showsCompass = false
    mapView.showsScale = true
    mapView.isPitchEnabled = false
    return mapView
  }

  func updateUIView(_ mapView: MKMapView, context: Context) {
    mapView.removeOverlays(mapView.overlays)

    var visibleRect = MKMapRect.null
    for trip in trips {
      let coordinates = trip.points.map(\.coordinate)
      guard coordinates.count > 1 else { continue }
      let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
      mapView.addOverlay(polyline)
      visibleRect = visibleRect.isNull ? polyline.boundingMapRect : visibleRect.union(polyline.boundingMapRect)
    }

    if visibleRect.isNull {
      mapView.setRegion(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
      ), animated: false)
    } else {
      mapView.setVisibleMapRect(
        visibleRect,
        edgePadding: UIEdgeInsets(top: 38, left: 30, bottom: 38, right: 30),
        animated: false
      )
    }
  }

  final class Coordinator: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      guard let polyline = overlay as? MKPolyline else {
        return MKOverlayRenderer(overlay: overlay)
      }
      let renderer = MKPolylineRenderer(polyline: polyline)
      renderer.strokeColor = UIColor(red: 0.03, green: 0.58, blue: 0.49, alpha: 0.42)
      renderer.lineWidth = 5
      renderer.lineCap = .round
      renderer.lineJoin = .round
      return renderer
    }
  }
}

struct NativeHeatLegend: View {
  var body: some View {
    HStack(spacing: 8) {
      Text("Fewer")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      Capsule()
        .fill(
          LinearGradient(
            colors: [OkkleColor.brand.opacity(0.18), OkkleColor.brand.opacity(0.72)],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
      .frame(maxWidth: .infinity)
      .frame(height: 8)
      Text("More")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
  }
}

struct NativeInsightsView: View {
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared
  @State private var heatFilter: NativeTimeFilter = .all
  private var shift: NativeShiftInsights {
    NativeShiftInsights.build(visits: autoTrack.visits, store: store)
  }
  private var selectedHeatTrips: [NativeTrip] {
    nativeHeatTrips(from: store.trips, filter: heatFilter)
  }
  private var selectedHeatSummary: NativeHeatSummary {
    nativeHeatSummary(from: store.trips, filter: heatFilter)
  }
  private var strongestHeatFilter: NativeTimeFilter? {
    nativeStrongestHeatFilter(from: store.trips)
  }
  private var hasAnyHeatTrips: Bool {
    !nativeHeatTrips(from: store.trips, filter: .all).isEmpty
  }

  var body: some View {
    NativeScreen(title: "Insights", subtitle: "AI guidance, smart nudges and patterns from your work.") {
      NativeHeatMapCard(
        trips: selectedHeatTrips,
        summary: selectedHeatSummary,
        strongestFilter: strongestHeatFilter,
        showsFilters: hasAnyHeatTrips,
        filter: $heatFilter
      )

      if store.settings.autoTrackTrips, shift.hasData {
        NativeAiCard(banner: "SHIFT PATTERNS") {
          VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
              Text("Your best window")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OkkleColor.muted)
              Text(shift.bestWindow ?? "Building your pattern")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(OkkleColor.ink)
            }
            HStack(spacing: 10) {
              NativeHeatStatChip(title: "Deliveries", value: "\(shift.deliveries)", symbol: "bag.fill", color: OkkleColor.brand)
              NativeHeatStatChip(title: "Unpaid miles", value: "\(shift.deadMilePct)%", symbol: "arrow.triangle.turn.up.right.diamond.fill", color: OkkleColor.amber)
              NativeHeatStatChip(title: "Per hour", value: shift.perHour.map { gbp($0, whole: true) } ?? "—", symbol: "sterlingsign.circle.fill", color: .green)
            }
            Text("Learned automatically from your tracked stops — no input needed. Log your pay to sharpen the £/hour estimate.")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      // These three cards are one-time set-up prompts: they only appear while
      // the feature is off. Once you turn one on it disappears here — the on/off
      // switch then lives in Settings.
      if !store.settings.autoTrackTrips {
        NativeAiCard(banner: "AUTOMATIC TRACKING") {
          VStack(alignment: .leading, spacing: 16) {
            Text("Track every shift automatically")
              .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("On your working days Okkle starts a trip for you the moment it detects you driving, so you never lose a mile. You can still start and stop by hand any time.")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
            Toggle("Automatic trip tracking", isOn: Binding(
              get: { store.settings.autoTrackTrips },
              set: { store.settings.autoTrackTrips = $0 }
            ))
            .font(.system(size: 17, weight: .bold))
            .tint(OkkleColor.brand)
            Label("Choose your working days in Settings.", systemImage: "calendar")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(OkkleColor.brandDark)
              .padding(14)
              .background(OkkleColor.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
          }
        }
      }

      if !store.settings.loggingReminder {
        NativeAiCard(banner: "REMINDERS") {
          VStack(alignment: .leading, spacing: 16) {
            Text("Keep your records fresh")
              .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Get a gentle nudge to log your miles and pay so nothing slips through the week.")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
            Toggle("Logging reminder", isOn: Binding(
              get: { store.settings.loggingReminder },
              set: { store.settings.loggingReminder = $0 }
            ))
            .font(.system(size: 17, weight: .bold))
            .tint(OkkleColor.brand)
          }
        }
      }

      if !store.settings.taxDeadlineReminders {
        NativeKeyTaxDatesPanel()
      }

      if store.history.isEmpty {
        NativeEmptyState(symbol: "sparkles", title: "Insights will grow with your data", message: "Track trips and log pay to unlock best zones, hours, platform mix and tax-aware suggestions.")
      }
    }
  }
}

struct NativeTaxDeadline: Identifiable {
  let title: String
  let month: Int
  let day: Int
  let note: String

  var id: String { title }

  func nextOccurrence(from reference: Date = Date()) -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: reference)
    let year = calendar.component(.year, from: reference)
    var components = DateComponents(year: year, month: month, day: day, hour: 9, minute: 0)
    var date = calendar.date(from: components) ?? reference
    if date < today {
      components.year = year + 1
      date = calendar.date(from: components) ?? reference
    }
    return date
  }
}

let nativeTaxDeadlines = [
  NativeTaxDeadline(title: "Register for Self Assessment", month: 10, day: 5, note: "Only if this was your first year self-employed."),
  NativeTaxDeadline(title: "File your return & pay your tax", month: 1, day: 31, note: "Online Self Assessment deadline for the previous tax year."),
  NativeTaxDeadline(title: "Second payment on account", month: 7, day: 31, note: "Only if HMRC asked you for payments on account.")
]

func nativeDaysUntil(_ date: Date) -> Int {
  let calendar = Calendar.current
  let today = calendar.startOfDay(for: Date())
  let target = calendar.startOfDay(for: date)
  return calendar.dateComponents([.day], from: today, to: target).day ?? 0
}

func nativeTaxDateLabel(_ date: Date) -> String {
  date.formatted(.dateTime.day().month(.wide).year())
}

@MainActor
func nativeAddDeadlineToCalendar(_ deadline: NativeTaxDeadline) async -> Bool {
  let eventStore = EKEventStore()
  do {
    let granted: Bool
    if #available(iOS 17.0, *) {
      granted = try await eventStore.requestFullAccessToEvents()
    } else {
      granted = try await withCheckedThrowingContinuation { continuation in
        eventStore.requestAccess(to: .event) { granted, error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: granted)
          }
        }
      }
    }
    guard granted, let calendar = eventStore.defaultCalendarForNewEvents else { return false }

    let start = deadline.nextOccurrence()
    let end = Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? start.addingTimeInterval(1800)
    let event = EKEvent(eventStore: eventStore)
    event.calendar = calendar
    event.title = "HMRC: \(deadline.title)"
    event.startDate = start
    event.endDate = end
    event.notes = deadline.note
    event.addAlarm(EKAlarm(relativeOffset: -60 * 60 * 24 * 7))
    try eventStore.save(event, span: .thisEvent)
    return true
  } catch {
    return false
  }
}

struct NativeKeyTaxDatesPanel: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var showSheet = false

  var body: some View {
    NativeAiCard(banner: "KEY TAX DATES") {
      VStack(alignment: .leading, spacing: 16) {
        Text("Keep HMRC deadlines close")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Review Self Assessment dates and add reminders to your calendar.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
        Toggle("Tax deadline reminders", isOn: Binding(
          get: { store.settings.taxDeadlineReminders },
          set: { store.settings.taxDeadlineReminders = $0 }
        ))
        .font(.system(size: 17, weight: .bold))
        .tint(OkkleColor.brand)
        Button {
          showSheet = true
        } label: {
          HStack {
            Text("View dates")
              .font(.system(size: 16, weight: .bold))
            Spacer()
            Image(systemName: "chevron.up")
              .font(.system(size: 15, weight: .bold))
          }
          .foregroundStyle(Color.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
          .background(OkkleColor.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .sheet(isPresented: $showSheet) {
      NativeKeyTaxDatesSheet()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
  }
}

struct NativeKeyTaxDatesSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var alertMessage: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Add these dates to Calendar with a reminder one week before.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)

          NativeGlassCard {
            VStack(spacing: 0) {
              ForEach(nativeTaxDeadlines) { deadline in
                NativeTaxDeadlineRow(deadline: deadline) { message in
                  alertMessage = message
                }
                if deadline.id != nativeTaxDeadlines.last?.id {
                  Divider().padding(.leading, 0)
                }
              }
            }
          }

          Button {
            Task {
              var added = 0
              for deadline in nativeTaxDeadlines {
                if await nativeAddDeadlineToCalendar(deadline) {
                  added += 1
                }
              }
              alertMessage = added == nativeTaxDeadlines.count
                ? "All key tax dates were added to your calendar."
                : "Added \(added) of \(nativeTaxDeadlines.count) dates. Please allow calendar access and try again for the rest."
            }
          } label: {
            Label("Add all dates", systemImage: "calendar.badge.plus")
              .font(.system(size: 16, weight: .bold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 15)
              .foregroundStyle(Color.white)
              .background(OkkleColor.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          }
          .buttonStyle(.plain)

          Text("Keep your records for at least 5 years after the 31 January deadline. MTD for Income Tax adds quarterly updates once your income passes the threshold.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
      }
      .background(NativeBackground())
      .navigationTitle("Key tax dates")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .fontWeight(.bold)
        }
      }
      .alert("Calendar", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(alertMessage ?? "")
      }
    }
  }
}

struct NativeTaxDeadlineRow: View {
  let deadline: NativeTaxDeadline
  let onResult: (String) -> Void
  @State private var busy = false

  var body: some View {
    let next = deadline.nextOccurrence()
    let days = nativeDaysUntil(next)
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(deadline.title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
        Text("\(nativeTaxDateLabel(next)) - \(daysLabel(days))")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.brandDark)
        Text(deadline.note)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Button {
        busy = true
        Task {
          let ok = await nativeAddDeadlineToCalendar(deadline)
          busy = false
          onResult(ok
            ? "\(deadline.title) was added to your calendar with a reminder one week before."
            : "Could not add \(deadline.title). Please allow calendar access and try again.")
        }
      } label: {
        Label(busy ? "Adding" : "Add", systemImage: "calendar.badge.plus")
          .font(.system(size: 13, weight: .bold))
          .labelStyle(.titleAndIcon)
          .foregroundStyle(OkkleColor.brandDark)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(OkkleColor.brand.opacity(0.13), in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(busy)
    }
    .padding(.vertical, 13)
  }

  private func daysLabel(_ days: Int) -> String {
    if days == 0 { return "today" }
    if days == 1 { return "tomorrow" }
    return "in \(days) days"
  }
}

// MARK: - Passive auto-tracking engine

import MapKit
import SwiftUI

// MARK: - Model

/// One passively-detected stop (from Core Location Visit monitoring). A short
/// stop with no food place nearby reads as a customer drop-off; a longer stop
/// at (or beside) a restaurant reads as an order pick-up.
struct NativeVisit: Codable, Identifiable, Equatable {
  var id = UUID()
  var latitude: Double
  var longitude: Double
  var arrival: Date
  var departure: Date
  var kindRaw: String = Kind.other.rawValue
  var placeName: String?

  enum Kind: String, Codable, CaseIterable { case pickup, dropoff, other }

  var kind: Kind {
    get { Kind(rawValue: kindRaw) ?? .other }
    set { kindRaw = newValue.rawValue }
  }
  var dwell: TimeInterval { max(0, departure.timeIntervalSince(arrival)) }
  var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
  var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// Whether a given weekday (0 = Sunday … 6 = Saturday) is a working day.
func nativeIsWorkingDay(_ date: Date, settings: NativeSettings) -> Bool {
  let weekday = Calendar.current.component(.weekday, from: date) - 1   // 1-based → 0-based
  return settings.workingDays.contains(weekday)
}

// MARK: - Engine

/// Passive, hands-off tracking. After a one-time "Always" location grant it
/// watches Core Location Visits in the background and, on working days, records
/// pick-up / drop-off stops — the raw material for the shift insights. No taps,
/// no screenshots, no shortcuts.
@MainActor
final class NativeAutoTrackEngine: NSObject, ObservableObject, CLLocationManagerDelegate {
  static let shared = NativeAutoTrackEngine()

  @Published private(set) var visits: [NativeVisit] = []

  private let manager = CLLocationManager()
  private let storageKey = "uk.okkle.native.autotrack.visits.v1"
  private weak var store: OkkleStore?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    load()
  }

  func configure(store: OkkleStore) {
    self.store = store
    refresh()
  }

  /// Start or stop passive monitoring to match the Automatic-tracking setting.
  func refresh() {
    let on = store?.settings.autoTrackTrips ?? false
    guard on else {
      manager.stopMonitoringVisits()
      return
    }
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestAlwaysAuthorization()
    case .authorizedAlways:
      manager.allowsBackgroundLocationUpdates = true
      manager.startMonitoringVisits()
    default:
      // While-in-use still lets us collect visits when the app is foreground.
      manager.startMonitoringVisits()
    }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in self.refresh() }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    // Ignore the "arrived, still here" event — wait for a completed visit.
    guard visit.departureDate != Date.distantFuture else { return }
    Task { @MainActor in self.record(visit) }
  }

  private func record(_ clVisit: CLVisit) {
    if let settings = store?.settings, !nativeIsWorkingDay(clVisit.departureDate, settings: settings) { return }
    let arrival = clVisit.arrivalDate == Date.distantPast ? clVisit.departureDate : clVisit.arrivalDate
    var visit = NativeVisit(
      latitude: clVisit.coordinate.latitude,
      longitude: clVisit.coordinate.longitude,
      arrival: arrival,
      departure: clVisit.departureDate
    )
    // Provisional guess from dwell; MapKit refines it below.
    visit.kind = visit.dwell >= 150 ? .pickup : .dropoff
    visits.append(visit)
    trim()
    save()
    classifyWithMapKit(visit.id, coordinate: visit.coordinate)
  }

  /// Use Apple Maps as an information layer: if there's a food place right by the
  /// stop it's a pick-up; otherwise it's most likely a customer drop-off.
  private func classifyWithMapKit(_ id: UUID, coordinate: CLLocationCoordinate2D) {
    let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 45)
    request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .foodMarket, .brewery, .nightlife])
    MKLocalSearch(request: request).start { [weak self] response, _ in
      guard let self else { return }
      Task { @MainActor in
        guard let index = self.visits.firstIndex(where: { $0.id == id }) else { return }
        if let food = response?.mapItems.first {
          self.visits[index].kind = .pickup
          self.visits[index].placeName = food.name
        } else if self.visits[index].dwell < 240 {
          self.visits[index].kind = .dropoff
        }
        self.save()
      }
    }
  }

  // MARK: Persistence

  private func trim() {
    // Keep the last 60 days of stops — plenty for pattern insights.
    let cutoff = Date().addingTimeInterval(-60 * 86_400)
    visits.removeAll { $0.departure < cutoff }
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: storageKey),
          let saved = try? JSONDecoder().decode([NativeVisit].self, from: data) else { return }
    visits = saved
  }

  private func save() {
    if let data = try? JSONEncoder().encode(visits) {
      UserDefaults.standard.set(data, forKey: storageKey)
    }
  }

  /// Test/demo seeding used by the SEED_DEMO launch flag only.
  func seed(_ seeded: [NativeVisit]) {
    visits = seeded
    save()
  }
}

/// Synthetic two-week stop history for the SEED_DEMO launch flag, weighted to
/// Thu–Sat evenings so the "best window" reads as a weekend dinner slot.
func nativeDemoVisits() -> [NativeVisit] {
  var out: [NativeVisit] = []
  let cal = Calendar.current
  let base = CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)
  for dayOffset in 1...14 {
    guard let day = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
    let weekday = cal.component(.weekday, from: day) - 1   // 0 = Sun … 6 = Sat
    let heavy = weekday >= 4                                // Thu/Fri/Sat
    let count = heavy ? 6 : 2
    for i in 0..<count {
      let hour = heavy ? 18 + (i / 3) : 12
      let minute = (i % 3) * 20
      guard let start = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
      let dLat = Double(i) * 0.004 - 0.01
      let dLon = Double((i * 7) % 5) * 0.004 - 0.008
      var pickup = NativeVisit(latitude: base.latitude + dLat, longitude: base.longitude + dLon,
                               arrival: start, departure: start.addingTimeInterval(240))
      pickup.kind = .pickup
      pickup.placeName = "Restaurant"
      out.append(pickup)
      let dropStart = start.addingTimeInterval(600)
      var drop = NativeVisit(latitude: base.latitude + dLat + 0.012, longitude: base.longitude + dLon + 0.01,
                             arrival: dropStart, departure: dropStart.addingTimeInterval(90))
      drop.kind = .dropoff
      out.append(drop)
    }
  }
  return out
}

// MARK: - Analysis

/// Everything the passive engine can tell a driver, derived from the stops plus
/// their (weekly) logged income. Aggregate totals stay exact; only the
/// within-week distribution is modelled, so estimates are bounded.
struct NativeShiftInsights {
  let deliveries: Int
  let activeHours: Double
  let paidMiles: Double
  let deadMiles: Double
  let bestWindow: String?
  let perHour: Double?

  var hasData: Bool { deliveries > 0 }
  var totalMiles: Double { paidMiles + deadMiles }
  var deadMilePct: Int {
    guard totalMiles > 0 else { return 0 }
    return Int((deadMiles / totalMiles * 100).rounded())
  }

  @MainActor
  static func build(visits: [NativeVisit], store: OkkleStore) -> NativeShiftInsights {
    let sorted = visits.sorted { $0.arrival < $1.arrival }
    guard sorted.count > 1 else {
      return NativeShiftInsights(deliveries: 0, activeHours: 0, paidMiles: 0, deadMiles: 0, bestWindow: nil, perHour: nil)
    }

    let roadFactor = 1.3
    let shiftGap: TimeInterval = 45 * 60   // a gap longer than this ends a shift

    // Total distance + active time across legs within a shift.
    var totalMeters = 0.0
    var activeSeconds = 0.0
    for k in 1..<sorted.count {
      let prev = sorted[k - 1], cur = sorted[k]
      let gap = cur.arrival.timeIntervalSince(prev.departure)
      if gap < shiftGap {
        totalMeters += cur.location.distance(from: prev.location)
        activeSeconds += max(0, gap) + prev.dwell
      }
    }
    activeSeconds += sorted.last?.dwell ?? 0

    // Deliveries + paid distance: a pick-up drives to the next drop-off.
    var deliveries = 0
    var paidMeters = 0.0
    var deliveryHits: [(weekday: Int, band: NativeTimeFilter)] = []
    var index = 0
    while index < sorted.count {
      if sorted[index].kind == .pickup,
         let dropIndex = (index + 1..<sorted.count).first(where: { sorted[$0].kind == .dropoff }) {
        deliveries += 1
        // Paid = the active delivery leg (restaurant → customer). Everything
        // else (repositioning back out to the next pick-up, idle wandering) is
        // unpaid mileage.
        paidMeters += sorted[dropIndex].location.distance(from: sorted[index].location)
        let date = sorted[dropIndex].arrival
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        let band = NativeTimeFilter.allCases.first { $0 != .all && $0.includes(date) } ?? .afternoon
        deliveryHits.append((weekday, band))
        index = dropIndex + 1
      } else {
        index += 1
      }
    }

    let paidMiles = paidMeters / 1609.34 * roadFactor
    let totalMiles = max(totalMeters / 1609.34 * roadFactor, paidMiles)
    let deadMiles = max(0, totalMiles - paidMiles)
    let activeHours = activeSeconds / 3600

    // Best window: the weekday + time-band with the most deliveries.
    var counts: [String: Int] = [:]
    for hit in deliveryHits {
      counts["\(hit.weekday)|\(hit.band.rawValue)", default: 0] += 1
    }
    var bestWindow: String?
    if let top = counts.max(by: { $0.value < $1.value })?.key {
      let parts = top.split(separator: "|")
      if parts.count == 2, let wd = Int(parts[0]) {
        let day = Calendar.current.shortWeekdaySymbols[wd]
        let band = NativeTimeFilter(rawValue: String(parts[1]))?.label.lowercased() ?? ""
        bestWindow = "\(day) \(band)"
      }
    }

    // £/hr over the last 14 days: logged income ÷ active hours in the window.
    let windowStart = Date().addingTimeInterval(-14 * 86_400)
    let income = store.records
      .filter { $0.kind == .income && $0.date >= windowStart }
      .reduce(0.0) { $0 + ($1.amount ?? 0) }
    let recentActive = recentActiveHours(sorted, since: windowStart, shiftGap: shiftGap)
    let perHour: Double? = (income > 0 && recentActive > 0.25) ? income / recentActive : nil

    return NativeShiftInsights(
      deliveries: deliveries,
      activeHours: activeHours,
      paidMiles: paidMiles,
      deadMiles: deadMiles,
      bestWindow: bestWindow,
      perHour: perHour
    )
  }

  private static func recentActiveHours(_ sorted: [NativeVisit], since: Date, shiftGap: TimeInterval) -> Double {
    var seconds = 0.0
    for k in 1..<max(sorted.count, 1) {
      let prev = sorted[k - 1], cur = sorted[k]
      guard cur.arrival >= since else { continue }
      let gap = cur.arrival.timeIntervalSince(prev.departure)
      if gap < shiftGap { seconds += max(0, gap) + prev.dwell }
    }
    return seconds / 3600
  }
}
