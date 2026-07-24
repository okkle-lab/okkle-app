import CoreLocation
import SwiftUI

let nativeInsightPromptAnimation = Animation.spring(response: 0.46, dampingFraction: 0.72, blendDuration: 0.08)

// Keep Insights visually distinct as Okkle's AI surface while retaining the
// native system typography, controls, spacing, and semantic card materials.
let nativeAIAccentPink = Color(red: 1.00, green: 0.22, blue: 0.72)
let nativeAIAccentPurple = Color(red: 0.55, green: 0.30, blue: 1.00)
let nativeAIAccentGradient = LinearGradient(
  colors: [nativeAIAccentPink, nativeAIAccentPurple],
  startPoint: .topLeading,
  endPoint: .bottomTrailing
)

enum NativeInsightPeriod: Int, CaseIterable, Identifiable {
  case today, week, month, year

  var id: Int { rawValue }

  var label: String {
    switch self {
    case .today: return "Today"
    case .week: return "This week"
    case .month: return "Monthly"
    case .year: return "Yearly"
    }
  }

  /// Rolling lookback in days — nil for "Today", which doesn't rebuild the
  /// shift model at all, it just reads todayPlan off the full history.
  var lookbackDays: Int? {
    switch self {
    case .today: return nil
    case .week: return 7
    case .month: return 30
    case .year: return 365
    }
  }
}

struct NativeInsightPeriodTabs: View {
  @Binding var period: NativeInsightPeriod

  var body: some View {
    Picker("", selection: $period) {
      ForEach(NativeInsightPeriod.allCases) { p in
        Text(p.label).tag(p)
      }
    }
    .pickerStyle(.segmented)
    .controlSize(.small)
  }
}

struct NativeShiftPatternsCard: View {
  let shift: NativeShiftInsights
  let visits: [NativeVisit]
  let trips: [NativeTrip]
  @Binding var autoTrackTrips: Bool
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var exploreCandidates = NativeExploreCandidateStore.shared
  @ObservedObject private var locator = NativeOneShotLocator.shared
  @Environment(\.openURL) private var openURL
  @State private var period: NativeInsightPeriod = .today

  /// Same metrics as "This week" for every non-today period — just fed a
  /// wider or narrower slice of the same visit history before re-running
  /// NativeShiftInsights.build, so month/year are directly comparable.
  ///
  /// Year is scoped to the actual UK tax year (store.taxYear), not a rolling
  /// 365 days — it must line up with store.yearIncome/yearMiles/taxSaved,
  /// which are themselves tax-year figures. Mixing a rolling window for
  /// activeHours against a tax-year window for income is exactly what made
  /// an earlier "Est. rate" on this tab silently wrong, which is why it had
  /// been removed rather than fixed properly.
  private var insightVisits: [NativeVisit] { NativeShiftInsights.enrichedVisits(visits: visits, trips: trips) }

  private func shift(for period: NativeInsightPeriod) -> NativeShiftInsights {
    if let cached = scopedShifts[period] { return cached }
    return period == .today ? shift : .empty
  }

  // Cache each period's projection so switching the segmented control is
  // immediate and never re-runs build() across the full visit history.
  @State private var scopedShifts: [NativeInsightPeriod: NativeShiftInsights] = [:]

  /// Keep a single period panel in the vertical screen scroll view. The old
  /// horizontally-paged TabView had to guess and animate its own height while
  /// nested inside that scroll view; Monthly and Yearly would consequently
  /// slide, clip card glows, and jump as their very different heights settled.
  @ViewBuilder private var selectedPeriodPanel: some View {
    switch period {
    case .today:
      NativeDailyInsightPanel(shift: shift, trips: trips)
    case .week:
      NativeWeeklyInsightPanel(shift: shift(for: .week))
    case .month:
      NativeMonthlyInsightPanel(shift: shift(for: .month))
    case .year:
      NativeYearlyInsightPanel(shift: shift(for: .year))
    }
  }

  private func rebuildScopedShifts() {
    let now = Date()
    var inputs: [NativeInsightPeriod: NativeInsightInput] = [:]
    for period in NativeInsightPeriod.allCases where period != .today {
      let cutoff: Date
      if period == .year {
        cutoff = store.taxYear.start
      } else {
        cutoff = Calendar.current.date(byAdding: .day, value: -(period.lookbackDays ?? 0), to: now) ?? now
      }
      inputs[period] = NativeInsightInput(
        visits: insightVisits.filter { $0.arrival >= cutoff },
        store: store,
        generatedAt: now
      )
    }
    Task {
      var projected: [NativeInsightPeriod: NativeShiftInsights] = [:]
      for (period, input) in inputs {
        projected[period] = await NativeInsightsProjector.shared.project(input).shift
      }
      await MainActor.run {
        scopedShifts = projected
        for zone in projected.values.flatMap(\.zones) {
          _ = NativeZonePOIPrior.shared.priorScore(for: zone.coordinate)
        }
      }
    }
  }

