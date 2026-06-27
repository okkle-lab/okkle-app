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

struct NativeHeatPoint: Identifiable, Equatable {
  let id: String
  let latitude: Double
  let longitude: Double
  let weight: Double

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

struct NativeHeatBubble: Identifiable {
  let id: String
  let latitude: Double
  let longitude: Double
  let weight: Double
  let normalized: Double

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  var diameter: CGFloat {
    CGFloat(34 + (normalized * 54))
  }
}

func nativeHeatPoints(from trips: [NativeTrip], filter: NativeTimeFilter) -> [NativeHeatPoint] {
  var points: [NativeHeatPoint] = []
  for trip in trips where filter.includes(trip.startedAt) {
    guard !trip.points.isEmpty else { continue }
    let stride = max(1, trip.points.count / 160)
    let sampled = trip.points.enumerated().filter { $0.offset % stride == 0 }
    let weight = max(0.35, trip.miles / Double(max(sampled.count, 1)))
    for item in sampled {
      points.append(NativeHeatPoint(
        id: "\(trip.id.uuidString)-\(item.offset)",
        latitude: item.element.latitude,
        longitude: item.element.longitude,
        weight: weight
      ))
    }
  }
  return points
}

func nativeDistinctCoordinateCount(_ points: [NativeHeatPoint]) -> Int {
  Set(points.map { "\(String(format: "%.3f", $0.latitude)),\(String(format: "%.3f", $0.longitude))" }).count
}

func nativeHeatRegion(for points: [NativeHeatPoint]) -> MKCoordinateRegion {
  guard !points.isEmpty else {
    return MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
      span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
  }

  var minLat = Double.infinity
  var maxLat = -Double.infinity
  var minLng = Double.infinity
  var maxLng = -Double.infinity

  for point in points {
    minLat = min(minLat, point.latitude)
    maxLat = max(maxLat, point.latitude)
    minLng = min(minLng, point.longitude)
    maxLng = max(maxLng, point.longitude)
  }

  return MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
    span: MKCoordinateSpan(
      latitudeDelta: max((maxLat - minLat) * 1.7, 0.012),
      longitudeDelta: max((maxLng - minLng) * 1.7, 0.012)
    )
  )
}

func nativeHeatBubbles(from points: [NativeHeatPoint]) -> [NativeHeatBubble] {
  guard !points.isEmpty else { return [] }

  var minLat = Double.infinity
  var maxLat = -Double.infinity
  var minLng = Double.infinity
  var maxLng = -Double.infinity

  for point in points {
    minLat = min(minLat, point.latitude)
    maxLat = max(maxLat, point.latitude)
    minLng = min(minLng, point.longitude)
    maxLng = max(maxLng, point.longitude)
  }

  let cols = 18
  let rows = 18
  let latSpan = max(maxLat - minLat, 0.0001)
  let lngSpan = max(maxLng - minLng, 0.0001)

  struct Accumulator {
    var latitude = 0.0
    var longitude = 0.0
    var weight = 0.0
  }

  var buckets: [String: Accumulator] = [:]
  for point in points {
    let col = min(cols - 1, max(0, Int(((point.longitude - minLng) / lngSpan) * Double(cols))))
    let row = min(rows - 1, max(0, Int(((maxLat - point.latitude) / latSpan) * Double(rows))))
    let key = "\(row)-\(col)"
    var bucket = buckets[key] ?? Accumulator()
    bucket.latitude += point.latitude * point.weight
    bucket.longitude += point.longitude * point.weight
    bucket.weight += point.weight
    buckets[key] = bucket
  }

  let maxWeight = max(buckets.values.map(\.weight).max() ?? 1, 1)
  return buckets.map { key, bucket in
    let safeWeight = max(bucket.weight, 0.0001)
    return NativeHeatBubble(
      id: key,
      latitude: bucket.latitude / safeWeight,
      longitude: bucket.longitude / safeWeight,
      weight: bucket.weight,
      normalized: min(1, bucket.weight / maxWeight)
    )
  }
  .sorted { $0.weight > $1.weight }
  .prefix(90)
  .map { $0 }
}

func nativeHeatColor(_ value: Double) -> Color {
  switch value {
  case ..<0.2:
    return Color(red: 0.61, green: 0.89, blue: 0.82)
  case ..<0.4:
    return Color(red: 0.37, green: 0.82, blue: 0.73)
  case ..<0.6:
    return Color(red: 0.91, green: 0.78, blue: 0.42)
  case ..<0.8:
    return Color(red: 0.88, green: 0.59, blue: 0.12)
  default:
    return Color(red: 0.89, green: 0.38, blue: 0.29)
  }
}

struct NativeHeatMapCard: View {
  let points: [NativeHeatPoint]
  let showsFilters: Bool
  @Binding var filter: NativeTimeFilter

