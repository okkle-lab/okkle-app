import CoreLocation
import SwiftUI

let nativeInsightPromptAnimation = Animation.spring(response: 0.46, dampingFraction: 0.72, blendDuration: 0.08)

let nativeAIAccentPink = Color(red: 1.00, green: 0.22, blue: 0.72)
let nativeAIAccentPurple = Color(red: 0.55, green: 0.30, blue: 1.00)
let nativeAIAccentGradient = LinearGradient(
  colors: [nativeAIAccentPink, nativeAIAccentPurple],
  startPoint: .topLeading,
  endPoint: .bottomTrailing
)
let nativeAIAccentHorizontalGradient = LinearGradient(
  colors: [nativeAIAccentPink, nativeAIAccentPurple],
  startPoint: .leading,
  endPoint: .trailing
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

/// Reports each carousel page's natural height, since a paged TabView
/// doesn't size itself to content — the card resizes to whichever page is
/// currently showing instead of leaving blank space or clipping.
private struct NativeInsightPageHeightKey: PreferenceKey {
  static var defaultValue: [NativeInsightPeriod: CGFloat] = [:]
  static func reduce(value: inout [NativeInsightPeriod: CGFloat], nextValue: () -> [NativeInsightPeriod: CGFloat]) {
    value.merge(nextValue()) { _, new in new }
  }
}

struct NativeInsightPeriodTabs: View {
  @Binding var period: NativeInsightPeriod

  var body: some View {
    // The original native segmented control — swiping the carousel below still
    // moves the selection, since both read and write the same binding.
    Picker("", selection: $period.animation(.easeInOut(duration: 0.2))) {
      ForEach(NativeInsightPeriod.allCases) { p in
        Text(p.label).tag(p)
      }
    }
    .pickerStyle(.segmented)
  }
}

struct NativeShiftPatternsCard: View {
  let shift: NativeShiftInsights
  let visits: [NativeVisit]
  let trips: [NativeTrip]
  @Binding var autoTrackTrips: Bool
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var exploreCandidates = NativeExploreCandidateStore.shared
  @State private var period: NativeInsightPeriod = .today
  @State private var pageHeights: [NativeInsightPeriod: CGFloat] = [:]

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
    let cutoff: Date
    switch period {
    case .today: return shift
    case .year: cutoff = store.taxYear.start
    default:
      guard let days = period.lookbackDays else { return shift }
      cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
    let scoped = insightVisits.filter { $0.arrival >= cutoff }
    return NativeShiftInsights.build(visits: scoped, store: store)
  }

  // The paged TabView keeps all four period panels alive at once, so without
  // this cache every body evaluation re-runs build() three times over the
  // full visit history.
  @State private var scopedShifts: [NativeInsightPeriod: NativeShiftInsights] = [:]

  private func rebuildScopedShifts() {
    scopedShifts = [:]
    for period in NativeInsightPeriod.allCases where period != .today {
      scopedShifts[period] = shift(for: period)
    }
  }

  var body: some View {
    // Full panels only once confidence is genuinely High — Medium ("good
    // read") is still shaky enough that presenting it as a confident
    // recommendation risks sending someone to the wrong place at the
    // wrong time. Below High, show the building state instead, even
    // though shift.hasData would already be true well before then.
    if shift.confidence == .high {
      VStack(alignment: .leading, spacing: 14) {
        NativeInsightPeriodTabs(period: $period)

        TabView(selection: $period) {
          ForEach(NativeInsightPeriod.allCases) { p in
            Group {
              switch p {
              case .today: NativeDailyInsightPanel(shift: shift, trips: trips)
              case .week:  NativeWeeklyInsightPanel(shift: shift(for: p))
              case .month: NativeMonthlyInsightPanel(shift: shift(for: p))
              case .year:  NativeYearlyInsightPanel(shift: shift(for: p))
              }
            }
            .background(GeometryReader { geo in
              Color.clear.preference(key: NativeInsightPageHeightKey.self, value: [p: geo.size.height])
            })
            .tag(p)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: pageHeights[period] ?? 200)
        .onPreferenceChange(NativeInsightPageHeightKey.self) { pageHeights = $0 }
        .animation(.easeInOut(duration: 0.2), value: pageHeights[period])
      }
      .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
      .onAppear { rebuildScopedShifts() }
      .onChange(of: insightVisits) { _ in rebuildScopedShifts() }
      .onChange(of: trips) { _ in rebuildScopedShifts() }
      .onChange(of: store.records) { _ in rebuildScopedShifts() }
      .onChange(of: store.settings.excludedPlaces) { _ in rebuildScopedShifts() }
    } else if !autoTrackTrips {
      NativeAiCard { offState }
        .transition(.nativeInsightSetupCard)
    } else {
      NativeAiCard { buildingState }
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        .onAppear { discoverTentativeZoneIfNeeded() }
    }
  }

  /// A brand-new driver has no visits at all yet, so the normal background
  /// exploration (triggered by real passive visits) has nothing to run from.
  /// Seed it once from Home, if set, so the cold-start card can still offer a
  /// tentative "worth trying" area on day one instead of nothing at all.
  private func discoverTentativeZoneIfNeeded() {
    guard exploreCandidates.candidates.isEmpty else { return }
    let home = store.settings.excludedPlaces.first { $0.label == "Home" } ?? store.settings.excludedPlaces.first
    guard let origin = home?.coordinate else { return }
    NativeAreaSuggester.refresh(near: origin, knownZones: [])
  }

  private var offState: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Know exactly when and where to work")
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
      Text("Enable automatic tracking in Settings so Okkle can learn your best times and areas passively.")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Cold start: sensible built-in guidance so a day-1 driver still gets
  /// something useful while their own pattern accrues. Clearly generic.
  /// Covers everything below medium confidence — zero deliveries all the
  /// way through a handful of shaky ones — with a progress bar so it
  /// reads as "still building" rather than "broken" or "empty".
  private var buildingState: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Learning your week")
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("This fills in automatically as you drive.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("BUILDING YOUR INSIGHTS")
            .font(.system(size: 12, weight: .heavy)).tracking(0.5)
            .foregroundStyle(OkkleColor.muted)
          Spacer()
          Text("\(Int((buildingProgress * 100).rounded()))%")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(nativeAIAccentGradient)
        }
        NativeAIProgressBar(progress: buildingProgress)
        // The real heat map, mid-build — your own tracked routes and
        // whatever zones have formed so far, however sparse. As it fills
        // in, this is the same map that shows on the finished panels; a
        // fake progress visual would say "trust me", this actually shows it.
        NativeShiftMapRepresentable(trips: trips, zones: shift.zones, interactive: false, pinLimit: 3)
          .frame(height: 150)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .allowsHitTesting(false)
        Text(buildingSubtitle)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 0) {
        baselineRow("fork.knife", "Dinner beats mid-afternoon", "5–9pm is usually your window", true)
        baselineRow("calendar", "Weekend evenings are strongest", "Friday to Sunday", true)
        baselineRow("cloud.rain.fill", "Rain and cold pay better", "More orders, fewer drivers", true)
        baselineRow("fuelpump.fill", "Cut the roaming", "Idle miles quietly eat profit", exploreCandidates.bestUnvalidatedCandidate != nil)
      }
      if let candidate = exploreCandidates.bestUnvalidatedCandidate {
        tentativeZoneRow(candidate)
      }
    }
  }

  /// Mirrors the high-confidence thresholds in NativeShiftInsights.confidence
  /// (20+ deliveries, 8+ distinct days, spread across at least two weeks —
  /// full panels now wait for High, not just Medium) — whichever of the
  /// three is further from being met is the real bottleneck, so progress
  /// is capped at the smallest ratio rather than averaged.
  private var buildingProgress: Double {
    let deliveryProgress = min(Double(shift.deliveries) / 20.0, 1.0)
    let dayProgress = min(Double(shift.activeDays) / 8.0, 1.0)
    let spanProgress = min(Double(shift.daySpan) / 14.0, 1.0)
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
    HStack(spacing: 12) {
      Image(systemName: "sparkle.magnifyingglass")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
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
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 10)
    .background(OkkleColor.muted.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
      .padding(.vertical, 10)
      if divider { Divider().padding(.leading, 36) }
    }
  }
}

