import Foundation

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
  static func achievements(store: OkkleStore, period: NativeProgressPeriod = .allTime) -> [NativeMedalAchievement] {
    let stats = stats(store: store, period: period)
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
      symbol: nativeCurrencySymbolName("sterlingsign.circle.fill"),
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
      unit: store.settings.taxCountry == .us ? "miles — iconic US routes" : "miles — iconic UK routes",
      specs: store.settings.taxCountry == .us
        ? [
          (54, "Boston → Providence"), (120, "Los Angeles → San Diego"), (200, "Dallas → Austin"),
          (330, "Houston → New Orleans"), (560, "Chicago → Memphis"), (874, "Chicago → Denver"),
          (1_407, "Los Angeles → Dallas"),
        ]
        : [
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

  private static func stats(store: OkkleStore, period: NativeProgressPeriod) -> NativeMedalStats {
    let calendar = Calendar.current
    let scoped = scopedActivity(store: store, period: period, calendar: calendar)
    let records = scoped.records
    let trips = scoped.trips
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
    let taxSaved = NativeProgressSummary.mileageTaxSavings(store: store, period: period).taxSaved
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
      taxSaved: taxSaved,
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

  private static func scopedActivity(store: OkkleStore, period: NativeProgressPeriod, calendar: Calendar) -> (records: [NativeRecord], trips: [NativeTrip]) {
    switch period {
    case .weekly:
      let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) ?? DateInterval(
        start: calendar.startOfDay(for: Date()),
        duration: 7 * 24 * 60 * 60
      )
      return (
        store.records.filter { interval.contains($0.date) },
        store.businessTrips.filter { interval.contains($0.startedAt) }
      )
    case .yearToDate:
      return (store.yearRecords, store.yearTrips)
    case .allTime:
      return (store.records, store.businessTrips)
    }
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
