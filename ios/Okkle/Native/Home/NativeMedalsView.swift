import SwiftUI

enum NativeMedalTier: String, CaseIterable {
  case bronze
  case silver
  case gold
  case special

  var label: String {
    rawValue.capitalized
  }
}

struct NativeMedalAchievement: Identifiable, Equatable {
  let key: String
  let label: String
  let desc: String
  let symbol: String
  let category: String
  let tier: NativeMedalTier
  let unlocked: Bool
  let progress: Double
  let target: Double?
  let value: Double?

  var id: String { key }
}

struct NativeMedalStats {
  var trips: Int
  var miles: Double
  var taxSaved: Double
  var earnings: Double
  var streak: Int
  var hours: Double
  var activeDays: Int
  var bestDayMiles: Double
  var longestTrip: Double
  var platforms: Int
  var nightTrips: Int
  var dawnTrips: Int
  var weekendTrips: Int
  var expenses: Int
  var receipts: Int
}

@MainActor
enum NativeMedalEngine {
  static func achievements(store: OkkleStore) -> [NativeMedalAchievement] {
    let stats = stats(store: store)
    var medals: [NativeMedalAchievement] = []

    medals += tiered(
      prefix: "trips",
      category: "Trips",
      symbol: "location.north.fill",
      value: Double(stats.trips),
      unit: "trips tracked",
      specs: [
        (1, "First trip"), (5, "Five down"), (10, "Getting rolling"), (25, "Quarter ton"),
        (50, "Seasoned rider"), (100, "Centurion"), (150, "Regular"), (200, "Double ton"),
        (250, "Road warrior"), (500, "Veteran"), (750, "Elite"), (1_000, "Legend"),
      ]
    )

    medals += tiered(
      prefix: "miles",
      category: "Miles",
      symbol: "map.fill",
      value: stats.miles,
      unit: "miles logged",
      specs: [
        (50, "First 50"), (100, "Century miles"), (250, "Local legend"), (500, "500 club"),
        (1_000, "Mile marker"), (2_500, "City mapper"), (5_000, "Distance pro"),
        (7_500, "Road master"), (10_000, "Deduction boss"), (15_000, "Mile machine"),
        (20_000, "Atlas"), (25_000, "Marathon year"),
      ]
    )

    medals += tiered(
      prefix: "tax",
      category: "Tax saved",
      symbol: "shield.fill",
      value: stats.taxSaved,
      unit: "saved through mileage",
      money: true,
      specs: [
        (50, "Tax saver"), (100, "Claim starter"), (250, "Smart records"), (500, "Half grand"),
        (1_000, "Four figures"), (1_500, "Sharp claim"), (2_000, "Deduction hero"),
        (2_500, "Quarter shield"), (5_000, "Tax warrior"), (7_500, "Relief rider"),
        (10_000, "Ledger legend"),
      ]
    )

    medals += tiered(
      prefix: "earn",
      category: "Earnings",
      symbol: "sterlingsign.circle.fill",
      value: stats.earnings,
      unit: "logged income",
      money: true,
      specs: [
        (250, "First payout"), (500, "Steady shift"), (1_000, "Four figure pay"),
        (2_500, "Momentum"), (5_000, "Side hustle"), (10_000, "Income engine"),
        (15_000, "Pro courier"), (20_000, "Serious operator"), (25_000, "Top line"),
        (50_000, "Heavy hitter"),
      ]
    )

    medals += tiered(
      prefix: "streak",
      category: "Streaks",
      symbol: "bolt.fill",
      value: Double(stats.streak),
      unit: "day streak",
      specs: [
        (2, "Back to back"), (3, "Three day run"), (5, "Week warmup"), (7, "Full week"),
        (14, "Fortnight"), (21, "Habit forming"), (30, "Monthly rhythm"),
        (50, "Reliable"), (75, "Locked in"), (100, "Hundred days"),
        (150, "Untouchable"), (200, "On fire"), (365, "Year round"),
      ]
    )

    medals += tiered(
      prefix: "hours",
      category: "Hours",
      symbol: "clock.fill",
      value: stats.hours,
      unit: "hours tracked",
      specs: [
        (5, "First shift"), (10, "Double digits"), (25, "Part timer"), (50, "Half century"),
        (100, "Hundred hours"), (250, "Committed"), (500, "Road regular"),
        (1_000, "Time lord"),
      ]
    )

    medals += tiered(
      prefix: "days",
      category: "Active days",
      symbol: "calendar",
      value: Double(stats.activeDays),
      unit: "active days",
      specs: [
        (3, "Third day"), (5, "Working week"), (10, "Ten days"), (25, "Monthly grind"),
        (50, "Fifty days"), (100, "Century days"), (200, "Two hundred"),
        (365, "Every season"),
      ]
    )

    medals += tiered(
      prefix: "bigday",
      category: "Big days",
      symbol: "chart.line.uptrend.xyaxis",
      value: stats.bestDayMiles,
      unit: "miles in one day",
      specs: [
        (15, "Solid day"), (25, "Big day"), (40, "Marathon shift"), (60, "Monster day"),
        (100, "Hundred mile day"),
      ]
    )

    medals += tiered(
      prefix: "longtrip",
      category: "Long trips",
      symbol: "point.topleft.down.curvedto.point.bottomright.up",
      value: stats.longestTrip,
      unit: "miles in one trip",
      specs: [
        (5, "Short hop"), (10, "Across town"), (15, "Long run"), (25, "Distance job"),
        (40, "Epic route"),
      ]
    )

    medals += tiered(
      prefix: "platforms",
      category: "Platforms",
      symbol: "square.grid.2x2.fill",
      value: Double(stats.platforms),
      unit: "platforms logged",
      specs: [
        (2, "Two apps"), (3, "Multi-apper"), (4, "Stacked"), (5, "Platform pro"),
      ]
    )

    medals += tiered(
      prefix: "journey",
      category: "Journeys",
      symbol: "signpost.right.fill",
      value: stats.miles,
      unit: "miles — iconic UK routes",
      specs: [
        (54, "London → Brighton"), (120, "London → Bristol"), (200, "London → Manchester"),
        (330, "London → Edinburgh"), (560, "Cardiff → Inverness"), (874, "Land's End → John o' Groats"),
        (1_407, "Coast to coast, twice"),
      ]
    )

    medals.append(flag(
      key: "night_owl",
      label: "Night owl",
      desc: "Track a trip after 10pm",
      symbol: "moon.stars.fill",
      category: "Special",
      tier: .special,
      done: stats.nightTrips > 0,
      progress: stats.nightTrips > 0 ? 1 : 0
    ))
    medals.append(flag(
      key: "early_bird",
      label: "Early bird",
      desc: "Track a trip before 8am",
      symbol: "sunrise.fill",
      category: "Special",
      tier: .special,
      done: stats.dawnTrips > 0,
      progress: stats.dawnTrips > 0 ? 1 : 0
    ))
    medals.append(flag(
      key: "weekend_warrior",
      label: "Weekend warrior",
      desc: "Track a weekend trip",
      symbol: "sparkles",
      category: "Special",
      tier: .special,
      done: stats.weekendTrips > 0,
      progress: stats.weekendTrips > 0 ? 1 : 0
    ))
    medals.append(flag(
      key: "first_expense",
      label: "Bookkeeper",
      desc: "Log your first expense",
      symbol: "receipt.fill",
      category: "Expenses",
      tier: .bronze,
      done: stats.expenses >= 1,
      progress: Double(stats.expenses)
    ))
    medals.append(flag(
      key: "ten_expenses",
      label: "Diligent",
      desc: "Log 10 expenses",
      symbol: "list.bullet.rectangle.fill",
      category: "Expenses",
      tier: .silver,
      done: stats.expenses >= 10,
      progress: Double(stats.expenses) / 10,
      target: 10,
      value: Double(stats.expenses)
    ))
    medals.append(flag(
      key: "fifty_expenses",
      label: "Meticulous",
      desc: "Log 50 expenses",
      symbol: "checklist",
      category: "Expenses",
      tier: .gold,
      done: stats.expenses >= 50,
      progress: Double(stats.expenses) / 50,
      target: 50,
      value: Double(stats.expenses)
    ))
    medals.append(flag(
      key: "receipt_keeper",
      label: "Receipt keeper",
      desc: "Attach your first receipt photo",
      symbol: "camera.fill",
      category: "Expenses",
      tier: .bronze,
      done: stats.receipts >= 1,
      progress: Double(stats.receipts),
      target: 1,
      value: Double(stats.receipts)
    ))
    medals.append(flag(
      key: "ten_receipts",
      label: "Paper trail",
      desc: "Attach 10 receipt photos",
      symbol: "doc.text.image.fill",
      category: "Expenses",
      tier: .silver,
      done: stats.receipts >= 10,
      progress: Double(stats.receipts) / 10,
      target: 10,
      value: Double(stats.receipts)
    ))

    return medals
  }

  private static func stats(store: OkkleStore) -> NativeMedalStats {
    let calendar = Calendar.current
    let records = store.records
    let trips = store.trips
    let mileageRecords = records.filter { $0.kind == .mileage }
    let incomeRecords = records.filter { $0.kind == .income }
    let expenseRecords = records.filter { $0.kind == .expense }

    var days = Set<Date>()
    var milesByDay: [Date: Double] = [:]
    for trip in trips {
      let day = calendar.startOfDay(for: trip.startedAt)
      days.insert(day)
      milesByDay[day, default: 0] += max(0, trip.miles)
    }
    for record in records {
      days.insert(calendar.startOfDay(for: record.date))
    }
    for record in mileageRecords {
      let day = calendar.startOfDay(for: record.date)
      milesByDay[day, default: 0] += max(0, record.miles ?? 0)
    }

    let tripMiles = trips.reduce(0) { $0 + max(0, $1.miles) }
    let recordMiles = mileageRecords.reduce(0) { $0 + max(0, $1.miles ?? 0) }
    let tripDeduction = trips.reduce(0) { partial, trip in
      partial + (trip.deduction > 0 ? trip.deduction : store.calcDeduction(miles: trip.miles, vehicle: trip.vehicle, date: trip.startedAt))
    }
    let recordDeduction = mileageRecords.reduce(0) { partial, record in
      partial + ((record.deduction ?? 0) > 0 ? (record.deduction ?? 0) : store.calcDeduction(miles: record.miles ?? 0, vehicle: record.vehicle ?? store.settings.defaultVehicle, date: record.date))
    }
    let hours = trips.reduce(0) { partial, trip in
      partial + max(0, trip.endedAt.timeIntervalSince(trip.startedAt) / 3_600)
    }
    let platforms = Set(incomeRecords.compactMap { record -> String? in
      let value = (record.platform ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : value.lowercased()
    })

    return NativeMedalStats(
      trips: trips.count,
      miles: tripMiles + recordMiles,
      taxSaved: (tripDeduction + recordDeduction) * store.settings.incomeBracket.marginalRate(region: store.settings.region),
      earnings: incomeRecords.reduce(0) { $0 + max(0, $1.amount ?? 0) },
      streak: streak(days: days),
      hours: hours,
      activeDays: days.count,
      bestDayMiles: milesByDay.values.max() ?? 0,
      longestTrip: trips.map(\.miles).max() ?? 0,
      platforms: platforms.count,
      nightTrips: trips.filter { calendar.component(.hour, from: $0.startedAt) >= 22 }.count,
      dawnTrips: trips.filter { calendar.component(.hour, from: $0.startedAt) < 8 }.count,
      weekendTrips: trips.filter { calendar.isDateInWeekend($0.startedAt) }.count,
      expenses: expenseRecords.count,
      receipts: expenseRecords.filter { $0.receiptImageData != nil }.count
    )
  }

  private static func streak(days: Set<Date>) -> Int {
    guard !days.isEmpty else { return 0 }
    let calendar = Calendar.current
    var cursor = calendar.startOfDay(for: Date())
    if !days.contains(cursor) {
      guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(yesterday) else {
        return 0
      }
      cursor = yesterday
    }

    var count = 0
    while days.contains(cursor) {
      count += 1
      guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
      cursor = previous
    }
    return count
  }

  private static func tiered(
    prefix: String,
    category: String,
    symbol: String,
    value: Double,
    unit: String,
    money: Bool = false,
    specs: [(Double, String)]
  ) -> [NativeMedalAchievement] {
    specs.enumerated().map { index, spec in
      let progress = spec.0 <= 0 ? 1 : min(1, max(0, value / spec.0))
      let descValue = money ? gbp(spec.0, whole: true) : wholeNumber(spec.0)
      return NativeMedalAchievement(
        key: "\(prefix)_\(Int(spec.0))",
        label: spec.1,
        desc: "\(descValue) \(unit)",
        symbol: symbol,
        category: category,
        tier: tier(for: index, total: specs.count),
        unlocked: value >= spec.0,
        progress: progress,
        target: spec.0,
        value: value
      )
    }
  }

  private static func flag(
    key: String,
    label: String,
    desc: String,
    symbol: String,
    category: String,
    tier: NativeMedalTier,
    done: Bool,
    progress: Double,
    target: Double? = nil,
    value: Double? = nil
  ) -> NativeMedalAchievement {
    NativeMedalAchievement(
      key: key,
      label: label,
      desc: desc,
      symbol: symbol,
      category: category,
      tier: tier,
      unlocked: done,
      progress: min(1, max(0, progress)),
      target: target,
      value: value
    )
  }

  private static func tier(for index: Int, total: Int) -> NativeMedalTier {
    guard total > 0 else { return .bronze }
    let ratio = Double(index + 1) / Double(total)
    if ratio > 0.85 { return .gold }
    if ratio > 0.45 { return .silver }
    return .bronze
  }

  private static func wholeNumber(_ value: Double) -> String {
    Int(value).formatted()
  }
}

struct NativeMedalPreviewCard: View {
  let achievements: [NativeMedalAchievement]
  let onOpen: () -> Void