  var body: some View {
    // Show useful early reads as soon as a delivery can be inferred. Confidence
    // remains visible while the same model continues building toward a solid
    // pattern; low-confidence copy stays exploratory rather than prescriptive.
    if shift.hasData {
      VStack(alignment: .leading, spacing: 24) {
        if shift.confidence != .high {
          learningStatus
        }

        NativeInsightPeriodTabs(period: $period)

        selectedPeriodPanel
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
      .onAppear { rebuildScopedShifts() }
      .onChange(of: insightVisits) { _ in rebuildScopedShifts() }
      .onChange(of: trips) { _ in rebuildScopedShifts() }
      .onChange(of: store.records) { _ in rebuildScopedShifts() }
      .onChange(of: store.settings.excludedPlaces) { _ in rebuildScopedShifts() }
      .onChange(of: store.insightEvidence) { _ in rebuildScopedShifts() }
    } else if !autoTrackTrips {
      NativeAiCard { offState }
        .transition(.nativeInsightSetupCard)
    } else {
      NativeAiCard { buildingState }
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        .onAppear {
          discoverTentativeZoneIfNeeded()
          // Otherwise the mid-build heatmap has no live-location fallback at
          // all until the high-confidence daily panel requests it — for
          // trips with no route points yet (manual entries), that meant no
          // fallback except a hardcoded default coordinate. Also feeds the
          // Home-address fallback below once it resolves (see onChange).
          NativeOneShotLocator.shared.request()
        }
        .onChange(of: locator.coordinate?.latitude) { _ in
          discoverTentativeZoneIfNeeded()
        }
    }
  }

  private var learningStatus: some View {
    NativeAiCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          Label("Improving your insights", systemImage: "chart.line.uptrend.xyaxis")
            .font(.headline)
            .foregroundStyle(.primary)
          Spacer(minLength: 8)
          Text("\(Int((buildingProgress * 100).rounded()))%")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(nativeAIAccentGradient)
        }
        ProgressView(value: buildingProgress)
          .progressViewStyle(.linear)
          .tint(nativeAIAccentPurple)
          .animation(.easeInOut(duration: 0.35), value: buildingProgress)
          .accessibilityLabel("Insight quality")
          .accessibilityValue("\(Int((buildingProgress * 100).rounded())) percent")
        Text(learningStatusLabel)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(learningStatusDetail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var learningStatusLabel: String {
    buildingProgress >= 1
      ? "Validating your pattern before marking it solid"
      : "\(shift.confidence.tag.capitalized) while the full pattern builds"
  }

  private var learningStatusDetail: String {
    let dayLabel = shift.activeDays == 1 ? "day" : "days"
    if shift.confidence == .medium {
      return "Useful estimates are available now. Okkle is checking them across more shifts before calling the pattern solid."
    }
    return "Based on \(shift.deliveries) deliveries across \(shift.activeDays) active \(dayLabel). These early estimates will adjust as more trips are tracked."
  }

  /// A brand-new driver has no visits at all yet, so the normal background
  /// exploration (triggered by real passive visits) has nothing to run from.
  /// Seed it once so the cold-start card can still offer a tentative "worth
  /// trying" area on day one instead of nothing at all.
  ///
  /// Prefers Home, since that's a stable, deliberately-chosen point rather
  /// than wherever the phone happens to be right now — but Home is a manual
  /// Settings entry nobody's ever prompted to add, so falling back to live
  /// location (already requested above) means this doesn't just silently do
  /// nothing for every driver who hasn't found that screen.
  private func discoverTentativeZoneIfNeeded() {
    guard exploreCandidates.candidates.isEmpty else { return }
    let home = store.settings.excludedPlaces.first { $0.label == "Home" } ?? store.settings.excludedPlaces.first
    guard let origin = home?.coordinate ?? locator.coordinate else { return }
    NativeAreaSuggester.refresh(near: origin, knownZones: [])
  }

  private var offState: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Know exactly when and where to work")
        .font(.title2.bold())
        .foregroundStyle(.primary)
      Text("Enable automatic tracking in Settings so Okkle can learn your best times and areas passively.")
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Cold start: sensible built-in guidance before the first usable delivery
  /// exists. Once real data is available, the live panels replace this card
  /// even while their confidence is still low.
  private var buildingState: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Learning your week")
          .font(.title2.bold())
          .foregroundStyle(.primary)
        Text("This fills in automatically as you drive.")
          .font(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Building your insights")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
          Spacer()
          Text("\(Int((buildingProgress * 100).rounded()))%")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(nativeAIAccentGradient)
        }
        ProgressView(value: buildingProgress)
          .progressViewStyle(.linear)
          .tint(nativeAIAccentPurple)
        // The real heat map, mid-build — your own tracked routes and
        // whatever zones have formed so far, however sparse. As it fills
        // in, this is the same map that shows on the finished panels; a
        // fake progress visual would say "trust me", this actually shows it.
        NativeShiftMapRepresentable(trips: trips, zones: shift.zones, interactive: false, pinLimit: 3)
          .frame(height: 150)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .allowsHitTesting(false)
        Text(buildingSubtitle)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 0) {
        baselineRow("fork.knife", "Dinner beats mid-afternoon", "5–9pm is usually your window", true)
        baselineRow("calendar", "Weekend evenings are strongest", "Friday to Sunday", true)
        baselineRow("cloud.rain.fill", "Rain and cold pay better", "More orders, fewer drivers", true)
      }
      if let candidate = exploreCandidates.bestUnvalidatedCandidate {
        tentativeZoneRow(candidate)
      } else {
        stillLookingRow
      }
    }
  }

  /// Mirrors the high-confidence thresholds in NativeShiftInsights.confidence
  /// (20+ deliveries, 8+ distinct days, spread across at least two weeks —
  /// full panels now wait for High, not just Medium) — whichever of the
  /// three is further from being met is the real bottleneck, so progress
  /// is capped at the smallest ratio rather than averaged. daySpan is an
  /// elapsed-day difference, so count its first calendar day inclusively;
  /// otherwise a real first-day insight would misleadingly remain at 0%.
  private var buildingProgress: Double {
    let deliveryProgress = min(Double(shift.deliveries) / 20.0, 1.0)
    let dayProgress = min(Double(shift.activeDays) / 8.0, 1.0)
    let inclusiveSpan = shift.activeDays > 0 ? shift.daySpan + 1 : 0
    let spanProgress = min(Double(inclusiveSpan) / 14.0, 1.0)
    return min(deliveryProgress, dayProgress, spanProgress)
  }

  private var buildingSubtitle: String {
    if shift.deliveries == 0 {
      return "Starts filling in as soon as you log your first delivery."
    } else if buildingProgress >= 1 {
      // Thresholds met on raw counts, but confidence can still be held
      // back by an uneven week (see NativeShiftInsights.confidence) — say
      // so rather than implying it's stuck.
      return "Almost there — a few more regular days will lock in your personalised timing and areas."
    } else if shift.daySpan < 14 {
      // Enough deliveries can pile up in under two weeks — that's not
      // enough to say the weekly pattern actually repeats, so call out
      // the two-week requirement specifically rather than just the
      // delivery count.
      return "\(shift.deliveries) deliveries so far — needs at least two weeks of driving before it can trust a pattern."
    } else {
      let dayLabel = shift.activeDays == 1 ? "day" : "days"
      return "\(shift.deliveries) deliveries across \(shift.activeDays) \(dayLabel) so far — keep driving and this sharpens up."
    }
  }

  /// Deliberately styled apart from the baseline tips above — this one is a
  /// guess about *this specific driver's* area (restaurant density nearby),
  /// not generic advice, but it's still unproven, so it says so rather than
  /// borrowing the confidence of an earned recommendation.
  private func tentativeZoneRow(_ candidate: NativeExploreCandidate) -> some View {
    Button {
      openInMaps(candidate)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "sparkle.magnifyingglass")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(OkkleColor.brand)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 1) {
          Text("Worth trying: \(candidate.name)")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(OkkleColor.ink)
          Text("Restaurant-dense nearby — unproven, not from your own data yet")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
        }
        Spacer(minLength: 0)
        Image(systemName: "arrow.up.right")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(OkkleColor.muted)
      }
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// Shown instead of tentativeZoneRow while nothing nearby has cleared the
  /// area-suggester's bar yet — without this, the row just silently
  /// disappears, which reads as broken rather than as the honest "no real
  /// standout nearby (yet)" it actually is.
  private var stillLookingRow: some View {
    HStack(spacing: 12) {
      Image(systemName: "sparkle.magnifyingglass")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(OkkleColor.brand)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 1) {
        Text("Still looking for a standout area")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(OkkleColor.ink)
        Text("Nothing nearby stands out yet — keep driving and this fills in")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 12)
  }

  /// Hands the candidate straight to Apple Maps rather than trying to build
  /// any in-app map view — the driver just wants directions.
  private func openInMaps(_ candidate: NativeExploreCandidate) {
    let query = candidate.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? candidate.name
    guard let url = URL(string: "https://maps.apple.com/?ll=\(candidate.latitude),\(candidate.longitude)&q=\(query)") else { return }
    openURL(url)
  }

  private func baselineRow(_ symbol: String, _ title: String, _ sub: String, _ divider: Bool) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(nativeAIAccentGradient)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(OkkleColor.ink)
          Text(sub).font(.system(size: 13, weight: .medium)).foregroundStyle(OkkleColor.muted)
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 12)
      if divider { Divider().padding(.leading, 36) }
    }
  }
}

