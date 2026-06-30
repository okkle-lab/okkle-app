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
  @Environment(\.colorScheme) private var colorScheme
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var session: NativeTripSession
  @State private var selectedVehicle: NativeVehicle = .car
  @State private var completedTrip: NativeTrip?
  @State private var infoCard = 0

  init(session: NativeTripSession = .shared) {
    self.session = session
  }

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
    // Keep the tab bar visible during tracking so the driver can switch tabs;
    // the shared session keeps recording in the background and the live map is
    // still here when they come back to the Trip tab.
    .toolbar(.visible, for: .tabBar)
  }

  private var setupScreen: some View {
    NativeScreen(title: "Trip", subtitle: "Track GPS miles for HMRC mileage relief.") {
      VStack(spacing: 18) {
        Spacer(minLength: 44)

        startTripButton

        vehicleSelector

        if let message = session.permissionMessage {
          Label(message, systemImage: "location.slash")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(OkkleColor.red)
            .multilineTextAlignment(.center)
            .padding(12)
            .background(OkkleColor.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 10)
        }

        Spacer(minLength: 72)
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: max(460, UIScreen.main.bounds.height * 0.58), alignment: .center)
    }
  }

  private var vehicleSelector: some View {
    Menu {
      ForEach(NativeVehicle.allCases) { vehicle in
        Button {
          selectedVehicle = vehicle
        } label: {
          Label(vehicle.label, systemImage: vehicle.symbol)
        }
      }
    } label: {
      HStack(spacing: 10) {
        Image(systemName: selectedVehicle.symbol)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(OkkleColor.brand)
        Text(selectedVehicle.label)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(OkkleColor.muted)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .background(.regularMaterial, in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .tint(OkkleColor.brand)
    .accessibilityLabel("Vehicle")
    .accessibilityValue(selectedVehicle.label)
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
        NativeRouteMapView(points: session.points, showsEndMarker: completedTrip != nil)
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
    .foregroundStyle(trackingPrimaryText)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(trackingGlassMaterial, in: Capsule())
    .background(trackingGlassTint, in: Capsule())
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
            .foregroundStyle(trackingPrimaryText)
            .minimumScaleFactor(0.62)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 6) {
          Text("Elapsed")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(trackingSecondaryText)
          Text(elapsedLabel(session.elapsed))
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(trackingPrimaryText)
        }
      }

      trackingInfoCarousel

      if session.points.isEmpty {
        Label("Waiting for GPS signal. Your route will draw here once location points arrive.", systemImage: "location.magnifyingglass")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(trackingSecondaryText)
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
    .background(trackingGlassMaterial, in: trackingPanelShape)
    .background(trackingPanelTint, in: trackingPanelShape)
    .overlay {
      trackingPanelShape
        .fill(trackingPanelSheen)
        .allowsHitTesting(false)
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

  // Swipe between the live deduction and this week's league goal.
  private var trackingInfoCarousel: some View {
    let fixture = NativeSeasonEngine.fixture(store: store)
    let division = NativeSeasonEngine.snapshot(store: store).division
    return VStack(spacing: 8) {
      TabView(selection: $infoCard) {
        trackingDeductionRow.tag(0)
        trackingLeagueRow(fixture: fixture, division: division).tag(1)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .frame(height: 78)
      HStack(spacing: 6) {
        ForEach(0..<2, id: \.self) { index in
          Capsule()
            .fill(infoCard == index ? trackingPrimaryText : trackingSecondaryText.opacity(0.35))
            .frame(width: infoCard == index ? 16 : 6, height: 6)
            .animation(.easeInOut(duration: 0.2), value: infoCard)
        }
      }
    }
  }

  // This week's league goal vs your past self, in the division's colours.
  private func trackingLeagueRow(fixture: NativeFixture, division: NativeDivision) -> some View {
    let target = max(1, Int(fixture.weeklyTarget.rounded()))
    let saved = Int(fixture.yourBanked.rounded())
    let toWin = max(0, Int((fixture.weeklyTarget - fixture.yourBanked).rounded(.up)))
    let won = fixture.pointsThisWeek == 3
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Image(systemName: won ? "checkmark.seal.fill" : "bolt.fill")
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(won ? OkkleColor.brand : division.accent)
          .frame(width: 36, height: 36)
          .background(division.accent.opacity(0.16), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(won ? "Week won — keep banking" : "£\(toWin) more to win this week")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(trackingPrimaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          Text("vs \(fixture.opponent)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(trackingSecondaryText)
        }
        Spacer(minLength: 8)
        Text("£\(saved) / £\(target)")
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .foregroundStyle(trackingPrimaryText)
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(trackingSecondaryText.opacity(0.18))
          Capsule()
            .fill(division.gradient)
            .frame(width: max(6, geo.size.width * fixture.progressToTarget))
        }
      }
      .frame(height: 6)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .background(trackingInsetTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
          .foregroundStyle(trackingPrimaryText)
        Text("HMRC mileage relief")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(trackingSecondaryText)
      }

      Spacer(minLength: 12)

      Text(gbp(store.calcDeduction(miles: session.miles, vehicle: session.vehicle), whole: true))
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .foregroundStyle(trackingPrimaryText)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .background(trackingInsetTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

  private var trackingGlassMaterial: Material {
    colorScheme == .dark ? .ultraThinMaterial : .regularMaterial
  }

  private var trackingPrimaryText: Color {
    colorScheme == .dark ? .white : OkkleColor.ink
  }

  private var trackingSecondaryText: Color {
    colorScheme == .dark ? .white.opacity(0.66) : OkkleColor.muted
  }

  private var trackingGlassTint: Color {
    colorScheme == .dark ? Color.black.opacity(0.30) : Color.white.opacity(0.06)
  }

  private var trackingPanelTint: Color {
    colorScheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.10)
  }

  private var trackingInsetTint: Color {
    colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.08)
  }

  private var trackingPanelSheen: LinearGradient {
    let colors: [Color] = colorScheme == .dark
      ? [.white.opacity(0.08), .white.opacity(0.025), .clear]
      : [.white.opacity(0.36), .white.opacity(0.10), .clear]
    return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
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
