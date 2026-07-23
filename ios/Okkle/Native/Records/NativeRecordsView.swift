import SwiftUI
import UIKit
import UniformTypeIdentifiers
struct NativeRecordsView: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var mode: RecordsMode
  @State private var filter: RecordsFilter = .all
  // nil = All time. Defaults to the current month — day-to-day you're
  // checking what's recent, not everything you've ever logged; All time is
  // one tap away via the month picker below.
  @State private var selectedMonth: Date? = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))
  @State private var tripCategoryFilter: NativeTripCategoryFilter = .all
  @State private var itemPendingDeletion: NativeHistoryItem?
  @State private var selectedHistoryItem: NativeHistoryItem?
  @State private var tripPendingEdit: NativeTrip?
  @State private var recordPendingEdit: NativeRecord?
  @State private var showsAddRecordPanel = false
  var onClose: (() -> Void)? = nil

  enum RecordsMode: String, CaseIterable, Identifiable {
    case history
    case tax

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
  }

  enum RecordsFilter: String, CaseIterable, Identifiable {
    case all
    case journeys
    case income
    case expense

    var id: String { rawValue }
    var label: String {
      switch self {
      case .all:
        return "All"
      case .journeys:
        return "Trips"
      case .income:
        return "Income"
      case .expense:
        return "Expense"
      }
    }
  }

  // Only ever narrows trips — income/expense records have no business/
  // personal concept, so they're unaffected regardless of this selection.
  enum NativeTripCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case business
    case personal

    var id: String { rawValue }
    var label: String {
      switch self {
      case .all: return "All"
      case .business: return "Business"
      case .personal: return "Personal"
      }
    }
  }

  init(initialMode: RecordsMode = .history, onClose: (() -> Void)? = nil) {
    _mode = State(initialValue: initialMode)
    self.onClose = onClose
  }

  var body: some View {
    NativeScreen(
      title: "Data",
      collapsedTitle: "Data",
      subtitle: "Log trip mileage, income and expenses - all export-ready.",
      onClose: onClose,
      fillsViewport: mode == .history
    ) {
      if mode == .tax {
        NativeTaxSummaryView()
      } else {
        recordsOverview
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      bottomAddRecordMenu
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
    .sheet(isPresented: $showsAddRecordPanel) {
      NativeAddRecordPanel(
        title: { logTitle(for: $0) },
        subtitle: { logSubtitle(for: $0) },
        onViewRecords: {
          showsAddRecordPanel = false
        }
      )
      .environmentObject(store)
      .presentationDetents([.medium])
      .presentationDragIndicator(.visible)
    }
  }

  private var recordsOverview: some View {
    VStack(spacing: 14) {
      recordsSummaryCard
      historyContent
    }
  }

  // Same scope as the list below it (month + trip-category filters) so the
  // headline figures always describe exactly what's currently on screen.
  private var monthScopedHistory: [NativeHistoryItem] {
    store.history.filter { item in
      guard let selectedMonth else { return true }
      return Calendar.current.isDate(item.date, equalTo: selectedMonth, toGranularity: .month)
    }
  }

  // Personal trips never count toward the headline miles figure — unless
  // the driver has explicitly filtered down to Personal while looking at
  // Trips, in which case that's exactly the figure they're asking to see.
  // Same gating as filteredHistory: the trip-type control only has a
  // visible effect while filter == .journeys.
  private var summaryMilesCategory: NativeTripCategory {
    filter == .journeys && tripCategoryFilter == .personal ? .personal : .business
  }

  private var summaryMiles: Double {
    monthScopedHistory.reduce(0) { partial, item in
      guard case .trip(let trip) = item, trip.category == summaryMilesCategory else { return partial }
      return partial + max(0, trip.miles)
    }
  }

  private var summaryIncome: Double {
    monthScopedHistory.reduce(0) { partial, item in
      guard case .record(let record) = item, record.kind == .income else { return partial }
      return partial + max(0, record.amount ?? 0)
    }
  }

  private var summaryExpense: Double {
    monthScopedHistory.reduce(0) { partial, item in
      guard case .record(let record) = item, record.kind == .expense else { return partial }
      return partial + max(0, record.amount ?? 0)
    }
  }

  private var recordsSummaryCard: some View {
    NativeGlassCard(cornerRadius: 28, contentPadding: 18) {
      VStack(alignment: .leading, spacing: 16) {
        Label(monthButtonLabel, systemImage: "calendar")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(OkkleColor.muted)

        HStack(alignment: .top, spacing: 0) {
          summaryStat(title: "\(summaryMilesCategory == .personal ? "Personal" : "Business") miles", value: miles(summaryMiles))
          Divider().frame(height: 46)
          summaryStat(title: "Income", value: gbp(summaryIncome, whole: true), color: .green)
          Divider().frame(height: 46)
          summaryStat(title: "Expenses", value: gbp(summaryExpense, whole: true), color: OkkleColor.red)
        }
      }
    }
  }

  private func summaryStat(title: String, value: String, color: Color = OkkleColor.ink) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Text(value)
        .font(.system(size: 19, weight: .heavy, design: .rounded))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 6)
  }

  private var addRecordButton: some View {
    Button {
      showsAddRecordPanel = true
    } label: {
      Label("Add record", systemImage: "plus")
        .font(.system(size: 17, weight: .heavy))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Add record")
  }

  private var bottomAddRecordMenu: some View {
    HStack {
      Spacer()
      addRecordButton
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(OkkleColor.brand, in: Capsule())
        .overlay {
          Capsule()
            .stroke(.white.opacity(0.22), lineWidth: 0.8)
        }
        .shadow(color: OkkleColor.brand.opacity(0.32), radius: 22, y: 10)
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .padding(.bottom, 10)
  }

  private func logTitle(for kind: NativeLogKind) -> String {
    switch kind {
    case .income:
      return "Log earnings"
    case .expense:
      return "Log expense"
    case .mileage:
      return "Log mileage"
    }
  }

  private func logSubtitle(for kind: NativeLogKind) -> String {
    switch kind {
    case .income:
      return "Add delivery pay, tips or bonuses."
    case .expense:
      return "Add a deductible cost."
    case .mileage:
      return "Add mileage from a previous journey."
    }
  }

  // A filter combination narrowing everything to zero results (e.g. "Trips"
  // + "Personal" when no whole trip has been marked personal — only a stop
  // within one has, a different, more granular thing) used to fall through
  // to the generic "log something" empty state, which reads as "the app
  // lost my data" rather than "this filter matched nothing." Distinguishing
  // the two, with a one-tap way back to "All", was reported as confusing.
  @ViewBuilder
  private var emptyStateView: some View {
    if store.history.isEmpty {
      NativeEmptyState(symbol: "archivebox", title: "Nothing here yet", message: "Mileage, earnings and expenses appear here after you save them.")
    } else {
      NativeGlassCard {
        VStack(spacing: 12) {
          Image(systemName: "line.3.horizontal.decrease.circle")
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(OkkleColor.brand)
            .frame(width: 68, height: 68)
            .background(OkkleColor.mint, in: Circle())
          Text("No matches for this filter")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(OkkleColor.ink)
          Text(noMatchesMessage)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .multilineTextAlignment(.center)
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              filter = .all
              selectedMonth = nil
              tripCategoryFilter = .all
            }
          } label: {
            Text("Clear filters")
              .font(.system(size: 15, weight: .bold))
          }
          .buttonStyle(.plain)
          .foregroundStyle(OkkleColor.brand)
          .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
      }
    }
  }

  private var noMatchesMessage: String {
    let monthSuffix = selectedMonth != nil ? " in \(monthButtonLabel)" : ""
    if filter == .journeys, tripCategoryFilter != .all {
      return "No \(tripCategoryFilter.label.lowercased()) trips\(monthSuffix)."
    }
    if filter != .all {
      return "No \(filter.label.lowercased()) logged\(monthSuffix)."
    }
    return "Nothing logged\(monthSuffix)."
  }

  private var historyContent: some View {
    LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
      Section {
        if filteredHistory.isEmpty {
          emptyStateView
            .padding(.top, 20)
        } else {
          NativeGlassCard {
            VStack(spacing: 0) {
              ForEach(filteredHistory) { item in
                NativeSelectableHistoryRow(
                  item: item,
                  onSelect: { selectFromAllHistory(item) },
                  onSetTripCategory: { category in
                    if let trip = item.trip {
                      store.setTripCategory(trip, to: category)
                    }
                  },
                  onDeleteTrip: {
                    if let trip = item.trip {
                      requestDelete(.trip(trip))
                    }
                  }
                )
                if item.id != filteredHistory.last?.id {
                  Divider().padding(.leading, 52)
                }
              }
            }
          }
        }
      } header: {
        historyFilterBar
      }
    }
    .frame(maxWidth: .infinity, alignment: .top)
    // Extra clearance below the last row so it doesn't sit visually cropped
    // under the floating "Add record" button — that button is a second,
    // taller safe-area inset on top of NativeScreen's generic bottom
    // padding, which alone wasn't enough on this screen.
    .padding(.bottom, 90)
  }

  private var historyFilterBar: some View {
    HStack(spacing: 10) {
      Picker("History filter", selection: $filter) {
        ForEach(RecordsFilter.allCases) { Text($0.label).tag($0) }
      }
      .pickerStyle(.segmented)

      Menu {
        Section("Month") {
          Button {
            selectedMonth = nil
          } label: {
            if selectedMonth == nil {
              Label("All time", systemImage: "checkmark")
            } else {
              Text("All time")
            }
          }

          ForEach(availableMonths, id: \.self) { month in
            Button {
              selectedMonth = month
            } label: {
              if selectedMonth == month {
                Label(monthLabel(for: month), systemImage: "checkmark")
              } else {
                Text(monthLabel(for: month))
              }
            }
          }
        }

        // Business/personal only makes sense while looking at trips —
        // income and expense records have no such concept.
        if filter == .journeys {
          Section("Trip type") {
            ForEach(NativeTripCategoryFilter.allCases) { option in
              Button {
                tripCategoryFilter = option
              } label: {
                if tripCategoryFilter == option {
                  Label(option.label, systemImage: "checkmark")
                } else {
                  Text(option.label)
                }
              }
            }
          }
        }
      } label: {
        Label(filterButtonLabel, systemImage: "line.3.horizontal.decrease")
          .labelStyle(.iconOnly)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(OkkleColor.brand)
          .padding(10)
          .background(OkkleColor.brand.opacity(isFilterActive ? 0.22 : 0.14), in: Circle())
          .overlay {
            Circle()
              .stroke(OkkleColor.brand.opacity(isFilterActive ? 0.38 : 0), lineWidth: 1)
          }
      }
      .accessibilityLabel(filterButtonLabel)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 8)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.white.opacity(0.18), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    .zIndex(1)
  }

  private func selectFromAllHistory(_ item: NativeHistoryItem) {
    selectedHistoryItem = currentItem(matching: item) ?? item
  }

  private var filteredHistory: [NativeHistoryItem] {
    store.history.filter { item in
      let typeOk: Bool
      switch filter {
      case .all:
        typeOk = true
      case .journeys:
        if case .trip = item { typeOk = true }
        else if case .record(let record) = item { typeOk = record.kind == .mileage }
        else { typeOk = false }
      case .income:
        if case .record(let record) = item { typeOk = record.kind == .income } else { typeOk = false }
      case .expense:
        if case .record(let record) = item { typeOk = record.kind == .expense } else { typeOk = false }
      }
      guard typeOk else { return false }
      // Trip type only ever has a visible control while looking at Trips
      // (see historyFilterBar) — it must not silently keep narrowing "All"
      // (or Income/Expense) after switching away from Trips with it set.
      if filter == .journeys, tripCategoryFilter != .all, case .trip(let trip) = item {
        let wantsBusiness = tripCategoryFilter == .business
        guard (trip.category == .business) == wantsBusiness else { return false }
      }
      guard let selectedMonth else { return true }
      return Calendar.current.isDate(item.date, equalTo: selectedMonth, toGranularity: .month)
    }
  }

  /// Distinct months present anywhere in history (not just the current type
  /// filter), newest first — what the month picker offers.
  private var availableMonths: [Date] {
    let calendar = Calendar.current
    let months = Set(store.history.map { calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date)) ?? $0.date })
    return months.sorted(by: >)
  }

  private func monthLabel(for month: Date) -> String {
    month.formatted(.dateTime.month(.abbreviated).year())
  }

  private var monthButtonLabel: String {
    selectedMonth.map(monthLabel) ?? "All time"
  }

  private var isFilterActive: Bool {
    selectedMonth != nil || (filter == .journeys && tripCategoryFilter != .all)
  }

  private var filterButtonLabel: String {
    guard filter == .journeys, tripCategoryFilter != .all else { return monthButtonLabel }
    return "\(monthButtonLabel), \(tripCategoryFilter.label)"
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
    edit(currentItem(matching: item) ?? item)
    selectedHistoryItem = nil
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
}