// MARK: - Daily panel

struct NativeDailyInsightPanel: View {
  let shift: NativeShiftInsights
  let trips: [NativeTrip]
  @ObservedObject private var areaNamer = NativeAreaNamer.shared
  @ObservedObject private var weather = NativeWeatherService.shared
  @ObservedObject private var locator = NativeOneShotLocator.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let plan = shift.todayPlan {
        // Panel 1 — WHEN: the one thing to do, plus the busy shape of the day.
        NativeAiCard {
          VStack(alignment: .leading, spacing: 16) {
            heroSection(plan)
            if let brk = plan.breakWindow {
              Label("Quiet \(brk.label) — a good window for your break.", systemImage: "cup.and.saucer.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OkkleColor.muted)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text("WHEN IT'S BUSY")
                  .font(.system(size: 12, weight: .heavy)).tracking(0.5)
                  .foregroundStyle(OkkleColor.muted)
                Spacer()
                NativeBusyLegend()
              }
              NativeHourStrip(hourCounts: plan.hourCounts)
            }
          }
        }

        // Panel 2 — WHERE: your best patches for today (the heat map itself now
        // lives on the Monthly/Yearly overviews).
        NativeAiCard {
          section("WHERE TO GO") {
            NativeTopAreasList(zones: shift.zones, limit: 3)
          }
        }
      }
    }
    .onAppear {
      locator.request()
      if let c = locator.coordinate { weather.refresh(for: c) }
    }
    .onChange(of: locator.coordinate?.latitude) { _ in
      if let c = locator.coordinate { weather.refresh(for: c) }
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 12, weight: .heavy)).tracking(0.5)
        .foregroundStyle(OkkleColor.muted)
      content()
    }
  }

  /// How sure Okkle is, as a labelled chip (not a menu) — signal bars + words so
  /// it reads as "how much data is behind this", not a tappable control.
  private var confidenceChip: some View {
    HStack(spacing: 5) {
      HStack(alignment: .bottom, spacing: 1.5) {
        ForEach(0..<3, id: \.self) { i in
          RoundedRectangle(cornerRadius: 0.5)
            .fill(i < shift.confidence.dots ? AnyShapeStyle(nativeAIAccentGradient) : AnyShapeStyle(OkkleColor.muted.opacity(0.25)))
            .frame(width: 3, height: 4 + CGFloat(i) * 3)
        }
      }
      Text("Confidence: \(shift.confidence.level)")
        .font(.system(size: 10, weight: .heavy)).tracking(0.3)
        .foregroundStyle(OkkleColor.muted)
    }
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(OkkleColor.muted.opacity(0.08), in: Capsule())
    .accessibilityLabel("Confidence: \(shift.confidence.level)")
  }

  // MARK: Hero — one calm, confident instruction (Apple-style: type, not chrome)

  private func heroSection(_ plan: NativeDayPlan) -> some View {
    let hero = heroContent(plan)
    return VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 7) {
        Text(plan.isToday ? "TODAY · \(Calendar.current.weekdaySymbols[plan.weekday].uppercased())"
                          : "NEXT: \(Calendar.current.weekdaySymbols[plan.weekday].uppercased())")
          .font(.system(size: 12, weight: .heavy)).tracking(0.5)
          .foregroundStyle(hero.color)
        Spacer()
        confidenceChip
      }
      Text(hero.title)
        .font(.system(size: 27, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .fixedSize(horizontal: false, vertical: true)
      Text(hero.detail)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// One instruction, chosen by priority: big night → in a window now → window
  /// coming → wound down → next working day. Weather escalates, never competes.
  private func heroContent(_ plan: NativeDayPlan) -> (symbol: String, color: AnyShapeStyle, title: String, detail: String) {
    let strongDay = shift.weekdayDetails.prefix(3).contains { $0.weekday == plan.weekday }
    let dayName = Calendar.current.weekdaySymbols[plan.weekday]
    let area = areaNamer.name(for: plan.zone ?? CLLocationCoordinate2D())
    let soft = shift.confidence == .low
    let peak = plan.peakWindow

    // Weather demand boost across the working day.
    let boost = weather.today?.hours.filter { (10...23).contains($0.hour) && $0.boostsDemand } ?? []
    let wet = boost.contains(where: \.isWet)

    let near = area.map { " near \($0)" } ?? ""

    // 1. Big night: bad weather on one of your strong days.
    if !boost.isEmpty, strongDay, let peak {
      let cond = wet ? "Wet" : "Cold"
      return ("flame.fill", AnyShapeStyle(nativeAIAccentGradient),
              plan.isToday ? "Tonight could be a big one" : "\(dayName) could be a big one",
              "\(cond) on one of your strong days — \(peak.label)\(near) tends to pay best.")
    }

    if plan.isToday, peak != nil {
      let hour = Calendar.current.component(.hour, from: Date())
      // 2. In a busy window right now.
      if let current = plan.driveWindows.first(where: { $0.startHour <= hour && hour <= $0.endHour }) {
        return ("bolt.fill", AnyShapeStyle(nativeAIAccentGradient),
                "Good time to be out",
                area.map { "Busy till \(nativeHourLabel(current.endHour + 1))\(soft ? "" : " around \($0)")." } ?? "Busy till \(nativeHourLabel(current.endHour + 1)).")
      }
      // 3. A window still ahead today.
      if let next = plan.driveWindows.first(where: { $0.startHour > hour }) {
        let boostNote = boost.isEmpty ? "" : (wet ? " Rain should help." : " Cold should help.")
        return ("figure.walk.arrival", AnyShapeStyle(nativeAIAccentGradient),
                "Great to be out for \(nativeHourLabel(next.startHour))",
                "\(next.label)\(near) \(soft ? "looks like" : "is usually") your strongest.\(boostNote)")
      }
      // 4. Peaks have passed.
      return ("moon.stars.fill", AnyShapeStyle(OkkleColor.muted),
              "Peaks are behind you",
              "Quieter from here — a good point to call it.")
    }

    // 5. Planning ahead for the next working day.
    if let peak {
      return ("calendar", AnyShapeStyle(nativeAIAccentGradient),
              "\(dayName) looks best from \(nativeHourLabel(peak.startHour))",
              "\(peak.label)\(near) \(soft ? "looks" : "is usually") strongest.")
    }
    return ("hourglass", AnyShapeStyle(OkkleColor.muted),
            "Still learning \(dayName)s",
            "A couple more shifts and the timing sharpens up.")
  }

}

/// A slim hour-by-hour intensity strip (9am–11pm) so "when exactly" is visible.
/// Tiny "quiet → busy" key so the heat colours on the graph read clearly and
/// aren't mistaken for the ranked-area badges.
struct NativeBusyLegend: View {
  var body: some View {
    HStack(spacing: 5) {
      Text("Quiet")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      Capsule()
        .fill(LinearGradient(colors: [nativeHeatColor(0), nativeHeatColor(0.5), nativeHeatColor(1)],
                             startPoint: .leading, endPoint: .trailing))
        .frame(width: 30, height: 5)
      Text("Busy")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
  }
}

struct NativeHourStrip: View {
  let hourCounts: [Int]
  private let hours = Array(9...23)

  var body: some View {
    let peak = max(1, hourCounts.max() ?? 1)
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .bottom, spacing: 3) {
        ForEach(hours, id: \.self) { h in
          let value = h < hourCounts.count ? hourCounts[h] : 0
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(value == 0 ? OkkleColor.muted.opacity(0.15) : nativeHeatColor(Double(value) / Double(peak)))
            .frame(maxWidth: .infinity)
            .frame(height: max(4, CGFloat(value) / CGFloat(peak) * 32))
        }
      }
      .frame(height: 32, alignment: .bottom)
      HStack(spacing: 0) {
        ForEach([9, 12, 15, 18, 21], id: \.self) { h in
          Text(nativeHourLabel(h))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }
}

/// A ranked, real (logged, not modelled) breakdown of this period's earnings
/// by platform — a cross-platform view no single delivery app can offer.
struct NativePlatformShareList: View {
  let shares: [NativePlatformShare]

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
        HStack(spacing: 12) {
          Image(systemName: nativePlatformSymbol(share.platform))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(nativeAIAccentGradient)
            .frame(width: 24)
          Text(share.platform)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(OkkleColor.ink)
          Spacer(minLength: 8)
          if let delta = share.deltaPct {
            Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(delta > 0 ? AnyShapeStyle(nativeAIAccentGradient) : AnyShapeStyle(OkkleColor.muted))
          }
          Text("\(share.sharePct)%")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
        }
        .padding(.vertical, 10)
        if index < shares.count - 1 { Divider() }
      }
    }
  }
}

