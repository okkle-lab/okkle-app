import SwiftUI

struct NativeProgressTotals {
  var mileageMiles: Double
  var recordsLogged: Int
  var tripsTracked: Int
}

enum NativeProgressPeriod: String, CaseIterable, Identifiable {
  case weekly
  case yearToDate
  case allTime

  var id: String { rawValue }

  var label: String {
    switch self {
    case .weekly:
      return "Weekly"
    case .yearToDate:
      return "YTD"
    case .allTime:
      return "All time"
    }
  }

  var medalScopeLabel: String {
    switch self {
    case .weekly:
      return "this week"
    case .yearToDate:
      return "this year"
    case .allTime:
      return "all time"
    }
  }
}

struct NativeMileageLoggedPanel: View {
  @Environment(\.colorScheme) private var colorScheme
  let totals: NativeProgressTotals

  private var mileageHeaderAccent: Color {
    colorScheme == .dark ? Color(red: 0.50, green: 0.84, blue: 0.77) : OkkleColor.brandDark
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          Image(systemName: "road.lanes")
            .font(.system(size: 14, weight: .bold))
          Text("Mileage logged")
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(mileageHeaderAccent)

        Text(miles(totals.mileageMiles))
          .font(.system(size: 40, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.52)
      }

      VStack(spacing: 16) {
        NativeProgressMetricRow(
          title: "First 10K mileage band",
          value: "\(Int(totals.mileageMiles.rounded()).formatted()) / 10,000 mi",
          progress: totals.mileageMiles / 10_000
        )

        NativeCityDistanceDetail(totalMiles: totals.mileageMiles)

        NativeProgressMetricRow(
          title: "Records logged",
          value: "\(totals.recordsLogged.formatted()) \(totals.recordsLogged == 1 ? "entry" : "entries")",
          progress: Double(totals.recordsLogged) / 25
        )
        NativeProgressMetricRow(
          title: "Trips tracked",
          value: "\(totals.tripsTracked.formatted()) \(totals.tripsTracked == 1 ? "trip" : "trips")",
          progress: Double(totals.tripsTracked) / 20
        )
      }
    }
  }
}

struct NativeMedalPreviewCard: View {
  let achievements: [NativeMedalAchievement]
  var progressPeriod: NativeProgressPeriod
  var weeklyProgress: NativeProgressTotals
  var yearToDateProgress: NativeProgressTotals
  var allTimeProgress: NativeProgressTotals
  var showsMedalsSection = true
  let onOpen: () -> Void

  private var unlocked: [NativeMedalAchievement] {
    achievements.filter(\.unlocked)
  }

  private var inProgress: [NativeMedalAchievement] {
    achievements
      .filter { !$0.unlocked && $0.progress > 0 }
      .sorted { $0.progress > $1.progress }
      .map { $0 }
  }

  private var selectedProgress: NativeProgressTotals {
    switch progressPeriod {
    case .weekly:
      return weeklyProgress
    case .yearToDate:
      return yearToDateProgress
    case .allTime:
      return allTimeProgress
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      NativeMileageLoggedPanel(totals: selectedProgress)

      if showsMedalsSection {
        Divider()

        NativeMedalPreviewPanelContent(
          unlocked: unlocked,
          inProgress: inProgress,
          progressPeriod: progressPeriod,
          onOpen: onOpen
        )
      }
    }
    .padding(16)
  }
}

struct NativeMedalPreviewPanel: View {
  let achievements: [NativeMedalAchievement]
  var progressPeriod: NativeProgressPeriod = .allTime
  let onOpen: () -> Void

  private var unlocked: [NativeMedalAchievement] {
    achievements.filter(\.unlocked)
  }

  private var inProgress: [NativeMedalAchievement] {
    achievements
      .filter { !$0.unlocked && $0.progress > 0 }
      .sorted { $0.progress > $1.progress }
      .map { $0 }
  }

  var body: some View {
    NativeMedalPreviewPanelContent(
      unlocked: unlocked,
      inProgress: inProgress,
      progressPeriod: progressPeriod,
      onOpen: onOpen
    )
    .padding(16)
  }
}

private struct NativeMedalPreviewPanelContent: View {
  let unlocked: [NativeMedalAchievement]
  let inProgress: [NativeMedalAchievement]
  let progressPeriod: NativeProgressPeriod
  let onOpen: () -> Void

  private var unlockedPreview: [NativeMedalAchievement] {
    Array(unlocked.suffix(3))
  }