  private var unlocked: [NativeMedalAchievement] {
    achievements.filter(\.unlocked)
  }

  private var featured: [NativeMedalAchievement] {
    let earned = unlocked.suffix(3)
    let close = achievements
      .filter { !$0.unlocked }
      .sorted { $0.progress > $1.progress }
      .prefix(max(0, 3 - earned.count))
    return Array(earned) + Array(close)
  }

  private var nextUp: [NativeMedalAchievement] {
    achievements
      .filter { !$0.unlocked }
      .sorted { $0.progress > $1.progress }
      .prefix(2)
      .map { $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Medals")
            .font(.system(size: 17, weight: .heavy))
          Text("\(unlocked.count) of \(achievements.count) unlocked")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
        }
        Spacer()
        Button(action: onOpen) {
          Label("See all", systemImage: "chevron.right")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(OkkleColor.brandDark)
        }
        .buttonStyle(.plain)
      }

      HStack(spacing: 14) {
        ForEach(featured) { achievement in
          VStack(spacing: 7) {
            NativeMedalIcon(achievement: achievement, size: 54, rendering: .compact)
            Text(achievement.label)
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(achievement.unlocked ? OkkleColor.ink : OkkleColor.muted)
              .lineLimit(1)
              .minimumScaleFactor(0.75)
          }
          .frame(maxWidth: .infinity)
        }
      }

      if !nextUp.isEmpty {
        VStack(spacing: 10) {
          ForEach(nextUp) { achievement in
            NativeMedalProgressRow(achievement: achievement)
          }
        }
      }
    }
    .padding(16)
  }
}

struct NativeMedalsView: View {
  @EnvironmentObject private var store: OkkleStore
  @Environment(\.dismiss) private var dismiss
  @State private var selected: NativeMedalAchievement?

  private var achievements: [NativeMedalAchievement] {
    NativeMedalEngine.achievements(store: store)
  }

  private var categories: [String] {
    var seen = Set<String>()
    return achievements.compactMap { achievement in
      guard !seen.contains(achievement.category) else { return nil }
      seen.insert(achievement.category)
      return achievement.category
    }
  }

  private var earnedCount: Int {
    achievements.filter(\.unlocked).count
  }

  private var completion: Double {
    guard !achievements.isEmpty else { return 0 }
    return Double(earnedCount) / Double(achievements.count)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          NativeMedalSummaryCard(earned: earnedCount, total: achievements.count, completion: completion)

          ForEach(categories, id: \.self) { category in
            VStack(alignment: .leading, spacing: 12) {
              Text(category)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(OkkleColor.ink)
              LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(achievements.filter { $0.category == category }) { achievement in
                  Button {
                    selected = achievement
                  } label: {
                    NativeMedalTile(achievement: achievement)
                  }
                  .buttonStyle(.plain)
                }
              }
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
      }
      .background { NativeBackground() }
      .navigationTitle("Medals")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .font(.system(size: 16, weight: .semibold))
        }
      }
      .sheet(item: $selected) { achievement in
        NativeMedalDetailSheet(achievement: achievement)
          .presentationDetents([.medium])
          .presentationDragIndicator(.visible)
      }
    }
  }
}

struct NativeMedalUnlockedOverlay: View {
  let achievement: NativeMedalAchievement
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.24)
        .ignoresSafeArea()
        .onTapGesture(perform: onDismiss)

      VStack(spacing: 16) {
        NativeMedalIcon(achievement: achievement, size: 94)
        VStack(spacing: 7) {
          Text("Medal unlocked")
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(medalPalette(for: achievement).deep)
            .textCase(.uppercase)
          Text(achievement.label)
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
            .multilineTextAlignment(.center)
          Text(achievement.desc)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .multilineTextAlignment(.center)
        }

        Button(action: onDismiss) {
          Text("Nice")
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(OkkleColor.brand, in: Capsule())
        }
        .buttonStyle(.plain)
      }
      .padding(24)
      .frame(maxWidth: 330)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
          .stroke(Color.white.opacity(0.32), lineWidth: 1)
      }
      .shadow(color: medalPalette(for: achievement).deep.opacity(0.24), radius: 32, y: 18)
      .padding(.horizontal, 26)
    }
  }
}

private struct NativeMedalSummaryCard: View {
  let earned: Int
  let total: Int
  let completion: Double

  var body: some View {
    NativeGlassCard(cornerRadius: 30) {
      HStack(spacing: 18) {
        ZStack {
          Circle()
            .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 9)
          Circle()
            .trim(from: 0, to: completion)
            .stroke(
              AngularGradient(colors: [OkkleColor.brand, .green, .yellow, .purple, OkkleColor.brand], center: .center),
              style: StrokeStyle(lineWidth: 9, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
          Text("\(earned)")
            .font(.system(size: 30, weight: .heavy, design: .rounded))
        }
        .frame(width: 82, height: 82)

        VStack(alignment: .leading, spacing: 6) {
          Text("Medal room")
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
          Text("\(earned) of \(total) achievements unlocked")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
          ProgressView(value: completion)
            .tint(OkkleColor.brand)
        }
      }
    }
  }
}

private struct NativeMedalTile: View {
  let achievement: NativeMedalAchievement

  var body: some View {
    VStack(spacing: 9) {
      NativeMedalIcon(achievement: achievement, size: 68, rendering: .compact)
      Text(achievement.label)
        .font(.system(size: 12, weight: .heavy))
        .foregroundStyle(achievement.unlocked ? OkkleColor.ink : OkkleColor.muted)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.78)
        .frame(height: 31)
      ProgressView(value: achievement.progress)
        .tint(achievement.unlocked ? medalPalette(for: achievement).deep : OkkleColor.muted.opacity(0.45))
        .opacity(achievement.unlocked ? 0.45 : 1)
    }
    .padding(12)
    .frame(maxWidth: .infinity)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
  }
}

private struct NativeMedalProgressRow: View {
  let achievement: NativeMedalAchievement

  var body: some View {
    HStack(spacing: 10) {
      NativeMedalIcon(achievement: achievement, size: 34, rendering: .compact)
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(achievement.label)
            .font(.system(size: 13, weight: .bold))
          Spacer()
          Text(progressText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
        }
        ProgressView(value: achievement.progress)
          .tint(medalPalette(for: achievement).deep)
      }
    }
  }

  private var progressText: String {
    guard let target = achievement.target, let value = achievement.value else {
      return "\(Int(achievement.progress * 100))%"
    }
    return "\(Int(min(target, value)).formatted()) / \(Int(target).formatted())"
  }
}

private struct NativeMedalDetailSheet: View {
  let achievement: NativeMedalAchievement

  var body: some View {
    VStack(spacing: 18) {
      NativeMedalIcon(achievement: achievement, size: 112)
      VStack(spacing: 8) {
        Text(achievement.label)
          .font(.system(size: 30, weight: .heavy, design: .rounded))
          .multilineTextAlignment(.center)
        Text(achievement.desc)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .multilineTextAlignment(.center)
        Text(achievement.unlocked ? "Unlocked" : "\(Int(achievement.progress * 100))% complete")
          .font(.system(size: 13, weight: .heavy))
          .foregroundStyle(medalPalette(for: achievement).deep)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(medalPalette(for: achievement).start.opacity(0.22), in: Capsule())
      }
      NativeMedalProgressRow(achievement: achievement)
        .padding(.horizontal, 12)
    }
    .padding(26)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { NativeBackground() }
  }
}

private enum NativeMedalRendering {
  case compact
  case full
}

private struct NativeMedalIcon: View {
  @Environment(\.colorScheme) private var colorScheme
  let achievement: NativeMedalAchievement
  let size: CGFloat
  var rendering: NativeMedalRendering = .full

  private var palette: NativeMedalPalette {
    medalPalette(for: achievement)
  }

