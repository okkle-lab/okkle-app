import CoreLocation
import MapKit
import SwiftUI
import UIKit

func nativeHeatColor(_ t: Double) -> Color {
  let stops: [(Double, Double, Double, Double)] = [
    (0.00, 0.20, 0.47, 0.93),
    (0.35, 0.10, 0.66, 0.62),
    (0.60, 0.24, 0.72, 0.30),
    (0.80, 0.95, 0.66, 0.23),
    (1.00, 0.86, 0.16, 0.16)
  ]
  let clamped = max(0, min(1, t))
  for i in 1..<stops.count {
    guard clamped <= stops[i].0 else { continue }
    let (t0, r0, g0, b0) = stops[i - 1]
    let (t1, r1, g1, b1) = stops[i]
    let f = t1 > t0 ? (clamped - t0) / (t1 - t0) : 0
    return Color(red: r0 + (r1 - r0) * f, green: g0 + (g1 - g0) * f, blue: b0 + (b1 - b0) * f)
  }
  let last = stops.last!
  return Color(red: last.1, green: last.2, blue: last.3)
}

func nativeHeatUIColor(_ t: Double) -> UIColor { UIColor(nativeHeatColor(t)) }

struct NativeHeatLegend: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("Quiet")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
        Capsule()
          .fill(LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.05).map(nativeHeatColor), startPoint: .leading, endPoint: .trailing))
          .frame(maxWidth: .infinity)
          .frame(height: 10)
        Text("Busiest")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
      }
    }
  }
}

// MARK: - One-shot location (so the map has somewhere to show before any data exists)


final class NativeRankAnnotation: MKPointAnnotation {
  var rank: Int = 0
  var weight: Double = 0.5
}

enum NativeShiftMapPresentation {
  case history
  case recommendation
  /// The wider-window (Monthly/Yearly) read: same soft glow blobs as
  /// `recommendation` — no route squiggles, no bordered circles — but
  /// shows every learned zone rather than just the handful nearest you
  /// right now, since a month/year overview isn't a "go now" prompt.
  case hotspot
}

