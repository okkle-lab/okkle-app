import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision

private struct NativeTopRoundedRectangle: Shape {
  let radius: CGFloat

  func path(in rect: CGRect) -> Path {
    let path = UIBezierPath(
      roundedRect: rect,
      byRoundingCorners: [.topLeft, .topRight],
      cornerRadii: CGSize(width: radius, height: radius)
    )
    return Path(path.cgPath)
  }
}

struct NativeTripView: View {
  @EnvironmentObject private var store: OkkleStore
  @StateObject private var session = NativeTripSession()
  @State private var selectedVehicle: NativeVehicle = .car
  @State private var completedTrip: NativeTrip?

  var body: some View {
    Group {
      if shouldShowTrackingMap {
        trackingMapScreen
      } else {
        setupScreen
      }
    }
    .animation(.spring(response: 0.36, dampingFraction: 0.88), value: session.phase)
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
    .onAppear {
      selectedVehicle = store.settings.defaultVehicle
      applyWidgetRequestIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      applyWidgetRequestIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: .nativeTripWidgetActionReceived)) { _ in
      applyWidgetRequestIfNeeded()
    }
    .toolbar(shouldShowTrackingMap ? .hidden : .visible, for: .tabBar)
  }

  private var setupScreen: some View {
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

          startTripButton

          HStack(spacing: 12) {
            NativeMetricTile(title: "Tax deduction", value: gbp(store.calcDeduction(miles: session.miles, vehicle: selectedVehicle), whole: true), symbol: "sterlingsign.arrow.circlepath")
            NativeMetricTile(title: "Elapsed", value: elapsedLabel(session.elapsed), symbol: "timer", color: OkkleColor.blue)
          }

          if let message = session.permissionMessage {
            Label(message, systemImage: "location.slash")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(OkkleColor.red)
              .padding(12)
              .background(OkkleColor.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
          }
        }
      }
    }
  }

  private var startTripButton: some View {
    ZStack {
      Circle()
        .stroke(OkkleColor.mint, lineWidth: 18)
        .frame(width: 270, height: 270)
      Circle()
        .fill(
          LinearGradient(colors: [OkkleColor.brand, OkkleColor.brandDark], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .frame(width: 222, height: 222)
        .shadow(color: OkkleColor.brand.opacity(0.32), radius: 28, y: 20)

      VStack(spacing: 8) {
        Image(systemName: "location.north.fill")
          .font(.system(size: 42, weight: .bold))
        Text("Start")
          .font(.system(size: 38, weight: .heavy, design: .rounded))
      }
      .foregroundStyle(.white)
    }
    .frame(maxWidth: .infinity)
    .contentShape(Circle())
    .onTapGesture {
      session.start(vehicle: selectedVehicle)
    }
  }

  private var trackingMapScreen: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        NativeRouteMapView(points: session.points)
          .ignoresSafeArea()
          .overlay(alignment: .top) {
            LinearGradient(
              colors: [.black.opacity(0.24), .black.opacity(0.04), .clear],
              startPoint: .top,
              endPoint: .bottom
            )
            .frame(height: 190 + proxy.safeAreaInsets.top)
            .allowsHitTesting(false)
            .ignoresSafeArea(.container, edges: .top)
          }

        VStack {
          trackingStatusBadge
          Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, proxy.safeAreaInsets.top + 12)
        .allowsHitTesting(false)

        trackingPanel(bottomInset: proxy.safeAreaInsets.bottom)
      }
      .background(Color(uiColor: .systemBackground))
      .ignoresSafeArea()
    }
    .transition(.opacity)
  }

  private var trackingStatusBadge: some View {
    HStack(spacing: 10) {
      Label(trackingStatusTitle, systemImage: trackingStatusSymbol)
        .font(.system(size: 14, weight: .bold))
      Spacer()
      Text(session.vehicle.label)
        .font(.system(size: 13, weight: .semibold))
    }
    .foregroundStyle(OkkleColor.ink)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: Capsule())
    .overlay {
      Capsule()
        .stroke(Color(uiColor: .separator).opacity(0.32), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
  }

  private func trackingPanel(bottomInset: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 6) {
          Text(trackingStatusTitle)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(trackingStatusColor)
          Text(miles(session.miles))
            .font(.system(size: 42, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.62)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 6) {
          Text("Elapsed")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
          Text(elapsedLabel(session.elapsed))
            .font(.system(size: 24, weight: .bold, design: .rounded))
        }
      }

      trackingDeductionRow

      if session.points.isEmpty {
        Label("Waiting for GPS signal. Your route will draw here once location points arrive.", systemImage: "location.magnifyingglass")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
      }

      if let message = session.permissionMessage {
        Label(message, systemImage: "location.slash")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.red)
          .padding(12)
          .background(OkkleColor.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }

      if completedTrip == nil {
        trackingActionButtons
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 18)
    .padding(.bottom, 16 + bottomInset)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: trackingPanelShape)
    .overlay {
      trackingPanelShape
        .fill(
          LinearGradient(
            colors: [.white.opacity(0.36), .white.opacity(0.10), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
    .overlay {
      trackingPanelShape
        .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  private var trackingPanelShape: NativeTopRoundedRectangle {
    NativeTopRoundedRectangle(radius: 38)
  }

  private var trackingActionButtons: some View {
    HStack(spacing: 12) {
      if session.phase == .live {
        Button {
          session.pause()
        } label: {
          Label("Pause", systemImage: "pause.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(OkkleColor.blue)
      } else {
        Button {
          session.resume()
        } label: {
          Label("Resume", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(OkkleColor.brand)
      }

      Button(role: .destructive) {
        finishTripForReview()
      } label: {
        Label("End", systemImage: "stop.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(OkkleColor.red)
    }
    .font(.system(size: 16, weight: .bold))
  }

  private var trackingDeductionRow: some View {
    HStack(spacing: 12) {
      Image(systemName: "sterlingsign.arrow.circlepath")
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(.green)
        .frame(width: 36, height: 36)
        .background(.green.opacity(0.14), in: Circle())

      VStack(alignment: .leading, spacing: 2) {
        Text("Deduction")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
        Text("HMRC mileage relief")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
      }

      Spacer(minLength: 12)

      Text(gbp(store.calcDeduction(miles: session.miles, vehicle: session.vehicle), whole: true))
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
    }
  }

  private var trackingStatusTitle: String {
    switch session.phase {
    case .live:
      return "Tracking trip"
    case .paused:
      return "Trip paused"
    case .setup, .summary:
      return completedTrip == nil ? "Trip" : "Review trip"
    }
  }

  private var trackingStatusSymbol: String {
    switch session.phase {
    case .live:
      return "location.north.fill"
    case .paused:
      return "pause.circle.fill"
    case .setup, .summary:
      return completedTrip == nil ? "location" : "checkmark.circle.fill"
    }
  }

  private var trackingStatusColor: Color {
    session.phase == .paused ? OkkleColor.blue : OkkleColor.brand
  }

  private var isTracking: Bool {
    session.phase == .live || session.phase == .paused
  }

  private var shouldShowTrackingMap: Bool {
    isTracking || completedTrip != nil
  }

  private func finishTripForReview() {
    completedTrip = session.end(store: store)
  }

  private func applyWidgetRequestIfNeeded() {
    guard let action = NativeTripWidgetStore.consumePendingAction() else { return }
    switch action {
    case .start:
      if session.phase == .setup || session.phase == .summary {
        selectedVehicle = store.settings.defaultVehicle
        session.start(vehicle: selectedVehicle)
      } else if session.phase == .paused {
        session.resume()
      }
    case .end:
      if session.phase == .live || session.phase == .paused {
        finishTripForReview()
      } else {
        NativeTripWidgetStore.markTripEnded()
      }
    }
  }

  private func elapsedLabel(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
  }
}