// MARK: - Daily panel

struct NativeDailyInsightPanel: View {
  let shift: NativeShiftInsights
  let trips: [NativeTrip]
  @ObservedObject private var areaNamer = NativeAreaNamer.shared
  @ObservedObject private var locator = NativeOneShotLocator.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      if let plan = shift.todayPlan {
        NativeAiCard {
          VStack(alignment: .leading, spacing: 14) {
            insightHeader("Time", systemImage: "clock.fill")
            Text(timeSummary(for: plan))
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(OkkleColor.ink)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        NativeAiCard {
          VStack(alignment: .leading, spacing: 14) {
            insightHeader("Place", systemImage: "map.fill")
            Text(placeSummary)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(OkkleColor.ink)
              .fixedSize(horizontal: false, vertical: true)
            NativeRecommendationHeatMap(trips: trips, zones: shift.zones)
          }
        }
      }
    }
    .onAppear {
      locator.request()
      for zone in shift.zones {
        _ = NativeZonePOIPrior.shared.priorScore(for: zone.coordinate)
      }
    }
  }

  private func insightHeader(_ title: String, systemImage: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(nativeAIAccentGradient)
        .frame(width: 34, height: 34)
        .background(nativeAIAccentPurple.opacity(0.08), in: Circle())
      Text(title)
        .font(.title3.bold())
        .foregroundStyle(.primary)
    }
  }

  private func timeSummary(for plan: NativeDayPlan) -> String {
    guard let peak = plan.peakWindow else {
      return "Okkle needs a few more tracked shifts before it can recommend a reliable time."
    }
    let day = Calendar.current.weekdaySymbols[plan.weekday]
    guard plan.isToday else {
      return "Based on your past shifts, \(day) from \(peak.label) is usually your strongest time to head out."
    }

    let hour = Calendar.current.component(.hour, from: Date())
    if let current = plan.driveWindows.first(where: { $0.startHour <= hour && hour <= $0.endHour }) {
      return "Based on your past shifts, now through \(nativeHourLabel(current.endHour + 1)) is usually a strong time to be out."
    }
    if let next = plan.driveWindows.first(where: { $0.startHour > hour }) {
      return "Based on your past shifts, \(next.label) is usually your strongest time to head out today."
    }
    return "Based on your past shifts, \(peak.label) is usually strongest, so today's best window has passed."
  }

  private var placeSummary: String {
    guard let zone = nativeTopZones(shift.zones, near: locator.coordinate, limit: 1).first else {
      return "Okkle needs a few more mapped trips before it can recommend a reliable place."
    }
    if let name = areaNamer.name(for: zone.coordinate) {
      return "Based on your past trips and nearby Apple Maps shopping areas, \(name) is the strongest place to try."
    }
    return "The brightest area on the map is your strongest place to try based on past trips and nearby shopping areas."
  }
}

/// One platform's real, logged earnings for a period, ranked, with how that
/// compares to the same platform's earnings the equivalent period before.
struct NativeTopPlatformEarning: Identifiable {
  let id = UUID()
  let rank: Int
  let platform: String
  let amount: Double
  let deltaPct: Int?   // vs the same platform's earnings last period; nil if no comparable prior data
}

/// Ranks platforms by real, logged income in `current`, comparing each to its
/// own total in `previous` (the equivalent prior period) for a trend arrow.
/// Only ever worth showing once there's an actual mix — a single platform
/// logged isn't a "ranking".
func nativeTopPlatformEarnings(current: [NativeRecord], previous: [NativeRecord], limit: Int = 3) -> [NativeTopPlatformEarning] {
  func totals(_ records: [NativeRecord]) -> [String: Double] {
    var totals: [String: Double] = [:]
    for record in records where record.kind == .income {
      totals[record.platform ?? "Other", default: 0] += record.amount ?? 0
    }
    return totals
  }
  let currentTotals = totals(current)
  guard currentTotals.count >= 2 else { return [] }
  let previousTotals = totals(previous)
  return currentTotals
    .sorted { $0.value > $1.value }
    .prefix(limit)
    .enumerated()
    .map { index, entry in
      var deltaPct: Int?
      if let prevAmount = previousTotals[entry.key], prevAmount > 0 {
        let delta = Int(((entry.value - prevAmount) / prevAmount * 100).rounded())
        if delta != 0 { deltaPct = delta }
      }
      return NativeTopPlatformEarning(rank: index + 1, platform: entry.key, amount: entry.value, deltaPct: deltaPct)
    }
}

/// A ranked, real (logged, not modelled) breakdown of this period's top
/// earning platforms — a cross-platform view no single delivery app can
/// offer — styled to match NativeTopAreasList directly above it.
struct NativeTopPlatformsList: View {
  let platforms: [NativeTopPlatformEarning]
  var previousPeriodLabel: String = "last period"