private struct NativeAddRecordPanel: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: OkkleStore
  @State private var logKind: NativeLogKind?
  let title: (NativeLogKind) -> String
  let subtitle: (NativeLogKind) -> String
  let onViewRecords: () -> Void

  private let options: [NativeLogKind] = [.income, .expense, .mileage]

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(options) { kind in
            Button {
              logKind = kind
            } label: {
              HStack(spacing: 14) {
                Image(systemName: kind.symbol)
                  .font(.system(size: 18, weight: .bold))
                  .foregroundStyle(optionTint(for: kind))
                  .frame(width: 36, height: 36)
                  .background(optionTint(for: kind).opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                  Text(optionTitle(for: kind))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OkkleColor.ink)
                  Text(optionSubtitle(for: kind))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(.tertiary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
          }
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.visible)
      .navigationTitle("Add record")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .fontWeight(.semibold)
        }
      }
      .sheet(item: $logKind) { kind in
        NativeLogView(
          initialKind: kind,
          allowedKinds: [kind],
          title: title(kind),
          subtitle: subtitle(kind),
          onClose: {
            logKind = nil
          },
          onViewRecords: {
            logKind = nil
            onViewRecords()
          }
        )
        .environmentObject(store)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
    }
  }

  private func optionTitle(for kind: NativeLogKind) -> String {
    switch kind {
    case .income:
      return "Earnings"
    case .expense:
      return "Expense"
    case .mileage:
      return "Mileage"
    }
  }

  private func optionSubtitle(for kind: NativeLogKind) -> String {
    switch kind {
    case .income:
      return "Pay, tips or bonuses"
    case .expense:
      return "Deductible cost"
    case .mileage:
      return "Previous journey"
    }
  }

  private func optionTint(for kind: NativeLogKind) -> Color {
    switch kind {
    case .income:
      return .green
    case .expense:
      return OkkleColor.red
    case .mileage:
      return OkkleColor.brand
    }
  }
}

