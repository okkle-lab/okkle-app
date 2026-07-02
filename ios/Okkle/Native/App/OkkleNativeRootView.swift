import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
enum NativeTab {
  case home
  case log
  case trip
  case insights
  case records
}

struct OkkleNativeRootView: View {
  @StateObject private var store = OkkleStore.shared
  @State private var selectedTab: NativeTab = .home

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
      routeWidgetTripRequestIfNeeded()
    }
    .onChange(of: store.settings.autoTrackTrips) { _ in
      NativeAutoTrackEngine.shared.refresh()
      NativePreShiftNotifier.refresh(store: store)
    }
    .onChange(of: store.settings.preShiftAlerts) { _ in
      NativePreShiftNotifier.refresh(store: store)
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      routeWidgetTripRequestIfNeeded()
      NativePreShiftNotifier.refresh(store: store)
    }
    .onReceive(NotificationCenter.default.publisher(for: .nativeTripWidgetActionReceived)) { _ in
      routeWidgetTripRequestIfNeeded()
    }
  }

  private var appTabs: some View {
    TabView(selection: $selectedTab) {
      NativeHomeView(selectedTab: $selectedTab)
        .tabItem { Label("Home", systemImage: "person.crop.circle") }
        .tag(NativeTab.home)
      NativeLogView(selectedTab: $selectedTab)
        .tabItem { Label("Log", systemImage: "square.and.pencil") }
        .tag(NativeTab.log)
      NativeTripView()
        .tabItem { Label("Trip", systemImage: "location.north") }
        .tag(NativeTab.trip)
      NativeInsightsView()
        .tabItem { Label("Insights", systemImage: "sparkles") }
        .tag(NativeTab.insights)
      NativeRecordsView()
        .tabItem { Label("Records", systemImage: "archivebox") }
        .tag(NativeTab.records)
    }
  }

  private func routeWidgetTripRequestIfNeeded() {
    guard store.settings.hasCompletedOnboarding else { return }
    if NativeTripWidgetStore.hasPendingAction {
      selectedTab = .trip
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