struct NativeShiftMapRepresentable: UIViewRepresentable {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  var interactive: Bool = false
  var pinLimit: Int = 5
  var presentation: NativeShiftMapPresentation = .history
  @ObservedObject private var locator = NativeOneShotLocator.shared
  @ObservedObject private var areaNamer = NativeAreaNamer.shared

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator
    mapView.isUserInteractionEnabled = interactive
    mapView.showsCompass = interactive
    mapView.showsScale = interactive
    mapView.isPitchEnabled = false
    mapView.showsUserLocation = true
    return mapView
  }

  func updateUIView(_ mapView: MKMapView, context: Context) {
    mapView.removeOverlays(mapView.overlays)
    mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

    if presentation == .history {
      for trip in trips {
        let coordinates = trip.points.map(\.coordinate)
        guard coordinates.count > 1 else { continue }
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)
      }
    }

    // The recommendation surface strips away routes and pins, leaving only a
    // soft heat glow over the learned zones. Zone weights already combine the
    // driver's past stops with the cached Apple Maps food/shopping-area prior.
    let displayedZones = presentation == .recommendation
      ? nativeTopZones(zones, near: locator.coordinate, limit: 5)
      : zones
    for zone in displayedZones {
      let radius: CLLocationDistance = presentation == .history ? 220 : 480
      let circle = NativeZoneCircle(center: zone.coordinate, radius: radius)
      circle.weight = zone.weight
      circle.rendersAsGlow = presentation != .history
      mapView.addOverlay(circle)
    }

    let ranked = nativeRankedAreas(zones, near: locator.coordinate, namer: areaNamer, limit: pinLimit)
    if pinLimit > 0 {
      // Numbered pins that line up with the "Where to go" list — pin 2 is list
      // row 2, the same named place — so the ranking reads as one idea.
      for area in ranked {
        let pin = NativeRankAnnotation()
        pin.coordinate = area.coordinate
        pin.rank = area.rank
        pin.weight = area.weight
        mapView.addAnnotation(pin)
      }
    }

    // Both the mini preview and the full detail map centre on you — when your
    // areas are spread miles apart, fitting them all zooms out to the whole
    // city and the pins become useless dots. Staying anchored near your
    // current spot keeps it readable; on the interactive map you can still
    // pan out to see the rest.
    //
    // Before any zones have formed (the early "building your insights"
    // state), ranked is empty — and if the one-shot locator hasn't resolved
    // yet either, this used to fall all the way back to a hardcoded central
    // London coordinate, showing a random part of the city instead of
    // anything to do with the driver. The actual driven routes are real
    // data already in hand at that point, so their centroid is a far
    // better stand-in than a fixed default.
    if presentation == .recommendation {
      let focus = displayedZones.first?.coordinate ?? tripsCentroid ?? locator.coordinate ?? CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)
      let delta = interactive ? 0.055 : 0.04
      mapView.setRegion(MKCoordinateRegion(center: focus, span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)), animated: false)
    } else if !interactive {
      let focus = ranked.first?.coordinate ?? tripsCentroid ?? locator.coordinate ?? CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)
      mapView.setRegion(MKCoordinateRegion(center: focus, span: MKCoordinateSpan(latitudeDelta: 0.055, longitudeDelta: 0.055)), animated: false)
    } else {
      let center = locator.coordinate ?? tripsCentroid ?? ranked.first?.coordinate ?? CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)
      mapView.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)), animated: false)
    }
  }

  /// Average point across every recorded route point in `trips` — a much
  /// better fallback focus than a hardcoded city coordinate once there's
  /// real driving data but no formed zones or live location yet.
  private var tripsCentroid: CLLocationCoordinate2D? {
    let points = trips.flatMap { $0.points.map(\.coordinate) }
    guard !points.isEmpty else { return nil }
    let lat = points.map(\.latitude).reduce(0, +) / Double(points.count)
    let lon = points.map(\.longitude).reduce(0, +) / Double(points.count)
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }

  final class Coordinator: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      if let polyline = overlay as? MKPolyline {
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = UIColor(OkkleColor.brand).withAlphaComponent(0.7)
        renderer.lineWidth = 4
        renderer.lineCap = .round
        renderer.lineJoin = .round
        return renderer
      }
      if let circle = overlay as? NativeZoneCircle {
        if circle.rendersAsGlow {
          return NativeZoneGlowRenderer(circle: circle)
        }
        let color = nativeHeatUIColor(circle.weight)
        let renderer = MKCircleRenderer(circle: circle)
        renderer.fillColor = color.withAlphaComponent(0.34)
        renderer.strokeColor = color.withAlphaComponent(0.8)
        renderer.lineWidth = 1.5
        return renderer
      }
      return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
      guard let rank = annotation as? NativeRankAnnotation else { return nil }
      let id = "rank"
      let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
        ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
      view.annotation = annotation
      view.markerTintColor = UIColor(OkkleColor.brand)
      view.glyphText = "\(rank.rank)"
      view.glyphTintColor = .white
      view.titleVisibility = .hidden
      view.subtitleVisibility = .hidden
      view.displayPriority = .required
      return view
    }
  }
}

/// A radial overlay with a vivid centre and transparent edge, so the map reads
/// as a recommendation heat map instead of a collection of bordered circles.
final class NativeZoneGlowRenderer: MKCircleRenderer {
  private let glowColor: UIColor

  override init(circle: MKCircle) {
    let weight = (circle as? NativeZoneCircle)?.weight ?? 0.5
    glowColor = nativeHeatUIColor(weight)
    super.init(circle: circle)
  }

