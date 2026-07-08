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
  @State private var showAddRecord = false
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
      routeManualTripAutoCompletedIfNeeded()
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
      routeAutomaticStartNotificationIfNeeded()
      routeAutomaticTripIfNeeded()
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
    .sheet(isPresented: $showAddRecord) {
      NativeLogView(
        initialKind: .income,
        allowedKinds: NativeLogKind.allCases,
        title: "Add record",
        subtitle: "Add income, expenses, or mileage.",
        onClose: {
          showAddRecord = false
        },
        onViewRecords: {
          showAddRecord = false
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
      NativeSidebar(
        selectedTab: $selectedTab,
        showAddRecord: { showAddRecord = true },
        showSettings: { showSettings = true }
      )
    } detail: {
      tabContent(for: selectedTab)
        .environment(\.nativeUsesSidebarNavigation, true)
    }
    .navigationSplitViewStyle(.balanced)
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

  private func routeAutomaticStartNotificationIfNeeded() {
    guard store.settings.hasCompletedOnboarding, notificationRouter.pendingAutoShiftStarted else { return }
    notificationRouter.pendingAutoShiftStarted = false
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

private struct NativeSidebar: View {
  @Binding var selectedTab: NativeTab
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
            Label(tab.label, systemImage: tab.symbol)
          }
          .foregroundStyle(selectedTab == tab ? OkkleColor.brand : Color.primary)
          .listRowBackground(selectedTab == tab ? OkkleColor.brand.opacity(0.12) : Color.clear)
        }
      }

      Section {
        Button(action: showAddRecord) {
          Label("Add record", systemImage: "plus.circle.fill")
        }
      }
    }
    .navigationTitle("Okkle")
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      Button(action: showSettings) {
        Label("Profile", systemImage: "person.crop.circle")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .background(.bar)
    }
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
