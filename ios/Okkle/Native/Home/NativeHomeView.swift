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
  @State private var taxPage = 0
  @ObservedObject private var tripSession = NativeTripSession.shared
  @State private var medalAlert: NativeMedalAchievement?
  @State private var seenMedalKeys = Set<String>()

  // MARK: Body

  var body: some View {
    ZStack {
      NativeBackground()

      // Fixed, non-scrolling dashboard. Top-aligned so the greeting always sits
      // just under the status bar; the Spacer takes any slack at the bottom.
      VStack(spacing: 12) {
        header
        VStack(alignment: .leading, spacing: 8) {
          sectionHeader("THIS TAX YEAR")
          taxCard
            .padding(.horizontal, -20)   // break out of the body inset so the
                                         // paging card can align at 20pt like
                                         // the league/recent cards, with room
                                         // for its shadow inside the page
        }
        VStack(alignment: .leading, spacing: 8) {
          sectionHeader("YOUR CLUB")
          NativeLeagueCard(
            snapshot: NativeSeasonEngine.snapshot(store: store),
            fixture: NativeSeasonEngine.fixture(store: store),
            medals: NativeMedalEngine.achievements(store: store),
            club: NativeSeasonEngine.clubIdentity(store: store)
          ) { showLeague = true }
        }

        recentCard

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    .fullScreenCover(isPresented: $showLeague) {
      NativeLeagueView().environmentObject(store)
    }
    .onAppear { prepareMedalAlerts() }
    .onChange(of: store.records) { _ in showNewMedalIfNeeded() }
    .onChange(of: store.trips) { _ in showNewMedalIfNeeded() }
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(homeGreetingTitle)
          .font(.system(size: 34, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.55)
        Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
        taxDeadlineChip
      }
      Spacer()
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


  // MARK: Tax card (one swipeable card: Tax saved ↔ Set aside)

  // Tax bill split colours — deliberately cool, to stay clear of the league's amber.
  private var incomeTaxColor: Color { OkkleColor.blue }
  private var class4Color: Color { Color(red: 0.48, green: 0.33, blue: 0.80) }

  private var taxCard: some View {
    VStack(spacing: 4) {
      // Two SEPARATE cards (each its own halo) that page past each other.
      TabView(selection: $taxPage) {
        taxSavedPage.tag(0)
        setAsidePage.tag(1)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .frame(height: 186)

      HStack(spacing: 7) {
        ForEach(0..<2, id: \.self) { index in
          Capsule()
            .fill(taxPage == index ? OkkleColor.ink : OkkleColor.muted.opacity(0.3))
            .frame(width: taxPage == index ? 18 : 7, height: 7)
            .animation(.easeInOut(duration: 0.2), value: taxPage)
        }
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var taxSavedPage: some View {
    taxPageShell(kicker: "TAX SAVED THIS YEAR", trailing: taxYearLabel(for: store.taxYear)) {
      Text(headlineGbp(store.taxSaved))
        .font(.system(size: 56, weight: .heavy, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      VStack(alignment: .leading, spacing: 10) {
        progressBar(value: min(1, store.yearMiles / 10_000), color: OkkleColor.brand)
        HStack {
          Text("\(miles(store.yearMiles)) logged")
          Spacer()
          Text(bandCaption)
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(OkkleColor.muted)
      }
    }
  }

  private var setAsidePage: some View {
    let pos = store.taxPosition
    let incomeTax = max(0, pos.incomeTax)
    let class4 = max(0, pos.class4)
    let composed = max(0.0001, incomeTax + class4)
    let dueYear = Calendar.current.component(.year, from: store.taxYear.end) + 1
    return taxPageShell(kicker: "SET ASIDE FOR TAX", trailing: "Due 31 Jan \(String(dueYear))") {
      Text(gbp(pos.totalDue))
        .font(.system(size: 56, weight: .heavy, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      VStack(alignment: .leading, spacing: 10) {
        splitBar(aFraction: incomeTax / composed, aColor: incomeTaxColor, bColor: class4Color)
        HStack(spacing: 0) {
          legendInline(incomeTaxColor, "Income tax", gbp(incomeTax))
          Spacer(minLength: 8)
          legendInline(class4Color, "Class 4 NIC", gbp(class4))
        }
      }
    }
  }

  /// One self-contained tax card (slim green band + white body + its own halo),
  /// inset so the two pages read as separate panels sliding past each other.
  private func taxPageShell<Content: View>(kicker: String, trailing: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
      HStack {
        Text(kicker)
          .font(.system(size: 14, weight: .heavy))
          .tracking(0.5)
          .foregroundStyle(.white)
        Spacer()
        Text(trailing)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.white.opacity(0.9))
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 11)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(LinearGradient(colors: [OkkleColor.bannerDark, OkkleColor.brand], startPoint: .leading, endPoint: .trailing))

      VStack(alignment: .leading, spacing: 16, content: content)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(OkkleColor.card)
    }
    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    // Single soft shadow that fits within the page padding — a bigger/clipped
    // shadow in the paging view is what caused the uneven "shades".
    .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
    .padding(.horizontal, 20)
    .padding(.top, 4)
    .padding(.bottom, 12)
    .contentShape(Rectangle())
    .onTapGesture {
      NotificationCenter.default.post(name: .nativeShowTaxRecords, object: nil)
      selectedTab = .records
    }
  }

  private func progressBar(value: Double, color: Color) -> some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(OkkleColor.line.opacity(0.25))
        Capsule().fill(color).frame(width: geo.size.width * value)
      }
    }
    .frame(height: 8)
  }

  private func splitBar(aFraction: Double, aColor: Color, bColor: Color) -> some View {
    GeometryReader { geo in
      HStack(spacing: 3) {
        Capsule().fill(aColor).frame(width: max(0, geo.size.width * aFraction - 1.5))
        Capsule().fill(bColor)
      }
    }
    .frame(height: 8)
  }

  private var bandCaption: String {
    let remaining = max(0, 10_000 - store.yearMiles)
    return remaining > 0 ? "\(miles(remaining)) to 25p rate" : "Into 25p band"
  }

  private func legendInline(_ color: Color, _ label: String, _ value: String) -> some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 9, height: 9)
      Text(label)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(OkkleColor.muted)
      Text(value)
        .font(.system(size: 14, weight: .heavy))
        .foregroundStyle(OkkleColor.ink)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.8)
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

  /// A live trip in progress takes over → tap goes to Trip. Otherwise the most
  /// recent past activity → tap goes to Records.
  private var recentCard: some View {
    if tripSession.phase == .live || tripSession.phase == .paused {
      return AnyView(liveTripCard)
    } else if let latest = store.history.first {
      return AnyView(pastActivityCard(latest))
    } else {
      return AnyView(EmptyView())
    }
  }

  private var liveTripCard: some View {
    let paused = tripSession.phase == .paused
    let accent = paused ? OkkleColor.amber : OkkleColor.brand
    return VStack(alignment: .leading, spacing: 12) {
      sectionHeader("TRIP IN PROGRESS")
      Button { selectedTab = .trip } label: {
        HStack(spacing: 12) {
          ZStack {
            Circle().fill(accent.opacity(0.15)).frame(width: 44, height: 44)
            Image(systemName: paused ? "pause.fill" : "location.north.fill")
              .font(.system(size: 18, weight: .bold))
              .foregroundStyle(accent)
          }
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
              Text(paused ? "Trip paused" : "Tracking trip")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(OkkleColor.ink)
              Text(paused ? "PAUSED" : "LIVE")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(paused ? OkkleColor.amber : OkkleColor.red, in: Capsule())
            }
            Text("\(miles(tripSession.miles)) tracked so far")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .okkleCard()
      }
      .buttonStyle(.plain)
    }
  }

  private func pastActivityCard(_ latest: NativeHistoryItem) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader("RECENT ACTIVITY")
      Button { selectedTab = .records } label: {
        HStack(spacing: 12) {
          NativeHistoryRow(item: latest)
          Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .okkleCard()
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: Derived values

  private var homeGreetingTitle: String {
    let name = store.settings.name
    guard !name.isEmpty else { return "Home" }
    // Long names get a short greeting so the line still fits.
    return "\(NativeGreeting.word(for: Date(), shortOnly: name.count > 8)), \(name)"
  }

  // MARK: Tax deadline countdown — only shows within a month of a key HMRC date

  /// The significant Self Assessment / HMRC dates, recurring each year.
  private static let taxDays: [(month: Int, day: Int, label: String)] = [
    (1, 31, "Self Assessment deadline"),   // file + balancing payment + 1st payment on account
    (4, 5, "the tax year end"),
    (7, 31, "the payment on account"),     // 2nd payment on account
    (10, 5, "Self Assessment registration"),
    (8, 7, "the MTD Q1 deadline"),
    (11, 7, "the MTD Q2 deadline"),
    (2, 7, "the MTD Q3 deadline"),
    (5, 7, "the MTD Q4 deadline"),
  ]

  /// The soonest upcoming tax date and how many days away it is.
  private var nextTaxDay: (label: String, days: Int)? {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let year = cal.component(.year, from: today)
    var best: (String, Int)?
    for entry in Self.taxDays {
      for candidateYear in [year, year + 1] {
        guard let date = cal.date(from: DateComponents(year: candidateYear, month: entry.month, day: entry.day)), date >= today else { continue }
        let days = cal.dateComponents([.day], from: today, to: date).day ?? 0
        if best == nil || days < best!.1 { best = (entry.label, days) }
        break
      }
    }
    return best
  }

  @ViewBuilder
  private var taxDeadlineChip: some View {
    if let next = nextTaxDay, next.days <= 30 {
      let urgent = next.days <= 7
      let tint = urgent ? OkkleColor.red : OkkleColor.amber
      HStack(spacing: 5) {
        Image(systemName: "calendar")
          .font(.system(size: 11, weight: .bold))
        Text(next.days == 0 ? "\(next.label.prefix(1).uppercased() + next.label.dropFirst()) is today" : "\(next.days) day\(next.days == 1 ? "" : "s") to \(next.label)")
          .font(.system(size: 12, weight: .heavy))
      }
      .foregroundStyle(tint)
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(tint.opacity(0.13), in: Capsule())
      .padding(.top, 4)
    }
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

/// A rotating home greeting — time of day, season, and a mix of British, Aussie
/// and American slang. Stable within the hour (no flicker), varies across the
/// day. Kept light and friendly, never rude.
enum NativeGreeting {
  static func word(for date: Date, shortOnly: Bool = false) -> String {
    let cal = Calendar.current
    let hour = cal.component(.hour, from: date)
    let month = cal.component(.month, from: date)
    let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) ?? 1

    var pool: [String]
    switch hour {
    case 5..<12:  pool = morning
    case 12..<17: pool = afternoon
    case 17..<22: pool = evening
    default:      pool = night
    }
    pool += anytime
    pool += seasonal(month: month)   // doubles as the weather flavour

    if shortOnly {
      let short = pool.filter { $0.count <= 7 }
      pool = short.isEmpty ? ["Hi"] : short
    }

    let index = (dayOfYear &* 24 &+ hour) % pool.count
    return pool[index]
  }

  private static let morning = ["Morning", "Mornin'", "Rise and grind", "Up and at 'em", "Top o' the morning", "Bright and early", "First light"]
  private static let afternoon = ["Afternoon", "Arvo", "Howdy", "Alright", "Ey up", "G'day"]
  private static let evening = ["Evening", "Evenin'", "Knock-off soon?", "Winding down", "Golden hour"]
  private static let night = ["Night owl", "Burning the midnight oil", "Still grafting", "Late one", "Owl mode"]
  private static let anytime = ["Alright", "Wotcha", "Now then", "G'day", "Howdy", "Yo", "Oi oi", "Easy", "What's good", "Howzit", "Good on ya", "Let's get that bread", "Pedal to the metal", "Cha-ching", "Another day, another quid"]

  // Season-appropriate weather flavour (no live feed, so it leans on the season).
  private static func seasonal(month: Int) -> [String] {
    switch month {
    case 12:        return ["Merry one", "Festive grind", "Wrap up warm", "Ho ho, hustle", "Frosty one", "Mind the ice"]
    case 1, 2:      return ["New year, new miles", "Fresh start", "Frosty one", "Bundle up", "Brrr out there", "Mind the ice"]
    case 3, 4, 5:   return ["Fresh one", "Spring in your step", "Bloomin' lovely", "Brolly weather", "April showers", "Grab a brolly"]
    case 6, 7, 8:   return ["Scorcher today", "Sunny side up", "Tan weather", "Cracking day", "Suncream on?", "Sunny one"]
    case 9, 10, 11: return ["Crisp one", "Cosy season", "Sweater weather", "Brolly weather", "Mind the puddles", "Chilly one"]
    default:        return []
    }
  }
}