  private var inProgressPreview: [NativeMedalAchievement] {
    Array(inProgress.prefix(3))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Medals")
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
          Text("Unlocked and in progress \(progressPeriod.medalScopeLabel)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
        }
        Spacer()
        Button(action: onOpen) {
          HStack(spacing: 6) {
            Image(systemName: "chevron.right")
              .font(.system(size: 16, weight: .heavy))
            Text("See all")
              .font(.system(size: 14, weight: .heavy))
          }
          .foregroundStyle(OkkleColor.brandDark)
        }
        .buttonStyle(.plain)
      }

      if unlockedPreview.isEmpty && inProgressPreview.isEmpty {
        NativeMedalEmptyMessage(scope: progressPeriod.medalScopeLabel)
      } else {
        if !unlockedPreview.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Text("Unlocked")
              .font(.system(size: 13, weight: .heavy))
              .foregroundStyle(OkkleColor.ink)

            HStack(alignment: .top, spacing: 14) {
              ForEach(unlockedPreview) { achievement in
                NativeMedalMiniTile(achievement: achievement)
              }
            }
          }
        }

        if !inProgressPreview.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("In progress")
              .font(.system(size: 13, weight: .heavy))
              .foregroundStyle(OkkleColor.ink)

            VStack(alignment: .leading, spacing: 14) {
              ForEach(inProgressPreview) { achievement in
                NativeMedalProgressRow(achievement: achievement)
              }
            }
          }
        }
      }
    }
  }
}

private struct NativeMedalMiniTile: View {
  let achievement: NativeMedalAchievement

  var body: some View {
    VStack(spacing: 7) {
      NativeMedalIcon(achievement: achievement, size: 56, rendering: .compact)
      Text(achievement.label)
        .font(.system(size: 11, weight: .heavy))
        .foregroundStyle(OkkleColor.ink)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.74)
        .frame(height: 32, alignment: .top)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct NativeMedalEmptyMessage: View {
  let scope: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "sparkles")
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(OkkleColor.brandDark)
        .frame(width: 30, height: 30)
        .background(OkkleColor.brand.opacity(0.12), in: Circle())

      Text("Track activity to unlock medals \(scope).")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(uiColor: .secondarySystemBackground).opacity(0.66), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

private struct NativeProgressMetricRow: View {
  let title: String
  let value: String
  let progress: Double

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.system(size: 15, weight: .heavy))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Spacer(minLength: 12)
        Text(value)
          .font(.system(size: 14, weight: .heavy))
          .foregroundStyle(OkkleColor.muted)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }

      NativeThinProgressBar(progress: progress, tint: OkkleColor.brandDark)
    }
  }
}

private struct NativeCityDistanceDetail: View {
  let totalMiles: Double

  private struct CityRoute {
    let miles: Double
    let label: String
  }

  private static let routes = [
    CityRoute(miles: 22, label: "London to Windsor"),
    CityRoute(miles: 25, label: "London to St Albans"),
    CityRoute(miles: 42, label: "London to Southend"),
    CityRoute(miles: 54, label: "London to Brighton"),
    CityRoute(miles: 61, label: "London to Cambridge"),
    CityRoute(miles: 62, label: "London to Oxford"),
    CityRoute(miles: 101, label: "London to Birmingham"),
    CityRoute(miles: 118, label: "London to Bristol"),
    CityRoute(miles: 200, label: "London to Manchester"),
    CityRoute(miles: 214, label: "London to Paris"),
    CityRoute(miles: 402, label: "London to Edinburgh"),
    CityRoute(miles: 579, label: "London to Berlin"),
    CityRoute(miles: 890, label: "London to the Colosseum"),
    CityRoute(miles: 1_550, label: "London to Istanbul"),
    CityRoute(miles: 2_180, label: "London to the Pyramids"),
    CityRoute(miles: 3_400, label: "London to Dubai"),
    CityRoute(miles: 3_460, label: "London to New York"),
    CityRoute(miles: 4_480, label: "London to Mumbai"),
    CityRoute(miles: 5_450, label: "London to Los Angeles"),
    CityRoute(miles: 5_960, label: "London to Tokyo"),
    CityRoute(miles: 6_760, label: "London to Singapore"),
    CityRoute(miles: 10_560, label: "London to Sydney"),
  ]

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "signpost.right.fill")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(OkkleColor.brandDark)
        .frame(width: 28, height: 28)
        .background(OkkleColor.brand.opacity(0.12), in: Circle())

      VStack(alignment: .leading, spacing: 5) {
        Text("City distance")
          .font(.system(size: 13, weight: .heavy))
          .foregroundStyle(OkkleColor.ink)

        Text(routeSummary)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)

        if let nextRoute {
          HStack(spacing: 8) {
            NativeThinProgressBar(progress: nextProgress, tint: OkkleColor.brandDark)
            Text("\(miles(max(0, nextRoute.miles - totalMiles))) left")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(OkkleColor.muted)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
        }
      }
    }
    .padding(12)
    .background(Color(uiColor: .secondarySystemBackground).opacity(0.66), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var previousRoute: CityRoute? {
    Self.routes.last { totalMiles >= $0.miles }
  }

  private var nextRoute: CityRoute? {
    Self.routes.first { totalMiles < $0.miles }
  }

  private var routeSummary: String {
    guard totalMiles > 0 else {
      return "Log miles to start building a world map."
    }

    if let previousRoute {
      if let nextRoute {
        return "Roughly \(previousRoute.label). Next: \(nextRoute.label)."
      }
      let longest = previousRoute
      let repeats = max(1, Int((totalMiles / longest.miles).rounded(.down)))
      return "Roughly \(repeats)x \(longest.label)."
    }

    guard let nextRoute else {
      return "Keep tracking to extend your city map."
    }
    return "On the way to \(nextRoute.label)."
  }

  private var nextProgress: Double {
    guard let nextRoute else { return 1 }
    return min(1, max(0, totalMiles / nextRoute.miles))
  }
}