  private var raisedHighlight: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.9)
  }

  private var raisedShadow: Color {
    colorScheme == .dark ? Color.black.opacity(0.62) : Color.black.opacity(0.18)
  }

  var body: some View {
    ZStack {
      if rendering == .full && achievement.unlocked && (achievement.tier == .gold || achievement.tier == .special) {
        NativeMedalBurstShape(points: achievement.tier == .special ? 18 : 14)
          .fill(palette.end.opacity(0.16))
          .frame(width: size * 1.14, height: size * 1.14)
          .rotationEffect(.degrees(achievement.tier == .special ? 7 : 0))
          .blur(radius: size * 0.01)
      }

      Circle()
        .fill(Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground))
        .shadow(color: raisedHighlight, radius: shadowScale(0.08), x: offsetScale(-0.08), y: offsetScale(-0.08))
        .shadow(color: raisedShadow, radius: shadowScale(0.11), x: offsetScale(0.08), y: offsetScale(0.1))

      Circle()
        .fill(metalFill)
        .padding(size * 0.04)
        .overlay {
          Circle()
            .stroke(
              LinearGradient(
                colors: [
                  Color.white.opacity(achievement.unlocked ? 0.92 : 0.52),
                  palette.deep.opacity(achievement.unlocked ? 0.42 : 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              lineWidth: max(1.5, size * 0.045)
            )
            .padding(size * 0.04)
        }
        .overlay {
          if rendering == .full {
            Circle()
              .stroke(Color.white.opacity(achievement.unlocked ? 0.52 : 0.24), lineWidth: max(1, size * 0.028))
              .blur(radius: size * 0.018)
              .offset(x: -size * 0.035, y: -size * 0.035)
              .padding(size * 0.12)
              .mask(Circle().padding(size * 0.04))
          }
        }
        .overlay {
          if rendering == .full {
            Circle()
              .stroke(palette.deep.opacity(achievement.unlocked ? 0.32 : 0.16), lineWidth: max(2, size * 0.07))
              .blur(radius: size * 0.026)
              .offset(x: size * 0.035, y: size * 0.04)
              .padding(size * 0.12)
              .mask(Circle().padding(size * 0.04))
          }
        }

      Circle()
        .fill(
          RadialGradient(
            colors: [
              Color.white.opacity(achievement.unlocked ? 0.54 : 0.26),
              palette.start.opacity(achievement.unlocked ? 0.74 : 0.32),
              palette.deep.opacity(achievement.unlocked ? 0.24 : 0.18),
            ],
            center: .topLeading,
            startRadius: 1,
            endRadius: size * 0.36
          )
        )
        .padding(size * 0.23)
        .shadow(color: Color.white.opacity(rendering == .full && achievement.unlocked ? 0.44 : 0.12), radius: shadowScale(0.025), x: offsetScale(-0.025), y: offsetScale(-0.025))
        .shadow(color: palette.deep.opacity(rendering == .full && achievement.unlocked ? 0.24 : 0.1), radius: shadowScale(0.03), x: offsetScale(0.025), y: offsetScale(0.025))
        .overlay {
          Circle()
            .stroke(palette.deep.opacity(achievement.unlocked ? 0.28 : 0.14), lineWidth: max(1, size * 0.026))
            .padding(size * 0.23)
        }

      Image(systemName: achievement.unlocked ? achievement.symbol : "lock.fill")
        .font(.system(size: size * 0.31, weight: .heavy))
        .foregroundStyle(achievement.unlocked ? palette.deep : Color(uiColor: .tertiaryLabel))
        .symbolRenderingMode(.hierarchical)
        .shadow(color: Color.white.opacity(rendering == .full && achievement.unlocked ? 0.36 : 0), radius: 0, x: -0.8, y: -0.8)
        .shadow(color: palette.deep.opacity(rendering == .full && achievement.unlocked ? 0.32 : 0), radius: 0, x: 0.9, y: 0.9)
    }
    .frame(width: size, height: size)
  }

  private var metalFill: some ShapeStyle {
    if rendering == .compact {
      return AnyShapeStyle(
        LinearGradient(
          colors: achievement.unlocked
            ? [palette.start.opacity(0.95), Color.white.opacity(0.64), palette.end, palette.deep.opacity(0.7)]
            : [Color(uiColor: .systemGray5), Color(uiColor: .systemGray4), Color(uiColor: .systemGray3)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    }

    if achievement.unlocked {
      return AnyShapeStyle(
        AngularGradient(
          colors: [
            palette.start,
            Color.white.opacity(0.86),
            palette.start.opacity(0.82),
            palette.end,
            palette.deep.opacity(0.74),
            palette.end.opacity(0.9),
            Color.white.opacity(0.72),
            palette.start,
          ],
          center: .center,
          angle: .degrees(-34)
        )
      )
    }

    return AnyShapeStyle(
      AngularGradient(
        colors: [
          Color(uiColor: .systemGray5),
          Color(uiColor: .systemGray3),
          Color(uiColor: .systemGray6),
          Color(uiColor: .systemGray2),
          Color(uiColor: .systemGray5),
        ],
        center: .center,
        angle: .degrees(-34)
      )
    )
  }

  private func shadowScale(_ multiplier: CGFloat) -> CGFloat {
    size * multiplier * (rendering == .compact ? 0.48 : 1)
  }

  private func offsetScale(_ multiplier: CGFloat) -> CGFloat {
    size * multiplier * (rendering == .compact ? 0.55 : 1)
  }
}

private struct NativeMedalPalette {
  let start: Color
  let end: Color
  let deep: Color
}

private func medalPalette(for achievement: NativeMedalAchievement) -> NativeMedalPalette {
  guard achievement.unlocked else {
    return NativeMedalPalette(
      start: Color(uiColor: .secondarySystemBackground),
      end: Color(uiColor: .systemGray5),
      deep: Color(uiColor: .secondaryLabel)
    )
  }

  switch achievement.tier {
  case .bronze:
    return NativeMedalPalette(start: Color(red: 1.0, green: 0.72, blue: 0.45), end: Color(red: 0.83, green: 0.38, blue: 0.13), deep: Color(red: 0.62, green: 0.25, blue: 0.08))
  case .silver:
    return NativeMedalPalette(start: Color(red: 0.90, green: 0.94, blue: 0.98), end: Color(red: 0.50, green: 0.62, blue: 0.76), deep: Color(red: 0.24, green: 0.34, blue: 0.49))
  case .gold:
    return NativeMedalPalette(start: Color(red: 1.0, green: 0.91, blue: 0.45), end: Color(red: 0.96, green: 0.58, blue: 0.10), deep: Color(red: 0.72, green: 0.39, blue: 0.02))
  case .special:
    return NativeMedalPalette(start: Color(red: 0.65, green: 0.98, blue: 0.90), end: Color(red: 0.41, green: 0.55, blue: 1.0), deep: OkkleColor.brandDark)
  }
}

private struct NativeMedalBurstShape: Shape {
  let points: Int

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outer = min(rect.width, rect.height) / 2
    let inner = outer * 0.78
    var path = Path()

    for step in 0..<(points * 2) {
      let radius = step.isMultiple(of: 2) ? outer : inner
      let angle = -.pi / 2 + Double(step) * .pi / Double(points)
      let point = CGPoint(
        x: center.x + CGFloat(cos(angle)) * radius,
        y: center.y + CGFloat(sin(angle)) * radius
      )
      if step == 0 {
        path.move(to: point)
      } else {
        path.addLine(to: point)
      }
    }
    path.closeSubpath()
    return path
  }
}

// MARK: - Leagues (local, season = tax year)

/// The English football pyramid, used as a local progression ladder.
/// No backend: a driver climbs divisions by earning XP through the season.
enum NativeDivision: Int, CaseIterable, Comparable {
  case nationalLeague
  case leagueTwo
  case leagueOne
  case championship
  case premierLeague

  static func < (lhs: NativeDivision, rhs: NativeDivision) -> Bool { lhs.rawValue < rhs.rawValue }

  /// Real tax £ banked this tax year required to sit in this division.
  /// The pyramid position is literally how much real money you've saved.
  var minBanked: Int {
    switch self {
    case .nationalLeague: return 0
    case .leagueTwo: return 300
    case .leagueOne: return 750
    case .championship: return 1_500
    case .premierLeague: return 3_000
    }
  }

  var name: String {
    switch self {
    case .nationalLeague: return "National League"
    case .leagueTwo: return "League Two"
    case .leagueOne: return "League One"
    case .championship: return "Championship"
    case .premierLeague: return "Premier League"
    }
  }

  var shortName: String {
    switch self {
    case .nationalLeague: return "Nat. League"
    case .leagueTwo: return "League Two"
    case .leagueOne: return "League One"
    case .championship: return "Champ."
    case .premierLeague: return "Premier"
    }
  }

  /// Colours drawn from the real English pyramid's brands: National League red,
  /// EFL amber/green/blue up the tiers, and the iconic Premier League purple.
  var gradientTop: Color {
    switch self {
    case .nationalLeague: return Color(red: 0.89, green: 0.27, blue: 0.25) // National League red
    case .leagueTwo:      return Color(red: 0.95, green: 0.66, blue: 0.23) // EFL amber
    case .leagueOne:      return Color(red: 0.18, green: 0.70, blue: 0.46) // green
    case .championship:   return Color(red: 0.18, green: 0.49, blue: 0.89) // Sky Bet blue
    case .premierLeague:  return Color(red: 0.62, green: 0.13, blue: 0.71) // PL magenta
    }
  }

  var gradientBottom: Color {
    switch self {
    case .nationalLeague: return Color(red: 0.69, green: 0.11, blue: 0.16)
    case .leagueTwo:      return Color(red: 0.78, green: 0.47, blue: 0.05)
    case .leagueOne:      return Color(red: 0.05, green: 0.48, blue: 0.31)
    case .championship:   return Color(red: 0.07, green: 0.31, blue: 0.65)
    case .premierLeague:  return Color(red: 0.24, green: 0.04, blue: 0.36) // deep PL purple
    }
  }

  /// Solid accent (the deeper stop) for borders, fills and text.
  var accent: Color { gradientBottom }

  /// Apple-style two-stop gradient in the league's colours.
  var gradient: LinearGradient {
    LinearGradient(colors: [gradientTop, gradientBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  /// SF Symbol that tells the climb: pitch → rosette → shield → trophy → crown.
  var glyph: String {
    switch self {
    case .nationalLeague: return "soccerball"
    case .leagueTwo: return "rosette"
    case .leagueOne: return "shield.fill"
    case .championship: return "trophy.fill"
    case .premierLeague: return "crown.fill"
    }
  }
}

struct NativeLeagueStatus {
  let banked: Int          // real £ tax saved this tax year
  let division: NativeDivision
  let next: NativeDivision?
  let progressToNext: Double
  let bankedToNext: Int    // real £ still to bank to climb
}

@MainActor
enum NativeLeagueEngine {
  /// Your standing in the pyramid is real money: the tax £ you've banked this
  /// tax year. Every logged mile that lifts your deduction lifts your league.
  static func banked(store: OkkleStore) -> Int {
    Int(store.taxSaved.rounded())
  }

  static func status(store: OkkleStore) -> NativeLeagueStatus {
    let points = banked(store: store)
    let division = NativeDivision.allCases.last(where: { points >= $0.minBanked }) ?? .nationalLeague
    let next = NativeDivision(rawValue: division.rawValue + 1)
    if let next {
      let span = max(1, next.minBanked - division.minBanked)
      let into = points - division.minBanked
      return NativeLeagueStatus(
        banked: points,
        division: division,
        next: next,
        progressToNext: min(1, Double(into) / Double(span)),
        bankedToNext: max(0, next.minBanked - points)
      )
    }
    return NativeLeagueStatus(banked: points, division: division, next: nil, progressToNext: 1, bankedToNext: 0)
  }

  /// Medals belonging to a division: within each category, easy→hard medals are
  /// spread across the five divisions, so climbing unlocks tougher challenges.
  static func medals(in division: NativeDivision, store: OkkleStore) -> [NativeMedalAchievement] {
    let byCategory = Dictionary(grouping: NativeMedalEngine.achievements(store: store), by: \.category)
    var result: [NativeMedalAchievement] = []
    for (_, items) in byCategory {
      let n = max(1, items.count)
      for (index, medal) in items.enumerated() where min(4, index * 5 / n) == division.rawValue {
        result.append(medal)
      }
    }
    return result.sorted { ($0.category, $0.target ?? 0) < ($1.category, $1.target ?? 0) }
  }
}

/// iOS Settings-style icon tile: a flat tinted rounded square with a clean white SF Symbol.
struct NativeDivisionCrest: View {
  let division: NativeDivision
  var size: CGFloat = 48

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
      .fill(division.gradient)
      .frame(width: size, height: size)
      .overlay(
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
          .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
      )
      .overlay(
        Image(systemName: division.glyph)
          .font(.system(size: size * 0.5, weight: .semibold))
          .foregroundStyle(.white)
      )
      .shadow(color: division.accent.opacity(0.35), radius: size * 0.12, y: size * 0.06)
  }
}

/// Form pips — last results as win/draw/loss dots.
struct NativeFormGuide: View {
  let form: [Int]
  var size: CGFloat = 7

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(form.enumerated()), id: \.offset) { _, result in
        Circle()
          .fill(color(result))
          .frame(width: size, height: size)
      }
    }
  }

  private func color(_ result: Int) -> Color {
    switch result {
    case 3: return OkkleColor.brand
    case 1: return OkkleColor.amber
    default: return OkkleColor.red
    }
  }
}

/// Compact Home card: current division, league position, and recent form.
struct NativeLeagueCard: View {
  let snapshot: NativeSeasonSnapshot
  var fixture: NativeFixture? = nil
  var medals: [NativeMedalAchievement] = []
  let onOpen: () -> Void

  private var earnedMedals: Int { medals.filter(\.unlocked).count }
  private var nextMedal: NativeMedalAchievement? {
    medals.filter { !$0.unlocked }.max { $0.progress < $1.progress }
  }

  private var positionLabel: String {
    snapshot.matchweek > 0 ? "\(ordinal(snapshot.yourPosition)) OF \(snapshot.rows.count)" : "NEW SEASON"
  }

  var body: some View {
    Button(action: onOpen) {
      NativeBannerCard(
        kicker: snapshot.division.name.uppercased(),
        trailing: positionLabel,
        band: LinearGradient(colors: [snapshot.division.gradientBottom, snapshot.division.gradientTop], startPoint: .leading, endPoint: .trailing)
      ) {
        VStack(spacing: 0) {
          HStack(spacing: 14) {
            NativeDivisionCrest(division: snapshot.division, size: 46)
            VStack(alignment: .leading, spacing: 5) {
              if snapshot.matchweek == 0 {
                Text("Kicking off")
                  .font(.system(size: 16, weight: .heavy))
                  .foregroundStyle(OkkleColor.ink)
                Text("£\(Int(snapshot.winBar.rounded())) of tax saved this week wins it")
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundStyle(OkkleColor.muted)
              } else {
                Text("£\(Int(snapshot.bankedThisSeason.rounded())) banked")
                  .font(.system(size: 16, weight: .heavy))
                  .foregroundStyle(OkkleColor.ink)
                HStack(spacing: 8) {
                  NativeFormGuide(form: snapshot.yourRow.form)
                  Text("Matchweek \(snapshot.matchweek)/\(snapshot.totalWeeks)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OkkleColor.muted)
                }
              }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(OkkleColor.muted)
          }

          if let fixture, fixture.matchweek > 0 {
            Divider().padding(.vertical, 13)
            HStack(spacing: 10) {
              Image(systemName: fixture.state == .fullTime ? "checkered.flag" : "dot.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(fixture.state == .live ? OkkleColor.red : snapshot.division.accent)
              Text("vs \(fixture.opponent)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OkkleColor.muted)
                .lineLimit(1)
              Spacer()
              Text("\(fixture.yourGoals)–\(fixture.oppGoals)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(OkkleColor.ink)
              Text(fixtureState(fixture))
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(fixtureColor(fixture))
            }
          }

          if !medals.isEmpty {
            Divider().padding(.vertical, 13)
            HStack(spacing: 10) {
              Image(systemName: "rosette")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(snapshot.division.accent)
              Text("\(earnedMedals) of \(medals.count) medals")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OkkleColor.ink)
              Spacer()
              if let nextMedal {
                Text("Next: \(nextMedal.label)")
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundStyle(OkkleColor.muted)
                  .lineLimit(1)
              }
            }
          }
        }
      }
    }
    .buttonStyle(.plain)
  }

  private func fixtureState(_ f: NativeFixture) -> String {
    switch f.state {
    case .kickoff: return "KICK-OFF"
    case .live: return f.youAreWinning ? "AHEAD" : (f.isLevel ? "LEVEL" : "BEHIND")
    case .fullTime: return f.youAreWinning ? "WON" : (f.isLevel ? "DREW" : "LOST")
    }
  }

  private func fixtureColor(_ f: NativeFixture) -> Color {
    if f.state == .kickoff { return OkkleColor.muted }
    if f.youAreWinning { return OkkleColor.brand }
    if f.isLevel { return OkkleColor.amber }
    return OkkleColor.red
  }
}

func ordinal(_ n: Int) -> String {
  let suffix: String
  switch (n % 100, n % 10) {
  case (11, _), (12, _), (13, _): suffix = "th"
  case (_, 1): suffix = "st"
  case (_, 2): suffix = "nd"
  case (_, 3): suffix = "rd"
  default: suffix = "th"
  }
  return "\(n)\(suffix)"
}

/// This week's fixture — you vs a past-self, scored live in real tax saved,
/// with the gaffer's team-talk underneath. The heartbeat of the league.
struct NativeMatchdayCard: View {
  let fixture: NativeFixture
  let division: NativeDivision
  var club: NativeClubIdentity? = nil

  var body: some View {
    VStack(spacing: 0) {
      if fixture.stakes != .none {
        banner
      }
      VStack(spacing: 14) {
        HStack {
          Text("\(division.name) · matchweek \(fixture.matchweek) of \(fixture.totalWeeks)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
          Spacer()
          Text(stateLabel)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(fixture.state == .live ? OkkleColor.red : OkkleColor.muted)
        }
        HStack(alignment: .top, spacing: 8) {
          youTeam
          VStack(spacing: 3) {
            Text("\(fixture.yourGoals)–\(fixture.oppGoals)")
              .font(.system(size: 30, weight: .heavy, design: .rounded))
              .foregroundStyle(OkkleColor.ink)
            Text(scoreCaption)
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(captionColor)
          }
          .frame(minWidth: 70)
          team(name: fixture.opponent, symbol: fixture.opponentSymbol, banked: fixture.oppBanked, accent: division.accent, filled: false)
        }
        pointsProgress
        gaffer
      }
      .padding(16)
    }
    .themedLeagueCard(division)
  }

  private var pointsProgress: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("THIS WEEK'S POINTS")
          .font(.system(size: 11, weight: .heavy))
          .tracking(0.6)
          .foregroundStyle(OkkleColor.muted)
        Spacer()
        Text("+\(fixture.pointsThisWeek) pt\(fixture.pointsThisWeek == 1 ? "" : "s")")
          .font(.system(size: 12, weight: .heavy))
          .foregroundStyle(pointsColor)
      }
      GeometryReader { geo in
        let w = geo.size.width
        ZStack(alignment: .leading) {
          Capsule().fill(OkkleColor.muted.opacity(0.16))
          Capsule()
            .fill(division.gradient)
            .frame(width: max(6, w * fixture.progressToTarget))
          // Draw line at the halfway (1-point) mark.
          Rectangle()
            .fill(OkkleColor.ink.opacity(0.35))
            .frame(width: 1.5, height: 14)
            .offset(x: w * 0.5)
        }
      }
      .frame(height: 12)
      Text(progressCaption)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
    .padding(12)
    .background(OkkleColor.muted.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var pointsColor: Color {
    switch fixture.pointsThisWeek {
    case 3: return OkkleColor.brand
    case 1: return OkkleColor.amber
    default: return OkkleColor.muted
    }
  }

  private var progressCaption: String {
    let toWin = max(0, Int((fixture.weeklyTarget - fixture.yourBanked).rounded(.up)))
    let toDraw = max(0, Int((fixture.drawTarget - fixture.yourBanked).rounded(.up)))
    if fixture.state == .fullTime {
      switch fixture.pointsThisWeek {
      case 3: return "Hit your £\(Int(fixture.weeklyTarget.rounded())) target — 3 points banked."
      case 1: return "Reached the halfway mark — 1 point earned."
      default: return "Missed the target this week — no points."
      }
    }
    switch fixture.pointsThisWeek {
    case 3: return "Target smashed — the 3 points are yours. Keep banking."
    case 1: return "In the draw zone (1 pt). £\(toWin) more saved this week wins it (3 pts)."
    default: return "£\(toDraw) more saved earns a draw (1 pt), £\(toWin) the win (3 pts)."
    }
  }

  private var banner: some View {
    let danger = fixture.stakes == .survival
    let symbol: String
    let text: String
    switch fixture.stakes {
    case .title:    symbol = "trophy.fill";              text = "Title decider — win to be champions"
    case .playoff:  symbol = "arrow.up.circle.fill";     text = "Play-off final — win to go up"
    case .survival: symbol = "exclamationmark.triangle.fill"; text = "Final week — avoid defeat to stay up"
    case .none:     symbol = "";                          text = ""
    }
    let tint = danger ? OkkleColor.red : OkkleColor.brandDark
    let fill = danger ? OkkleColor.red : OkkleColor.brand
    return HStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .bold))
      Text(text)
        .font(.system(size: 13, weight: .heavy))
      Spacer()
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity)
    .background(fill.opacity(0.13))
  }

  private var youTeam: some View {
    VStack(spacing: 7) {
      ZStack(alignment: .top) {
        NativeKitTile(
          kit: club?.kit ?? .solid,
          color: club?.color ?? OkkleColor.brand,
          secondary: club?.secondaryColor,
          crestShape: club?.crestShape ?? .rounded,
          trim: club?.trim ?? .none,
          size: 46,
          emblem: club?.emblem ?? "figure.walk"
        )
        NativeTitleStars(count: NativeSeasonEngine.honours().filter { $0.kind == .champions }.count, size: 8)
          .offset(y: -7)
      }
      Text(club?.name ?? "You")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text("£\(Int(fixture.yourBanked.rounded())) saved")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
    .frame(maxWidth: .infinity)
  }

  private func team(name: String, symbol: String, banked: Double, accent: Color, filled: Bool) -> some View {
    VStack(spacing: 7) {
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .fill(accent.opacity(filled ? 0.16 : 0.10))
        .frame(width: 46, height: 46)
        .overlay(
          Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(accent)
        )
      Text(name)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text("£\(Int(banked.rounded())) saved")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
    .frame(maxWidth: .infinity)
  }

  private var gaffer: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "person.fill")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(division.accent)
        .padding(.top, 1)
      (Text("The gaffer: ").font(.system(size: 13, weight: .heavy)).foregroundColor(OkkleColor.ink)
        + Text(NativeGaffer.teamTalk(for: fixture)).font(.system(size: 13, weight: .medium)).foregroundColor(OkkleColor.muted))
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(OkkleColor.muted.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var stateLabel: String {
    switch fixture.state {
    case .kickoff: return "KICK-OFF"
    case .live: return "● LIVE"
    case .fullTime: return "FULL TIME"
    }
  }

  private var scoreCaption: String {
    switch fixture.state {
    case .kickoff: return "kick-off"
    case .live: return fixture.youAreWinning ? "you lead" : (fixture.isLevel ? "level" : "behind")
    case .fullTime: return fixture.youAreWinning ? "won" : (fixture.isLevel ? "drew" : "lost")
    }
  }

  private var captionColor: Color {
    if fixture.state == .kickoff { return OkkleColor.muted }
    if fixture.youAreWinning { return OkkleColor.brand }
    if fixture.isLevel { return OkkleColor.amber }
    return OkkleColor.red
  }
}

/// The trophy cabinet — every division won, kept forever.
struct NativeHonoursCard: View {
  let honours: [NativeHonour]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 8) {
        Image(systemName: "trophy.fill")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(OkkleColor.amber)
        Text("Honours")
          .font(.system(size: 17, weight: .heavy))
          .foregroundStyle(OkkleColor.ink)
        Spacer()
        if !honours.isEmpty {
          Text("\(honours.count)")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
        }
      }

      if honours.isEmpty {
        Text("No silverware yet — win your division to fill the cabinet.")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
      } else {
        VStack(spacing: 0) {
          ForEach(honours) { honour in
            HStack(spacing: 13) {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(honour.division.accent)
                .frame(width: 38, height: 38)
                .overlay(
                  Image(systemName: honour.kind == .champions ? "trophy.fill" : "rosette")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                )
              VStack(alignment: .leading, spacing: 2) {
                Text(honour.title)
                  .font(.system(size: 15, weight: .bold))
                  .foregroundStyle(OkkleColor.ink)
                Text(honour.subtitle)
                  .font(.system(size: 12, weight: .medium))
                  .foregroundStyle(OkkleColor.muted)
              }
              Spacer()
              Image(systemName: "medal.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OkkleColor.amber)
            }
            .padding(.vertical, 10)
            if honour.id != honours.last?.id {
              Divider().padding(.leading, 51)
            }
          }
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .okkleCard()
  }
}

/// Make the club yours — name, colour and crest. Investment breeds attachment.
struct NativeClubEditorView: View {
  @EnvironmentObject private var store: OkkleStore
  @Environment(\.dismiss) private var dismiss

  private enum Cat: Int, CaseIterable { case shape, colour, pattern, crest, trim
    var label: String {
      switch self {
      case .shape: return "Shape"
      case .colour: return "Colour"
      case .pattern: return "Kit"
      case .crest: return "Crest"
      case .trim: return "Trim"
      }
    }
  }

  @State private var name: String = ""
  @State private var colorIndex: Int = 0
  @State private var emblem: String = "shield.fill"
  @State private var kitIndex: Int = 0
  @State private var shapeIndex: Int = 0
  @State private var secondaryIndex: Int? = nil
  @State private var trimIndex: Int = 0
  @State private var cat: Cat = .shape
  @State private var editingSecondary = false
  @State private var balance: Int = 0
  @State private var purchaseError = false

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
  private var secondaryColor: Color? { secondaryIndex.map { NativeClubIdentity.palette[$0] } }
  private var titles: Int { NativeSeasonEngine.honours().filter { $0.kind == .champions }.count }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        preview
        Picker("", selection: $cat) {
          ForEach(Cat.allCases, id: \.rawValue) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)

        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            switch cat {
            case .shape: shapeGrid
            case .colour: colourGrid
            case .pattern: patternGrid
            case .crest: crestGrid
            case .trim: trimGrid
            }
            Text("Locked items cost Coins — earn them from medals, wins and promotions.")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
          }
          .padding(.horizontal, 20)
          .padding(.top, 10)
          .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
      }
      .background { NativeBackground() }
      .navigationTitle("Your club")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Save") { saveAndClose() }.font(.system(size: 16, weight: .bold))
        }
      }
      .alert("Not enough Coins", isPresented: $purchaseError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("This badge uses locked items worth \(lockedCost) Coins, but you have \(balance). Earn more from medals and wins, or switch the locked pieces back to free ones.")
      }
      .onAppear(perform: load)
    }
  }

  // MARK: Pinned preview

  private var preview: some View {
    VStack(spacing: 12) {
      VStack(spacing: 6) {
        NativeTitleStars(count: titles, size: 13)
        NativeKitTile(kit: NativeKit(rawValue: kitIndex) ?? .solid,
                      color: NativeClubIdentity.palette[colorIndex],
                      secondary: secondaryColor,
                      crestShape: NativeCrestShape(rawValue: shapeIndex) ?? .rounded,
                      trim: NativeTrim(rawValue: trimIndex) ?? .none,
                      size: 92, emblem: emblem)
      }
      TextField("Your club", text: $name)
        .multilineTextAlignment(.center)
        .font(.system(size: 18, weight: .heavy, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(OkkleColor.muted.opacity(0.08), in: Capsule())
        .frame(maxWidth: 250)
      if lockedCost > 0 {
        HStack(spacing: 6) {
          Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold))
          Text("Trying it on — unlocks for \(lockedCost) Coins on Save")
            .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(lockedCost <= balance ? OkkleColor.brandDark : OkkleColor.red)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background((lockedCost <= balance ? OkkleColor.brand : OkkleColor.red).opacity(0.12), in: Capsule())
      } else {
        coinsPill
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 10)
    .padding(.bottom, 16)
  }

  // MARK: Option grids

  private var shapeGrid: some View {
    LazyVGrid(columns: columns, spacing: 14) {
      ForEach(NativeCrestShape.pickable, id: \.rawValue) { shape in
        let free = shape.rawValue < NativeClubIdentity.freeShapes
        let id = NativeClubIdentity.shapeId(shape.rawValue)
        let owned = NativeWallet.isUnlocked(id, free: free)
        Button { select(shape: shape, id: id, owned: owned) } label: {
          VStack(spacing: 6) {
            shape.anyShape()
              .fill(NativeClubIdentity.palette[colorIndex])
              .frame(width: 48, height: 48)
              .overlay(shape.anyShape().stroke(OkkleColor.ink, lineWidth: shapeIndex == shape.rawValue ? 3 : 0))
              .overlay(lockBadge(owned))
              .opacity(owned ? 1 : 0.5)
            Text(shape.name)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
              .lineLimit(1).minimumScaleFactor(0.8)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var colourGrid: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("", selection: $editingSecondary) {
        Text("Primary").tag(false)
        Text("Second").tag(true)
      }
      .pickerStyle(.segmented)
      LazyVGrid(columns: columns, spacing: 14) {
        if editingSecondary {
          Button { secondaryIndex = nil } label: {
            Image(systemName: "slash.circle")
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
              .frame(width: 46, height: 46)
              .overlay(Circle().strokeBorder(OkkleColor.ink, lineWidth: secondaryIndex == nil ? 3 : 0))
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.plain)
        }
        ForEach(Array(NativeClubIdentity.palette.enumerated()), id: \.offset) { index, color in
          let free = index < NativeClubIdentity.freeColours
          let id = NativeClubIdentity.colourId(index)
          let owned = editingSecondary || NativeWallet.isUnlocked(id, free: free)
          let selected = editingSecondary ? (secondaryIndex == index) : (colorIndex == index)
          Button { tapColour(index: index, id: id, owned: owned) } label: {
            Circle()
              .fill(color)
              .frame(width: 46, height: 46)
              .overlay(Circle().strokeBorder(OkkleColor.ink, lineWidth: selected ? 3 : 0))
              .overlay(lockBadge(owned))
              .opacity(owned ? 1 : 0.5)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var patternGrid: some View {
    LazyVGrid(columns: columns, spacing: 14) {
      ForEach(NativeKit.allCases, id: \.rawValue) { kit in
        let free = kit.rawValue < NativeClubIdentity.freeKits
        let id = NativeClubIdentity.kitId(kit.rawValue)
        let owned = NativeWallet.isUnlocked(id, free: free)
        Button { select(kit: kit, id: id, owned: owned) } label: {
          VStack(spacing: 6) {
            NativeKitTile(kit: kit, color: NativeClubIdentity.palette[colorIndex], secondary: secondaryColor, size: 48)
              .overlay(RoundedRectangle(cornerRadius: 48 * 0.26, style: .continuous).strokeBorder(OkkleColor.ink, lineWidth: kitIndex == kit.rawValue ? 3 : 0))
              .overlay(lockBadge(owned))
              .opacity(owned ? 1 : 0.5)
            Text(kit.name)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
              .lineLimit(1).minimumScaleFactor(0.8)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var crestGrid: some View {
    LazyVGrid(columns: columns, spacing: 14) {
      ForEach(Array(NativeClubIdentity.emblems.enumerated()), id: \.offset) { index, symbol in
        let free = index < NativeClubIdentity.freeCrests
        let id = NativeClubIdentity.crestId(symbol)
        let owned = NativeWallet.isUnlocked(id, free: free)
        Button { select(emblem: symbol, id: id, owned: owned) } label: {
          Image(systemName: symbol)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(emblem == symbol ? .white : OkkleColor.muted)
            .frame(width: 48, height: 48)
            .background(emblem == symbol ? NativeClubIdentity.palette[colorIndex] : OkkleColor.muted.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(lockBadge(owned))
            .opacity(owned ? 1 : 0.5)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var trimGrid: some View {
    LazyVGrid(columns: columns, spacing: 14) {
      ForEach(NativeTrim.allCases, id: \.rawValue) { trim in
        let free = trim.rawValue < NativeClubIdentity.freeTrims
        let id = NativeClubIdentity.trimId(trim.rawValue)
        let owned = NativeWallet.isUnlocked(id, free: free)
        Button { select(trim: trim, id: id, owned: owned) } label: {
          VStack(spacing: 6) {
            Circle()
              .fill(NativeClubIdentity.palette[colorIndex])
              .frame(width: 48, height: 48)
              .overlay(Circle().strokeBorder(trim.color, lineWidth: trim == .none ? 1.5 : 4))
              .overlay(Circle().inset(by: 6).strokeBorder(OkkleColor.ink, lineWidth: trimIndex == trim.rawValue ? 2.5 : 0))
              .overlay(lockBadge(owned))
              .opacity(owned ? 1 : 0.5)
            Text(trim.name)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
              .lineLimit(1).minimumScaleFactor(0.8)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: Bits

  private var coinsPill: some View {
    HStack(spacing: 7) {
      Image(systemName: "bitcoinsign.circle.fill")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(OkkleColor.amber)
      Text("\(balance) Coins")
        .font(.system(size: 15, weight: .heavy, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
    }
    .padding(.horizontal, 14)
    .frame(height: 38)
    .background(OkkleColor.amber.opacity(0.14), in: Capsule())
  }

  @ViewBuilder
  private func lockBadge(_ owned: Bool) -> some View {
    if !owned {
      Image(systemName: "lock.fill")
        .font(.system(size: 10, weight: .heavy))
        .foregroundStyle(.white)
        .padding(4)
        .background(Circle().fill(OkkleColor.ink.opacity(0.6)))
        .offset(x: 17, y: 17)
    }
  }

  // MARK: Actions

  private func load() {
    let club = NativeSeasonEngine.clubIdentity(store: store)
    name = club.name
    colorIndex = max(0, min(club.colorIndex, NativeClubIdentity.palette.count - 1))
    emblem = club.emblem
    kitIndex = club.kitIndex ?? 0
    shapeIndex = club.shapeIndex ?? 0
    secondaryIndex = club.secondaryIndex
    trimIndex = club.trimIndex ?? 0
    balance = NativeWallet.balance(store: store)
  }

  /// Ids of the components currently on the crest that aren't owned yet.
  private func lockedIds() -> [String] {
    var ids: [String] = []
    if !NativeWallet.isUnlocked(NativeClubIdentity.colourId(colorIndex), free: colorIndex < NativeClubIdentity.freeColours) {
      ids.append(NativeClubIdentity.colourId(colorIndex))
    }
    if !NativeWallet.isUnlocked(NativeClubIdentity.kitId(kitIndex), free: kitIndex < NativeClubIdentity.freeKits) {
      ids.append(NativeClubIdentity.kitId(kitIndex))
    }
    if !NativeWallet.isUnlocked(NativeClubIdentity.shapeId(shapeIndex), free: shapeIndex < NativeClubIdentity.freeShapes) {
      ids.append(NativeClubIdentity.shapeId(shapeIndex))
    }
    if !NativeWallet.isUnlocked(NativeClubIdentity.trimId(trimIndex), free: trimIndex < NativeClubIdentity.freeTrims) {
      ids.append(NativeClubIdentity.trimId(trimIndex))
    }
    if let ei = NativeClubIdentity.emblems.firstIndex(of: emblem),
       !NativeWallet.isUnlocked(NativeClubIdentity.crestId(emblem), free: ei < NativeClubIdentity.freeCrests) {
      ids.append(NativeClubIdentity.crestId(emblem))
    }
    return ids
  }

  private var lockedCost: Int { lockedIds().reduce(0) { $0 + NativeWallet.cost(for: $1) } }

  private func saveAndClose() {
    let locked = lockedIds()
    if !locked.isEmpty {
      let total = locked.reduce(0) { $0 + NativeWallet.cost(for: $1) }
      guard NativeWallet.balance(store: store) >= total else { purchaseError = true; return }
      locked.forEach { _ = NativeWallet.purchase($0, store: store) }
      balance = NativeWallet.balance(store: store)
    }
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    NativeSeasonEngine.saveClubIdentity(NativeClubIdentity(
      name: trimmed.isEmpty ? "Your club" : trimmed,
      colorIndex: colorIndex, emblem: emblem, kitIndex: kitIndex,
      shapeIndex: shapeIndex, secondaryIndex: secondaryIndex, trimIndex: trimIndex))
    dismiss()
  }

  // Tapping any swatch just tries it on — nothing is bought until Save.
  private func tapColour(index: Int, id: String, owned: Bool) {
    if editingSecondary { secondaryIndex = index } else { colorIndex = index }
  }
  private func select(colourIndex index: Int, id: String, owned: Bool) { colorIndex = index }
  private func select(emblem symbol: String, id: String, owned: Bool) { emblem = symbol }
  private func select(kit: NativeKit, id: String, owned: Bool) { kitIndex = kit.rawValue }
  private func select(shape: NativeCrestShape, id: String, owned: Bool) { shapeIndex = shape.rawValue }
  private func select(trim: NativeTrim, id: String, owned: Bool) { trimIndex = trim.rawValue }
}

extension View {
  /// A card washed in the division's colour — tinted surface, coloured hairline
  /// border and a coloured glow, so it reads as part of the league's theme.
  func themedLeagueCard(_ division: NativeDivision, cornerRadius: CGFloat = 20) -> some View {
    self
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(OkkleColor.card)
          .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
              .fill(division.gradientTop.opacity(0.09))
          )
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(division.accent.opacity(0.28), lineWidth: 1)
      )
      .shadow(color: division.accent.opacity(0.28), radius: 16, y: 8)
  }
}

/// The league's atmosphere — a deep, floodlit-stadium gradient in the division's
/// colours, so bright cards glow against it (Champions-League night mood).
struct NativeLeagueBackground: View {
  let division: NativeDivision

  var body: some View {
    ZStack {
      Color.black
      LinearGradient(
        colors: [
          division.gradientTop.opacity(0.55),
          division.gradientBottom.opacity(0.9),
          Color.black
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      RadialGradient(
        colors: [division.gradientTop.opacity(0.65), .clear],
        center: .init(x: 0.5, y: 0.0),
        startRadius: 0,
        endRadius: 460
      )
      .blendMode(.screen)
    }
    .ignoresSafeArea()
  }
}

/// League screen: a live season table (you vs your past selves, with
/// promotion/relegation zones) and a Medals tab that drills into medals.
struct NativeLeagueView: View {
  @EnvironmentObject private var store: OkkleStore
  @Environment(\.dismiss) private var dismiss
  private enum Segment: Hashable { case table, medals }
  @State private var segment: Segment = .table
  @State private var ceremony: NativeDivision?
  @State private var editingClub = false

  var body: some View {
    let snapshot = NativeSeasonEngine.snapshot(store: store)
    NavigationStack {
      VStack(spacing: 16) {
        Picker("", selection: $segment) {
          Text("Table").tag(Segment.table)
          Text("Medals").tag(Segment.medals)
        }
        .pickerStyle(.segmented)

        ScrollView {
          if segment == .table {
            tableTab(snapshot)
          } else {
            medalsTab(current: snapshot.division)
          }
        }
        .scrollIndicators(.hidden)
      }
      .padding(20)
      .background { NativeLeagueBackground(division: snapshot.division) }
      .navigationTitle("League")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button { editingClub = true } label: {
            Label("Club", systemImage: "shield.lefthalf.filled")
              .labelStyle(.titleAndIcon)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(.white)
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") { dismiss() }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
        }
      }
    }
    .sheet(isPresented: $editingClub) {
      NativeClubEditorView().environmentObject(store)
    }
    .overlay {
      if let ceremony {
        NativePromotionOverlay(division: ceremony) {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.ceremony = nil }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }
    }
    .onAppear {
      guard let promoted = snapshot.ceremonyTo else { return }
      NativeSeasonEngine.clearCeremony(store: store)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { ceremony = promoted }
      }
    }
  }

  // MARK: Table tab

  private func tableTab(_ snapshot: NativeSeasonSnapshot) -> some View {
    VStack(spacing: 16) {
      NativeMatchdayCard(
        fixture: NativeSeasonEngine.fixture(store: store),
        division: snapshot.division,
        club: NativeSeasonEngine.clubIdentity(store: store)
      )
      seasonHeader(snapshot)
      standingsTable(snapshot)
      zonesLegend(snapshot.division)
      NativeHonoursCard(honours: NativeSeasonEngine.honours())
    }
  }

  private func seasonHeader(_ s: NativeSeasonSnapshot) -> some View {
    VStack(spacing: 12) {
      NativeDivisionCrest(division: s.division, size: 60)
      Text(s.division.name)
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
      Text("£\(Int(s.bankedThisSeason.rounded())) banked · Matchweek \(min(s.matchweek + 1, s.totalWeeks)) of \(s.totalWeeks)")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      Text("Out-earn your past selves to go up. £\(Int(s.winBar.rounded()))/week saved is a win.")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
      if !s.yourRow.form.isEmpty {
        HStack(spacing: 8) {
          Text("Your form")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
          NativeFormGuide(form: s.yourRow.form, size: 9)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 20)
    .themedLeagueCard(s.division, cornerRadius: 22)
  }

  private func standingsTable(_ s: NativeSeasonSnapshot) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: s.division.glyph)
          .font(.system(size: 13, weight: .bold))
        Text(s.division.name)
          .font(.system(size: 13, weight: .heavy))
        Spacer()
        Text("TABLE")
          .font(.system(size: 11, weight: .heavy))
          .tracking(1)
          .foregroundStyle(.white.opacity(0.85))
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .background(s.division.gradient)

      HStack(spacing: 10) {
        Text("#").frame(width: 22, alignment: .leading)
        Text("Club")
        Spacer()
        Text("Pts").frame(width: 34, alignment: .trailing)
      }
      .font(.system(size: 11, weight: .heavy))
      .tracking(0.5)
      .foregroundStyle(OkkleColor.muted)
      .padding(.horizontal, 14)
      .padding(.top, 12)
      .padding(.bottom, 8)
      Divider()
      ForEach(Array(s.rows.enumerated()), id: \.element.id) { index, row in
        standingRow(row: row, index: index, total: s.rows.count, division: s.division)
        if index != s.rows.count - 1 {
          Divider().padding(.leading, 40)
        }
      }
    }
    .themedLeagueCard(s.division)
  }

  private func standingRow(row: NativeClubRow, index: Int, total: Int, division: NativeDivision) -> some View {
    let pos = index + 1
    let canPromote = division != .premierLeague
    let canRelegate = division != .nationalLeague
    let zone: Color
    if pos == 1 && canPromote { zone = OkkleColor.brand }              // champions
    else if (pos == 2 || pos == 3) && canPromote { zone = OkkleColor.amber } // play-offs
    else if pos >= total && canRelegate { zone = OkkleColor.red }      // relegation
    else { zone = .clear }
    return HStack(spacing: 10) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(zone)
        .frame(width: 3, height: 18)
      Text("\(pos)")
        .font(.system(size: 14, weight: row.isYou ? .heavy : .semibold, design: .rounded))
        .foregroundStyle(row.isYou ? OkkleColor.ink : OkkleColor.muted)
        .frame(width: 18, alignment: .leading)
      Text(row.name)
        .font(.system(size: 15, weight: row.isYou ? .heavy : .medium))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
      Spacer()
      NativeFormGuide(form: row.form)
      Text("\(row.points)")
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .frame(width: 30, alignment: .trailing)
    }
    .padding(.horizontal, 13)
    .padding(.vertical, 11)
    .background(
      row.isYou
        ? AnyShapeStyle(division.gradient.opacity(0.12))
        : AnyShapeStyle(Color.clear)
    )
  }

  @ViewBuilder
  private func zonesLegend(_ division: NativeDivision) -> some View {
    HStack(spacing: 16) {
      if division != .premierLeague {
        Label("1st up", systemImage: "trophy.fill")
          .foregroundStyle(OkkleColor.brand)
        Label("2nd–3rd play-offs", systemImage: "arrow.up.circle.fill")
          .foregroundStyle(OkkleColor.amber)
      }
      if division != .nationalLeague {
        Label("Bottom down", systemImage: "arrow.down.circle.fill")
          .foregroundStyle(OkkleColor.red)
      }
    }
    .font(.system(size: 12, weight: .semibold))
    .frame(maxWidth: .infinity)
  }

  // MARK: Medals tab — your whole collection, organised by the division that unlocks it.

  private func medalsTab(current: NativeDivision) -> some View {
    let all = NativeMedalEngine.achievements(store: store)
    let earned = all.filter(\.unlocked).count
    return VStack(spacing: 16) {
      NativeMedalSummaryCard(earned: earned, total: all.count, completion: all.isEmpty ? 0 : Double(earned) / Double(all.count))
      coinsBanner
      Text("Climb the table to unlock tougher medals — each division holds its own set.")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
      ladder(current: current)
    }
  }

  private var coinsBanner: some View {
    HStack(spacing: 10) {
      Image(systemName: "bitcoinsign.circle.fill")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(OkkleColor.amber)
      VStack(alignment: .leading, spacing: 1) {
        Text("\(NativeWallet.balance(store: store)) Coins to spend")
          .font(.system(size: 14, weight: .heavy))
          .foregroundStyle(OkkleColor.ink)
        Text("Earned from medals, wins & promotions · spend on your club")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
      Spacer()
    }
    .padding(12)
    .frame(maxWidth: .infinity)
    .okkleCard()
  }

  private func ladder(current: NativeDivision) -> some View {
    let rows = NativeDivision.allCases.reversed()
    return VStack(spacing: 0) {
      ForEach(Array(rows), id: \.self) { division in
        NavigationLink {
          NativeDivisionMedalsView(division: division).environmentObject(store)
        } label: {
          row(division, current: current)
        }
        .buttonStyle(.plain)
        if division != .nationalLeague {
          Divider().padding(.leading, 64)
        }
      }
    }
    .okkleCard()
  }

  private func row(_ division: NativeDivision, current: NativeDivision) -> some View {
    HStack(spacing: 14) {
      NativeDivisionCrest(division: division, size: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(division.name)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(OkkleColor.ink)
        Text(division.minBanked == 0 ? "Starting tier" : "£\(division.minBanked.formatted())+ tax banked")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
      }
      Spacer()
      accessory(for: division, current: current)
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(OkkleColor.muted.opacity(0.5))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
    .background(division == current ? division.accent.opacity(0.07) : .clear)
  }

  @ViewBuilder
  private func accessory(for division: NativeDivision, current: NativeDivision) -> some View {
    if division == current {
      Text("YOU")
        .font(.system(size: 11, weight: .heavy))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(division.accent, in: Capsule())
    } else if division < current {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(OkkleColor.brand)
    } else {
      Image(systemName: "lock.fill")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.muted.opacity(0.55))
    }
  }

}

/// A tasteful promotion moment — crest, headline, and a single call to action.
struct NativePromotionOverlay: View {
  let division: NativeDivision
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onDismiss)
      VStack(spacing: 18) {
        NativeDivisionCrest(division: division, size: 92)
        VStack(spacing: 6) {
          Text("PROMOTED")
            .font(.system(size: 13, weight: .heavy))
            .tracking(2)
            .foregroundStyle(division.accent)
          Text("Welcome to the\n\(division.name)")
            .multilineTextAlignment(.center)
            .font(.system(size: 23, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
          Text("You finished in the promotion places. New season, new challenge.")
            .multilineTextAlignment(.center)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .padding(.horizontal, 4)
        }
        Button(action: onDismiss) {
          Text("Let's go")
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(division.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
      }
      .padding(28)
      .frame(maxWidth: 320)
      .background(OkkleColor.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      .padding(32)
    }
  }
}

/// The medals that live inside one division — drilled into from the league table,
/// in the same clean Settings-style language (no separate medal room).
struct NativeDivisionMedalsView: View {
  let division: NativeDivision
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    let items = NativeLeagueEngine.medals(in: division, store: store)
    let earned = items.filter(\.unlocked).count
    ScrollView {
      VStack(spacing: 16) {
        VStack(spacing: 10) {
          NativeDivisionCrest(division: division, size: 56)
          Text(division.name)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
          Text("\(earned) of \(items.count) medals earned")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .themedLeagueCard(division, cornerRadius: 22)

        VStack(spacing: 0) {
          ForEach(items) { medal in
            medalRow(medal)
            if medal.id != items.last?.id {
              Divider().padding(.leading, 62)
            }
          }
        }
        .themedLeagueCard(division)
      }
      .padding(20)
    }
    .background { NativeLeagueBackground(division: division) }
    .navigationTitle(division.shortName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbarColorScheme(.dark, for: .navigationBar)
  }

  private func medalRow(_ medal: NativeMedalAchievement) -> some View {
    HStack(spacing: 14) {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(medal.unlocked ? AnyShapeStyle(division.gradient) : AnyShapeStyle(OkkleColor.muted.opacity(0.22)))
        .frame(width: 34, height: 34)
        .overlay(
          Image(systemName: medal.symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(medal.unlocked ? .white : OkkleColor.muted)
        )
      VStack(alignment: .leading, spacing: 2) {
        Text(medal.label)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(medal.unlocked ? OkkleColor.ink : OkkleColor.muted)
        Text(medal.desc)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .lineLimit(1)
      }
      Spacer()
      if medal.unlocked {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(OkkleColor.brand)
      } else {
        Text("\(Int((medal.progress * 100).rounded()))%")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(OkkleColor.muted)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

// MARK: - Solo season (fictional-club table, weekly form, promotion/relegation)

/// Persisted league standing. A "season" is a fixed 4-week block; at its end the
/// driver is promoted (top 2) or relegated (bottom 2) of an 8-club table.
struct NativeLeagueState: Codable {
  var divisionRaw: Int
  var seasonStart: Date
  var ceremonyToRaw: Int?
}

/// A piece of silverware for the trophy cabinet — a division won, kept forever.
struct NativeHonour: Codable, Identifiable {
  enum Kind: String, Codable { case champions, playoff }
  let seasonIndex: Int
  let divisionRaw: Int
  let kind: Kind
  let date: Date

  var id: String { "\(seasonIndex)-\(divisionRaw)-\(kind.rawValue)" }
  var division: NativeDivision { NativeDivision(rawValue: divisionRaw) ?? .nationalLeague }
  var title: String {
    kind == .champions ? "\(division.name) champions" : "Promoted from \(division.name)"
  }
  var subtitle: String {
    kind == .champions ? "Won the division outright" : "Won the play-off final"
  }
}

/// The driver's club — name, colour and crest emblem, all theirs to shape.
/// Kit patterns painted over the club colour — solid through to a diagonal sash.
enum NativeKit: Int, CaseIterable {
  case solid, gradient, stripes, hoops, sash, halves

  var name: String {
    switch self {
    case .solid: return "Solid"
    case .gradient: return "Fade"
    case .stripes: return "Stripes"
    case .hoops: return "Hoops"
    case .sash: return "Sash"
    case .halves: return "Halves"
    }
  }
}

/// The outline of the badge — a real football-crest silhouette, not just a square.
enum NativeCrestShape: Int, CaseIterable {
  case rounded, circle, shield, hexagon, diamond, oval, octagon, pennant, spade, tudor, banner, pentagon, heater

  /// The shapes offered in the editor (pennant + oval retired — kept in the enum
  /// so saved badges keep their raw values, but no longer selectable; oval read
  /// as a duplicate roundel).
  static let pickable: [NativeCrestShape] = allCases.filter { $0 != .pennant && $0 != .oval }

  /// Coins to unlock — simple shapes are free/cheap, proper football crests cost more.
  var coins: Int {
    switch self {
    case .rounded, .circle: return 0
    case .diamond, .hexagon, .octagon, .pentagon, .oval: return 150
    case .shield, .spade, .tudor, .banner, .heater, .pennant: return 450
    }
  }

  var name: String {
    switch self {
    case .rounded: return "Tile"
    case .circle: return "Roundel"
    case .shield: return "Shield"
    case .hexagon: return "Hex"
    case .diamond: return "Diamond"
    case .oval: return "Oval"
    case .octagon: return "Octagon"
    case .pennant: return "Pennant"
    case .spade: return "Spade"
    case .tudor: return "Tudor"
    case .banner: return "Banner"
    case .pentagon: return "Pentagon"
    case .heater: return "Heater"
    }
  }

  func anyShape() -> AnyShape {
    switch self {
    case .rounded: return AnyShape(NativeRoundedRel())
    case .circle: return AnyShape(Circle())
    case .shield: return AnyShape(NativeShieldShape())
    case .hexagon: return AnyShape(NativeHexagonShape())
    case .diamond: return AnyShape(NativeDiamondShape())
    case .oval: return AnyShape(Ellipse())
    case .octagon: return AnyShape(NativeOctagonShape())
    case .pennant: return AnyShape(NativePennantShape())
    case .spade: return AnyShape(NativeSpadeShape())
    case .tudor: return AnyShape(NativeTudorShape())
    case .banner: return AnyShape(NativeBannerShieldShape())
    case .pentagon: return AnyShape(NativePentagonShape())
    case .heater: return AnyShape(NativeHeaterShape())
    }
  }
}

struct NativeRoundedRel: Shape {
  func path(in r: CGRect) -> Path { RoundedRectangle(cornerRadius: r.width * 0.26, style: .continuous).path(in: r) }
}

struct NativeShieldShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.04))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.04))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.55))
    p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.86))
    p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.55), control: CGPoint(x: r.minX, y: r.minY + r.height * 0.86))
    p.closeSubpath()
    return p
  }
}

struct NativeHexagonShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let cx = r.midX, cy = r.midY, rad = min(r.width, r.height) / 2
    for i in 0..<6 {
      let a = (Double(i) * 60.0 - 90.0) * .pi / 180.0
      let pt = CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
      if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
  }
}

struct NativeDiamondShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.midX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
    p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX, y: r.midY))
    p.closeSubpath()
    return p
  }
}

struct NativeOctagonShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let cx = r.midX, cy = r.midY, rad = min(r.width, r.height) / 2
    for i in 0..<8 {
      let a = (Double(i) * 45.0 - 22.5) * .pi / 180.0
      let pt = CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
      if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
  }
}

/// A bunting pennant — flat top, straight sides into a point.
struct NativePennantShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.04))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.04))
    p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
    p.closeSubpath()
    return p
  }
}

/// A heraldic spade — a peaked top centre curving down to a point.
struct NativeSpadeShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let w = r.width, h = r.height
    p.move(to: CGPoint(x: r.midX, y: r.minY))
    p.addLine(to: CGPoint(x: r.minX + w * 0.92, y: r.minY + h * 0.28))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.5))
    p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.minY + h * 0.84))
    p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.5), control: CGPoint(x: r.minX, y: r.minY + h * 0.84))
    p.addLine(to: CGPoint(x: r.minX + w * 0.08, y: r.minY + h * 0.28))
    p.closeSubpath()
    return p
  }
}

/// A Tudor shield — rounded top corners curving down to a point.
struct NativeTudorShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let w = r.width, h = r.height
    p.move(to: CGPoint(x: r.minX, y: r.minY + h * 0.16))
    p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.16, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - w * 0.16, y: r.minY))
    p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.16), control: CGPoint(x: r.maxX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.55))
    p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.minY + h * 0.86))
    p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.55), control: CGPoint(x: r.minX, y: r.minY + h * 0.86))
    p.closeSubpath()
    return p
  }
}