struct NativeSelectableHistoryRow: View {
  let item: NativeHistoryItem
  let onSelect: () -> Void
  var onSetTripCategory: ((NativeTripCategory) -> Void)? = nil
  var onDeleteTrip: (() -> Void)? = nil

  var body: some View {
    if let trip = item.trip {
      NativeTripSwipeRow(
        trip: trip,
        onSetCategory: { onSetTripCategory?($0) }
      ) {
        row
      }
    } else {
      row
    }
  }

  private var row: some View {
    Button(action: onSelect) {
      NativeHistoryRow(item: item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isButton)
    .accessibilityHint("Opens details.")
    .contextMenu {
      if item.trip != nil, let onDeleteTrip {
        Button(role: .destructive, action: onDeleteTrip) {
          Label("Delete", systemImage: "trash")
        }
      }
    }
  }
}

/// Swipe a trip to reclassify it — two fixed edges, not one dynamic toggle:
/// swiping right (leading edge) always reveals Business, swiping left
/// (trailing edge) always reveals Personal. Full swipe on either side
/// commits immediately since this is reversible. Delete moved to a
/// long-press context menu on the row (see NativeSelectableHistoryRow) so
/// the swipe gesture means the same thing everywhere it appears — this
/// exact same left/right convention repeats on individual stop rows inside
/// a trip's detail screen (NativeVisitSwipeRow). Built by hand rather than
/// SwiftUI's native `.swipeActions` because this list lives in a
/// `LazyVStack` inside `NativeScreen`'s outer ScrollView, not a `List` —
/// `.swipeActions` only works on List rows.
private struct NativeTripSwipeRow<Content: View>: View {
  let trip: NativeTrip
  let onSetCategory: (NativeTripCategory) -> Void
  @ViewBuilder var content: () -> Content

