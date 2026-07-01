import SwiftUI

enum NativeDivision: Int, CaseIterable, Comparable {
  case nationalLeague
  case leagueTwo
  case leagueOne
  case championship
  case premierLeague

  static func < (lhs: NativeDivision, rhs: NativeDivision) -> Bool { lhs.rawValue < rhs.rawValue }

  /// Fixed weekly mileage that wins the week in this division — an absolute,
  /// known effort, not something scaled to your own pace. Calibrated to real UK
  /// courier weekly mileage so each tier is a genuine status: a casual driver
  /// settles low, only a dedicated long-range driver holds the Premier League.
  /// None of these are impossible — they're a full week's honest shifts.
  var mileTarget: Int {
    switch self {
    case .nationalLeague: return 50    // a few shifts a week
    case .leagueTwo:      return 120   // steady part-time
    case .leagueOne:      return 220   // committed
    case .championship:   return 340   // full-time
    case .premierLeague:  return 480   // long-range grinder
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
  let weeklyMiles: Int     // your typical weekly mileage
  let division: NativeDivision
  let next: NativeDivision?
  let progressToNext: Double
  let milesToNext: Int     // weekly miles still to average to climb a tier
}

@MainActor
enum NativeLeagueEngine {
  /// Your standing in the pyramid is your sustained weekly mileage: the division
  /// is the toughest tier whose fixed weekly target you can typically clear. It's
  /// a status earned by how much you actually drive, not by a goal bent to your pace.
  static func banked(store: OkkleStore) -> Int {
    Int(store.taxSaved.rounded())
  }

  static func status(store: OkkleStore) -> NativeLeagueStatus {
    let pace = Int(NativeSeasonEngine.avgWeeklyMiles(store: store).rounded())
    let division = NativeDivision.allCases.last(where: { pace >= $0.mileTarget }) ?? .nationalLeague
    let next = NativeDivision(rawValue: division.rawValue + 1)
    if let next {
      let span = max(1, next.mileTarget - division.mileTarget)
      let into = pace - division.mileTarget
      return NativeLeagueStatus(
        weeklyMiles: pace,
        division: division,
        next: next,
        progressToNext: min(1, Double(into) / Double(span)),
        milesToNext: max(0, next.mileTarget - pace)
      )
    }
    return NativeLeagueStatus(weeklyMiles: pace, division: division, next: nil, progressToNext: 1, milesToNext: 0)
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