  override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
    let drawRect = rect(for: overlay.boundingMapRect)
    guard drawRect.width > 0, drawRect.height > 0 else { return }
    let strength = 0.5 + (((overlay as? NativeZoneCircle)?.weight ?? 0.5) * 0.35)
    let colors = [
      glowColor.withAlphaComponent(strength).cgColor,
      glowColor.withAlphaComponent(strength * 0.38).cgColor,
      glowColor.withAlphaComponent(0).cgColor
    ] as CFArray
    guard let gradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: colors,
      locations: [0, 0.42, 1]
    ) else { return }

    context.saveGState()
    context.addEllipse(in: drawRect)
    context.clip()
    let center = CGPoint(x: drawRect.midX, y: drawRect.midY)
    context.drawRadialGradient(
      gradient,
      startCenter: center,
      startRadius: 0,
      endCenter: center,
      endRadius: max(drawRect.width, drawRect.height) / 2,
      options: []
    )
    context.restoreGState()
  }
}

/// The focused Place preview for Today: historical routes and ranking pins are
/// intentionally hidden so the strongest recommendation is clear at a glance.
struct NativeRecommendationHeatMap: View {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  /// The best time window to be out, shown as a floating readout on the map
  /// itself — one glance covers both "where" and "when" together.
  var timeLabel: String? = nil
  @State private var showDetail = false