/// A banner-top shield — a flat scroll ledge across the top, shield below.
struct NativeBannerShieldShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let w = r.width, h = r.height
    p.move(to: CGPoint(x: r.minX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.20))
    p.addLine(to: CGPoint(x: r.maxX - w * 0.07, y: r.minY + h * 0.20))
    p.addLine(to: CGPoint(x: r.maxX - w * 0.07, y: r.minY + h * 0.56))
    p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX - w * 0.07, y: r.minY + h * 0.86))
    p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.07, y: r.minY + h * 0.56), control: CGPoint(x: r.minX + w * 0.07, y: r.minY + h * 0.86))
    p.addLine(to: CGPoint(x: r.minX + w * 0.07, y: r.minY + h * 0.20))
    p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.20))
    p.closeSubpath()
    return p
  }
}

/// A point-up pentagon.
struct NativePentagonShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let cx = r.midX, cy = r.midY, rad = min(r.width, r.height) / 2
    for i in 0..<5 {
      let a = (Double(i) * 72.0 - 90.0) * .pi / 180.0
      let pt = CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
      if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
  }
}

/// A heater shield — flat top, straight sides angling to a point.
struct NativeHeaterShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.03))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.03))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.45))
    p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.45))
    p.closeSubpath()
    return p
  }
}