  @State private var dragOffset: CGFloat = 0
  @State private var isOpen = false

  private let revealWidth: CGFloat = 92
  private let fullSwipeCommitDistance: CGFloat = 150

  var body: some View {
    ZStack {
      HStack(spacing: 0) {
        if dragOffset > 0 {
          swipeButton(label: "Business", symbol: "briefcase.fill", tint: OkkleColor.brand) { commit(.business) }
            .frame(width: max(dragOffset, revealWidth), alignment: .leading)
          Spacer(minLength: 0)
        } else if dragOffset < 0 {
          Spacer(minLength: 0)
          swipeButton(label: "Personal", symbol: "person.fill", tint: .gray) { commit(.personal) }
            .frame(width: max(-dragOffset, revealWidth), alignment: .trailing)
        }
      }

      content()
        .background(.regularMaterial)
        .offset(x: dragOffset)
        .contentShape(Rectangle())
        .onTapGesture {
          if isOpen { close() }
        }
        .highPriorityGesture(
          DragGesture(minimumDistance: 14)
            .onChanged { value in
              guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
              let base: CGFloat = isOpen ? (dragOffset >= 0 ? revealWidth : -revealWidth) : 0
              let proposed = base + value.translation.width
              dragOffset = max(-fullSwipeCommitDistance - 30, min(fullSwipeCommitDistance + 30, proposed))
            }
            .onEnded { value in
              handleDragEnd(value.translation.width)
            }
        )
    }
    .clipped()
  }

