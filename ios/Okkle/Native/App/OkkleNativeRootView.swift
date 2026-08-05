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
  @ObservedObject private var tripSession = NativeTripSession.shared
  @State private var selectedTab: NativeTab = .trip
  @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
  @State private var showSettings = false
  @State private var showAddRecord = false
  @State private var hasPresentedCurrentAutomaticTrip = false
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
      // Both of these can trigger a system permission prompt (location,
      // notifications) the moment their guard conditions are met — which
      // defaults alone already satisfy before onboarding has shown the
      // driver why. Waiting for onboarding to finish first (see onChange
      // below for the moment it actually does) keeps every permission ask
      // behind an explanation screen instead of firing cold on launch.
      if store.settings.hasCompletedOnboarding {
        NativeAutoTrackEngine.shared.configure(store: store)
        NativePreShiftNotifier.refresh(store: store)
        NativeLoggingReminder.refresh(store: store)
      }
      store.refreshICloudSyncIfNeeded()
      routeWidgetTripRequestIfNeeded()
      routeAutomaticTripIfNeeded()
      routeManualTripStopPromptIfNeeded()
      routeManualTripAutoCompletedIfNeeded()
    }
    .onChange(of: store.settings.hasCompletedOnboarding) { completed in
      if completed {
        NativeAutoTrackEngine.shared.configure(store: store)
        NativePreShiftNotifier.refresh(store: store)
        NativeLoggingReminder.refresh(store: store)
      }
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
    .onChange(of: store.settings.autoTrackTrips) { enabled in
      if enabled, !store.settings.enhancedAutoTracking {
        store.settings.enhancedAutoTracking = true
      }
      NativeAutoTrackEngine.shared.refresh()
      NativePreShiftNotifier.refresh(store: store)
      NativeLoggingReminder.refresh(store: store)
      store.refreshICloudSyncIfNeeded()
    }
    .onChange(of: store.settings.enhancedAutoTracking) { _ in
      NativeAutoTrackEngine.shared.refresh()
      store.refreshICloudSyncIfNeeded()
    }
    .onChange(of: store.settings.workingDays) { _ in
      NativeAutoTrackEngine.shared.refresh()
      NativePreShiftNotifier.refresh(store: store)
    }
    .onChange(of: store.settings.preShiftAlerts) { _ in
      NativePreShiftNotifier.refresh(store: store)
    }
    .onChange(of: store.settings.insightsEnabled) { _ in
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
      routeAutomaticStartNotificationIfNeeded()
      routeManualTripStopPromptIfNeeded()
      routeManualTripAutoCompletedIfNeeded()
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
    .onChange(of: notificationRouter.pendingAutoShiftStarted) { _ in
      routeAutomaticStartNotificationIfNeeded()
    }
    .onChange(of: notificationRouter.pendingManualTripStopPrompt) { _ in
      routeManualTripStopPromptIfNeeded()
    }
    .onChange(of: notificationRouter.pendingManualTripAutoCompleted) { _ in
      routeManualTripAutoCompletedIfNeeded()
    }
    .onChange(of: autoTrack.shiftPhase) { phase in
      if phase == .idle {
        hasPresentedCurrentAutomaticTrip = false
      } else if !hasPresentedCurrentAutomaticTrip {
        routeAutomaticTripIfNeeded()
      }
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
        }
      )
      .environmentObject(store)
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
      .nativeIPadPagePresentation()
    }
    .sheet(isPresented: $showAddRecord) {
      NativeLogView(
        initialKind: .income,
        allowedKinds: NativeLogKind.allCases,
        title: "Add record",
        subtitle: "Add income, expenses, or mileage.",
        onClose: {
          showAddRecord = false
        }
      )
      .environmentObject(store)
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
      .nativeIPadPagePresentation()
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
        .badge(isAnyTripActive ? Text("LIVE") : nil)
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

  @ViewBuilder
  private var iPadSidebarApp: some View {
    iPadNavigationSplitView
      .navigationSplitViewStyle(.balanced)
  }

  private var iPadNavigationSplitView: some View {
    NavigationSplitView(columnVisibility: $sidebarVisibility) {
      NativeSidebar(
        selectedTab: $selectedTab,
        isTripActive: isAnyTripActive,
        showAddRecord: { showAddRecord = true },
        showSettings: { showSettings = true }
      )
      .navigationSplitViewColumnWidth(
        min: NativeSidebarMetrics.minimumWidth,
        ideal: NativeSidebarMetrics.idealWidth,
        max: NativeSidebarMetrics.maximumWidth
      )
    } detail: {
      tabContent(for: selectedTab)
        .environment(\.nativeUsesSidebarNavigation, true)
        .environment(\.nativeSidebarAvoidanceInset, sidebarAvoidanceInset)
    }
  }

  private var sidebarAvoidanceInset: CGFloat {
    return sidebarVisibility == .detailOnly ? 0 : NativeSidebarMetrics.avoidanceInset
  }

  private var isAnyTripActive: Bool {
    tripSession.phase == .live || tripSession.phase == .paused || autoTrack.shiftPhase != .idle
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
    hasPresentedCurrentAutomaticTrip = true
    selectedTab = .trip
  }

  private func routeAutomaticStartNotificationIfNeeded() {
    guard store.settings.hasCompletedOnboarding, notificationRouter.pendingAutoShiftStarted else { return }
    notificationRouter.pendingAutoShiftStarted = false
    hasPresentedCurrentAutomaticTrip = true
    selectedTab = .trip
  }

  private func routeManualTripStopPromptIfNeeded() {
    guard store.settings.hasCompletedOnboarding, notificationRouter.pendingManualTripStopPrompt else { return }
    notificationRouter.pendingManualTripStopPrompt = false
    selectedTab = .trip
  }

  private func routeManualTripAutoCompletedIfNeeded() {
    guard store.settings.hasCompletedOnboarding, notificationRouter.pendingManualTripAutoCompleted else { return }
    notificationRouter.pendingManualTripAutoCompleted = false
    selectedTab = .records
  }
}