/// Gold stars above a crest — one per division title won, like a real badge.
struct NativeTitleStars: View {
  let count: Int
  var size: CGFloat = 11
  var body: some View {
    if count > 0 {
      HStack(spacing: 3) {
        ForEach(0..<min(count, 5), id: \.self) { _ in
          Image(systemName: "star.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.20))
        }
      }
    }
  }
}

/// A metallic edge around the badge — prestige trim.
enum NativeTrim: Int, CaseIterable {
  case none, white, black, gold, silver, bronze, graphite, roseGold

  var name: String {
    switch self {
    case .none: return "None"
    case .white: return "White"
    case .black: return "Black"
    case .gold: return "Gold"
    case .silver: return "Silver"
    case .bronze: return "Bronze"
    case .graphite: return "Graphite"
    case .roseGold: return "Rose"
    }
  }

  var color: Color {
    switch self {
    case .none: return .white.opacity(0.30)
    case .white: return .white
    case .black: return Color(red: 0.12, green: 0.12, blue: 0.14)
    case .gold: return Color(red: 0.95, green: 0.78, blue: 0.25)
    case .silver: return Color(red: 0.80, green: 0.82, blue: 0.86)
    case .bronze: return Color(red: 0.80, green: 0.52, blue: 0.27)
    case .graphite: return Color(red: 0.36, green: 0.38, blue: 0.42)
    case .roseGold: return Color(red: 0.90, green: 0.62, blue: 0.58)
    }
  }