  var body: some View {
    NativeAiCard {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 10) {
          Image(systemName: "map.circle.fill")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(OkkleColor.brand)
            .frame(width: 42, height: 42)
            .background(OkkleColor.brand.opacity(0.14), in: Circle())
          Text("HOTSPOT MAP")
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(.purple)
        }
        Text("See where your work clusters")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Okkle maps your saved GPS trips so you can spot the areas you keep returning to.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
        if showsFilters {
          NativeHeatFilterBar(selection: $filter)
        }
        NativeHeatMapView(points: points)
        NativeHeatLegend()
        Text("Built on-device from your trip breadcrumbs.")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
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

struct NativeHeatMapView: View {
  let points: [NativeHeatPoint]
  @State private var region = nativeHeatRegion(for: [])

  private var hasEnoughPoints: Bool {
    points.count >= 2 && nativeDistinctCoordinateCount(points) >= 2
  }

  private var signature: String {
    "\(points.count)-\(points.first?.id ?? "none")-\(points.last?.id ?? "none")"
  }

  var body: some View {
    Group {
      if hasEnoughPoints {
        Map(coordinateRegion: $region, annotationItems: nativeHeatBubbles(from: points)) { bubble in
          MapAnnotation(coordinate: bubble.coordinate) {
            Circle()
              .fill(nativeHeatColor(bubble.normalized).opacity(0.42))
              .frame(width: bubble.diameter, height: bubble.diameter)
              .blur(radius: 5)
              .allowsHitTesting(false)
          }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear(perform: updateRegion)
        .onChange(of: signature) { _ in updateRegion() }
      } else {
        NativeHeatMapEmpty()
      }
    }
  }

  private func updateRegion() {
    region = nativeHeatRegion(for: points)
  }
}

struct NativeHeatMapEmpty: View {
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "map")
        .font(.system(size: 30, weight: .bold))
        .foregroundStyle(OkkleColor.brand)
      Text("Track a few GPS trips and your hotspots will appear here.")
        .font(.system(size: 15, weight: .semibold))
        .multilineTextAlignment(.center)
        .foregroundStyle(OkkleColor.muted)
        .padding(.horizontal, 18)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 220)
    .background(Color(red: 0.94, green: 0.97, blue: 0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
  }
}

struct NativeHeatLegend: View {
  private let colors = [
    Color(red: 0.61, green: 0.89, blue: 0.82),
    Color(red: 0.37, green: 0.82, blue: 0.73),
    Color(red: 0.91, green: 0.78, blue: 0.42),
    Color(red: 0.88, green: 0.59, blue: 0.12),
    Color(red: 0.89, green: 0.38, blue: 0.29)
  ]

  var body: some View {
    HStack(spacing: 8) {
      Text("Quieter")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      HStack(spacing: 0) {
        ForEach(colors.indices, id: \.self) { index in
          colors[index]
            .frame(maxWidth: .infinity)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 8)
      .clipShape(Capsule())
      Text("Busier")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
  }
}

struct NativeInsightsView: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var heatFilter: NativeTimeFilter = .all
  private let weekdays = Calendar.current.shortWeekdaySymbols
  private var selectedHeatPoints: [NativeHeatPoint] {
    nativeHeatPoints(from: store.trips, filter: heatFilter)
  }
  private var hasAnyHeatPoints: Bool {
    !nativeHeatPoints(from: store.trips, filter: .all).isEmpty
  }

  var body: some View {
    NativeScreen(title: "Insights", subtitle: "AI guidance, smart nudges and patterns from your work.") {
      NativeHeatMapCard(points: selectedHeatPoints, showsFilters: hasAnyHeatPoints, filter: $heatFilter)

      NativeAiCard {
        VStack(alignment: .leading, spacing: 16) {
          cardHeader("Trip nudges", symbol: "location.north.circle.fill", color: OkkleColor.blue)
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

      NativeAiCard {
        VStack(alignment: .leading, spacing: 16) {
          cardHeader("Reminders", symbol: "bell.circle.fill", color: .purple)
          Text("Keep your records fresh")
            .font(.system(size: 26, weight: .bold, design: .rounded))

          Toggle("Logging reminder", isOn: Binding(
            get: { store.settings.loggingReminder },
            set: { store.settings.loggingReminder = $0 }
          ))
          .font(.system(size: 17, weight: .bold))
          .tint(OkkleColor.brand)

          if store.settings.loggingReminder {
            Picker("Frequency", selection: Binding(
              get: { store.settings.logFrequency },
              set: { store.settings.logFrequency = $0 }
            )) {
              ForEach(NativeLogFrequency.allCases) { frequency in
                Text(frequency.label).tag(frequency)
              }
            }
            .pickerStyle(.segmented)

            Picker("Reminder day", selection: Binding(
              get: { store.settings.reminderDay },
              set: { store.settings.reminderDay = $0 }
            )) {
              ForEach(0..<weekdays.count, id: \.self) { index in
                Text(weekdays[index]).tag(index)
              }
            }
            .pickerStyle(.segmented)
          }

          Divider()

          Toggle("Tax deadline reminders", isOn: Binding(
            get: { store.settings.taxDeadlineReminders },
            set: { store.settings.taxDeadlineReminders = $0 }
          ))
          .font(.system(size: 17, weight: .bold))
          .tint(OkkleColor.brand)
        }
      }

      NativeKeyTaxDatesPanel()

      if store.history.isEmpty {
        NativeEmptyState(symbol: "sparkles", title: "Insights will grow with your data", message: "Track trips and log pay to unlock best zones, hours, platform mix and tax-aware suggestions.")
      }
    }
  }

  private func cardHeader(_ title: String, symbol: String, color: Color) -> some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(color)
        .frame(width: 42, height: 42)
        .background(color.opacity(0.14), in: Circle())
      Text(title.uppercased())
        .font(.system(size: 15, weight: .heavy))
        .foregroundStyle(.purple)
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
  @State private var showSheet = false

  var body: some View {
    NativeAiCard {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 10) {
          Image(systemName: "calendar.circle.fill")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(OkkleColor.brand)
            .frame(width: 42, height: 42)
            .background(OkkleColor.brand.opacity(0.14), in: Circle())
          Text("KEY TAX DATES")
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(.purple)
        }
        Text("Keep HMRC deadlines close")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Review Self Assessment dates and add reminders to your calendar.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
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