  private func swipeButton(label: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: symbol)
          .font(.system(size: 16, weight: .bold))
        Text(label)
          .font(.system(size: 11, weight: .bold))
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .buttonStyle(.plain)
    .background(tint)
  }

  private func handleDragEnd(_ translation: CGFloat) {
    if translation <= -fullSwipeCommitDistance {
      commit(.personal)
      return
    }
    if translation >= fullSwipeCommitDistance {
      commit(.business)
      return
    }
    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
      if dragOffset > revealWidth / 2 {
        dragOffset = revealWidth
        isOpen = true
      } else if dragOffset < -revealWidth / 2 {
        dragOffset = -revealWidth
        isOpen = true
      } else {
        dragOffset = 0
        isOpen = false
      }
    }
  }

  private func commit(_ category: NativeTripCategory) {
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
    onSetCategory(category)
    close()
  }

  private func close() {
    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
      dragOffset = 0
      isOpen = false
    }
  }
}

struct NativeHistoryRow: View {
  let item: NativeHistoryItem

  var body: some View {
    HStack(spacing: 12) {
      iconView
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
        Text(subtitle)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .lineLimit(1)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        Text(value)
          .font(.system(size: 16, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        if let detail {
          Text(detail)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
        }
      }
    }
    .padding(.vertical, 12)
  }

  private var symbol: String {
    switch item {
    case .trip: return "location.north.fill"
    case .record(let record): return record.kind.symbol
    }
  }

  /// An income row's real platform logo when we have one bundled, otherwise
  /// falls back to the existing kind/tint-based circle exactly as before —
  /// trips, expenses and mileage entries aren't tied to a delivery platform,
  /// so they're untouched.
  @ViewBuilder
  private var iconView: some View {
    if case .record(let record) = item,
       record.kind == .income,
       let platform = record.platform,
       let assetName = nativePlatformIconAssetName(platform) {
      Image(assetName)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    } else {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 40, height: 40)
        .background(tint.opacity(0.13), in: Circle())
    }
  }

  private var tint: Color {
    switch item {
    // Indigo for a business trip, gray for personal — kept distinct from
    // expense's red so the two don't read as the same color in a mixed
    // list (they used to both be amber, which was the actual complaint).
    case .trip(let trip): return trip.category == .personal ? .gray : .indigo
    case .record(let record):
      switch record.kind {
      case .income: return .green
      case .expense: return OkkleColor.red
      case .mileage: return OkkleColor.brand
      }
    }
  }

  private var title: String {
    switch item {
    case .trip(let trip): return "Trip - \(trip.vehicle.label)"
    case .record(let record):
      switch record.kind {
      case .income: return record.platform ?? "Earnings"
      case .expense: return record.category ?? "Expense"
      case .mileage: return "Mileage - \(record.vehicle?.label ?? "Vehicle")"
      }
    }
  }

  private var subtitle: String {
    switch item {
    case .trip(let trip): return "GPS - \(shortDate(trip.startedAt))"
    case .record(let record):
      if record.kind == .expense, let merchant = record.merchant, !merchant.isEmpty {
        return "\(merchant) - \(shortDate(record.date))"
      }
      return "\(record.kind.label) - \(shortDate(record.date))"
    }
  }

  private var value: String {
    switch item {
    case .trip(let trip): return miles(trip.miles)
    case .record(let record):
      if record.kind == .mileage { return miles(record.miles ?? 0) }
      return gbp(record.amount ?? 0)
    }
  }

  private var detail: String? {
    switch item {
    case .trip(let trip): return gbp(trip.deduction, whole: true)
    case .record(let record):
      if let deduction = record.deduction { return gbp(deduction, whole: true) }
      return record.period.label
    }
  }
}