  var widthRatio: CGFloat { self == .none ? 0.02 : 0.06 }
}

struct NativeClubIdentity: Codable {
  var name: String
  var colorIndex: Int
  var emblem: String
  var kitIndex: Int? = nil
  var shapeIndex: Int? = nil
  var secondaryIndex: Int? = nil
  var trimIndex: Int? = nil

  // First `free*` of each are free; the rest are bought with Coins.
  static let palette: [Color] = [
    Color(red: 0.12, green: 0.55, blue: 0.95),  // blue (free)
    Color(red: 0.85, green: 0.23, blue: 0.24),  // red (free)
    Color(red: 0.12, green: 0.66, blue: 0.42),  // green (free)
    Color(red: 0.55, green: 0.27, blue: 0.68),  // purple
    Color(red: 0.95, green: 0.55, blue: 0.10),  // orange
    Color(red: 0.10, green: 0.20, blue: 0.45),  // navy
    Color(red: 0.85, green: 0.65, blue: 0.13),  // gold
    Color(red: 0.83, green: 0.24, blue: 0.55),  // pink
    Color(red: 0.10, green: 0.62, blue: 0.62),  // teal
    Color(red: 0.40, green: 0.42, blue: 0.46),  // slate
    Color(red: 0.55, green: 0.75, blue: 0.20),  // lime
    Color(red: 0.90, green: 0.36, blue: 0.30),  // coral
  ]
  static let emblems = ["shield.fill", "flame.fill", "bolt.fill", "hare.fill", "crown.fill", "flag.fill", "star.fill", "pawprint.fill", "anchor", "seal.fill", "hexagon.fill", "diamond.fill", "bird.fill", "tortoise.fill", "ant.fill", "fish.fill", "leaf.fill", "drop.fill", "cat.fill", "hammer.fill", "soccerball", "sailboat.fill", "building.columns.fill", "globe.europe.africa.fill", "dog.fill", "lizard.fill", "ladybug.fill", "car.fill", "bus.fill", "bicycle", "fuelpump.fill", "steeringwheel", "airplane", "gearshape.fill"]