  var body: some View {
    VStack(spacing: 0) {
      ForEach(platforms) { entry in
        HStack(spacing: 12) {
          Text("\(entry.rank)")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(OkkleColor.brand, in: Circle())
          NativePlatformIcon(platform: entry.platform)
            .frame(width: 30, height: 30)
            .clipShape(Circle())
          VStack(alignment: .leading, spacing: 2) {
            Text(entry.platform)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(OkkleColor.ink)
            if let delta = entry.deltaPct {
              HStack(spacing: 3) {
                Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                  .font(.system(size: 10, weight: .bold))
                Text("\(abs(delta))% vs \(previousPeriodLabel)")
                  .font(.system(size: 12, weight: .semibold))
              }
              .foregroundStyle(delta > 0 ? AnyShapeStyle(nativeAIAccentGradient) : AnyShapeStyle(OkkleColor.red))
            } else {
              Text("New this period")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OkkleColor.muted)
            }
          }
          Spacer(minLength: 8)
          Text(gbp(entry.amount, whole: true))
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
        }
        .padding(.vertical, 10)
        if entry.id != platforms.last?.id { Divider().padding(.leading, 36) }
      }
    }
  }
}

/// Shared "TOP PLATFORMS" card for the Weekly/Monthly/Yearly panels — only
/// appears once there's an actual multi-platform mix to rank.
@ViewBuilder
func nativeTopPlatformsCard(current: [NativeRecord], previous: [NativeRecord], previousPeriodLabel: String) -> some View {
  let ranked = nativeTopPlatformEarnings(current: current, previous: previous)
  if !ranked.isEmpty {
    NativeAiCard {
      VStack(alignment: .leading, spacing: 12) {
        nativeInsightKicker("TOP PLATFORMS")
        Text("Real, logged earnings by app — a cross-platform view no single delivery app can offer.")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(OkkleColor.muted.opacity(0.8))
          .fixedSize(horizontal: false, vertical: true)
        NativeTopPlatformsList(platforms: ranked, previousPeriodLabel: previousPeriodLabel)
      }
    }
  }
}

// MARK: - Weekly panel

struct NativeWeeklyInsightPanel: View {
  let shift: NativeShiftInsights
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var areaNamer = NativeAreaNamer.shared
  @State private var selectedWeekday: Int?
  private var todayWeekday: Int { Calendar.current.component(.weekday, from: Date()) - 1 }

  private var currentWeekRecords: [NativeRecord] {
    let start = Date().addingTimeInterval(-7 * 86_400)
    return store.records.filter { $0.date >= start }
  }

  private var previousWeekRecords: [NativeRecord] {
    let start = Date().addingTimeInterval(-14 * 86_400)
    let end = Date().addingTimeInterval(-7 * 86_400)
    return store.records.filter { $0.date >= start && $0.date < end }
  }

  private var orderedWeekdayStats: [NativeWeekdayStat] {
    [1, 2, 3, 4, 5, 6, 0].compactMap { wd in shift.weekdayStats.first { $0.weekday == wd } }
  }

  /// Which day the breakdown reflects on: your tap, else today (if you worked
  /// it), else your busiest day.
  private var activeWeekday: Int {
    if let selectedWeekday { return selectedWeekday }
    if (shift.weekdayStats.first { $0.weekday == todayWeekday }?.count ?? 0) > 0 { return todayWeekday }
    return shift.weekdayDetails.first?.weekday ?? todayWeekday
  }