struct NativeShareItem: Identifiable {
  let id = UUID()
  let urls: [URL]

  init(urls: [URL]) { self.urls = urls }
  init(url: URL) { self.urls = [url] }
}

struct NativeShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    // Wrap file URLs so the share sheet declares an explicit UTType (from
    // the file's own extension) rather than leaving Mail/Files/AirDrop to
    // infer one — without this, some destinations fall back to treating
    // the file as generic plain text instead of recognising it as a CSV
    // or PDF.
    let wrapped = items.map { item -> Any in
      guard let url = item as? URL else { return item }
      return NativeFileActivityItem(url: url)
    }
    return UIActivityViewController(activityItems: wrapped, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class NativeFileActivityItem: NSObject, UIActivityItemSource {
  let url: URL
  private let utType: UTType

  init(url: URL) {
    self.url = url
    self.utType = UTType(filenameExtension: url.pathExtension) ?? .data
  }

  func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
    url
  }

  func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
    url
  }

  func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
    url.deletingPathExtension().lastPathComponent
  }

  func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
    utType.identifier
  }
}

struct NativeBackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }

  var data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

enum NativeBackupResult {
  case iCloud(URL)
  case share(NativeShareItem)
  case failed(String)
}

@MainActor
func nativeCreateBackup(store: OkkleStore) -> NativeBackupResult {
  let fileManager = FileManager.default
  if let container = nativeICloudContainerURL(fileManager: fileManager) {
    do {
      let folder = container
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("Okkle Backups", isDirectory: true)
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

      let fileName = nativeBackupFileName()
      let cloudURL = folder.appendingPathComponent(fileName)
      let localURL = fileManager.temporaryDirectory.appendingPathComponent(fileName)
      try store.backupData().write(to: localURL, options: [.atomic])
      if fileManager.fileExists(atPath: cloudURL.path) {
        try fileManager.removeItem(at: cloudURL)
      }

      do {
        try fileManager.setUbiquitous(true, itemAt: localURL, destinationURL: cloudURL)
      } catch {
        try store.backupData().write(to: cloudURL, options: [.atomic])
        try? fileManager.removeItem(at: localURL)
      }

      return .iCloud(cloudURL)
    } catch {
      if let item = nativeCreateShareBackup(store: store) {
        return .share(item)
      }
      return .failed("Could not write to iCloud Drive. \(error.localizedDescription)")
    }
  }

  if let item = nativeCreateShareBackup(store: store) {
    return .share(item)
  }
  return .failed("iCloud Drive is not available on this device.")
}

let nativeICloudContainerIdentifier = "iCloud.okklelab.app"

func nativeICloudContainerURL(fileManager: FileManager = .default) -> URL? {
  fileManager.url(forUbiquityContainerIdentifier: nativeICloudContainerIdentifier)
    ?? fileManager.url(forUbiquityContainerIdentifier: nil)
}

@MainActor
func nativeCreateShareBackup(store: OkkleStore) -> NativeShareItem? {
  do {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(nativeBackupFileName())
    try store.backupData().write(to: url, options: [.atomic])
    return NativeShareItem(url: url)
  } catch {
    return nil
  }
}

func nativeBackupFileName() -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
  return "Okkle_Backup_\(formatter.string(from: Date())).json"
}

enum NativeExportFormat: String, CaseIterable, Identifiable {
  case pdf
  case csv

  var id: String { rawValue }
  var label: String { self == .pdf ? "PDF" : "CSV" }
}

/// The five exportable documents. Some (accountant pack, self assessment,
/// mileage) are available in either format — the picker asks PDF, CSV, or
/// both — while the raw-data pair only ever existed as CSV.
enum NativeExportDocument: String, CaseIterable, Identifiable {
  case accountantPack
  case selfAssessment
  case mileage
  case freeAgent
  case quickBooks
  case xero
  case wave
  case allData

  var id: String { rawValue }

  /// The raw-data bookkeeping-software exports, filtered to what's actually
  /// relevant for the driver's market — FreeAgent is a UK-only product, so
  /// there's no point offering it to a US driver.
  static func available(for country: NativeTaxCountry) -> [NativeExportDocument] {
    allCases.filter { $0 != .freeAgent || country == .uk }
  }

