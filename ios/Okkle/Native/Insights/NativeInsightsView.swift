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
  @State private var heatFilter: NativeTimeFilter = .all
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

      // These three cards are one-time set-up prompts: they only appear while
      // the feature is off. Once you turn one on it disappears here — the on/off
      // switch then lives in Settings.
      if !store.settings.tripNudges {
        NativeAiCard(banner: "TRIP NUDGES") {
          VStack(alignment: .leading, spacing: 16) {
            Text("Never forget to track a trip")
              .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Okkle watches both ends of your trip. When it senses you have started driving it nudges you to start tracking, then reminds you to end and save your miles once you have stopped.")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
            Toggle("Trip nudges", isOn: Binding(
              get: { store.settings.tripNudges },
              set: { store.settings.tripNudges = $0 }
            ))
            .font(.system(size: 17, weight: .bold))
            .tint(OkkleColor.brand)
            Label("Detection is a prompt, not auto-logging. Nothing is recorded until you confirm.", systemImage: "exclamationmark.circle")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(OkkleColor.amber)
              .padding(14)
              .background(Color.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
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