  /// A calm reflection on one day: how big it was, when it peaked, where.
  private var dayBreakdown: some View {
    let wd = activeWeekday
    let name = Calendar.current.weekdaySymbols[wd]
    let stat = shift.weekdayStats.first { $0.weekday == wd }
    let detail = shift.weekdayDetails.first { $0.weekday == wd }
    let area = detail?.coordinate.flatMap { areaNamer.name(for: $0) }

    let reliability = shift.weekdayReliability[wd]

    return VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        Text(name)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
        if let reliability {
          Text(reliability == .reliable ? "Reliable" : "Hit or miss")
            .font(.system(size: 10, weight: .heavy)).tracking(0.3)
            .foregroundStyle(reliability == .reliable ? AnyShapeStyle(nativeAIAccentGradient) : AnyShapeStyle(OkkleColor.amber))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((reliability == .reliable ? OkkleColor.brand : OkkleColor.amber).opacity(0.14), in: Capsule())
        }
        Spacer()
        if let stat, stat.count > 0 {
          Text("\(stat.sharePct)% of your week")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
        }
      }
      if let detail {
        breakdownRow("clock.fill", "Best window", detail.band.timeRange)
        if let area {
          breakdownRow("mappin.circle.fill", "Busiest area", area)
        }
        breakdownRow("shippingbox.fill", "Deliveries", "about \(detail.count)")
        if let pct = detail.deadMilePct {
          breakdownRow("fuelpump.fill", "Unpaid miles", "\(pct)%")
        }
      } else {
        Text("You don't usually work \(name)s — nothing tracked yet.")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func breakdownRow(_ symbol: String, _ label: String, _ value: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(nativeAIAccentGradient)
        .frame(width: 20)
      Text(label)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
      Spacer(minLength: 8)
      Text(value)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.ink)
    }
  }

  /// The busiest patch and when it peaks — so the advice can name a real place
  /// and time instead of a generic "wait nearer a pick-up zone".
  private var topSpot: (area: String, time: String)? {
    guard let zone = nativeTopZones(shift.zones, near: nil, limit: 1).first,
          let area = areaNamer.name(for: zone.coordinate),
          let time = zone.timeLabel else { return nil }
    return (area, time)
  }

  /// One specific, actionable line — grounded in the driver's own busiest area
  /// and time — that replaces the vague generic warning where we can.
  private var specificAdvice: (symbol: String, color: AnyShapeStyle, text: String)? {
    if shift.confidence == .low {
      guard let spot = topSpot else { return nil }
      return ("sparkles", AnyShapeStyle(nativeAIAccentGradient),
              "Early pattern: \(spot.area) around \(spot.time) is showing up most often so far. Treat it as a place to test while Okkle keeps learning.")
    }
    if shift.deadMilePct >= 25, let spot = topSpot {
      return ("exclamationmark.triangle.fill", AnyShapeStyle(OkkleColor.amber),
              "You cover a lot of empty miles between orders. Sit tight around \(spot.area) at \(spot.time) — that's where most of your pickups start.")
    }
    if let spot = topSpot {
      return ("mappin.and.ellipse", AnyShapeStyle(nativeAIAccentGradient),
              "Your strongest patch is \(spot.area) at \(spot.time) — base yourself there and let the orders come to you.")
    }
    if let warning = shift.warning {
      return ("exclamationmark.triangle.fill", AnyShapeStyle(OkkleColor.amber), warning)
    }
    return nil
  }

  /// Surfaces the self-correcting confidence loop — whether "your peak" has
  /// actually been paying off — so the check that runs silently in the
  /// background isn't invisible to the driver.
  private var peakHitRateLine: (symbol: String, color: AnyShapeStyle, text: String)? {
    guard let rate = shift.peakHitRate else { return nil }
    if rate >= 0.55 {
      return ("checkmark.seal.fill", AnyShapeStyle(nativeAIAccentGradient), "Your peak-day calls have been paying off lately.")
    }
    return ("arrow.triangle.2.circlepath", AnyShapeStyle(OkkleColor.muted), "Recent peak days haven't stood out much — we're adjusting.")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // Card 1 — a suggestion, clearly set apart as advice (not a stat) — the
      // one thing to act on, so it leads rather than trailing behind stats.
      if let advice = specificAdvice {
        NativeAiCard {
          section("Suggestion") {
            insightLine(symbol: advice.symbol, color: advice.color, text: advice.text)
          }
        }
      }

      // Card 2 — a reflection on how your week actually went.
      NativeAiCard {
        VStack(alignment: .leading, spacing: 22) {
          section("Busiest days", subtitle: "Deliveries you made on each day.") {
            let maxCount = max(1, shift.weekdayStats.map(\.count).max() ?? 1)
            HStack(alignment: .bottom, spacing: 8) {
              ForEach(orderedWeekdayStats) { stat in
                let selected = stat.weekday == activeWeekday
                VStack(spacing: 6) {
                  Capsule()
                    // One brand colour, deepening with how busy the day is —
                    // your best day reads as your strongest green, not an alarm
                    // red (which the heat ramp used to give the busiest bar).
                    .fill(stat.count == 0
                          ? OkkleColor.muted.opacity(0.18)
                          : OkkleColor.brand.opacity(0.4 + 0.6 * (Double(stat.count) / Double(maxCount))))
                    .frame(width: 12, height: max(5, CGFloat(stat.count) / CGFloat(maxCount) * 60))
                  Text(stat.symbol)
                    .font(.system(size: 12, weight: selected ? .heavy : .semibold))
                    .foregroundStyle(selected ? OkkleColor.ink : OkkleColor.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? Color(uiColor: .tertiarySystemFill) : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                  withAnimation(.easeInOut(duration: 0.15)) { selectedWeekday = stat.weekday }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Calendar.current.weekdaySymbols[stat.weekday]), \(stat.count) deliveries")
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityAction {
                  selectedWeekday = stat.weekday
                }
              }
            }
            .frame(height: 100, alignment: .bottom)
          }

          Divider()
          dayBreakdown

          if shift.perHourBand != nil {
            Divider()
            statsStrip
          }

          // Surfaces the self-correcting confidence loop — only appears once
          // there's genuinely enough evidence, so a newer account sees nothing.
          if let hitRate = peakHitRateLine {
            Divider()
            insightLine(symbol: hitRate.symbol, color: hitRate.color, text: hitRate.text)
          }
        }
      }

      // Card 3 — your top areas, with how much of your work each one carries.
      NativeAiCard {
        section("Your top areas", subtitle: "Bar shows how busy each area is compared to your #1 spot.") {
          NativeTopAreasList(zones: shift.zones, limit: 4, showShareBar: true)
        }
      }

      // Card 4 — real, logged platform ranking, underneath top areas. Only
      // worth showing once there's an actual mix — a single platform isn't
      // a "ranking".
      nativeTopPlatformsCard(current: currentWeekRecords, previous: previousWeekRecords, previousPeriodLabel: "last week")
    }
  }

  private func section<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)
        if let subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      content()
    }
  }

  // Est. rate only, when the passive signal is solid — unpaid miles now shows
  // per-day in the breakdown above instead of as a whole-week aggregate here.
  private var statsStrip: some View {
    HStack(spacing: 0) {
      if let band = shift.perHourBand {
        stat("Est. rate", "\(band)/hr")
      }
    }
    .padding(.vertical, 4)
  }

  private func stat(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      nativeStatValue(value, size: .secondary)
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func insightLine(symbol: String, color: AnyShapeStyle, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(color)
        .padding(.top, 1)
      Text(text)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(OkkleColor.ink)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
  }
}

// MARK: - Shared bits for the wider-window (Monthly / Yearly) panels

private func nativeInsightKicker(_ text: String) -> some View {
  Text(text)
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(.secondary)
}

/// The one number style every Insights figure routes through — same font,
/// weight and no-shrink behaviour everywhere, just two sizes: `.hero` for the
/// one headline figure a card leads with (Earned, Tax relief), `.secondary`
/// for supporting stats underneath it (Est. rate, Unpaid miles) — a deliberate
/// hierarchy, not the accidental kind this used to have.
private enum NativeStatSize {
  case hero, secondary
  var points: CGFloat { self == .hero ? 42 : 30 }
}

private func nativeStatValue(_ value: String, size: NativeStatSize = .hero, color: AnyShapeStyle = AnyShapeStyle(OkkleColor.ink)) -> some View {
  Text(value)
    .font(.system(size: size.points, weight: .bold))
    .foregroundStyle(color)
    .lineLimit(1)
    // No minimumScaleFactor: that let this shrink under width pressure while
    // sibling stats elsewhere didn't need to, which is exactly what made
    // supposedly-identical figures render at different sizes. This always
    // renders at its true, fixed intrinsic size — never auto-shrunk.
    .fixedSize(horizontal: true, vertical: false)
}

private func nativeHeadlineStat(kicker: String, value: String, valueColor: AnyShapeStyle = AnyShapeStyle(OkkleColor.ink),
                                sub: (symbol: String, color: AnyShapeStyle, text: String)?) -> some View {
  VStack(alignment: .leading, spacing: 10) {
    nativeInsightKicker(kicker)
    nativeStatValue(value, color: valueColor)
    if let sub {
      HStack(spacing: 6) {
        Image(systemName: sub.symbol).font(.system(size: 13, weight: .bold))
        Text(sub.text).font(.system(size: 13, weight: .semibold))
          .fixedSize(horizontal: false, vertical: true)
      }
      .foregroundStyle(sub.color)
    }
  }
  .frame(maxWidth: .infinity, alignment: .leading)
}

