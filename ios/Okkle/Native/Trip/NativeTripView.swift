import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
struct NativeTripView: View {
  @EnvironmentObject private var store: OkkleStore
  @StateObject private var session = NativeTripSession()
  @State private var selectedVehicle: NativeVehicle = .car
  @State private var completedTrip: NativeTrip?
  @State private var showTripActionDialog = false

  var body: some View {
    NativeScreen(title: "Trip", subtitle: "Track GPS miles for HMRC mileage relief.") {
      NativeGlassCard(cornerRadius: 34) {
        VStack(spacing: 22) {
          Picker("Vehicle", selection: $selectedVehicle) {
            ForEach(NativeVehicle.allCases) { vehicle in
              Label(vehicle.label, systemImage: vehicle.symbol).tag(vehicle)
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, alignment: .leading)
          .disabled(session.phase == .live || session.phase == .paused)
          .tint(OkkleColor.brand)

          ZStack {
            Circle()
              .stroke(tripButtonRingColor, lineWidth: 18)
              .frame(width: 270, height: 270)
            Circle()
              .fill(
                LinearGradient(colors: tripButtonColors, startPoint: .topLeading, endPoint: .bottomTrailing)
              )
              .frame(width: 222, height: 222)
              .shadow(color: tripButtonShadowColor, radius: 28, y: 20)

            VStack(spacing: 8) {
              if session.phase == .setup {
                Image(systemName: "location.north.fill")
                  .font(.system(size: 42, weight: .bold))
                Text("Start")
                  .font(.system(size: 38, weight: .heavy, design: .rounded))
              } else {
                Text(miles(session.miles))
                  .font(.system(size: 44, weight: .heavy, design: .rounded))
                  .minimumScaleFactor(0.6)
                Text(tripButtonSubtitle)
                  .font(.system(size: 16, weight: .bold))
                  .multilineTextAlignment(.center)
              }
            }
            .foregroundStyle(.white)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Circle())
          .onTapGesture {
            switch session.phase {
            case .setup:
              session.start(vehicle: selectedVehicle)
            case .live:
              showTripActionDialog = true
            case .paused:
              session.resume()
            case .summary:
              break
            }
          }

          HStack(spacing: 12) {
            NativeMetricTile(title: "Tax deduction", value: gbp(store.calcDeduction(miles: session.miles, vehicle: selectedVehicle), whole: true), symbol: "sterlingsign.arrow.circlepath")
            NativeMetricTile(title: "Elapsed", value: elapsedLabel(session.elapsed), symbol: "timer", color: OkkleColor.blue)
          }

          if !session.points.isEmpty {
            NativeTripMap(points: session.points)
              .frame(height: 190)
              .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
          }

          if let message = session.permissionMessage {
            Label(message, systemImage: "location.slash")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(OkkleColor.red)
              .padding(12)
              .background(OkkleColor.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
          }

          if session.phase != .setup {
            tripControls
          }
        }
      }
    }
    .alert("Save this trip?", isPresented: Binding(
      get: { completedTrip != nil },
      set: { isPresented in
        if !isPresented, completedTrip != nil {
          completedTrip = nil
          session.continueTrackingAfterEndReview()
        }
      }
    )) {
      Button("Continue trip", role: .cancel) {
        completedTrip = nil
        session.continueTrackingAfterEndReview()
      }
      Button("Discard", role: .destructive) {
        completedTrip = nil
        session.discard()
      }
      Button("Save") {
        if let completedTrip {
          store.addTrip(completedTrip)
        }
        completedTrip = nil
        session.discard()
      }
    } message: {
      if let completedTrip {
        Text("\(miles(completedTrip.miles)) with \(gbp(completedTrip.deduction, whole: true)) deduction.")
      }
    }
    .confirmationDialog("Trip options", isPresented: $showTripActionDialog, titleVisibility: .visible) {
      if session.phase == .live {
        Button("Pause trip") {
          session.pause()
        }
      } else if session.phase == .paused {
        Button("Resume trip") {
          session.resume()
        }
      }

      if session.phase == .live || session.phase == .paused {
        Button("End trip", role: .destructive) {
          finishTripForReview()
        }
      }

      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Pause tracking, end and review this trip, or keep it going.")
    }
    .onAppear {
      selectedVehicle = store.settings.defaultVehicle
    }
  }

  private var tripButtonColors: [Color] {
    switch session.phase {
    case .live:
      return [OkkleColor.red, Color(red: 0.98, green: 0.30, blue: 0.24)]
    case .paused:
      return [OkkleColor.blue, Color(red: 0.35, green: 0.55, blue: 0.95)]
    case .setup, .summary:
      return [OkkleColor.brand, OkkleColor.brandDark]
    }
  }

  private var tripButtonRingColor: Color {
    switch session.phase {
    case .live:
      return OkkleColor.red.opacity(0.16)
    case .paused:
      return OkkleColor.blue.opacity(0.15)
    case .setup, .summary:
      return OkkleColor.mint
    }
  }

  private var tripButtonShadowColor: Color {
    switch session.phase {
    case .live:
      return OkkleColor.red.opacity(0.28)
    case .paused:
      return OkkleColor.blue.opacity(0.24)
    case .setup, .summary:
      return OkkleColor.brand.opacity(0.32)
    }
  }

  private var tripButtonSubtitle: String {
    switch session.phase {
    case .live:
      return "Tap to end or pause"
    case .paused:
      return "Tap to resume"
    case .summary:
      return "Reviewing"
    case .setup:
      return ""
    }
  }

  private var tripControls: some View {
    HStack(spacing: 12) {
      switch session.phase {
      case .setup:
        Button {
          session.start(vehicle: selectedVehicle)
        } label: {
          Label("Start trip", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(OkkleColor.brand)
      case .live:
        Button {
          session.pause()
        } label: {
          Label("Pause", systemImage: "pause.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
          showTripActionDialog = true
        } label: {
          Label("End", systemImage: "stop.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(OkkleColor.red)
      case .paused:
        Button {
          session.resume()
        } label: {
          Label("Resume", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(OkkleColor.brand)

        Button(role: .destructive) {
          showTripActionDialog = true
        } label: {
          Label("End", systemImage: "stop.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      case .summary:
        EmptyView()
      }
    }
    .font(.system(size: 16, weight: .bold))
  }

  private func finishTripForReview() {
    completedTrip = session.end(store: store)
  }

  private func elapsedLabel(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
  }
}

struct NativeTripMap: View {
  let points: [RoutePoint]
  @State private var region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
    span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
  )

  var body: some View {
    Map(coordinateRegion: $region, annotationItems: Array(points.suffix(1))) { point in
      MapMarker(coordinate: point.coordinate, tint: OkkleColor.brand)
    }
    .onAppear(perform: updateRegion)
    .onChange(of: points) { _ in updateRegion() }
  }

  private func updateRegion() {
    guard let last = points.last else { return }
    region = MKCoordinateRegion(center: last.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
  }
}
