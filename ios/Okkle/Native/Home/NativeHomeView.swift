import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
struct NativeHomeView: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var showMedals = false
  @State private var medalAlert: NativeMedalAchievement?
  @State private var seenMedalKeys = Set<String>()

  var body: some View {
    NativeScreen(
      title: homeGreetingTitle,
      collapsedTitle: store.settings.name.isEmpty ? nil : "Home",
      subtitle: "Your tax saved this year and progress."
    ) {
      NativeGlassCard(cornerRadius: 32) {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Label("Tax saved this year", systemImage: "chart.line.uptrend.xyaxis")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(OkkleColor.brandDark)
            Spacer()
            Text(taxYearLabel(for: store.taxYear))
              .font(.caption.weight(.semibold))
              .foregroundStyle(OkkleColor.muted)
          }
          Text(headlineGbp(store.taxSaved))
            .font(.system(size: 58, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
            .minimumScaleFactor(0.55)
          Text("From \(miles(store.yearMiles)) and \(gbp(store.yearMileageDeduction, whole: true)) of mileage deductions.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
          ProgressView(value: min(1, store.yearMiles / 10_000))
            .tint(OkkleColor.brand)
          mileageBandScale
        }
      }

      HStack(spacing: 12) {
        NativeMetricTile(title: "Mileage", value: miles(store.yearMiles), symbol: "road.lanes")
        NativeMetricTile(title: "Earnings", value: gbp(store.yearIncome, whole: true), symbol: "sterlingsign.circle.fill", color: .green)
      }

      NativeSectionTitle(title: "Progress", symbol: "sparkles")
      NativeGlassCard {
        VStack(alignment: .leading, spacing: 16) {
          progressRow(
            "First 10k mileage band",
            value: min(1, store.yearMiles / 10_000),
            trailing: "\(Int(min(10_000, store.yearMiles)).formatted()) / 10,000 mi",
            showsMileageScale: true
          )
          progressRow("Records logged", value: min(1, Double(store.records.count) / 24), trailing: "\(store.records.count) entries")
          progressRow("Trips tracked", value: min(1, Double(store.trips.count) / 20), trailing: "\(store.trips.count) trips")
          NativeMedalPreviewCard(achievements: NativeMedalEngine.achievements(store: store)) {
            showMedals = true
          }
        }
      }

      NativeSectionTitle(title: "Recent activity", symbol: "clock")
      if store.history.isEmpty {
        NativeEmptyState(symbol: "tray", title: "No records yet", message: "Track a trip or log earnings and expenses to see your history here.")
      } else {
        NativeGlassCard {
          VStack(spacing: 0) {
            ForEach(store.history.prefix(4)) { item in
              NativeHistoryRow(item: item)
              if item.id != store.history.prefix(4).last?.id {
                Divider().padding(.leading, 52)
              }
            }
          }
        }
      }
    }
    .sheet(isPresented: $showMedals) {
      NativeMedalsView()
        .environmentObject(store)
    }
    .overlay {
      if let medalAlert {
        NativeMedalUnlockedOverlay(achievement: medalAlert) {
          withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            self.medalAlert = nil
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showNewMedalIfNeeded()
          }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }
    }
    .onAppear {
      prepareMedalAlerts()
    }
    .onChange(of: store.records) { _ in
      showNewMedalIfNeeded()
    }
    .onChange(of: store.trips) { _ in
      showNewMedalIfNeeded()
    }
  }

  private var homeGreetingTitle: String {
    store.settings.name.isEmpty ? "Home" : "Hi, \(store.settings.name)"
  }

  @ViewBuilder
  private func progressRow(_ title: String, value: Double, trailing: String, showsMileageScale: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Text(trailing)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
      }
      ProgressView(value: value)
        .tint(OkkleColor.brand)
      if showsMileageScale {
        mileageBandScale
      }
    }
  }

  private var mileageBandScale: some View {
    HStack {
      Text("0 mi")
      Spacer()
      Text("5,000 mi")
      Spacer()
      Text("10,000 mi")
    }
    .font(.system(size: 11, weight: .bold))
    .foregroundStyle(OkkleColor.muted)
  }

  private func taxYearLabel(for interval: DateInterval) -> String {
    let start = Calendar.current.component(.year, from: interval.start)
    let end = Calendar.current.component(.year, from: interval.end)
    return "\(start)/\(String(end).suffix(2))"
  }

  private func prepareMedalAlerts() {
    let unlockedKeys = Set(NativeMedalEngine.achievements(store: store).filter(\.unlocked).map(\.key))
    if let savedKeys = UserDefaults.standard.array(forKey: nativeSeenMedalsKey) as? [String] {
      seenMedalKeys = Set(savedKeys)
      showNewMedalIfNeeded()
    } else {
      seenMedalKeys = unlockedKeys
      saveSeenMedalKeys()
    }
  }

  private func showNewMedalIfNeeded() {
    guard medalAlert == nil else { return }
    let unlocked = NativeMedalEngine.achievements(store: store).filter(\.unlocked)
    guard let achievement = unlocked.first(where: { !seenMedalKeys.contains($0.key) }) else { return }
    seenMedalKeys.insert(achievement.key)
    saveSeenMedalKeys()
    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
      medalAlert = achievement
    }
  }

  private func saveSeenMedalKeys() {
    UserDefaults.standard.set(Array(seenMedalKeys).sorted(), forKey: nativeSeenMedalsKey)
  }
}

let nativeSeenMedalsKey = "uk.okkle.native.medals.seen.v1"

let nativeExpenseCategories = [
  "Fuel",
  "Charging",
  "Parking",
  "Phone / data",
  "Insurance",
  "Maintenance / repairs",
  "Tyres",
  "Congestion charge",
  "ULEZ charge",
  "Insulated bag",
  "Waterproof gear",
  "Helmet / safety",
  "Phone mount",
  "App subscription",
]