/// Always full card width, one per row — never squeezed into a side-by-side
/// column, which is what let "Est. rate" and "Unpaid miles" render smaller
/// than the headline figures above them despite requesting the same size.
private func nativeEfficiencyStat(_ title: String, _ value: String) -> some View {
  VStack(alignment: .leading, spacing: 5) {
    nativeStatValue(value, size: .secondary)
    Text(title)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(OkkleColor.muted)
  }
  .frame(maxWidth: .infinity, alignment: .leading)
}

/// The geographic hotspot history as a card for the wider-window panels.
/// Unlike Today's focused recommendation glow, this keeps routes, ranked pins,
/// and comparative bars so a month or year can be explored in more detail.
@ViewBuilder
private func nativeHotspotMapCard(trips: [NativeTrip], zones: [NativeZonePoint]) -> some View {
  if !zones.isEmpty {
    NativeAiCard {
      VStack(alignment: .leading, spacing: 16) {
        nativeInsightKicker("Where you earn")
        NativeZoneMiniMap(trips: trips, zones: zones)
        Text("Numbered pins match the list below — 1 is your busiest patch. Tap the map to explore full-screen.")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
        Divider()
        Text("Bar shows how busy each area is compared to your #1 spot.")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(OkkleColor.muted.opacity(0.8))
          .fixedSize(horizontal: false, vertical: true)
        NativeTopAreasList(zones: zones, limit: 4, showShareBar: true)
      }
    }
  }
}

/// £/hr as an honest range (matching NativeShiftInsights.perHourBand), for the
/// wider windows where the built-in 14-day figure doesn't apply.
private func nativePerHourBand(income: Double, activeHours: Double) -> String? {
  guard income > 0, activeHours > 1 else { return nil }
  let rate = income / activeHours
  // Matches NativeShiftInsights's currency-specific plausibility range — US
  // gig pay (tipping, higher urban cost of living) genuinely clears £45's
  // worth in dollars on a strong shift far more often than the UK market
  // this range was first calibrated against.
  let plausibleRange: ClosedRange<Double> = nativeActiveCurrencyCode == "USD" ? 5.0...65.0 : 4.0...45.0
  guard plausibleRange.contains(rate) else { return nil }
  let symbol = nativeActiveCurrencyCode == "USD" ? "$" : "£"
  return "\(symbol)\(Int((rate * 0.85).rounded(.down)))–\(Int((rate * 1.15).rounded(.up)))"
}

// MARK: - Monthly panel: earnings + tax relief + efficiency, over 30 days

struct NativeMonthlyInsightPanel: View {
  let shift: NativeShiftInsights
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var areaNamer = NativeAreaNamer.shared

  private let day: TimeInterval = 86_400

  private func windowIncome(fromDaysAgo: Int, toDaysAgo: Int) -> Double {
    let now = Date()
    let start = now.addingTimeInterval(-Double(fromDaysAgo) * day)
    let end = now.addingTimeInterval(-Double(toDaysAgo) * day)
    return store.records
      .filter { $0.kind == .income && $0.date >= start && $0.date < end }
      .reduce(0) { $0 + ($1.amount ?? 0) }
  }

  private var incomeThis: Double { windowIncome(fromDaysAgo: 30, toDaysAgo: 0) }
  private var incomePrev: Double { windowIncome(fromDaysAgo: 60, toDaysAgo: 30) }

  private var currentMonthRecords: [NativeRecord] {
    store.records.filter { $0.date >= Date().addingTimeInterval(-30 * day) }
  }

  private var previousMonthRecords: [NativeRecord] {
    let start = Date().addingTimeInterval(-60 * day)
    let end = Date().addingTimeInterval(-30 * day)
    return store.records.filter { $0.date >= start && $0.date < end }
  }

  private var savings: NativeMileageTaxSavings {
    store.mileageTaxSavings(for: DateInterval(start: Date().addingTimeInterval(-30 * day), end: Date()))
  }

  private var incomeTrend: (symbol: String, color: AnyShapeStyle, text: String)? {
    guard incomePrev > 0 else { return nil }
    let delta = (incomeThis - incomePrev) / incomePrev
    if abs(delta) < 0.05 {
      return ("equal", AnyShapeStyle(OkkleColor.muted), "About the same as the 30 days before")
    }
    let pct = Int((abs(delta) * 100).rounded())
    return delta > 0
      ? ("arrow.up.right", AnyShapeStyle(nativeAIAccentGradient), "\(pct)% more than the 30 days before")
      : ("arrow.down.right", AnyShapeStyle(OkkleColor.amber), "\(pct)% less than the 30 days before")
  }

  private var bestDayLine: String? {
    guard let detail = shift.weekdayDetails.first else { return nil }
    let name = Calendar.current.weekdaySymbols[detail.weekday]
    if let coordinate = detail.coordinate, let area = areaNamer.name(for: coordinate) {
      return "\(name)s are your strongest day, busiest around \(area)."
    }
    return "\(name)s are your strongest day."
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // Card 1 — the money: earned this month, its trend, efficiency, pattern.
      NativeAiCard {
        VStack(alignment: .leading, spacing: 18) {
          nativeHeadlineStat(
            kicker: "Earned · Last 30 days",
            value: gbp(incomeThis, whole: true),
            sub: incomeThis == 0
              ? ("square.and.pencil", AnyShapeStyle(OkkleColor.muted), "Log your pay to track your month")
              : incomeTrend
          )
          if nativePerHourBand(income: incomeThis, activeHours: shift.activeHours) != nil || shift.deadMilePct > 0 {
            Divider()
            VStack(alignment: .leading, spacing: 14) {
              if let band = nativePerHourBand(income: incomeThis, activeHours: shift.activeHours) {
                nativeEfficiencyStat("Est. rate", "\(band)/hr")
              }
              nativeEfficiencyStat("Unpaid miles", "\(shift.deadMilePct)%")
            }
          }
          if let line = bestDayLine {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "calendar")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(nativeAIAccentGradient)
              Text(line)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OkkleColor.muted)
                .fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 0)
            }
          }
        }
      }

      // Card 2 — tax relief banked this month.
      NativeAiCard {
        VStack(alignment: .leading, spacing: 10) {
          nativeInsightKicker("Tax relief banked · 30 days")
          nativeStatValue(gbp(savings.taxSaved, whole: true), color: AnyShapeStyle(nativeAIAccentGradient))
          Text("\(gbp(savings.mileageDeduction, whole: true)) off your taxable profit, from \(miles(savings.miles)) of business driving.")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      // Card 3 — where you earn, over the last 30 days.
      nativeHotspotMapCard(trips: store.businessTrips, zones: shift.zones)

      // Card 4 — top earning platforms, underneath where you earn.
      nativeTopPlatformsCard(current: currentMonthRecords, previous: previousMonthRecords, previousPeriodLabel: "the 30 days before")
    }
  }
}