  func title(for country: NativeTaxCountry) -> String {
    switch self {
    case .accountantPack: return "Accountant pack"
    case .selfAssessment: return country == .uk ? "Self Assessment summary" : "Schedule C summary"
    case .mileage: return "Mileage"
    case .freeAgent: return "FreeAgent CSV"
    case .quickBooks: return "QuickBooks CSV"
    case .xero: return "Xero CSV"
    case .wave: return "Wave CSV"
    case .allData: return "All data CSV"
    }
  }

  func subtitle(for country: NativeTaxCountry) -> String {
    switch self {
    case .accountantPack: return "Mileage, expenses & receipts"
    case .selfAssessment: return "Turnover, profit and tax due"
    case .mileage: return country == .uk ? "Rate-band report or full CSV log" : "Mileage report or full CSV log"
    case .freeAgent: return "Ready for FreeAgent's bank statement import"
    case .quickBooks: return "Ready for QuickBooks Online's transaction import"
    case .xero: return "Ready for Xero's bank statement import"
    case .wave: return "Ready for Wave's statement import"
    case .allData: return "Trips, earnings and expenses"
    }
  }

  var symbol: String {
    switch self {
    case .accountantPack: return "doc.richtext.fill"
    case .selfAssessment: return "doc.text.fill"
    case .mileage: return "map.fill"
    case .freeAgent, .quickBooks, .xero, .wave: return "arrow.up.doc.fill"
    case .allData: return "externaldrive.fill"
    }
  }

  var group: NativeTaxExportGroup {
    switch self {
    case .accountantPack, .selfAssessment: return .accountant
    case .mileage: return .mileage
    case .freeAgent, .quickBooks, .xero, .wave, .allData: return .rawData
    }
  }

  var formats: [NativeExportFormat] {
    switch self {
    case .accountantPack, .selfAssessment, .mileage: return [.pdf, .csv]
    case .freeAgent, .quickBooks, .xero, .wave, .allData: return [.csv]
    }
  }

  func kind(for format: NativeExportFormat) -> NativeTaxExportKind {
    switch (self, format) {
    case (.accountantPack, .pdf): return .accountantPackPdf
    case (.accountantPack, .csv): return .accountantPackCsv
    case (.selfAssessment, .pdf): return .selfAssessmentPdf
    case (.selfAssessment, .csv): return .selfAssessmentCsv
    case (.mileage, .pdf): return .mileageReportPdf
    case (.mileage, .csv): return .mileageLogCsv
    case (.freeAgent, _): return .freeAgent
    case (.quickBooks, _): return .quickBooks
    case (.xero, _): return .xero
    case (.wave, _): return .wave
    case (.allData, _): return .allData
    }
  }
}

enum NativeTaxExportGroup: CaseIterable {
  case mileage
  case accountant
  case rawData

  var title: String {
    switch self {
    case .accountant: return "Accountant & tax summary"
    case .mileage: return "Mileage"
    case .rawData: return "Raw data"
    }
  }
}

enum NativeTaxExportKind: String, CaseIterable, Identifiable {
  case accountantPackPdf
  case accountantPackCsv
  case selfAssessmentPdf
  case selfAssessmentCsv
  case mileageReportPdf
  case mileageLogCsv
  case freeAgent
  case quickBooks
  case xero
  case wave
  case allData

  var id: String { rawValue }

  var format: NativeExportFormat {
    switch self {
    case .accountantPackPdf, .selfAssessmentPdf, .mileageReportPdf: return .pdf
    case .accountantPackCsv, .selfAssessmentCsv, .mileageLogCsv, .freeAgent, .quickBooks, .xero, .wave, .allData: return .csv
    }
  }

  func fileStem(for country: NativeTaxCountry) -> String {
    switch self {
    case .accountantPackPdf, .accountantPackCsv: return "Accountant-Pack"
    case .selfAssessmentPdf, .selfAssessmentCsv: return country == .uk ? "SelfAssessment-Summary" : "ScheduleC-Summary"
    case .mileageReportPdf: return "Mileage-Report"
    case .mileageLogCsv: return country == .uk ? "HMRC-Mileage-Log" : "IRS-Mileage-Log"
    case .freeAgent: return "FreeAgent-Import"
    case .quickBooks: return "QuickBooks-Import"
    case .xero: return "Xero-Import"
    case .wave: return "Wave-Import"
    case .allData: return "All-Data"
    }
  }

  var fileExtension: String { format == .pdf ? "pdf" : "csv" }
}
