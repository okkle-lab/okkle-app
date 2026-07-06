import SwiftUI
import UIKit
enum NativeTab: String, CaseIterable, Hashable {
  case trip
  case log
  case insights
  case records
  case tax
}

struct OkkleNativeRootView: View {
  @StateObject private var store = OkkleStore.shared
  @ObservedObject private var notificationRouter = NativeNotificationRouter.shared
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared
  @State private var selectedTab: NativeTab = .trip

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
      NativeAutoTrackEngine.shared.refresh()
      NativePreShiftNotifier.refresh(store: store)
      NativeLoggingReminder.refresh(store: store)
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
    TabView(selection: $selectedTab) {
      NativeTripView(selectedTab: $selectedTab)
        .tabItem { Label("Trip", systemImage: "location.north") }
        .tag(NativeTab.trip)
      NativeInsightsView()
        .tabItem { Label("Insights", systemImage: "sparkles") }
        .tag(NativeTab.insights)
      NativeRecordsView()
        .tabItem { Label("Data", systemImage: "archivebox") }
        .tag(NativeTab.records)
      NativeTaxDetailView()
        .tabItem { Label("Reports", systemImage: "doc.text.magnifyingglass") }
        .tag(NativeTab.tax)
    }
    .id("okkle-main-tabs-trip-log-insights-records-tax")
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