// MARK: - Yearly panel: tax-year totals, Self Assessment deduction, seasonal shape

struct NativeYearlyInsightPanel: View {
  let shift: NativeShiftInsights
  @EnvironmentObject private var store: OkkleStore
  @State private var selectedMonth: Int?

  private var currentTaxYearRecords: [NativeRecord] {
    let year = store.taxYear
    return store.records.filter { year.contains($0.date) }
  }

  private var previousTaxYearRecords: [NativeRecord] {
    let previousYear = store.taxYearInterval(containing: store.taxYear.start.addingTimeInterval(-1))
    return store.records.filter { previousYear.contains($0.date) }
  }

  private struct MonthStat: Identifiable {
    let index: Int
    let name: String        // full month name, e.g. "June"
    let interval: DateInterval
    let income: Double
    var id: Int { index }
  }

  /// Income by calendar month across the last 12 months, oldest → newest.
  private var monthlyStats: [MonthStat] {
    let cal = Calendar.current
    let now = Date()
    return (0..<12).reversed().enumerated().compactMap { position, back in
      guard let monthDate = cal.date(byAdding: .month, value: -back, to: now),
            let interval = cal.dateInterval(of: .month, for: monthDate) else { return nil }
      let income = store.records
        .filter { $0.kind == .income && interval.contains($0.date) }
        .reduce(0.0) { $0 + ($1.amount ?? 0) }
      let name = cal.monthSymbols[cal.component(.month, from: monthDate) - 1]
      return MonthStat(index: position, name: name, interval: interval, income: income)
    }
  }

  /// Tapped month, else the current month if it has earnings, else the best.
  private func activeIndex(_ stats: [MonthStat]) -> Int {
    if let selectedMonth, stats.indices.contains(selectedMonth) { return selectedMonth }
    if let last = stats.last, last.income > 0 { return last.index }
    return stats.max(by: { $0.income < $1.income })?.index ?? (stats.count - 1)
  }