// MARK: - Weekly panel

struct NativeWeeklyInsightPanel: View {
  let shift: NativeShiftInsights
  @ObservedObject private var areaNamer = NativeAreaNamer.shared
  @State private var selectedWeekday: Int?
  private var todayWeekday: Int { Calendar.current.component(.weekday, from: Date()) - 1 }

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

    return VStack(alignment: .leading, spacing: 12) {
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
    VStack(alignment: .leading, spacing: 14) {
      // Card 1 — a suggestion, clearly set apart as advice (not a stat) — the
      // one thing to act on, so it leads rather than trailing behind stats.
      if let advice = specificAdvice {
        NativeAiCard {
          section("SUGGESTION") {
            insightLine(symbol: advice.symbol, color: advice.color, text: advice.text)
          }
        }
      }

      // Card 2 — a reflection on how your week actually went.
      NativeAiCard {
        VStack(alignment: .leading, spacing: 18) {
          section("BUSIEST DAYS", subtitle: "Deliveries you made on each day.") {
            let maxCount = max(1, shift.weekdayStats.map(\.count).max() ?? 1)
            HStack(alignment: .bottom, spacing: 8) {
              ForEach(orderedWeekdayStats) { stat in
                let selected = stat.weekday == activeWeekday
                VStack(spacing: 6) {
                  // The concrete count of drops that day — more use than an
                  // abstract "% of your week".
                  Text(stat.count > 0 ? "\(stat.count)" : "")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selected ? OkkleColor.ink : OkkleColor.muted)
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
                .padding(.vertical, 6)
                .background(selected ? OkkleColor.muted.opacity(0.10) : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                  withAnimation(.easeInOut(duration: 0.15)) { selectedWeekday = stat.weekday }
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

      // Card 3 — real, logged platform ranking. Only worth showing once
      // there's an actual mix — a single platform isn't a "ranking".
      if shift.platformShares.count >= 2 {
        NativeAiCard {
          section("PLATFORM MIX", subtitle: "Share of your logged earnings this period, by app.") {
            NativePlatformShareList(shares: shift.platformShares)
          }
        }
      }

      // Card 4 — your top areas, with how much of your work each one carries.
      NativeAiCard {
        section("YOUR TOP AREAS", subtitle: "Bar shows how busy each area is compared to your #1 spot.") {
          NativeTopAreasList(zones: shift.zones, limit: 4, showShareBar: true)
        }
      }
    }
  }

  private func section<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 12, weight: .heavy)).tracking(0.5)
          .foregroundStyle(OkkleColor.muted)
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OkkleColor.muted.opacity(0.8))
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
    .font(.system(size: 12, weight: .heavy)).tracking(0.5)
    .foregroundStyle(OkkleColor.muted)
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
    .font(.system(size: size.points, weight: .bold, design: .rounded))
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
  VStack(alignment: .leading, spacing: 8) {
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
  VStack(alignment: .leading, spacing: 3) {
    nativeStatValue(value, size: .secondary)
    Text(title)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(OkkleColor.muted)
  }
  .frame(maxWidth: .infinity, alignment: .leading)
}

/// The geographic hotspot heat map as a card — the where-you-earn overview
/// reads better across a whole month or year than a single day, so it lives on
/// the wider-window panels. (Today keeps the where-to-go list + busiest hours.)
@ViewBuilder
private func nativeHotspotMapCard(trips: [NativeTrip], zones: [NativeZonePoint]) -> some View {
  if !zones.isEmpty {
    NativeAiCard {
      VStack(alignment: .leading, spacing: 12) {
        nativeInsightKicker("WHERE YOU EARN")
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
  guard (4.0...45.0).contains(rate) else { return nil }
  return "£\(Int((rate * 0.85).rounded(.down)))–\(Int((rate * 1.15).rounded(.up)))"
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
    VStack(alignment: .leading, spacing: 10) {
      // Card 1 — the money: earned this month, its trend, efficiency, pattern.
      NativeAiCard {
        VStack(alignment: .leading, spacing: 12) {
          nativeHeadlineStat(
            kicker: "EARNED · LAST 30 DAYS",
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
        VStack(alignment: .leading, spacing: 6) {
          nativeInsightKicker("TAX RELIEF BANKED · 30 DAYS")
          nativeStatValue(gbp(savings.taxSaved, whole: true), color: AnyShapeStyle(nativeAIAccentGradient))
          Text("\(gbp(savings.mileageDeduction, whole: true)) off your taxable profit, from \(miles(savings.miles)) of business driving.")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      // Card 3 — where you earn, over the last 30 days.
      nativeHotspotMapCard(trips: store.trips, zones: shift.zones)
    }
  }
}

// MARK: - Yearly panel: tax-year totals, Self Assessment deduction, seasonal shape

struct NativeYearlyInsightPanel: View {
  let shift: NativeShiftInsights
  @EnvironmentObject private var store: OkkleStore
  @State private var selectedMonth: Int?

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
    VStack(alignment: .leading, spacing: 10) {
      // Card 1 — earned this tax year, plus the same efficiency stats Monthly
      // shows (now that shift is scoped to store.taxYear, income and active
      // hours share the same window, so the rate is actually trustworthy).
      NativeAiCard {
        VStack(alignment: .leading, spacing: 12) {
          nativeHeadlineStat(
            kicker: "EARNED · THIS TAX YEAR",
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
        VStack(alignment: .leading, spacing: 6) {
          nativeInsightKicker("TAX RELIEF · THIS TAX YEAR")
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
          VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
              nativeInsightKicker("BUSIEST MONTHS")
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
                .padding(.vertical, 6)
                .background(selected ? OkkleColor.muted.opacity(0.10) : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
      nativeHotspotMapCard(trips: store.trips, zones: shift.zones)
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
        breakdownRow("sterlingsign.circle.fill", "Tax relief", gbp(savings.taxSaved, whole: true))
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
    NativeShiftInsights.enrichedVisits(visits: autoTrack.visits, trips: store.trips)
  }

  private var shift: NativeShiftInsights {
    cachedShift ?? NativeShiftInsights.build(visits: insightVisits, store: store)
  }

  private func rebuildShift() {
    cachedShift = NativeShiftInsights.build(visits: insightVisits, store: store)
  }

  var body: some View {
    NativeScreen(title: "Insights", collapsedTitle: "Insights",
                 subtitle: "From your trips: when to head out and where to go. Sharper the more you drive.") {
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
          trips: store.trips,
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
            VStack(alignment: .leading, spacing: 16) {
              Text("Keep your records fresh")
                .font(.system(size: 26, weight: .bold, design: .rounded))
              Text("Get a gentle nudge to log your miles and pay so nothing slips through the week.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(OkkleColor.muted)
              Toggle("Logging reminder", isOn: Binding(
                get: { store.settings.loggingReminder },
                set: { value in
                  withAnimation(nativeInsightPromptAnimation) {
                    store.settings.loggingReminder = value
                  }
                }
              ))
              .font(.system(size: 17, weight: .bold))
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

private struct NativeAIProgressBar: View {
  let progress: Double

  private var clampedProgress: CGFloat {
    CGFloat(min(1, max(0, progress)))
  }

  private var fillGradient: LinearGradient {
    LinearGradient(
      colors: [
        nativeAIAccentPink,
        nativeAIAccentPurple
      ],
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  var body: some View {
    GeometryReader { proxy in
      let fillWidth = proxy.size.width * clampedProgress

      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color(uiColor: .systemGray5).opacity(0.82))

        if clampedProgress > 0 {
          Capsule()
            .fill(fillGradient)
            .frame(width: max(10, fillWidth))
            .blur(radius: 4)
            .opacity(0.22)

          Capsule()
            .fill(fillGradient)
            .frame(width: max(10, fillWidth))
            .shadow(color: nativeAIAccentPink.opacity(0.16), radius: 5)
            .shadow(color: nativeAIAccentPurple.opacity(0.12), radius: 9)
            .overlay(alignment: .top) {
              Capsule()
                .fill(.white.opacity(0.16))
                .frame(height: 2)
                .padding(.horizontal, 2)
                .padding(.top, 1)
                .blendMode(.screen)
            }
        }
      }
      .overlay {
        Capsule()
          .stroke(.white.opacity(0.36), lineWidth: 1)
      }
    }
    .frame(height: 8)
    .padding(.vertical, 3)
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
      VStack(alignment: .leading, spacing: 16) {
        Text("Start trips by voice")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Let Siri and Shortcuts start or resume trip tracking with your default vehicle.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
        Toggle("Siri trip tracking", isOn: Binding(
          get: { store.settings.siriTripTrackingEnabled },
          set: { value in
            withAnimation(nativeInsightPromptAnimation) {
              store.settings.siriTripTrackingEnabled = value
            }
          }
        ))
        .font(.system(size: 17, weight: .bold))
        .tint(OkkleColor.brand)
      }
    }
  }
}