  var body: some View {
    Button { showDetail = true } label: {
      ZStack(alignment: .bottomTrailing) {
        NativeShiftMapRepresentable(
          trips: trips,
          zones: zones,
          interactive: false,
          pinLimit: 3,
          presentation: .recommendation
        )
        .frame(height: 180)
        .allowsHitTesting(false)
        HStack(spacing: 5) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
          Text("Expand")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .padding(10)
        if let timeLabel {
          VStack {
            HStack {
              Text(timeLabel)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
              Spacer()
            }
            Spacer()
          }
          .padding(10)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open recommended areas heat map")
    .sheet(isPresented: $showDetail) {
      NativeShiftMapDetailView(trips: trips, zones: zones, presentation: .recommendation)
    }
  }
}

/// A compact historical heat-map used by the longer-period overviews. Tap to
/// open the full explorable map with routes and ranked pins.
struct NativeZoneMiniMap: View {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  @State private var showDetail = false

  var body: some View {
    Button { showDetail = true } label: {
      ZStack(alignment: .bottomTrailing) {
        NativeShiftMapRepresentable(trips: trips, zones: zones, interactive: false, pinLimit: 3, presentation: .hotspot)
          .frame(height: 150)
          .allowsHitTesting(false)
        // Little affordance so it clearly opens something bigger.
        HStack(spacing: 5) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
          Text("Expand")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .padding(10)
      }
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $showDetail) {
      NativeShiftMapDetailView(trips: trips, zones: zones, presentation: .hotspot)
    }
  }
}

/// A ranked list of your busiest areas (top few near you). Resolves area names
/// on-device and de-dupes, so "Camden · Soho · Islington" reads cleanly.
/// A clean, grouped list of your best areas — each with *when* it's busy for
/// you, so "where to go" and "when to go" read as one line.
struct NativeTopAreasList: View {
  let zones: [NativeZonePoint]
  var limit: Int = 5
  /// Show a thin bar of how much of your work each area carries — turns a plain
  /// rank into a sense of *how dominant* the top patch really is.
  var showShareBar: Bool = false
  /// Show how far each area is from you right now, alongside its busy time.
  var showDistance: Bool = false
  @ObservedObject private var areaNamer = NativeAreaNamer.shared
  @ObservedObject private var locator = NativeOneShotLocator.shared
  @State private var directionsTarget: NativeRankedArea?

  var body: some View {
    let rows = nativeRankedAreas(zones, near: locator.coordinate, namer: areaNamer, limit: limit)
    if !rows.isEmpty {
      VStack(spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, area in
          Button {
            directionsTarget = area
          } label: {
            HStack(spacing: 12) {
              // Numbered badge — one brand colour so the number carries the rank.
              // (Heat colours are reserved for the busy-hours graph and map, to
              // avoid reading rank and busyness as the same scale.)
              Text("\(area.rank)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(OkkleColor.brand, in: Circle())
              VStack(alignment: .leading, spacing: showShareBar ? 5 : 1) {
                Text(area.name)
                  .font(.system(size: 16, weight: .semibold))
                  .foregroundStyle(OkkleColor.ink)
                Text(subtitle(for: area))
                  .font(.system(size: 13, weight: .medium))
                  .foregroundStyle(OkkleColor.muted)
                if showShareBar {
                  HStack(spacing: 8) {
                    GeometryReader { geo in
                      ZStack(alignment: .leading) {
                        Capsule().fill(OkkleColor.muted.opacity(0.12)).frame(height: 4)
                        Capsule().fill(OkkleColor.brand).frame(width: max(6, geo.size.width * area.weight), height: 4)
                      }
                    }
                    .frame(height: 4)
                    // The bar alone can't say whether it means 90% or 20% — put
                    // the actual number on it, same as Platform Mix does.
                    Text("\(Int((area.weight * 100).rounded()))%")
                      .font(.system(size: 11, weight: .bold))
                      .foregroundStyle(OkkleColor.muted)
                      .frame(width: 38, alignment: .trailing)
                  }
                  .padding(.top, 1)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OkkleColor.muted.opacity(0.5))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          if index < rows.count - 1 {
            Divider().padding(.leading, 36)
          }
        }
      }
      .confirmationDialog(
        directionsTarget.map { "Directions to \($0.name)" } ?? "Directions",
        isPresented: Binding(get: { directionsTarget != nil }, set: { if !$0 { directionsTarget = nil } }),
        titleVisibility: .visible
      ) {
        if let area = directionsTarget {
          Button("Apple Maps") { nativeOpenDirections(to: area.coordinate, name: area.name, app: .apple) }
          if nativeGoogleMapsInstalled {
            Button("Google Maps") { nativeOpenDirections(to: area.coordinate, name: area.name, app: .google) }
          }
        }
      }
    } else {
      Text("Your best areas will show here once a few more shifts are tracked.")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }
  }

  private func subtitle(for area: NativeRankedArea) -> String {
    let busy = area.time.map { "Busy \($0)" } ?? "One of your patches"
    guard showDistance, let coordinate = locator.coordinate else { return busy }
    return "\(busy) · \(nativeZoneDistanceLabel(from: coordinate, to: area.coordinate))"
  }
}

enum NativeMapsApp {
  case apple
  case google
}

var nativeGoogleMapsInstalled: Bool {
  guard let url = URL(string: "comgooglemaps://") else { return false }
  return UIApplication.shared.canOpenURL(url)
}

@MainActor
func nativeOpenDirections(to coordinate: CLLocationCoordinate2D, name: String, app: NativeMapsApp) {
  switch app {
  case .apple:
    let placemark = MKPlacemark(coordinate: coordinate)
    let item = MKMapItem(placemark: placemark)
    item.name = name
    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
  case .google:
    guard let url = URL(string: "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&directionsmode=driving") else { return }
    UIApplication.shared.open(url)
  }
}

struct NativeShiftMapDetailView: View {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  var presentation: NativeShiftMapPresentation = .history
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        NativeShiftMapRepresentable(trips: trips, zones: zones, interactive: true, presentation: presentation)
          .ignoresSafeArea(edges: .bottom)
        VStack(spacing: 16) {
          Text(presentation == .recommendation
               ? "Numbered pins are ranked 1–5. Brighter glows mark the areas that best combine your past trip patterns with nearby shopping and food activity."
               : "Numbered pins are your busiest areas, ranked 1–5. Warmer glows are where you pick up and drop off most.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          NativeHeatLegend()
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
      }
      .navigationTitle(presentation == .recommendation ? "Where to go" : "Where you earn")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }.fontWeight(.bold)
        }
      }
    }
  }
}

// MARK: - The main card: your shift plan (Today / This week / Monthly / Yearly)

/// Which window the shift panel reflects. "Today" reads the existing
/// day-plan logic unchanged; the other three re-run the same weekly-panel
/// metrics over a wider or narrower slice of the same visit history, so the
/// numbers are always directly comparable across periods.