  var body: some View {
    let stats = monthlyStats
    VStack(alignment: .leading, spacing: 24) {
      // Card 1 — earned this tax year, plus the same efficiency stats Monthly
      // shows (now that shift is scoped to store.taxYear, income and active
      // hours share the same window, so the rate is actually trustworthy).
      NativeAiCard {
        VStack(alignment: .leading, spacing: 18) {
          nativeHeadlineStat(
            kicker: "Earned · This tax year",
            value: gbp(store.yearIncome, whole: true),
            sub: store.yearIncome == 0
              ? ("square.and.pencil", AnyShapeStyle(OkkleColor.muted), "Log your pay to total your year")
              : nil
          )
          if nativePerHourBand(income: store.yearIncome, activeHours: shift.activeHours) != nil || shift.deadMilePct > 0 {
            Divider()
            VStack(alignment: .leading, spacing: 14) {
              if let band = nativePerHourBand(income: store.yearIncome, activeHours: shift.activeHours) {
                nativeEfficiencyStat("Est. rate", "\(band)/hr")
              }
              nativeEfficiencyStat("Unpaid miles", "\(shift.deadMilePct)%")
            }
          }
        }
      }

      // Card 2 — tax relief (same treatment as Monthly, for consistency).
      NativeAiCard {
        VStack(alignment: .leading, spacing: 10) {
          nativeInsightKicker("Tax relief · This tax year")
          nativeStatValue(gbp(store.taxSaved, whole: true), color: AnyShapeStyle(nativeAIAccentGradient))
          Text("A \(gbp(store.yearMileageDeduction, whole: true)) deduction off your Self Assessment profit, from \(miles(store.yearMiles)) driven. See the Tax tab.")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      // Card 3 — seasonal earnings by month; tap a bar for that month's stats.
      if stats.contains(where: { $0.income > 0 }) {
        NativeAiCard {
          VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
              nativeInsightKicker("Busiest months")
              Text("Earnings each month — tap a bar for the detail.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OkkleColor.muted.opacity(0.8))
            }
            let maxTotal = max(1, stats.map(\.income).max() ?? 1)
            let active = activeIndex(stats)
            HStack(alignment: .bottom, spacing: 5) {
              ForEach(stats) { month in
                let selected = month.index == active
                VStack(spacing: 5) {
                  Capsule()
                    .fill(month.income == 0
                          ? OkkleColor.muted.opacity(0.18)
                          : OkkleColor.brand.opacity(0.4 + 0.6 * (month.income / maxTotal)))
                    .frame(width: 9, height: max(5, CGFloat(month.income / maxTotal) * 64))
                  Text(month.name.prefix(1))
                    .font(.system(size: 10, weight: selected ? .heavy : .semibold))
                    .foregroundStyle(selected ? OkkleColor.ink : OkkleColor.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? Color(uiColor: .tertiarySystemFill) : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                  withAnimation(.easeInOut(duration: 0.15)) { selectedMonth = month.index }
                }
              }
            }
            .frame(height: 104, alignment: .bottom)

            Divider()
            monthBreakdown(stats[active])
          }
        }
      }

      // Card 4 — where you earn, across the year.
      nativeHotspotMapCard(trips: store.businessTrips, zones: shift.zones)

      // Card 5 — top earning platforms, underneath where you earn.
      nativeTopPlatformsCard(current: currentTaxYearRecords, previous: previousTaxYearRecords, previousPeriodLabel: "last tax year")
    }
  }

  /// One month, expanded: what you earned, drove and saved that month.
  private func monthBreakdown(_ month: MonthStat) -> some View {
    let savings = store.mileageTaxSavings(for: month.interval)
    let year = Calendar.current.component(.year, from: month.interval.start)
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(month.name) \(String(year))")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
        Spacer()
        Text(gbp(month.income, whole: true))
          .font(.system(size: 18, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
      }
      if month.income > 0 || savings.miles > 0 {
        breakdownRow("map.fill", "Business miles", miles(savings.miles))
        breakdownRow(nativeCurrencySymbolName("sterlingsign.circle.fill"), "Tax relief", gbp(savings.taxSaved, whole: true))
        breakdownRow("percent", "Deduction", gbp(savings.mileageDeduction, whole: true))
      } else {
        Text("Nothing logged for \(month.name).")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func breakdownRow(_ symbol: String, _ label: String, _ value: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(nativeAIAccentGradient)
        .frame(width: 20)
      Text(label)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
      Spacer(minLength: 8)
      Text(value)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.ink)
    }
  }
}

struct NativeInsightsView: View {
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared
  // build() walks the whole visit history, so it only reruns when one of its
  // inputs changes rather than on every body evaluation.
  @State private var cachedShift: NativeShiftInsights?
  private var insightVisits: [NativeVisit] {
    NativeShiftInsights.enrichedVisits(visits: autoTrack.visits, trips: store.businessTrips)
  }

  private var shift: NativeShiftInsights {
    cachedShift ?? .empty
  }

  private func rebuildShift() {
    guard store.settings.insightsEnabled else {
      cachedShift = .empty
      return
    }
    let input = NativeInsightInput(visits: insightVisits, store: store)
    Task {
      let snapshot = await NativeInsightsProjector.shared.project(input)
      await MainActor.run {
        cachedShift = snapshot.shift
        for zone in snapshot.shift.zones {
          _ = NativeZonePOIPrior.shared.priorScore(for: zone.coordinate)
        }
      }
    }
  }

  var body: some View {
    NativeScreen(title: "Insights", collapsedTitle: "Insights",
                 subtitle: "From your trips: when to head out and where to go. Sharper the more you drive.",
                 style: .standard) {
      VStack(alignment: .leading, spacing: 28) {
        if !store.settings.insightsEnabled {
          NativeEmptyState(
            symbol: "sparkles",
            title: "Insights are off",
            message: "Enable Insights in Settings to use AI insights from your trips and records."
          )
        } else {
          NativeShiftPatternsCard(
            shift: shift,
            visits: insightVisits,
            trips: store.businessTrips,
            autoTrackTrips: Binding(
              get: { store.settings.autoTrackTrips },
              set: { value in
                withAnimation(nativeInsightPromptAnimation) {
                  store.settings.autoTrackTrips = value
                  if value {
                    store.settings.enhancedAutoTracking = true
                  }
                }
              }
            )
          )

          // These cards are one-time set-up prompts: they only appear while
          // the feature is off. Once you turn one on it disappears here — the on/off
          // switch then lives in Settings.
          if !store.settings.siriTripTrackingEnabled {
            NativeSiriTripTrackingPrompt()
              .transition(.nativeInsightSetupCard)
          }

          if !store.settings.loggingReminder {
            NativeAiCard(banner: "REMINDERS") {
              VStack(alignment: .leading, spacing: 18) {
                Text("Keep your records fresh")
                  .font(.title2.bold())
                Text("Get a gentle nudge to log your miles and pay so nothing slips through the week.")
                  .font(.body)
                  .foregroundStyle(.secondary)
                Toggle("Logging reminder", isOn: Binding(
                  get: { store.settings.loggingReminder },
                  set: { value in
                    withAnimation(nativeInsightPromptAnimation) {
                      store.settings.loggingReminder = value
                    }
                  }
                ))
                .font(.headline)
                .tint(OkkleColor.brand)
              }
            }
            .transition(.nativeInsightSetupCard)
          }

          if !store.settings.taxDeadlineReminders {
            NativeKeyTaxDatesPanel()
              .transition(.nativeInsightSetupCard)
          }

          if store.history.isEmpty {
            NativeEmptyState(symbol: "sparkles", title: "Insights will grow with your data", message: "Track trips and log pay to unlock best zones, hours, platform mix and tax-aware suggestions.")
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .animation(nativeInsightPromptAnimation, value: store.settings.insightsEnabled)
    .animation(nativeInsightPromptAnimation, value: store.settings.autoTrackTrips)
    .animation(nativeInsightPromptAnimation, value: store.settings.siriTripTrackingEnabled)
    .animation(nativeInsightPromptAnimation, value: store.settings.loggingReminder)
    .animation(nativeInsightPromptAnimation, value: store.settings.taxDeadlineReminders)
    .onAppear { rebuildShift() }
    .onChange(of: insightVisits) { _ in rebuildShift() }
    .onChange(of: store.trips) { _ in rebuildShift() }
    .onChange(of: store.records) { _ in rebuildShift() }
    .onChange(of: store.settings.excludedPlaces) { _ in rebuildShift() }
    .onChange(of: store.insightEvidence) { _ in rebuildShift() }
    .onChange(of: store.settings.insightsEnabled) { _ in rebuildShift() }
  }
}

private struct NativeInsightSetupCardTransition: ViewModifier {
  let progress: CGFloat

  func body(content: Content) -> some View {
    content
      .opacity(1 - progress)
      .scaleEffect(1 - (0.12 * progress), anchor: .top)
      .offset(y: -24 * progress)
      .rotationEffect(.degrees(-2.5 * progress), anchor: .topTrailing)
      .blur(radius: 8 * progress)
  }
}

private extension AnyTransition {
  static var nativeInsightSetupCard: AnyTransition {
    .asymmetric(
      insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .move(edge: .top)),
      removal: .modifier(
        active: NativeInsightSetupCardTransition(progress: 1),
        identity: NativeInsightSetupCardTransition(progress: 0)
      )
    )
  }
}

struct NativeSiriTripTrackingPrompt: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    NativeAiCard(banner: "SIRI") {
      VStack(alignment: .leading, spacing: 18) {
        Text("Start trips by voice")
          .font(.title2.bold())
          .foregroundStyle(.primary)
        Text("Let Siri and Shortcuts start or resume trip tracking with your default vehicle.")
          .font(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Toggle("Siri trip tracking", isOn: Binding(
          get: { store.settings.siriTripTrackingEnabled },
          set: { value in
            withAnimation(nativeInsightPromptAnimation) {
              store.settings.siriTripTrackingEnabled = value
            }
          }
        ))
        .font(.headline)
        .tint(OkkleColor.brand)
      }
    }
  }
}
