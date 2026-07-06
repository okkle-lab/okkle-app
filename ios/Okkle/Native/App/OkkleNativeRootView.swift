import SwiftUI
import UIKit
enum NativeTab: String, CaseIterable, Hashable {
  case trip
  case log
  case insights
  case records
  case tax

  var label: String {
    switch self {
    case .trip:
      return "Trip"
    case .log:
      return "Log mileage"
    case .insights:
      return "Insights"
    case .records:
      return "Data"
    case .tax:
      return "Reports"
    }
  }

  var symbol: String {
    switch self {
    case .trip:
      return "location.north"
    case .log:
      return "plus.circle.fill"
    case .insights:
      return "sparkles"
    case .records:
      return "archivebox"
    case .tax:
      return "doc.text.magnifyingglass"
    }
  }
}

struct OkkleNativeRootView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @StateObject private var store = OkkleStore.shared
  @ObservedObject private var notificationRouter = NativeNotificationRouter.shared
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared
  @State private var selectedTab: NativeTab = .trip
  @State private var showSettings = false
  private let iCloudAutoSyncTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

  var body: some View {
    Group {
      if store.settings.hasCompletedOnboarding {
        appTabs
      } else {
        NativeOnboardingView(selectedTab: $selectedTab)
      }
    }
    .environmentObject(store)
    .tint(OkkleColor.brand)
    .onAppear {
      NativeAutoTrackEngine.shared.configure(store: store)
      NativePreShiftNotifier.refresh(store: store)
      NativeLoggingReminder.refresh(store: store)
      store.refreshICloudSyncIfNeeded()
      routeWidgetTripRequestIfNeeded()
      routeAutomaticTripIfNeeded()
      routeManualTripStopPromptIfNeeded()
    }
    .sheet(isPresented: Binding(
      get: { notificationRouter.pendingAutoShiftReviewTripID != nil },
      set: { isPresented in
        if !isPresented { notificationRouter.pendingAutoShiftReviewTripID = nil }
      }
    )) {
      if let tripID = notificationRouter.pendingAutoShiftReviewTripID {
        NativeAutoShiftReviewView(tripID: tripID)
          .environmentObject(store)
      }
    }
    .onChange(of: store.settings.autoTrackTrips) { _ in
      NativeAutoTrackEngine.shared.refresh()
      NativePreShiftNotifier.refresh(store: store)
      NativeLoggingReminder.refresh(store: store)
      store.refreshICloudSyncIfNeeded()
    }
    .onChange(of: store.settings.workingDays) { _ in
      NativeAutoTrackEngine.shared.refresh()
      NativePreShiftNotifier.refresh(store: store)
    }
    .onChange(of: store.settings.preShiftAlerts) { _ in
      NativePreShiftNotifier.refresh(store: store)
    }
    .onChange(of: store.settings.loggingReminder) { _ in
      NativeLoggingReminder.refresh(store: store)
    }
    .onChange(of: store.settings.logFrequency) { _ in
      NativeLoggingReminder.refresh(store: store)
    }
    .onChange(of: store.settings.reminderDay) { _ in
      NativeLoggingReminder.refresh(store: store)
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      routeWidgetTripRequestIfNeeded()
      routeAutomaticTripIfNeeded()
      routeManualTripStopPromptIfNeeded()
      NativeAutoTrackEngine.shared.refresh()
      NativePreShiftNotifier.refresh(store: store)
      NativeLoggingReminder.refresh(store: store)
      store.refreshICloudSyncIfNeeded()
    }
    .onReceive(iCloudAutoSyncTimer) { _ in
      store.refreshICloudSyncIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: .nativeTripWidgetActionReceived)) { _ in
      routeWidgetTripRequestIfNeeded()
    }
    .onChange(of: autoTrack.shiftPhase) { _ in
      routeAutomaticTripIfNeeded()
      NativePreShiftNotifier.refresh(store: store)
    }
  }

  private var appTabs: some View {
    Group {
      if usesSidebarNavigation {
        iPadSidebarApp
      } else {
        phoneTabApp
      }
    }
    .id("okkle-main-shell-sidebar-tabs")
    .sheet(isPresented: Binding(
      get: { selectedTab == .log },
      set: { isPresented in
        if !isPresented, selectedTab == .log {
          selectedTab = .trip
        }
      }
    )) {
      NativeLogView(
        initialKind: .mileage,
        allowedKinds: [.mileage],
        title: "Log mileage",
        subtitle: "Add mileage from a previous journey.",
        onClose: {
          selectedTab = .trip
        },
        onViewRecords: {
          selectedTab = .records
        }
      )
      .environmentObject(store)
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showSettings) {
      NativeSettingsView()
        .environmentObject(store)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(36)
    }
  }

  private var usesSidebarNavigation: Bool {
    UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
  }

  private var phoneTabApp: some View {
    TabView(selection: $selectedTab) {
      NativeTripView(selectedTab: $selectedTab)
        .tabItem { Label(NativeTab.trip.label, systemImage: NativeTab.trip.symbol) }
        .tag(NativeTab.trip)
      NativeInsightsView()
        .tabItem { Label(NativeTab.insights.label, systemImage: NativeTab.insights.symbol) }
        .tag(NativeTab.insights)
      NativeRecordsView()
        .tabItem { Label(NativeTab.records.label, systemImage: NativeTab.records.symbol) }
        .tag(NativeTab.records)
      NativeTaxDetailView()
        .tabItem { Label(NativeTab.tax.label, systemImage: NativeTab.tax.symbol) }
        .tag(NativeTab.tax)
    }
    .id("okkle-main-tabs-trip-log-insights-records-tax")
  }

  private var iPadSidebarApp: some View {
    NavigationSplitView {
      NativeLiquidSidebar(
        selectedTab: $selectedTab,
        showSettings: { showSettings = true }
      )
    } detail: {
      tabContent(for: selectedTab)
    }
    .navigationSplitViewStyle(.balanced)
    .background(NativeBackground())
  }

  @ViewBuilder
  private func tabContent(for tab: NativeTab) -> some View {
    switch tab {
    case .trip, .log:
      NativeTripView(selectedTab: $selectedTab)
    case .insights:
      NativeInsightsView()
    case .records:
      NativeRecordsView()
    case .tax:
      NativeTaxDetailView()
    }
  }

  private func routeWidgetTripRequestIfNeeded() {
    guard store.settings.hasCompletedOnboarding else { return }
    if NativeTripWidgetStore.hasPendingAction {
      selectedTab = .trip
    }
  }

  private func routeAutomaticTripIfNeeded() {
    guard store.settings.hasCompletedOnboarding,
          autoTrack.shiftPhase != .idle else { return }
    selectedTab = .trip
  }

  private func routeManualTripStopPromptIfNeeded() {
    guard store.settings.hasCompletedOnboarding, notificationRouter.pendingManualTripStopPrompt else { return }
    notificationRouter.pendingManualTripStopPrompt = false
    selectedTab = .trip
  }
}

