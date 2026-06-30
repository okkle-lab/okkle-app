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
  @Binding var selectedTab: NativeTab
  @State private var showLeague = false
  @State private var showSettings = false
  @State private var medalAlert: NativeMedalAchievement?
  @State private var seenMedalKeys = Set<String>()

  // MARK: Body

  var body: some View {
    ZStack {
      NativeBackground()

      VStack(spacing: 16) {
        header
        VStack(alignment: .leading, spacing: 12) {
          sectionHeader("THIS TAX YEAR")
          heroCard
          statTiles
        }
        VStack(alignment: .leading, spacing: 12) {
          sectionHeader("YOUR CLUB")
          NativeLeagueCard(
            snapshot: NativeSeasonEngine.snapshot(store: store),
            medals: NativeMedalEngine.achievements(store: store)
          ) { showLeague = true }
        }

        if !store.history.isEmpty {
          recentCard
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 20)
      .padding(.top, 6)
      .padding(.bottom, 10)
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
    .sheet(isPresented: $showSettings) { NativeSettingsView() }
    .sheet(isPresented: $showLeague) {
      NativeLeagueView().environmentObject(store)
    }
    .onAppear { prepareMedalAlerts() }
    .onChange(of: store.records) { _ in showNewMedalIfNeeded() }
    .onChange(of: store.trips) { _ in showNewMedalIfNeeded() }
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(homeGreetingTitle)
          .font(.system(size: 28, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
      }
      Spacer()
      if loggingStreak > 0 {
        Button { showLeague = true } label: { streakPill }
          .buttonStyle(.plain)
      }
      Button { showSettings = true } label: {
        Image(systemName: "gearshape.fill")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .frame(width: 44, height: 44)
          .background(.thinMaterial, in: Circle())
      }
      .accessibilityLabel("Settings")
    }
  }

  private var streakPill: some View {
    HStack(spacing: 5) {
      Image(systemName: "flame.fill")
        .font(.system(size: 13, weight: .bold))
      Text("\(loggingStreak)")
        .font(.system(size: 16, weight: .heavy, design: .rounded))
      Text("day\(loggingStreak == 1 ? "" : "s")")
        .font(.system(size: 12, weight: .bold))
        .opacity(0.8)
    }
    .foregroundStyle(OkkleColor.amber)
    .padding(.horizontal, 12)
    .frame(height: 44)
    .background(OkkleColor.amber.opacity(0.14), in: Capsule())
  }

  // MARK: Hero

  private var heroCard: some View {
    Button { selectedTab = .insights } label: {
      NativeBannerCard(kicker: "TAX SAVED THIS YEAR", trailing: taxYearLabel(for: store.taxYear), cornerRadius: 26) {
        VStack(alignment: .leading, spacing: 12) {
          Text(headlineGbp(store.taxSaved))
            .font(.system(size: 56, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
          VStack(alignment: .leading, spacing: 7) {
            ProgressView(value: min(1, store.yearMiles / 10_000))
              .tint(OkkleColor.brand)
            HStack {
              Text("\(miles(store.yearMiles)) logged")
              Spacer()
              Text(bandCaption)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
          }
        }
      }
    }
    .buttonStyle(.plain)
  }

  private var bandCaption: String {
    let remaining = max(0, 10_000 - store.yearMiles)
    return remaining > 0 ? "\(miles(remaining)) to 25p rate" : "Into 25p band"
  }

  // MARK: Stat tiles

  private var statTiles: some View {
    HStack(spacing: 12) {
      Button { selectedTab = .insights } label: {
        NativeMetricTile(title: "Mileage", value: miles(store.yearMiles), symbol: "road.lanes")
      }
      .buttonStyle(.plain)
      Button { selectedTab = .insights } label: {
        NativeMetricTile(title: "Set aside for tax", value: gbp(store.taxPosition.totalDue, whole: true), symbol: "shield.lefthalf.filled", color: OkkleColor.amber)
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: Recent

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .heavy))
      .tracking(0.6)
      .foregroundStyle(OkkleColor.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4)
  }

  private var recentCard: some View {
    let items = Array(store.history.prefix(3))
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        sectionHeader("RECENT ACTIVITY")
        Button { selectedTab = .records } label: {
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
        }
        .buttonStyle(.plain)
      }
      VStack(spacing: 0) {
        ForEach(items) { item in
          Button { selectedTab = .records } label: {
            NativeHistoryRow(item: item).padding(.vertical, 4)
          }
          .buttonStyle(.plain)
          if item.id != items.last?.id {
            Divider().padding(.leading, 52)
          }
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .okkleCard()
    }
  }

  // MARK: Derived values

  private var homeGreetingTitle: String {
    store.settings.name.isEmpty ? "Home" : "Hi, \(store.settings.name)"
  }

  /// Consecutive days (ending today or yesterday) with at least one logged record.
  private var loggingStreak: Int {
    let cal = Calendar.current
    let days = Set(store.records.map { cal.startOfDay(for: $0.date) })
    guard !days.isEmpty else { return 0 }
    var day = cal.startOfDay(for: Date())
    if !days.contains(day) {
      guard let yesterday = cal.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else { return 0 }
      day = yesterday
    }
    var streak = 0
    while days.contains(day) {
      streak += 1
      guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
      day = prev
    }
    return streak
  }

  private func taxYearLabel(for interval: DateInterval) -> String {
    let start = Calendar.current.component(.year, from: interval.start)
    let end = Calendar.current.component(.year, from: interval.end)
    return "\(start)/\(String(end).suffix(2))"
  }

  // MARK: Medal alerts

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
