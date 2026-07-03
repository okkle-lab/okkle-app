import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision

struct NativeProgressView: View {
  @Environment(\.nativeViewportHeight) private var nativeViewportHeight
  @EnvironmentObject private var store: OkkleStore
  @Binding var selectedTab: NativeTab
  @State private var recordsDestination: RecordsDestination?
  @State private var showsTaxBreakdown = false
  @ObservedObject private var tripSession = NativeTripSession.shared
  @State private var showsMedals = false
  @State private var medalAlert: NativeMedalAchievement?
  @State private var seenMedalKeys = Set<String>()
  @State private var selectedHistoryItem: NativeHistoryItem?
  @State private var itemPendingDeletion: NativeHistoryItem?
  @State private var tripPendingEdit: NativeTrip?
  @State private var recordPendingEdit: NativeRecord?
  @State private var recentPanelContentY: CGFloat = 0
  @State private var progressPeriod: NativeProgressPeriod = .yearToDate

  private enum RecordsDestination: String, Identifiable {
    case history
    case tax

    var id: String { rawValue }

    var recordsMode: NativeRecordsView.RecordsMode {
      switch self {
      case .history:
        return .history
      case .tax:
        return .tax
      }
    }
  }

  // MARK: Body

  var body: some View {
    ZStack {
      NativeScreen(title: "Progress", collapsedTitle: "Progress", fillsViewport: true) {
        VStack(alignment: .leading, spacing: 16) {
          progressSection

          Spacer(minLength: 0)
        }
      }
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
    .fullScreenCover(item: $recordsDestination) { destination in
      NativeRecordsView(initialMode: destination.recordsMode) {
        recordsDestination = nil
      }
      .environmentObject(store)
    }
    .fullScreenCover(isPresented: $showsMedals) {
      NativeMedalsView(initialPeriod: progressPeriod)
        .environmentObject(store)
    }
    .fullScreenCover(isPresented: $showsTaxBreakdown) {
      NativeTaxSavedBreakdownView(period: progressPeriod) {
        showsTaxBreakdown = false
      }
      .environmentObject(store)
    }
    .alert("Delete this entry?", isPresented: Binding(
      get: { itemPendingDeletion != nil },
      set: { if !$0 { itemPendingDeletion = nil } }
    )) {
      Button("Cancel", role: .cancel) {
        itemPendingDeletion = nil
      }
      Button("Delete", role: .destructive) {
        if let item = itemPendingDeletion {
          delete(item)
        }
        itemPendingDeletion = nil
      }
    } message: {
      Text(pendingDeletionMessage)
    }
    .sheet(item: $selectedHistoryItem) { item in
      let current = currentItem(matching: item) ?? item
      NativeHistoryDetailSheet(
        item: current,
        onEdit: { requestEdit(current) },
        onDelete: { requestDelete(current) }
      )
    }
    .sheet(item: $tripPendingEdit) { trip in
      NativeTripEditSheet(trip: currentTrip(matching: trip) ?? trip) { updatedTrip in
        store.updateTrip(updatedTrip)
        tripPendingEdit = nil
      }
    }
    .sheet(item: $recordPendingEdit) { record in
      NativeRecordEditSheet(record: currentRecord(matching: record) ?? record) { updatedRecord in
        store.updateRecord(updatedRecord)
        recordPendingEdit = nil
      }
    }
    .onAppear { prepareMedalAlerts() }
    .onChange(of: store.records) { _ in showNewMedalIfNeeded() }
    .onChange(of: store.trips) { _ in showNewMedalIfNeeded() }
    .onReceive(NotificationCenter.default.publisher(for: .nativeShowRecords)) { _ in
      openRecords(.history)
    }
    .onReceive(NotificationCenter.default.publisher(for: .nativeShowTaxRecords)) { _ in
      openRecords(.tax)
    }
    .onPreferenceChange(RecentPanelTopPreferenceKey.self) { top in
      if top > 0 {
        recentPanelContentY = top
      }
    }
  }

  // MARK: Tax card

  private var taxCard: some View {
    let taxSavings = selectedMileageTaxSavings
    return Button {
      showsTaxBreakdown = true
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.system(size: 14, weight: .bold))
          Text(taxCardTitle)
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(OkkleColor.muted)

        Text(headlineGbp(taxSavings.taxSaved))
          .font(.system(size: 40, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.52)

        Text("from \(miles(taxSavings.miles)) · \(gbp(taxSavings.mileageDeduction)) mileage deduction")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)

        Text("\(taxCardPeriodLabel) · see breakdown")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(OkkleColor.ink)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(Color(uiColor: .secondarySystemBackground).opacity(0.76), in: Capsule())
          .overlay {
            Capsule()
              .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
          }
          .padding(.top, 2)
      }
      .padding(20)
      .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
      .background(OkkleColor.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
      .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
    }
    .buttonStyle(.plain)
  }