struct NativeAchievementsView: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var showsMedalRoom = false

  private var progress: NativeProgressTotals {
    NativeProgressSummary.yearToDate(store: store)
  }

  private var achievements: [NativeMedalAchievement] {
    NativeMedalEngine.achievements(store: store, period: .allTime)
  }

  var body: some View {
    NativeScreen(
      title: "Achievements",
      collapsedTitle: "Achievements",
      subtitle: "Mileage milestones and medal progress."
    ) {
      VStack(alignment: .leading, spacing: 18) {
        NativeMileageLoggedPanel(totals: progress)
          .padding(16)
          .okkleCard(cornerRadius: 26)

        NativeMedalPreviewPanel(achievements: achievements, progressPeriod: .allTime) {
          showsMedalRoom = true
        }
        .okkleCard(cornerRadius: 26)
      }
    }
    .fullScreenCover(isPresented: $showsMedalRoom) {
      NativeMedalsView(initialPeriod: .allTime)
        .environmentObject(store)
    }
  }
}

struct NativeMedalsView: View {
  @EnvironmentObject private var store: OkkleStore
  @Environment(\.dismiss) private var dismiss
  var showsDoneButton = true
  @State private var selected: NativeMedalAchievement?
  private let progressPeriod: NativeProgressPeriod

  init(initialPeriod: NativeProgressPeriod = .allTime, showsDoneButton: Bool = true) {
    self.showsDoneButton = showsDoneButton
    self.progressPeriod = initialPeriod
  }

  private var achievements: [NativeMedalAchievement] {
    NativeMedalEngine.achievements(store: store, period: progressPeriod)
  }

  private var unlockedAchievements: [NativeMedalAchievement] {
    achievements.filter(\.unlocked)
  }

  private var inProgressAchievements: [NativeMedalAchievement] {
    achievements
      .filter { !$0.unlocked && $0.progress > 0 }
      .sorted { $0.progress > $1.progress }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          NativeMedalGridSection(
            title: "Unlocked",
            emptyMessage: "No medals unlocked \(progressPeriod.medalScopeLabel) yet.",
            achievements: unlockedAchievements,
            selected: $selected
          )

          NativeMedalGridSection(
            title: "In progress",
            emptyMessage: "No medals are in progress \(progressPeriod.medalScopeLabel) yet.",
            achievements: inProgressAchievements,
            selected: $selected
          )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
      }
      .background { NativeBackground() }
      .navigationTitle("All medals")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if showsDoneButton {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
              .font(.system(size: 16, weight: .semibold))
          }
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
  let progressPeriod: NativeProgressPeriod

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Medal room")
        .font(.system(size: 24, weight: .heavy, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
      Text("Unlocked and in progress \(progressPeriod.medalScopeLabel)")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(OkkleColor.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
      .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
  }
}

private struct NativeMedalGridSection: View {
  let title: String
  let emptyMessage: String
  let achievements: [NativeMedalAchievement]
  @Binding var selected: NativeMedalAchievement?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(size: 21, weight: .heavy, design: .rounded))
        .foregroundStyle(OkkleColor.ink)

      if achievements.isEmpty {
        Text(emptyMessage)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(OkkleColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      } else {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
          ForEach(achievements) { achievement in
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
            .font(.system(size: 13, weight: .heavy))
          Spacer()
          Text(progressText)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(OkkleColor.muted)
        }
        NativeThinProgressBar(progress: achievement.progress, tint: OkkleColor.muted.opacity(0.78))
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

private struct NativeThinProgressBar: View {
  let progress: Double
  let tint: Color

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color(uiColor: .systemGray5))
        Capsule()
          .fill(tint)
          .frame(width: proxy.size.width * min(1, max(0, progress)))
      }
    }
    .frame(height: 5)
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
