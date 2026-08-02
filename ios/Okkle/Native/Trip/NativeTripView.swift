import MapKit
import SwiftUI
import UIKit

/// Reports the live-tracking bottom panel's actual rendered height, since it
/// varies with content (permission message, action buttons) — used to keep
/// the map's auto-fit region from hiding the current position under it.
private struct NativeTrackingPanelHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

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
  @Environment(\.nativeUsesSidebarNavigation) private var nativeUsesSidebarNavigation
  @Environment(\.nativeSidebarAvoidanceInset) private var nativeSidebarAvoidanceInset
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var session: NativeTripSession
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared
  @Binding private var selectedTab: NativeTab
  @State private var selectedVehicle: NativeVehicle = .car
  @State private var completedTrip: NativeTrip?
  @State private var infoCard = 0
  @State private var showProfile = false
  @State private var now = Date()
  // Reasonable pre-measurement default (roughly matches the panel's usual
  // height) so the very first map layout isn't unpadded before the real
  // height reports back.
  @State private var trackingPanelHeight: CGFloat = 260
  // Manually managed (not a stored/autoconnected Combine timer) so it can
  // actually stop firing when no trip is being tracked or reviewed, rather
  // than waking up every 5s for the app's whole foreground lifetime.
  @State private var trackingTimer: Timer?
  @State private var projectedShift = NativeShiftInsights.empty

  private var insightProjectionRevision: String {
    NativeInsightInput(visits: autoTrack.visits, store: store).revision
  }

  init(session: NativeTripSession = .shared, selectedTab: Binding<NativeTab> = .constant(.trip)) {
    self.session = session
    self._selectedTab = selectedTab
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
    .task(id: insightProjectionRevision) {
      guard store.settings.insightsEnabled else {
        projectedShift = .empty
        return
      }
      let input = NativeInsightInput(visits: autoTrack.visits, store: store)
      projectedShift = await NativeInsightsProjector.shared.project(input).shift
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
        Text("\(miles(completedTrip.miles)) with \(nativeMoney(completedTrip.deduction, currencyCode: completedTrip.displayCurrencyCode, whole: true)) deduction.")
      }
    }
    .alert("Still tracking this trip?", isPresented: Binding(
      get: { session.stopPromptRequested && completedTrip == nil && session.phase == .live },
      set: { isPresented in
        if !isPresented {
          session.dismissStopPrompt()
        }
      }
    )) {
      Button("Continue tracking", role: .cancel) {
        session.dismissStopPrompt()
      }
      Button("Stop trip") {
        session.dismissStopPrompt()
        finishTripForReview()
      }
      Button("Auto-complete trips") {
        store.settings.manualTripAutoComplete = true
        session.dismissStopPrompt()
        finishTripForReview()
      }
    } message: {
      Text("You've been in one place for a while. Stop now, keep tracking, or let Okkle auto-complete stopped manual trips next time.")
    }
    .onAppear {
      selectedVehicle = store.settings.defaultVehicle
      now = Date()
      applyWidgetRequestIfNeeded()
      if completedTrip == nil, session.phase == .summary {
        completedTrip = session.tripForReview(store: store)
      }
      updateTrackingTimer(active: shouldShowTrackingMap)
    }
    .onDisappear {
      trackingTimer?.invalidate()
      trackingTimer = nil
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      applyWidgetRequestIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: .nativeTripWidgetActionReceived)) { _ in
      applyWidgetRequestIfNeeded()
    }
    .onChange(of: shouldShowTrackingMap) { active in
      updateTrackingTimer(active: active)
    }
    // Tracking continues in the session object, so keep normal app navigation
    // available while this view is showing the live map.
    .toolbar(.visible, for: .tabBar)
  }

  private func updateTrackingTimer(active: Bool) {
    guard active else {
      trackingTimer?.invalidate()
      trackingTimer = nil
      return
    }
    guard trackingTimer == nil else { return }
    let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
      Task { @MainActor in now = Date() }
    }
    timer.tolerance = 1
    trackingTimer = timer
  }

  private var setupScreen: some View {
    NavigationStack {
      GeometryReader { proxy in
        ZStack {
          tripStartBackground
            .ignoresSafeArea()

          if usesCompactStartLayout(proxy) {
            compactStartLayout(proxy)
          } else {
            regularStartLayout(proxy)
          }
        }
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        if !nativeUsesSidebarNavigation {
          ToolbarItem(placement: .topBarTrailing) {
            NativeProfileToolbarButton {
              showProfile = true
            }
          }
        }
      }
      .sheet(isPresented: $showProfile) {
        NativeSettingsView()
          .presentationDetents([.large])
          .presentationDragIndicator(.hidden)
          .presentationCornerRadius(36)
      }
    }
  }

  private func usesCompactStartLayout(_ proxy: GeometryProxy) -> Bool {
    proxy.size.height < 560
  }

  private func regularStartLayout(_ proxy: GeometryProxy) -> some View {
    let centerY = proxy.size.height * 0.45

    return ZStack {
      Text("Tap to Record")
        .font(.system(size: 30, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .position(x: proxy.size.width / 2, y: centerY - 166)

      startTripButton()
        .position(x: proxy.size.width / 2, y: centerY)

      vehicleSelector
        .position(x: proxy.size.width / 2, y: centerY + 176)

      if nativeUsesSidebarNavigation {
        VStack {
          Spacer()
          missedTripPanel
            .frame(maxWidth: 620)
            .padding(.horizontal, 18)
            .padding(.bottom, max(proxy.safeAreaInsets.bottom + 18, 24))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        missedTripPanel
          .padding(.horizontal, 18)
          .position(x: proxy.size.width / 2, y: proxy.size.height - proxy.safeAreaInsets.bottom - (proxy.size.height * 0.05) + 56)
      }

      if let message = session.permissionMessage {
        permissionMessage(message, maxWidth: proxy.size.width - 36)
          .position(x: proxy.size.width / 2, y: min(proxy.size.height - proxy.safeAreaInsets.bottom - 148, centerY + 258))
      }
    }
  }

  private func compactStartLayout(_ proxy: GeometryProxy) -> some View {
    let buttonSize = min(max(proxy.size.height * 0.42, 132), 174)
    let horizontalPadding: CGFloat = proxy.size.width < 760 ? 20 : 34

    return HStack(spacing: proxy.size.width < 760 ? 18 : 30) {
      VStack(spacing: 14) {
        Text("Tap to Record")
          .font(.system(size: 24, weight: .heavy, design: .rounded))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.82)

        startTripButton(size: buttonSize)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      VStack(spacing: 12) {
        vehicleSelector

        missedTripPanel

        if let message = session.permissionMessage {
          permissionMessage(message, maxWidth: 360)
        }
      }
      .frame(width: min(360, max(260, proxy.size.width * 0.42)))
    }
    .padding(.horizontal, horizontalPadding)
    .padding(.top, proxy.safeAreaInsets.top + 8)
    .padding(.bottom, proxy.safeAreaInsets.bottom + 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func permissionMessage(_ message: String, maxWidth: CGFloat) -> some View {
    Label(message, systemImage: "location.slash")
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(.white)
      .multilineTextAlignment(.center)
      .padding(12)
      .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .frame(maxWidth: maxWidth)
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
          .foregroundStyle(.white)
        Text(selectedVehicle.label)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(.white)
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.white.opacity(0.72))
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .background(Color.white.opacity(0.16), in: Capsule())
      .overlay {
        Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .tint(OkkleColor.brand)
    .accessibilityLabel("Vehicle")
      .accessibilityValue(selectedVehicle.label)
  }

  private var missedTripPanel: some View {
    Button {
      selectedTab = .log
    } label: {
      HStack(spacing: 14) {
        Image(systemName: "clock.arrow.circlepath")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        VStack(alignment: .leading, spacing: 3) {
          Text("Log mileage")
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
          Text("From a previous journey")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(.white.opacity(0.76))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
      }
      .shadow(color: Color.black.opacity(0.18), radius: 22, y: 10)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Log mileage from a previous journey")
  }

  @ViewBuilder
  private func startTripButton(size: CGFloat = 236) -> some View {
    if #available(iOS 26.0, *) {
      Button {
        session.start(vehicle: selectedVehicle)
      } label: {
        nativeStartTripButtonFace(size: size)
      }
      .buttonStyle(.plain)
      .shadow(color: Color.black.opacity(0.22), radius: 34, y: 18)
      .shadow(color: OkkleColor.brand.opacity(0.30), radius: 24)
    } else {
      Button {
        session.start(vehicle: selectedVehicle)
      } label: {
        startTripButtonFace(size: size)
      }
      .buttonStyle(.plain)
      .shadow(color: Color.black.opacity(0.22), radius: 34, y: 18)
      .shadow(color: OkkleColor.brand.opacity(0.30), radius: 24)
    }
  }

  @available(iOS 26.0, *)
  private func nativeStartTripButtonFace(size: CGFloat) -> some View {
    startTripButtonFace(size: size)
      .glassEffect(.regular.tint(OkkleColor.brand.opacity(0.26)).interactive(), in: Circle())
  }

  private func startTripButtonFace(size: CGFloat) -> some View {
    ZStack {
      Circle()
        .fill(startButtonFill)

      Circle()
        .fill(startButtonDepthGlow)
        .blendMode(.screen)

      Circle()
        .stroke(startButtonRim, lineWidth: 1.6)

      Circle()
        .stroke(Color.white.opacity(0.34), lineWidth: 0.7)
        .padding(7)

      Image(systemName: "location.north.fill")
        .font(.system(size: size * 0.32, weight: .heavy))
        .foregroundStyle(.white)
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .contentShape(Circle())
  }

  private var startButtonHighlight: Color {
    Color(red: 0.10, green: 0.70, blue: 0.61)
  }

  private var startButtonFill: LinearGradient {
    LinearGradient(
      colors: [
        startButtonHighlight,
        OkkleColor.brand,
        Color(red: 0.02, green: 0.42, blue: 0.36),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var startButtonDepthGlow: RadialGradient {
    RadialGradient(
      colors: [
        Color.white.opacity(0.24),
        Color.white.opacity(0.08),
        Color.clear,
        Color.black.opacity(0.22),
      ],
      center: .topLeading,
      startRadius: 10,
      endRadius: 230
    )
  }

  private var startButtonRim: LinearGradient {
    LinearGradient(
      colors: [
        Color.white.opacity(0.74),
        Color.white.opacity(0.18),
        Color.black.opacity(0.18),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var tripStartBackground: LinearGradient {
    LinearGradient(
      colors: [
        Color(red: 0.07, green: 0.64, blue: 0.55),
        OkkleColor.brand,
        Color(red: 0.02, green: 0.30, blue: 0.26),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  private var trackingMapScreen: some View {
    GeometryReader { proxy in
      let sidebarInset = trackingSidebarAvoidanceInset(for: proxy)

      ZStack(alignment: .bottom) {
        NativeRouteMapView(
          points: trackingPoints,
          showsEndMarker: completedTrip != nil,
          isInteractive: true,
          allowsPanning: false,
          bottomInset: trackingPanelHeight
        )
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
        .padding(.leading, 18 + sidebarInset)
        .padding(.trailing, 18)
        .padding(.top, proxy.safeAreaInsets.top + 12)

        trackingPanel(bottomInset: proxy.safeAreaInsets.bottom, leadingInset: sidebarInset)
          .background(GeometryReader { panelProxy in
            Color.clear.preference(key: NativeTrackingPanelHeightKey.self, value: panelProxy.size.height)
          })
      }
      .background(Color(uiColor: .systemBackground))
      .ignoresSafeArea()
      .onPreferenceChange(NativeTrackingPanelHeightKey.self) { trackingPanelHeight = $0 }
    }
    .transition(.opacity)
  }

  private var trackingStatusBadge: some View {
    HStack(spacing: 10) {
      Label(trackingStatusTitle, systemImage: trackingStatusSymbol)
        .font(.system(size: 14, weight: .bold))
      Spacer()
      Text(trackingVehicle.label)
        .font(.system(size: 13, weight: .semibold))
      Button {
        selectedTab = .insights
      } label: {
        Image(systemName: "chevron.down")
          .font(.system(size: 13, weight: .bold))
          .frame(width: 28, height: 28)
          .background(Color.primary.opacity(0.08), in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Minimize tracking")
    }
    .foregroundStyle(trackingPrimaryText)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(trackingGlassMaterial, in: Capsule())
    .background(trackingGlassTint, in: Capsule())
    .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
  }

  private func trackingPanel(bottomInset: CGFloat, leadingInset: CGFloat = 0) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 6) {
          Text(trackingStatusTitle)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(trackingStatusColor)
          if isAutomaticTrackingVisible {
            Text(automaticTrackingDetail)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(trackingSecondaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
          Text(miles(trackingMiles))
            .font(.system(size: 42, weight: .heavy, design: .rounded))
            .foregroundStyle(trackingPrimaryText)
            .minimumScaleFactor(0.62)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 6) {
          Text("Elapsed")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(trackingSecondaryText)
          Text(elapsedLabel(trackingElapsed))
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(trackingPrimaryText)
        }
      }

      trackingInfoCarousel

      if trackingPoints.isEmpty {
        Label("Waiting for GPS signal. Your route will draw here once location points arrive.", systemImage: "location.magnifyingglass")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(trackingSecondaryText)
      }

      if let message = trackingPermissionMessage {
        Label(message, systemImage: "location.slash")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.red)
          .padding(12)
          .background(OkkleColor.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }

      if completedTrip == nil {
        trackingActionButtons
          .frame(maxWidth: nativeUsesSidebarNavigation ? 680 : .infinity)
          .frame(maxWidth: .infinity, alignment: .center)
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
    .padding(.leading, leadingInset)
    .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  private func trackingSidebarAvoidanceInset(for proxy: GeometryProxy) -> CGFloat {
    guard nativeUsesSidebarNavigation else { return 0 }
    let minimumReadableWidth: CGFloat = 500
    let maximumInset = max(0, proxy.size.width - minimumReadableWidth)
    return min(nativeSidebarAvoidanceInset, maximumInset)
  }

  private var trackingPanelShape: NativeTopRoundedRectangle {
    NativeTopRoundedRectangle(radius: 38)
  }

  private var trackingActionButtons: some View {
    HStack(spacing: 12) {
      if isAutomaticTrackingVisible {
        automaticTrackingActionButtons
      } else {
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
    }
    .font(.system(size: 16, weight: .bold))
  }

  @ViewBuilder
  private var automaticTrackingActionButtons: some View {
    if autoTrack.shiftPhase == .paused {
      Button {
        autoTrack.resumeCurrentShift()
      } label: {
        Label("Resume", systemImage: "play.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(OkkleColor.brand)
    } else {
      Button {
        autoTrack.pauseCurrentShift()
      } label: {
        Label("Pause", systemImage: "pause.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(OkkleColor.blue)
    }

    Button(role: .destructive) {
      autoTrack.endCurrentShift()
    } label: {
      Label("End", systemImage: "stop.fill")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .tint(OkkleColor.red)
  }

  // Swipe between the live coach and mileage deduction — each its own clean
  // panel, kept to the deduction row's height.
  private var trackingInfoCarousel: some View {
    VStack(spacing: 8) {
      TabView(selection: $infoCard) {
        trackingLiveCoachRow.tag(0)
        trackingDeductionRow.tag(1)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .frame(height: 60)
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

  // Live driving coach: one context-aware nudge based on the time of day vs
  // your own shift pattern, how long you've been out, and the weather.
  private var trackingLiveCoachRow: some View {
    let tip = liveCoachTip()
    return carouselCard {
      HStack(spacing: 12) {
        Image(systemName: tip.symbol)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(tip.color)
          .frame(width: 36, height: 36)
          .background(tip.color.opacity(0.16), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(tip.title)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(trackingPrimaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          Text(tip.detail)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(trackingSecondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        Spacer(minLength: 8)
      }
    }
  }

  private func liveCoachTip() -> (symbol: String, color: Color, title: String, detail: String) {
    let hour = Calendar.current.component(.hour, from: Date())
    if isAutomaticTrackingVisible {
      if autoTrack.shiftPhase == .paused {
        return ("pause.fill", OkkleColor.blue, "Auto trip paused",
                "Resume when you're back on the road.")
      }
      if autoTrack.liveShiftUsesEnhancedTracking {
        return ("car.fill", OkkleColor.brand, "Enhanced automatic tracking",
                "Ends after 5 min disconnected, or when you arrive home.")
      }
      return ("location.north.line.fill", OkkleColor.brand, "Automatically tracking",
              "Based on movement and work schedule.")
    }

    let elapsedHours = trackingElapsed / 3600
    let shift = projectedShift
    let plan = shift.todayPlan
    let area = plan?.zone.flatMap { NativeAreaNamer.shared.name(for: $0) }

    // 1. Safety first — a long stint at the wheel.
    if elapsedHours >= 3 {
      return ("figure.walk.motion", OkkleColor.amber, "Take a breather",
              "You've been out \(Int(elapsedHours))h — stay sharp.")
    }
    // 2. In a predicted lull → good moment to rest.
    if let brk = plan?.breakWindow, brk.startHour <= hour, hour <= brk.endHour {
      return ("cup.and.saucer.fill", OkkleColor.amber, "Quiet spell now",
              "Usually a lull — good time for a break.")
    }
    // 3. In a busy window → stay out where the orders are.
    if plan?.driveWindows.first(where: { $0.startHour <= hour && hour <= $0.endHour }) != nil {
      return ("bolt.fill", OkkleColor.brand, "Busy window now",
              area.map { "Stay around \($0) — your peak." } ?? "This is one of your peaks.")
    }
    // 4. A rush is coming up soon → start heading over.
    if let next = plan?.driveWindows.first(where: { $0.startHour > hour && $0.startHour - hour <= 1 }) {
      return ("location.fill.viewfinder", OkkleColor.brand, "Rush coming up",
              area.map { "Head toward \($0) for \(nativeHourLabel(next.startHour))." } ?? "Get set for \(nativeHourLabel(next.startHour)).")
    }
    // 5. Rain right now → drive steady.
    if let now = NativeWeatherService.shared.today?.at(hour), now.isWet {
      return ("cloud.rain.fill", OkkleColor.blue, "Rain right now",
              "Roads slower — take it steady out there.")
    }
    // 6. Default.
    return ("steeringwheel", trackingSecondaryText, "On the road",
            "Keep it steady — you're doing great.")
  }

  private func carouselCard<V: View>(@ViewBuilder _ content: () -> V) -> some View {
    content()
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(trackingCardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var trackingDeductionRow: some View {
    carouselCard {
      HStack(spacing: 12) {
        Image(systemName: nativeCurrencySymbolName("sterlingsign.arrow.circlepath", currencyCode: trackingCurrencyCode))
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

        Text(nativeMoney(
          store.calcDeduction(miles: trackingMiles, vehicle: trackingVehicle),
          currencyCode: trackingCurrencyCode,
          whole: true
        ))
          .font(.system(size: 20, weight: .bold, design: .rounded))
          .foregroundStyle(trackingPrimaryText)
      }
    }
  }

  private var trackingStatusTitle: String {
    if isAutomaticTrackingVisible {
      if autoTrack.shiftPhase == .paused {
        return "Auto trip paused"
      }
      if autoTrack.liveShiftUsesEnhancedTracking {
        return "Enhanced automatic tracking"
      }
      return "Automatically tracking"
    }
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
    if isAutomaticTrackingVisible {
      if autoTrack.shiftPhase == .stationaryPending || autoTrack.shiftPhase == .paused {
        return "pause.circle.fill"
      }
      if autoTrack.liveShiftUsesEnhancedTracking {
        return "car.fill"
      }
      return "location.north.line.fill"
    }
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
    if isAutomaticTrackingVisible {
      return autoTrack.shiftPhase == .paused ? OkkleColor.blue : OkkleColor.brand
    }
    return session.phase == .paused ? OkkleColor.blue : OkkleColor.brand
  }

  private var automaticTrackingDetail: String {
    if autoTrack.shiftPhase == .paused {
      return "Paused by you. Resume when you're ready."
    }
    if autoTrack.liveShiftUsesEnhancedTracking {
      return "Ends after 5 min disconnected, or when you arrive home."
    }
    return "Based on movement and work schedule."
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

  /// A clean solid card fill for the carousel panels — no material-on-material,
  /// so there's no muddy halo over the glass tracking panel.
  private var trackingCardFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.78)
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
    isTracking || isAutomaticTrackingVisible || completedTrip != nil
  }

  private var isAutomaticTrackingVisible: Bool {
    completedTrip == nil && session.phase == .setup && autoTrack.shiftPhase != .idle
  }

  private var trackingPoints: [RoutePoint] {
    isAutomaticTrackingVisible ? autoTrack.liveShiftPoints : session.points
  }

  private var trackingMiles: Double {
    isAutomaticTrackingVisible ? autoTrack.liveShiftMiles : session.miles
  }

  private var trackingVehicle: NativeVehicle {
    isAutomaticTrackingVisible ? autoTrack.liveShiftVehicle : session.vehicle
  }

  private var trackingCurrencyCode: String {
    nativeTripCurrencyCode(for: trackingPoints) ?? nativeActiveCurrencyCode
  }

  private var trackingElapsed: TimeInterval {
    if isAutomaticTrackingVisible {
      guard let startedAt = autoTrack.liveShiftStartedAt else { return 0 }
      return max(0, now.timeIntervalSince(startedAt))
    }
    return session.elapsed
  }

  private var trackingPermissionMessage: String? {
    isAutomaticTrackingVisible ? nil : session.permissionMessage
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
      if isAutomaticTrackingVisible {
        autoTrack.endCurrentShift()
        NativeTripWidgetStore.markTripEnded()
      } else if session.phase == .live || session.phase == .paused {
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