  static let freeColours = 3
  static let freeCrests = 3
  static let freeKits = 1
  static let freeShapes = 2
  static let freeTrims = 2
  static let colourCost = 300
  static let crestCost = 250
  static let kitCost = 200
  static let shapeCost = 250
  static let trimCost = 200

  static func colourId(_ index: Int) -> String { "colour-\(index)" }
  static func crestId(_ symbol: String) -> String { "crest-\(symbol)" }
  static func kitId(_ index: Int) -> String { "kit-\(index)" }
  static func shapeId(_ index: Int) -> String { "shape-\(index)" }
  static func trimId(_ index: Int) -> String { "trim-\(index)" }

  private static func paletteColor(_ index: Int) -> Color {
    palette[max(0, min(index, palette.count - 1))]
  }

  var color: Color { NativeClubIdentity.paletteColor(colorIndex) }
  var secondaryColor: Color? { secondaryIndex.map { NativeClubIdentity.paletteColor($0) } }
  var kit: NativeKit { NativeKit(rawValue: kitIndex ?? 0) ?? .solid }
  var crestShape: NativeCrestShape { NativeCrestShape(rawValue: shapeIndex ?? 0) ?? .rounded }
  var trim: NativeTrim { NativeTrim(rawValue: trimIndex ?? 0) ?? .none }
}

/// A rounded tile painted in the club colour with its kit pattern and (optional)
/// crest — reused in the editor, the matchday card and the table.
struct NativeKitTile: View {
  let kit: NativeKit
  let color: Color
  var secondary: Color? = nil
  var crestShape: NativeCrestShape = .rounded
  var trim: NativeTrim = .none
  var size: CGFloat = 44
  var emblem: String? = nil

  private var darkAccent: Color { secondary ?? Color.black.opacity(0.20) }
  private var lightAccent: Color { secondary ?? Color.white.opacity(0.24) }

  var body: some View {
    let shape = crestShape.anyShape()
    return shape
      .fill(color)
      .frame(width: size, height: size)
      .overlay(pattern)
      .overlay(
        Group {
          if let emblem {
            Image(systemName: emblem)
              .font(.system(size: size * 0.44, weight: .semibold))
              .foregroundStyle(.white)
              .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
          }
        }
      )
      .clipShape(shape)
      .overlay(shape.stroke(trim.color, lineWidth: max(1, size * trim.widthRatio)))
  }

  @ViewBuilder private var pattern: some View {
    switch kit {
    case .solid:
      Color.clear
    case .gradient:
      LinearGradient(colors: [.white.opacity(0.22), .black.opacity(0.20)], startPoint: .top, endPoint: .bottom)
    case .stripes:
      HStack(spacing: 0) {
        ForEach(0..<6, id: \.self) { i in
          Rectangle().fill(i % 2 == 0 ? Color.clear : darkAccent)
        }
      }
    case .hoops:
      VStack(spacing: 0) {
        ForEach(0..<6, id: \.self) { i in
          Rectangle().fill(i % 2 == 0 ? Color.clear : lightAccent)
        }
      }
    case .sash:
      GeometryReader { geo in
        Path { p in
          p.move(to: CGPoint(x: 0, y: geo.size.height))
          p.addLine(to: CGPoint(x: geo.size.width * 0.34, y: geo.size.height))
          p.addLine(to: CGPoint(x: geo.size.width, y: 0))
          p.addLine(to: CGPoint(x: geo.size.width * 0.66, y: 0))
          p.closeSubpath()
        }
        .fill(secondary ?? .white.opacity(0.30))
      }
    case .halves:
      HStack(spacing: 0) {
        Rectangle().fill(Color.clear)
        Rectangle().fill(darkAccent)
      }
    }
  }
}

/// The Coins wallet — earned from medals, wins and promotions, spent only on
/// club customisation. Cosmetic by design: Coins never help you win a match.
@MainActor
enum NativeWallet {
  private static let unlockedKey = "uk.okkle.native.wallet.unlocked.v1"

  /// Deterministic: total Coins earned to date from real achievements.
  static func earned(store: OkkleStore) -> Int {
    var total = 0
    for medal in NativeMedalEngine.achievements(store: store) where medal.unlocked {
      switch medal.tier {
      case .bronze:  total += 10
      case .silver:  total += 25
      case .gold:    total += 50
      case .special: total += 40
      }
    }
    for honour in NativeSeasonEngine.honours() {
      total += honour.kind == .champions ? 200 : 150
    }
    return total
  }

  static func unlocked() -> Set<String> {
    Set(UserDefaults.standard.array(forKey: unlockedKey) as? [String] ?? [])
  }

  static func cost(for id: String) -> Int {
    if id.hasPrefix("colour-") { return NativeClubIdentity.colourCost }
    if id.hasPrefix("crest-") { return NativeClubIdentity.crestCost }
    if id.hasPrefix("kit-") { return NativeClubIdentity.kitCost }
    if id.hasPrefix("shape-") {
      let raw = Int(id.dropFirst("shape-".count)) ?? 0
      return NativeCrestShape(rawValue: raw)?.coins ?? NativeClubIdentity.shapeCost
    }
    if id.hasPrefix("trim-") { return NativeClubIdentity.trimCost }
    return 0
  }

  static func spent() -> Int { unlocked().reduce(0) { $0 + cost(for: $1) } }
  static func balance(store: OkkleStore) -> Int { max(0, earned(store: store) - spent()) }

  static func isUnlocked(_ id: String, free: Bool) -> Bool { free || unlocked().contains(id) }

  /// Buy an item if it isn't owned and the balance covers it. Returns success.
  static func purchase(_ id: String, store: OkkleStore) -> Bool {
    var set = unlocked()
    guard !set.contains(id), balance(store: store) >= cost(for: id) else { return false }
    set.insert(id)
    UserDefaults.standard.set(Array(set), forKey: unlockedKey)
    return true
  }
}

/// One row of the division table — the driver plus the fictional rival clubs.
struct NativeClubRow: Identifiable {
  let id: Int
  let name: String
  let isYou: Bool
  let played: Int
  let points: Int
  let form: [Int] // 3 = win, 1 = draw, 0 = loss
}

struct NativeSeasonSnapshot {
  let division: NativeDivision
  let matchweek: Int
  let totalWeeks: Int
  let rows: [NativeClubRow]
  let yourRow: NativeClubRow
  let yourPosition: Int
  let ceremonyTo: NativeDivision?
  let bankedThisSeason: Double   // real tax £ you've banked this season
  let winBar: Double             // real £/week needed for a "win" this division
}

/// This week's match — you versus one past-self ghost, scored in real tax saved.
struct NativeFixture {
  enum State { case kickoff, live, fullTime }
  /// What the final week is worth, based on where you sit in the table.
  enum Stakes { case none, title, playoff, survival }
  let opponent: String
  let opponentSymbol: String
  let yourBanked: Double
  let oppBanked: Double
  let yourGoals: Int
  let oppGoals: Int
  let matchweek: Int
  let totalWeeks: Int
  let isFinalDay: Bool
  let state: State
  let stakes: Stakes
  let weeklyTarget: Double   // £ tax saved this week that earns the win (3 pts)

  /// How you earn league points each week, from real tax saved vs your target.
  var pointsThisWeek: Int { yourBanked >= weeklyTarget ? 3 : (yourBanked >= weeklyTarget * 0.5 ? 1 : 0) }
  var drawTarget: Double { weeklyTarget * 0.5 }
  var progressToTarget: Double { weeklyTarget <= 0 ? 0 : min(1, yourBanked / weeklyTarget) }

  var youAreWinning: Bool { yourGoals > oppGoals }
  var isLevel: Bool { yourGoals == oppGoals }
  var lead: Double { yourBanked - oppBanked }
}

/// The gaffer — a plain-spoken British manager who narrates the week. The solo
/// stand-in for a crowd: motivation comes from his team-talk, not other users.
enum NativeGaffer {
  static func teamTalk(for f: NativeFixture) -> String {
    let opp = f.opponent
    let toWin = max(0, Int((f.oppBanked - f.yourBanked).rounded())) + 1

    switch f.stakes {
    case .title:
      switch f.state {
      case .kickoff: return "Title decider, this. Beat \(opp) and the trophy's ours. Let's not leave it to chance."
      case .live:
        if f.youAreWinning { return "We're champions if this holds — £\(Int(f.lead.rounded())) clear of \(opp). See it home." }
        if f.isLevel { return "Level with \(opp) and the title on the line. One more shift wins it." }
        return "We've slipped behind \(opp) with the trophy at stake. £\(toWin) saved snatches it back — go."
      case .fullTime:
        return f.youAreWinning ? "Champions! Saw off \(opp) when it mattered most. Up we go." : "So close. \(opp) pipped us — we'll settle for the play-offs."
      }
    case .playoff:
      switch f.state {
      case .kickoff: return "Play-off final. Win this one match against \(opp) and we're promoted. Everything on it."
      case .live:
        if f.youAreWinning { return "We're going up — £\(Int(f.lead.rounded())) ahead of \(opp) in the final. Hold your nerve." }
        if f.isLevel { return "Dead level in the play-off final. Next shift could be the one that sends us up." }
        return "Behind in the play-off final. £\(toWin) of tax saved beats \(opp) and books promotion — dig in."
      case .fullTime:
        return f.youAreWinning ? "We've done it! Beat \(opp) in the final — promotion through the play-offs!" : "Heartbreak. \(opp) won the final. We dust ourselves down and go again."
      }
    case .survival:
      switch f.state {
      case .kickoff: return "Must not lose this. Avoid defeat to \(opp) and we stay up. Roll your sleeves up."
      case .live:
        if f.youAreWinning { return "This keeps us up — £\(Int(f.lead.rounded())) clear of \(opp). Don't switch off." }
        if f.isLevel { return "A draw with \(opp) keeps us safe. Hold it together." }
        return "We're going down as it stands. £\(toWin) saved beats \(opp) and saves our season — fight."
      case .fullTime:
        return f.youAreWinning || f.isLevel ? "Survived! Held off \(opp) when it counted. We live to fight another season." : "Relegated. \(opp) sent us down. We bounce straight back."
      }
    case .none:
      switch f.state {
      case .kickoff:
        return "\(opp) up next. £\(Int(f.oppBanked.rounded())) of tax saved beats them — log your shifts and it's ours."
      case .live:
        if f.youAreWinning { return "Tidy. £\(Int(f.lead.rounded())) clear of \(opp). Keep logging and the points are ours." }
        if f.isLevel { return "Neck and neck with \(opp). One more decent shift nicks it." }
        return "We're chasing \(opp) — £\(toWin) of tax saved this week flips the result."
      case .fullTime:
        if f.youAreWinning { return "Three points. Saw off \(opp) — that's how we climb." }
        if f.isLevel { return "A point apiece with \(opp). Take it and kick on." }
        return "\(opp) had our number this week. Reset, go harder."
      }
    }
  }
}

@MainActor
enum NativeSeasonEngine {
  static let weeksPerSeason = 4
  static let weekSeconds: TimeInterval = 7 * 24 * 3600
  private static let storageKey = "uk.okkle.native.league.season.v1"
  private static let honoursKey = "uk.okkle.native.league.honours.v1"
  private static let clubKey = "uk.okkle.native.league.club.v1"
  private static let epoch = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01

  /// Your rivals are your own past selves — no fictional clubs, every result real.
  /// Each ghost replays real weekly banked £ drawn from your own history.
  enum Ghost: Int, CaseIterable {
    case lastSeason   // you, one 4-week block ago
    case bestEver     // your best weeks ever, replayed
    case average      // your all-time average week, held steady

    var clubName: String {
      switch self {
      case .lastSeason: return "Last Season You"
      case .bestEver:   return "Your Best XI"
      case .average:    return "The Form Book"
      }
    }

    var symbol: String {
      switch self {
      case .lastSeason: return "clock.arrow.circlepath"
      case .bestEver:   return "star.fill"
      case .average:    return "chart.bar.fill"
      }
    }
  }

  // MARK: Public

