import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
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

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if hasMapDetails {
            NativeRouteMapView(points: trip.points)
              .frame(height: 280)
              .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
          }

          HStack(spacing: 12) {
            NativeMetricTile(title: "Miles", value: miles(trip.miles), symbol: "road.lanes")
            NativeMetricTile(title: "Deduction", value: gbp(trip.deduction, whole: true), symbol: "sterlingsign.circle.fill", color: .green)
          }

          NativeGlassCard {
            VStack(alignment: .leading, spacing: 14) {
              tripDetailRow("Vehicle", value: trip.vehicle.label, symbol: trip.vehicle.symbol)
              Divider()
              tripDetailRow("Started", value: trip.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()), symbol: "play.circle")
              tripDetailRow("Ended", value: trip.endedAt.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()), symbol: "stop.circle")
              tripDetailRow("Duration", value: nativeDurationLabel(trip.endedAt.timeIntervalSince(trip.startedAt)), symbol: "timer")
            }
          }

          if hasMapDetails {
            NativeGlassCard {
              VStack(alignment: .leading, spacing: 14) {
                Label("Map details", systemImage: "map.fill")
                  .font(.system(size: 16, weight: .bold))
                  .foregroundStyle(OkkleColor.ink)
                if let startPoint {
                  tripDetailRow("Start location", value: coordinateLabel(startPoint), symbol: "location.circle")
                }
                if let endPoint {
                  tripDetailRow("End location", value: coordinateLabel(endPoint), symbol: "mappin.circle")
                }
                tripDetailRow("Route points", value: "\(trip.points.count)", symbol: "point.3.connected.trianglepath.dotted")
              }
            }
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

  private func coordinateLabel(_ point: RoutePoint) -> String {
    String(format: "%.5f, %.5f", point.latitude, point.longitude)
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
  @State private var vehicle: NativeVehicle
  @State private var milesText: String
  @State private var startedAt: Date
  @State private var endedAt: Date

  init(trip: NativeTrip, onSave: @escaping (NativeTrip) -> Void) {
    self.trip = trip
    self.onSave = onSave
    _vehicle = State(initialValue: trip.vehicle)
    _milesText = State(initialValue: String(format: "%.1f", trip.miles))
    _startedAt = State(initialValue: trip.startedAt)
    _endedAt = State(initialValue: trip.endedAt)
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

        Section("Preview") {
          HStack {
            Text("Deduction")
            Spacer()
            Text(gbp(previewDeduction, whole: true))
              .fontWeight(.bold)
          }
          Text("Editing keeps the saved route points and recalculates the mileage deduction.")
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

  private func save() {
    guard canSave else { return }
    var updated = trip
    updated.vehicle = vehicle
    updated.miles = milesValue
    updated.startedAt = startedAt
    updated.endedAt = endedAt
    updated.deduction = previewDeduction
    onSave(updated)
    dismiss()
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

      let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
      mapView.addOverlay(polyline)
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
