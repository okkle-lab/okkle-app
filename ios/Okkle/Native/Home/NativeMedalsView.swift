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
      Divider()
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
