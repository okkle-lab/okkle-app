import SwiftUI

struct NativeMedalPreviewCard: View {
  let achievements: [NativeMedalAchievement]
  var mileageBandMiles: Double
  var recordsLogged: Int
  var tripsTracked: Int
  var cityDistanceMiles: Double
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
      .filter { !$0.unlocked && $0.progress > 0 }
      .sorted { $0.progress > $1.progress }
      .prefix(2)
      .map { $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(spacing: 16) {
        NativeProgressMetricRow(
          title: "First 10K mileage band",
          value: "\(Int(mileageBandMiles.rounded()).formatted()) / 10,000 mi",
          progress: mileageBandMiles / 10_000
        )
        NativeProgressMetricRow(
          title: "Records logged",
          value: "\(recordsLogged.formatted()) \(recordsLogged == 1 ? "entry" : "entries")",
          progress: Double(recordsLogged) / 25
        )
        NativeProgressMetricRow(
          title: "Trips tracked",
          value: "\(tripsTracked.formatted()) \(tripsTracked == 1 ? "trip" : "trips")",
          progress: Double(tripsTracked) / 20
        )
      }

      NativeCityDistanceDetail(totalMiles: cityDistanceMiles)

      Divider()

      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Medals")
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
          Text("\(unlocked.count) of \(achievements.count) unlocked")
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

      HStack(alignment: .top, spacing: 14) {
        ForEach(featured) { achievement in
          VStack(spacing: 7) {
            NativeMedalIcon(achievement: achievement, size: 56, rendering: .compact)
            Text(achievement.label)
              .font(.system(size: 11, weight: .heavy))
              .foregroundStyle(achievement.unlocked ? OkkleColor.ink : OkkleColor.muted)
              .multilineTextAlignment(.center)
              .lineLimit(2)
              .minimumScaleFactor(0.74)
              .frame(height: 32, alignment: .top)
          }
          .frame(maxWidth: .infinity)
        }
      }

      if !nextUp.isEmpty {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(nextUp) { achievement in
            NativeMedalProgressRow(achievement: achievement)
          }
        }
      }
    }
    .padding(16)
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
    CityRoute(miles: 54, label: "London to Brighton"),
    CityRoute(miles: 118, label: "London to Bristol"),
    CityRoute(miles: 200, label: "London to Manchester"),
    CityRoute(miles: 286, label: "Bristol to Newcastle"),
    CityRoute(miles: 402, label: "London to Edinburgh"),
    CityRoute(miles: 548, label: "Cardiff to Inverness"),
    CityRoute(miles: 874, label: "Land's End to John o'Groats"),
  ]

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "signpost.right.fill")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(OkkleColor.brandDark)
        .frame(width: 28, height: 28)
        .background(OkkleColor.brand.opacity(0.12), in: Circle())

      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline) {
          Text("City distance")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(OkkleColor.ink)
          Spacer(minLength: 12)
          Text(miles(totalMiles))
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.brandDark)
            .lineLimit(1)
        }

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
      return "Log miles to start building a city-to-city map."
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

struct NativeMedalsView: View {
  @EnvironmentObject private var store: OkkleStore
  @Environment(\.dismiss) private var dismiss
  var showsDoneButton = true
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
  let earned: Int
  let total: Int
  let completion: Double

  var body: some View {
    medalContent
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(OkkleColor.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
      .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
  }

  private var medalContent: some View {
      VStack(spacing: 14) {
        HStack(spacing: 18) {
          ZStack {
            Circle()
              .stroke(OkkleColor.muted.opacity(0.22), lineWidth: 9)
            Circle()
              .trim(from: 0, to: max(completion, 0.001))
              .stroke(
                AngularGradient(colors: [OkkleColor.brand, .green, .yellow, .purple, OkkleColor.brand], center: .center),
                style: StrokeStyle(lineWidth: 9, lineCap: .round)
              )
              .rotationEffect(.degrees(-90))
            Text("\(earned)")
              .font(.system(size: 30, weight: .heavy, design: .rounded))
          }
          .frame(width: 82, height: 82)

          VStack(alignment: .leading, spacing: 4) {
            Text("Medal room")
              .font(.system(size: 24, weight: .heavy, design: .rounded))
              .foregroundStyle(OkkleColor.ink)
            Text("\(earned) of \(total) unlocked")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
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