  private var selectedMileageTaxSavings: NativeMileageTaxSavings {
    NativeProgressSummary.mileageTaxSavings(store: store, period: progressPeriod)
  }

  private var taxCardTitle: String {
    switch progressPeriod {
    case .weekly:
      return "Tax saved this week"
    case .yearToDate:
      return "Tax saved this year"
    case .allTime:
      return "Tax saved all time"
    }
  }

  private var taxCardPeriodLabel: String {
    switch progressPeriod {
    case .weekly:
      return "This week"
    case .yearToDate:
      return "Tax year \(taxYearLabel(for: store.taxYear))"
    case .allTime:
      return "All time"
    }
  }

  // MARK: Recent

  private var summaryMetricsGrid: some View {
    HStack(spacing: 10) {
      flatMetricTile(
        title: "Mileage",
        value: miles(store.yearMiles),
        symbol: "road.lanes",
        color: OkkleColor.brand
      )

      flatMetricTile(
        title: "Earnings",
        value: gbp(store.yearIncome),
        symbol: "sterlingsign.circle.fill",
        color: OkkleColor.brand
      )
    }
  }

  private func flatMetricTile(title: String, value: String, symbol: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(color)
      Text(value)
        .font(.system(size: 21, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
    .padding(14)
    .background(Color(uiColor: .secondarySystemBackground).opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var progressSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      progressPeriodPicker

      taxCard

      NativeMedalPreviewCard(
        achievements: selectedMedalAchievements,
        progressPeriod: progressPeriod,
        weeklyProgress: weeklyProgressTotals,
        yearToDateProgress: yearToDateProgressTotals,
        allTimeProgress: allTimeProgressTotals,
        showsMedalsSection: false
      ) {
        showsMedals = true
      }
      .okkleCard(cornerRadius: 26)

      NativeMedalPreviewPanel(achievements: selectedMedalAchievements, progressPeriod: progressPeriod) {
        showsMedals = true
      }
      .okkleCard()
    }
  }

  private var progressPeriodPicker: some View {
    Picker("Progress period", selection: $progressPeriod) {
      ForEach(NativeProgressPeriod.allCases) { period in
        Text(period.label).tag(period)
      }
    }
    .pickerStyle(.segmented)
  }

  /// A live trip in progress takes over → tap goes to Trip. Otherwise the most
  /// recent past activity → tap opens Records.
  private var recentSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("Recent activity")
          .font(.system(size: 20, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Spacer()
        Button { openRecords(.history) } label: {
          Text("Show all")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(OkkleColor.brand)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 4)

      let hasLiveTrip = tripSession.phase == .live || tripSession.phase == .paused
      if hasLiveTrip {
        liveTripCard
      }

      recentPanel
    }
    .frame(maxWidth: .infinity, alignment: .top)
  }

  private var recentHistory: [NativeHistoryItem] {
    Array(store.history.prefix(5))
  }

  private var liveTripCard: some View {
    let paused = tripSession.phase == .paused
    let accent = paused ? OkkleColor.amber : OkkleColor.brand
    return VStack(alignment: .leading, spacing: 0) {
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

  private var recentPanel: some View {
    let isEmpty = recentHistory.isEmpty
    return Group {
      if isEmpty {
        recentEmptyContent
      } else {
        recentHistoryContent
      }
    }
    .padding(isEmpty ? 18 : 16)
    .frame(
      maxWidth: .infinity,
      minHeight: isEmpty ? emptyRecentPanelHeight : nil,
      maxHeight: isEmpty ? emptyRecentPanelHeight : nil,
      alignment: isEmpty ? .center : .topLeading
    )
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .shadow(color: .black.opacity(0.07), radius: 22, y: 12)
    .background {
      GeometryReader { proxy in
        Color.clear.preference(
          key: RecentPanelTopPreferenceKey.self,
          value: proxy.frame(in: .named(nativeScreenContentCoordinateSpace)).minY
        )
      }
    }
  }

  private var recentHistoryContent: some View {
    VStack(spacing: 0) {
      ForEach(Array(recentHistory.enumerated()), id: \.element.id) { index, item in
        Button { selectedHistoryItem = currentItem(matching: item) ?? item } label: {
          HStack(spacing: 12) {
            NativeHistoryRow(item: item)
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(OkkleColor.muted)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if index < recentHistory.count - 1 {
          Divider()
            .padding(.leading, 52)
        }
      }
    }
  }

  private var recentEmptyContent: some View {
    VStack(spacing: 16) {
      VStack(spacing: 10) {
        Image(systemName: "archivebox")
          .font(.system(size: 24, weight: .bold))
          .foregroundStyle(OkkleColor.brand)
          .frame(width: 58, height: 58)
          .background(OkkleColor.brand.opacity(0.13), in: Circle())

        VStack(spacing: 0) {
          Text("No records yet")
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
          Text("Trips, earnings and expenses will appear here.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
        }
      }

      HStack(spacing: 10) {
        recentEmptyAction("Track trip", symbol: "location.north.fill") {
          selectedTab = .trip
        }
        recentEmptyAction("Records", symbol: "archivebox.fill") {
          selectedTab = .records
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  private var emptyRecentPanelHeight: CGFloat {
    guard nativeViewportHeight > 0, recentPanelContentY > 0 else {
      return 320
    }
    // NativeScreen keeps 120pt of scroll padding so content clears the system
    // tab bar. Use the same lower guard here so the empty panel stops above it
    // and does not resize during scroll bounce.
    return max(260, min(420, nativeViewportHeight - recentPanelContentY - 112))
  }

  private func recentEmptyAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .bold))
        Text(title)
          .font(.system(size: 13, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
      .foregroundStyle(OkkleColor.brand)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 9)
      .background(OkkleColor.brand.opacity(0.12), in: Capsule())
    }
    .buttonStyle(.plain)
  }

  // MARK: Derived values

  private var homeGreetingTitle: String {
    let name = store.settings.name
    guard !name.isEmpty else { return "Home" }
    // Long names get a short greeting so the line still fits.
    return "\(NativeGreeting.word(for: Date(), shortOnly: name.count > 8)), \(name)"
  }

  private var weeklyProgressTotals: NativeProgressTotals {
    NativeProgressSummary.weekly(store: store)
  }

  private var yearToDateProgressTotals: NativeProgressTotals {
    NativeProgressSummary.yearToDate(store: store)
  }

  private var allTimeProgressTotals: NativeProgressTotals {
    NativeProgressSummary.allTime(store: store)
  }

  private var selectedMedalAchievements: [NativeMedalAchievement] {
    NativeMedalEngine.achievements(store: store, period: progressPeriod)
  }

  private func openRecords(_ destination: RecordsDestination) {
    recordsDestination = destination
  }

  private func delete(_ item: NativeHistoryItem) {
    switch item {
    case .trip(let trip):
      store.deleteTrip(trip)
      if tripPendingEdit?.id == trip.id {
        tripPendingEdit = nil
      }
    case .record(let record):
      store.deleteRecord(record)
      if recordPendingEdit?.id == record.id {
        recordPendingEdit = nil
      }
    }
    if selectedHistoryItem?.id == item.id {
      selectedHistoryItem = nil
    }
  }

  private func edit(_ item: NativeHistoryItem) {
    switch item {
    case .trip(let trip):
      tripPendingEdit = currentTrip(matching: trip) ?? trip
    case .record(let record):
      recordPendingEdit = currentRecord(matching: record) ?? record
    }
  }

  private func requestEdit(_ item: NativeHistoryItem) {
    selectedHistoryItem = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      edit(currentItem(matching: item) ?? item)
    }
  }

  private func requestDelete(_ item: NativeHistoryItem) {
    selectedHistoryItem = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      itemPendingDeletion = currentItem(matching: item) ?? item
    }
  }

  private func currentTrip(matching trip: NativeTrip) -> NativeTrip? {
    store.trips.first { $0.id == trip.id }
  }

  private func currentRecord(matching record: NativeRecord) -> NativeRecord? {
    store.records.first { $0.id == record.id }
  }

  private func currentItem(matching item: NativeHistoryItem) -> NativeHistoryItem? {
    switch item {
    case .trip(let trip):
      return store.trips.first { $0.id == trip.id }.map(NativeHistoryItem.trip)
    case .record(let record):
      return store.records.first { $0.id == record.id }.map(NativeHistoryItem.record)
    }
  }

  private var pendingDeletionMessage: String {
    guard let item = itemPendingDeletion else {
      return "This cannot be undone."
    }
    switch item {
    case .trip:
      return "This trip, route and mileage deduction will be removed from Records. This cannot be undone."
    case .record(let record):
      return "This \(record.kind.label.lowercased()) entry will be removed from Records and tax totals. This cannot be undone."
    }
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
    if let next = nextTaxDay, next.days <= 14 {
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

private struct NativeTaxSavedBreakdownView: View {
  @EnvironmentObject private var store: OkkleStore
  let period: NativeProgressPeriod
  let onClose: () -> Void

  private var savings: NativeMileageTaxSavings {
    NativeProgressSummary.mileageTaxSavings(store: store, period: period)
  }

  private var taxRate: Double {
    store.settings.incomeBracket.marginalRate(region: store.settings.region)
  }

  var body: some View {
    let savings = savings
    NativeScreen(
      title: "Tax breakdown",
      collapsedTitle: "Tax",
      subtitle: "How Okkle estimates tax saved from your logged mileage.",
      onClose: onClose
    ) {
      VStack(alignment: .leading, spacing: 14) {
        NativeGlassCard(cornerRadius: 30) {
          VStack(alignment: .leading, spacing: 12) {
            Label("Estimated tax saved", systemImage: "shield.lefthalf.filled")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(OkkleColor.muted)

            Text(headlineGbp(savings.taxSaved))
              .font(.system(size: 48, weight: .heavy, design: .rounded))
              .foregroundStyle(OkkleColor.ink)
              .lineLimit(1)
              .minimumScaleFactor(0.56)

            Text(periodDetail)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
          }
        }

        NativeGlassCard {
          VStack(spacing: 12) {
            breakdownRow("Period", periodDetail)
            breakdownRow("Business miles", miles(savings.miles))
            breakdownRow("Mileage deduction", headlineGbp(savings.mileageDeduction))
            breakdownRow("Tax band", store.settings.incomeBracket.label)
            breakdownRow("Tax rate used", taxRateLabel)
            Divider()
            breakdownRow("Estimated saving", headlineGbp(savings.taxSaved), emphasized: true)
          }
        }

        Text("Estimate only, not tax advice. This uses your selected tax band and the mileage deduction for the selected period.")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 4)
      }
    }
  }

  private var periodDetail: String {
    switch period {
    case .weekly:
      return "This week"
    case .yearToDate:
      return "Tax year \(nativeTaxYearLabel(for: store.taxYear))"
    case .allTime:
      return "All time"
    }
  }

  private var taxRateLabel: String {
    let percentage = taxRate * 100
    if percentage.rounded() == percentage {
      return "\(Int(percentage))%"
    }
    return String(format: "%.1f%%", percentage)
  }

  private func breakdownRow(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .font(.system(size: 15, weight: emphasized ? .bold : .semibold))
        .foregroundStyle(emphasized ? OkkleColor.ink : OkkleColor.muted)
      Spacer(minLength: 12)
      Text(value)
        .font(.system(size: emphasized ? 18 : 16, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
        .minimumScaleFactor(0.74)
    }
  }
}

private struct RecentPanelTopPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    let next = nextValue()
    if next > 0 {
      value = next
    }
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