  static func snapshot(store: OkkleStore) -> NativeSeasonSnapshot {
    var state = loadState(store: store)
    advance(&state, store: store)
    save(state)
    let division = NativeDivision(rawValue: state.divisionRaw) ?? .nationalLeague
    let rows = standings(seasonStart: state.seasonStart, divisionRaw: state.divisionRaw, store: store)
    let completed = completedWeeks(since: state.seasonStart)
    let yourRow = rows.first { $0.isYou } ?? NativeClubRow(id: 0, name: "You", isYou: true, played: 0, points: 0, form: [])
    let position = (rows.firstIndex { $0.isYou } ?? 0) + 1
    var banked = 0.0
    for week in 0..<completed {
      let start = state.seasonStart.addingTimeInterval(Double(week) * weekSeconds)
      banked += weeklyBanked(start: start, end: start.addingTimeInterval(weekSeconds), store: store)
    }
    return NativeSeasonSnapshot(
      division: division,
      matchweek: completed,
      totalWeeks: weeksPerSeason,
      rows: rows,
      yourRow: yourRow,
      yourPosition: position,
      ceremonyTo: state.ceremonyToRaw.flatMap { NativeDivision(rawValue: $0) },
      bankedThisSeason: banked,
      winBar: winBar(division, store: store)
    )
  }

  static func clearCeremony(store: OkkleStore) {
    var state = loadState(store: store)
    state.ceremonyToRaw = nil
    save(state)
  }

  /// This week's fixture: you vs one rotating past-self, live in real tax saved.
  static func fixture(store: OkkleStore) -> NativeFixture {
    var state = loadState(store: store)
    advance(&state, store: store)
    save(state)
    let division = NativeDivision(rawValue: state.divisionRaw) ?? .nationalLeague
    let completed = completedWeeks(since: state.seasonStart)
    let total = weeksPerSeason
    let weekIndex = min(completed, total - 1)
    let weekStart = state.seasonStart.addingTimeInterval(Double(weekIndex) * weekSeconds)
    let weekEnd = weekStart.addingTimeInterval(weekSeconds)
    let weekFinished = completed > weekIndex
    let yourBanked = weeklyBanked(start: weekStart, end: weekFinished ? weekEnd : min(Date(), weekEnd), store: store)

    let ghost = Ghost.allCases[weekIndex % Ghost.allCases.count]
    let oppBanked = ghostWeekBanked(ghost: ghost, weekIndex: weekIndex, seasonStart: state.seasonStart, store: store)

    let goalUnit = max(1, winBar(division, store: store) / 3)
    let yourGoals = min(6, Int((yourBanked / goalUnit).rounded(.down)))
    let oppGoals = min(6, Int((oppBanked / goalUnit).rounded(.down)))

    let fxState: NativeFixture.State = weekFinished ? .fullTime : (yourBanked <= 0 ? .kickoff : .live)
    let isFinal = weekIndex == total - 1

    var stakes: NativeFixture.Stakes = .none
    if isFinal {
      let rows = standings(seasonStart: state.seasonStart, divisionRaw: state.divisionRaw, store: store)
      let position = (rows.firstIndex { $0.isYou } ?? 0) + 1
      let canPromote = division != .premierLeague
      if position == 1, canPromote {
        stakes = .title
      } else if (position == 2 || position == 3), canPromote {
        stakes = .playoff
      } else if position >= rows.count, division != .nationalLeague {
        stakes = .survival
      }
    }

    return NativeFixture(
      opponent: ghost.clubName,
      opponentSymbol: ghost.symbol,
      yourBanked: yourBanked,
      oppBanked: oppBanked,
      yourGoals: yourGoals,
      oppGoals: oppGoals,
      matchweek: weekIndex + 1,
      totalWeeks: total,
      isFinalDay: isFinal,
      state: fxState,
      stakes: stakes,
      weeklyTarget: winBar(division, store: store)
    )
  }

  private static func ghostWeekBanked(ghost: Ghost, weekIndex: Int, seasonStart: Date, store: OkkleStore) -> Double {
    switch ghost {
    case .lastSeason:
      let start = seasonStart.addingTimeInterval(Double(weekIndex) * weekSeconds - weekSeconds * Double(weeksPerSeason))
      return weeklyBanked(start: start, end: start.addingTimeInterval(weekSeconds), store: store)
    case .bestEver:
      let best = Array(allWeeklyBanked(store: store).sorted(by: >).prefix(weeksPerSeason))
      return weekIndex < best.count ? best[weekIndex] : 0
    case .average:
      return weeklyBenchmark(store: store)
    }
  }

  // MARK: Standings

  static func standings(seasonStart: Date, divisionRaw: Int, store: OkkleStore) -> [NativeClubRow] {
    let division = NativeDivision(rawValue: divisionRaw) ?? .nationalLeague
    let completed = completedWeeks(since: seasonStart)
    let bar = winBar(division, store: store)

    // You — this season's real weekly banked £.
    var yourForm: [Int] = []
    var yourPoints = 0
    for week in 0..<completed {
      let start = seasonStart.addingTimeInterval(Double(week) * weekSeconds)
      let result = result(forBanked: weeklyBanked(start: start, end: start.addingTimeInterval(weekSeconds), store: store), bar: bar)
      yourPoints += result
      yourForm.append(result)
    }
    let yourName = clubIdentity(store: store).name
    var rows = [NativeClubRow(id: 0, name: yourName, isYou: true, played: completed, points: yourPoints, form: Array(yourForm.suffix(5)))]

    // Your past selves — real history replayed, no fictional clubs.
    let bestWeeks = topWeeklyBanked(count: weeksPerSeason, store: store)
    let benchmark = weeklyBenchmark(store: store)
    for ghost in Ghost.allCases {
      var points = 0
      var form: [Int] = []
      for week in 0..<completed {
        let banked: Double
        switch ghost {
        case .lastSeason:
          let start = seasonStart.addingTimeInterval(Double(week) * weekSeconds - weekSeconds * Double(weeksPerSeason))
          banked = weeklyBanked(start: start, end: start.addingTimeInterval(weekSeconds), store: store)
        case .bestEver:
          banked = week < bestWeeks.count ? bestWeeks[week] : 0
        case .average:
          banked = benchmark
        }
        let r = result(forBanked: banked, bar: bar)
        points += r
        form.append(r)
      }
      rows.append(NativeClubRow(id: ghost.rawValue + 1, name: ghost.clubName, isYou: false, played: completed, points: points, form: Array(form.suffix(5))))
    }

    // Ties break in your favour, then by name — deterministic, no RNG.
    return rows.sorted {
      ($0.points, $0.isYou ? 1 : 0, $1.name) > ($1.points, $1.isYou ? 1 : 0, $0.name)
    }
  }

  // MARK: Mechanics — all in real banked £

  /// A "win" each week means out-earning your own pace. The bar compounds ~25%
  /// per division, so each tier up is markedly harder to win and to hold:
  /// National 1.0× → League Two 1.25× → League One 1.56× → Championship 1.95×
  /// → Premier League 2.44× your personal weekly benchmark.
  static func winBar(_ division: NativeDivision, store: OkkleStore) -> Double {
    weeklyBenchmark(store: store) * pow(1.25, Double(division.rawValue))
  }

  private static func result(forBanked banked: Double, bar: Double) -> Int {
    banked >= bar ? 3 : (banked >= bar * 0.5 ? 1 : 0)
  }

  /// Real tax £ banked in a week = that week's mileage deduction × your marginal rate.
  static func weeklyBanked(start: Date, end: Date, store: OkkleStore) -> Double {
    let range = start..<end
    let rate = store.settings.incomeBracket.marginalRate(region: store.settings.region)
    var deduction = 0.0
    for record in store.records where range.contains(record.date) {
      deduction += store.calcDeduction(miles: record.miles ?? 0, vehicle: record.vehicle ?? store.settings.defaultVehicle, date: record.date)
    }
    for trip in store.trips where range.contains(trip.startedAt) {
      deduction += store.calcDeduction(miles: trip.miles, vehicle: trip.vehicle, date: trip.startedAt)
    }
    return deduction * rate
  }

  /// Your typical week: all-time average banked £, with a gentle floor so brand-new
  /// drivers can still post a win in their first weeks.
  static func weeklyBenchmark(store: OkkleStore) -> Double {
    let buckets = allWeeklyBanked(store: store).filter { $0 > 0 }
    guard !buckets.isEmpty else { return 12 } // ~£12 floor before any history
    let avg = buckets.reduce(0, +) / Double(buckets.count)
    return max(8, avg)
  }

  private static func topWeeklyBanked(count: Int, store: OkkleStore) -> [Double] {
    Array(allWeeklyBanked(store: store).sorted(by: >).prefix(count))
  }

  /// Banked £ bucketed into aligned weeks across the driver's whole history.
  private static func allWeeklyBanked(store: OkkleStore) -> [Double] {
    let dates = store.records.map(\.date) + store.trips.map(\.startedAt)
    guard let earliest = dates.min() else { return [] }
    let firstWeek = floor(earliest.timeIntervalSince1970 / weekSeconds)
    let lastWeek = floor(Date().timeIntervalSince1970 / weekSeconds)
    guard lastWeek >= firstWeek else { return [] }
    var buckets: [Double] = []
    var w = firstWeek
    while w <= lastWeek {
      let start = Date(timeIntervalSince1970: w * weekSeconds)
      buckets.append(weeklyBanked(start: start, end: start.addingTimeInterval(weekSeconds), store: store))
      w += 1
    }
    return buckets
  }

  // MARK: Season advance + persistence

  private static func advance(_ state: inout NativeLeagueState, store: OkkleStore) {
    let seasonLength = weekSeconds * Double(weeksPerSeason)
    var guardrail = 0
    while Date().timeIntervalSince(state.seasonStart) >= seasonLength, guardrail < 240 {
      let rows = standings(seasonStart: state.seasonStart, divisionRaw: state.divisionRaw, store: store)
      let yourRow = rows.first { $0.isYou }
      let position = (rows.firstIndex { $0.isYou } ?? 0) + 1
      let wonFinal = (yourRow?.form.last ?? 0) == 3
      let canPromote = state.divisionRaw < NativeDivision.premierLeague.rawValue
      let fromDivision = state.divisionRaw
      let season = seasonIndex(state.seasonStart)

      if position == 1, canPromote {
        // Champions — automatic promotion.
        state.divisionRaw += 1
        state.ceremonyToRaw = state.divisionRaw
        recordHonour(NativeHonour(seasonIndex: season, divisionRaw: fromDivision, kind: .champions, date: state.seasonStart.addingTimeInterval(seasonLength)))
      } else if (position == 2 || position == 3), canPromote, wonFinal {
        // Play-off final won — promoted the hard way.
        state.divisionRaw += 1
        state.ceremonyToRaw = state.divisionRaw
        recordHonour(NativeHonour(seasonIndex: season, divisionRaw: fromDivision, kind: .playoff, date: state.seasonStart.addingTimeInterval(seasonLength)))
      } else if position >= rows.count, state.divisionRaw > 0 {
        // Bottom of the table — relegated.
        state.divisionRaw -= 1
      }
      state.seasonStart = state.seasonStart.addingTimeInterval(seasonLength)
      guardrail += 1
    }
  }

  private static func seasonIndex(_ seasonStart: Date) -> Int {
    Int(floor(seasonStart.timeIntervalSince(epoch) / (weekSeconds * Double(weeksPerSeason))))
  }

  private static func loadState(store: OkkleStore) -> NativeLeagueState {
    if let data = UserDefaults.standard.data(forKey: storageKey),
       let state = try? JSONDecoder().decode(NativeLeagueState.self, from: data) {
      return state
    }
    let division = NativeLeagueEngine.status(store: store).division
    let state = NativeLeagueState(divisionRaw: division.rawValue, seasonStart: alignedSeasonStart(for: Date()), ceremonyToRaw: nil)
    save(state)
    return state
  }

  private static func save(_ state: NativeLeagueState) {
    if let data = try? JSONEncoder().encode(state) {
      UserDefaults.standard.set(data, forKey: storageKey)
    }
  }

  // MARK: Honours (the trophy cabinet)

  static func honours() -> [NativeHonour] {
    guard let data = UserDefaults.standard.data(forKey: honoursKey),
          let list = try? JSONDecoder().decode([NativeHonour].self, from: data) else { return [] }
    return list.sorted { $0.date > $1.date }
  }

  private static func recordHonour(_ honour: NativeHonour) {
    var list = honours()
    guard !list.contains(where: { $0.id == honour.id }) else { return }
    list.append(honour)
    if let data = try? JSONEncoder().encode(list) {
      UserDefaults.standard.set(data, forKey: honoursKey)
    }
  }

  // MARK: Club identity

  static func clubIdentity(store: OkkleStore) -> NativeClubIdentity {
    if let data = UserDefaults.standard.data(forKey: clubKey),
       let club = try? JSONDecoder().decode(NativeClubIdentity.self, from: data) {
      return club
    }
    let base = store.settings.name.isEmpty ? "Your club" : "\(store.settings.name) FC"
    return NativeClubIdentity(name: base, colorIndex: 0, emblem: "shield.fill")
  }

  static func saveClubIdentity(_ club: NativeClubIdentity) {
    if let data = try? JSONEncoder().encode(club) {
      UserDefaults.standard.set(data, forKey: clubKey)
    }
  }

  // MARK: Helpers

  private static func completedWeeks(since seasonStart: Date) -> Int {
    max(0, min(weeksPerSeason, Int(floor(Date().timeIntervalSince(seasonStart) / weekSeconds))))
  }

  private static func alignedSeasonStart(for date: Date) -> Date {
    let blockLength = weekSeconds * Double(weeksPerSeason)
    let blocks = floor(date.timeIntervalSince(epoch) / blockLength)
    return epoch.addingTimeInterval(blocks * blockLength)
  }
}