private enum NativeSidebarMetrics {
  static let minimumWidth: CGFloat = 220
  static let idealWidth: CGFloat = 236
  static let maximumWidth: CGFloat = 264
  static let avoidanceInset: CGFloat = 252
}

private struct NativeSidebar: View {
  @Binding var selectedTab: NativeTab
  let isTripActive: Bool
  let showAddRecord: () -> Void
  let showSettings: () -> Void

  private let primaryTabs: [NativeTab] = [.trip, .insights, .records, .tax]

  var body: some View {
    List {
      Section {
        ForEach(primaryTabs, id: \.self) { tab in
          Button {
            selectedTab = tab
          } label: {
            NativeSidebarRow(
              title: tab.label,
              symbol: tab.symbol,
              isSelected: selectedTab == tab
            )
              .badge(tab == .trip && isTripActive ? Text("LIVE") : nil)
          }
          .buttonStyle(.plain)
          .foregroundStyle(selectedTab == tab ? OkkleColor.brand : Color.primary)
          .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
          .listRowBackground(Color.clear)
        }
      }

      Section {
        Button(action: showAddRecord) {
          NativeSidebarRow(title: "Add record", symbol: "plus.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
        .listRowBackground(Color.clear)
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      Button(action: showSettings) {
        NativeSidebarRow(title: "Profile", symbol: "person.crop.circle")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .padding(.leading, 34)
      .padding(.trailing, 10)
      .padding(.vertical, 2)
      .background(.bar)
    }
  }
}

private struct NativeSidebarRow: View {
  let title: String
  let symbol: String
  var isSelected = false

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .medium))
        .frame(width: 22, alignment: .center)
      Text(title)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(isSelected ? OkkleColor.brand.opacity(0.12) : Color.clear)
    }
    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

/// The delivery apps offered in onboarding, by market. A driver can always add
/// their own via "Other", so this is just the common set for each country.
func nativeOnboardingPlatforms(for country: NativeTaxCountry) -> [String] {
  switch country {
  case .uk: return ["Uber Eats", "Deliveroo", "Just Eat", "Stuart", "Amazon Flex", "Other"]
  case .us: return ["DoorDash", "Uber Eats", "Grubhub", "Instacart", "Amazon Flex", "Other"]
  }
}

/// Every platform Okkle knows by name across all markets — used to decide
/// whether a saved platform is a "custom" one and to seed the record picker,
/// independent of the driver's current country.
let nativeAllKnownPlatforms: [String] = [
  "Uber Eats", "Deliveroo", "Just Eat", "Stuart", "Amazon Flex",
  "DoorDash", "Grubhub", "Instacart",
]

/// Move a driver's selected apps to another market without touching any old
/// trip or income records. Shared apps and genuinely custom apps survive;
/// known apps that only operate in the old list are removed. If that leaves
/// nothing selected, use the new market's first common app as a safe default.
func nativePlatformsAfterCountryChange(_ current: [String], to country: NativeTaxCountry) -> [String] {
  let market = nativeOnboardingPlatforms(for: country).filter { $0 != "Other" }
  let retainedMarketApps = market.filter { candidate in
    current.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
  }
  let customApps = current.filter { platform in
    platform.caseInsensitiveCompare("Other") != .orderedSame &&
      !nativeAllKnownPlatforms.contains { $0.caseInsensitiveCompare(platform) == .orderedSame }
  }
  let migrated = uniqueStrings(retainedMarketApps + customApps)
  return migrated.isEmpty ? Array(market.prefix(1)) : migrated
}

func nativePlatformSymbol(_ platform: String) -> String {
  switch platform {
  case "Uber Eats": return "bag.fill"
  case "Deliveroo": return "takeoutbag.and.cup.and.straw.fill"
  case "Just Eat": return "fork.knife"
  case "Stuart": return "shippingbox.fill"
  case "Amazon Flex", "Instacart": return "cube.box.fill"
  case "DoorDash": return "bag.fill"
  case "Grubhub": return "fork.knife"
  default: return "plus.circle.fill"
  }
}

/// The bundled real app-icon asset for a known platform (sourced from each
/// platform's own official App Store listing), or nil for a custom/"Other"
/// platform, which falls back to `nativePlatformSymbol`'s generic glyph.
func nativePlatformIconAssetName(_ platform: String) -> String? {
  switch platform {
  case "Uber Eats": return "PlatformIcon-UberEats"
  case "Deliveroo": return "PlatformIcon-Deliveroo"
  case "Just Eat": return "PlatformIcon-JustEat"
  case "Stuart": return "PlatformIcon-Stuart"
  case "Amazon Flex": return "PlatformIcon-AmazonFlex"
  case "DoorDash": return "PlatformIcon-DoorDash"
  case "Grubhub": return "PlatformIcon-Grubhub"
  case "Instacart": return "PlatformIcon-Instacart"
  default: return nil
  }
}

/// A platform's real app icon when we have one bundled, falling back to a
/// generic SF Symbol glyph for a custom/"Other" platform. `foregroundStyle`
/// only visibly affects the symbol fallback — a real logo image keeps its
/// own brand colors, which is the point.
struct NativePlatformIcon: View {
  let platform: String

  var body: some View {
    if let assetName = nativePlatformIconAssetName(platform) {
      Image(assetName)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    } else {
      Image(systemName: nativePlatformSymbol(platform))
    }
  }
}
