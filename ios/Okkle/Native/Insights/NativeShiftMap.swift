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

struct NativeShiftMapRepresentable: UIViewRepresentable {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  var interactive: Bool = false
  var pinLimit: Int = 5
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

    for trip in trips {
      let coordinates = trip.points.map(\.coordinate)
      guard coordinates.count > 1 else { continue }
      let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
      mapView.addOverlay(polyline)
    }

    // Zones layer gradually as stops accumulate — with none yet, nothing draws
    // and the map just centres on you; each new pattern adds a coloured cell.
    for zone in zones {
      let circle = NativeZoneCircle(center: zone.coordinate, radius: 220)
      circle.weight = zone.weight
      mapView.addOverlay(circle)
    }

    // Numbered pins that line up with the "Where to go" list — pin 2 is list
    // row 2, the same named place — so the ranking reads as one idea.
    let ranked = nativeRankedAreas(zones, near: locator.coordinate, namer: areaNamer, limit: pinLimit)
    for area in ranked {
      let pin = NativeRankAnnotation()
      pin.coordinate = area.coordinate
      pin.rank = area.rank
      pin.weight = area.weight
      mapView.addAnnotation(pin)
    }

    // Both the mini preview and the full detail map centre on you — when your
    // areas are spread miles apart, fitting them all zooms out to the whole
    // city and the pins become useless dots. Staying anchored near your
    // current spot keeps it readable; on the interactive map you can still
    // pan out to see the rest.
    if !interactive {
      let focus = ranked.first?.coordinate ?? locator.coordinate ?? CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)
      mapView.setRegion(MKCoordinateRegion(center: focus, span: MKCoordinateSpan(latitudeDelta: 0.055, longitudeDelta: 0.055)), animated: false)
    } else {
      let center = locator.coordinate ?? ranked.first?.coordinate ?? CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)
      mapView.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)), animated: false)
    }
  }

  final class Coordinator: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      if let polyline = overlay as? MKPolyline {
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = UIColor(red: 0.20, green: 0.47, blue: 0.93, alpha: 0.55)
        renderer.lineWidth = 4
        renderer.lineCap = .round
        renderer.lineJoin = .round
        return renderer
      }
      if let circle = overlay as? NativeZoneCircle {
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
      let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
      view.annotation = annotation
      let size: CGFloat = 26
      let badge = UILabel(frame: CGRect(x: 0, y: 0, width: size, height: size))
      badge.text = "\(rank.rank)"
      badge.textAlignment = .center
      badge.textColor = .white
      badge.font = .systemFont(ofSize: 13, weight: .heavy)
      badge.backgroundColor = UIColor(OkkleColor.brand)   // rank marker, not a heat value
      badge.layer.cornerRadius = size / 2
      badge.layer.borderColor = UIColor.white.cgColor
      badge.layer.borderWidth = 2
      badge.layer.masksToBounds = true
      let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
      view.image = renderer.image { _ in badge.layer.render(in: UIGraphicsGetCurrentContext()!) }
      view.centerOffset = .zero
      return view
    }
  }
}

/// A small live heat-map of your busy areas, right on the daily panel — a glance
/// tells you where the warm patches are. Tap to open the full explorable map.
struct NativeZoneMiniMap: View {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  @State private var showDetail = false

  var body: some View {
    Button { showDetail = true } label: {
      ZStack(alignment: .bottomTrailing) {
        NativeShiftMapRepresentable(trips: trips, zones: zones, interactive: false, pinLimit: 3)
          .frame(height: 150)
          .allowsHitTesting(false)
        // Little affordance so it clearly opens something bigger.
        HStack(spacing: 5) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .bold))
          Text("Explore")
            .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(OkkleColor.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(10)
      }
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $showDetail) {
      NativeShiftMapDetailView(trips: trips, zones: zones)
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
                Text(area.time.map { "Busy \($0)" } ?? "One of your patches")
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
                      .frame(width: 32, alignment: .trailing)
                  }
                  .padding(.top, 1)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OkkleColor.muted.opacity(0.5))
            }
            .padding(.vertical, 10)
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
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        NativeShiftMapRepresentable(trips: trips, zones: zones, interactive: true)
          .ignoresSafeArea(edges: .bottom)
        VStack(spacing: 12) {
          Text("Numbered pins are your busiest areas near you, ranked 1–5. Warmer patches are where you pick up and drop off most.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          NativeHeatLegend()
        }
        .padding(16)
        .background(.regularMaterial)
      }
      .navigationTitle("Where you earn")
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