private struct NativeLiquidSidebar: View {
  @Binding var selectedTab: NativeTab
  let showSettings: () -> Void

  private let primaryTabs: [NativeTab] = [.trip, .insights, .records, .tax]

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Okkle")
          .font(.system(size: 30, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Courier records")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(OkkleColor.muted)
      }
      .padding(.top, 18)
      .padding(.horizontal, 16)

      VStack(spacing: 8) {
        ForEach(primaryTabs, id: \.self) { tab in
          NativeSidebarTabButton(
            tab: tab,
            isSelected: selectedTab == tab,
            action: { selectedTab = tab }
          )
        }
      }

      Button {
        selectedTab = .log
      } label: {
        NativeSidebarCommandLabel(
          title: NativeTab.log.label,
          symbol: NativeTab.log.symbol,
          tint: OkkleColor.brand
        )
      }
      .buttonStyle(.plain)
      .padding(.top, 4)

      Spacer(minLength: 20)

      Divider()
        .opacity(0.55)

      Button(action: showSettings) {
        NativeSidebarCommandLabel(
          title: "Settings",
          symbol: "person.crop.circle",
          tint: OkkleColor.ink
        )
      }
      .buttonStyle(.plain)
      .padding(.bottom, 8)
    }
    .padding(.horizontal, 14)
    .frame(minWidth: 240, idealWidth: 270, maxWidth: 310, maxHeight: .infinity, alignment: .topLeading)
    .background {
      Rectangle()
        .fill(.ultraThinMaterial)
        .ignoresSafeArea()
    }
  }
}

private struct NativeSidebarTabButton: View {
  let tab: NativeTab
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: tab.symbol)
          .font(.system(size: 17, weight: .bold))
          .frame(width: 24)
        Text(tab.label)
          .font(.system(size: 16, weight: .bold))
        Spacer()
      }
      .foregroundStyle(isSelected ? OkkleColor.brandDark : OkkleColor.ink)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .background { selectedBackground }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  @ViewBuilder
  private var selectedBackground: some View {
    if isSelected {
      if #available(iOS 26.0, *) {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(.regularMaterial)
          .glassEffect(.regular.tint(OkkleColor.brand.opacity(0.18)).interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      } else {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(OkkleColor.brand.opacity(0.14))
      }
    }
  }
}

private struct NativeSidebarCommandLabel: View {
  let title: String
  let symbol: String
  let tint: Color

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 24)
      Text(title)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
      Spacer()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

let nativeOnboardingPlatforms = ["Uber Eats", "Deliveroo", "Just Eat", "Stuart", "Amazon Flex", "Other"]
let nativeDeliveryServiceOptions = nativeOnboardingPlatforms.filter { $0 != "Other" }

func nativePlatformSymbol(_ platform: String) -> String {
  switch platform {
  case "Uber Eats": return "bag.fill"
  case "Deliveroo": return "takeoutbag.and.cup.and.straw.fill"
  case "Just Eat": return "fork.knife"
  case "Stuart": return "shippingbox.fill"
  case "Amazon Flex": return "cube.box.fill"
  default: return "plus.circle.fill"
  }
}
