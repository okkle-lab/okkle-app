import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
enum NativeTab: String, CaseIterable, Hashable {
  case trip
  case log
  case insights
  case records
  case progress
}

struct OkkleNativeRootView: View {
  @StateObject private var store = OkkleStore.shared
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
      routeWidgetTripRequestIfNeeded()
    }
    .onChange(of: store.settings.autoTrackTrips) { _ in
      NativeAutoTrackEngine.shared.refresh()
      NativePreShiftNotifier.refresh(store: store)
    }
    .onChange(of: store.settings.workingDays) { _ in
      NativeAutoTrackEngine.shared.refresh()
      NativePreShiftNotifier.refresh(store: store)
    }
    .onChange(of: store.settings.preShiftAlerts) { _ in
      NativePreShiftNotifier.refresh(store: store)
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      routeWidgetTripRequestIfNeeded()
      NativeAutoTrackEngine.shared.refresh()
      NativePreShiftNotifier.refresh(store: store)
    }
    .onReceive(NotificationCenter.default.publisher(for: .nativeTripWidgetActionReceived)) { _ in
      routeWidgetTripRequestIfNeeded()
    }
    .alert("Start tracking this trip?", isPresented: Binding(
      get: { autoTrack.pendingStartPrompt },
      set: { isPresented in
        if !isPresented {
          autoTrack.dismissStartPrompt()
        }
      }
    )) {
      Button("Not now", role: .cancel) {
        autoTrack.dismissStartPrompt()
      }
      Button("Start trip") {
        autoTrack.acceptStartPrompt()
        selectedTab = .trip
        NativeTripSession.shared.start(vehicle: store.settings.defaultVehicle)
      }
    } message: {
      Text("Okkle detected that you may be driving. Do you want to start recording this trip?")
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
        .tabItem { Label("Records", systemImage: "archivebox") }
        .tag(NativeTab.records)
      NativeProgressView(selectedTab: $selectedTab)
        .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
        .tag(NativeTab.progress)
    }
    .id("okkle-main-tabs-trip-log-insights-records-progress")
    .fullScreenCover(isPresented: Binding(
      get: { selectedTab == .log },
      set: { isPresented in
        if !isPresented, selectedTab == .log {
          selectedTab = .trip
        }
      }
    )) {
      NativeLogView(selectedTab: $selectedTab)
        .environmentObject(store)
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
