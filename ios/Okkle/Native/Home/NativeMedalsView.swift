import SwiftUI

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
  var coins: Int? = nil

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

        if let coins {
          Divider()
          HStack(spacing: 12) {
            Image(systemName: "bitcoinsign.circle.fill")
              .font(.system(size: 20, weight: .bold))
              .foregroundStyle(OkkleColor.amber)
            VStack(alignment: .leading, spacing: 1) {
              Text("\(coins) Coins to spend")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(OkkleColor.ink)
              Text("Earned here · spend on your club crest")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OkkleColor.muted)
            }
            Spacer()
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
  var club: NativeClubIdentity? = nil
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
            if let club {
              NativeKitTile(
                kit: club.kit, color: club.color, secondary: club.secondaryColor,
                crestShape: club.crestShape, trimColor: club.trimColor,
                trimWidth: club.trimWidthRatio, size: 52, emblem: club.emblem
              )
            } else {
              NativeDivisionCrest(division: snapshot.division, size: 52)
            }
            VStack(alignment: .leading, spacing: 6) {
              if snapshot.matchweek == 0 {
                Text("Kicking off")
                  .font(.system(size: 20, weight: .heavy))
                  .foregroundStyle(OkkleColor.ink)
                Text("\(Int(snapshot.winBar.rounded())) miles this week wins it")
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(OkkleColor.muted)
              } else {
                Text("£\(Int(snapshot.bankedThisSeason.rounded())) banked")
                  .font(.system(size: 21, weight: .heavy, design: .rounded))
                  .foregroundStyle(OkkleColor.ink)
                HStack(spacing: 8) {
                  NativeFormGuide(form: snapshot.yourRow.form, size: 9)
                  Text("Matchweek \(snapshot.matchweek)/\(snapshot.totalWeeks)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OkkleColor.muted)
                }
              }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(OkkleColor.muted)
          }

          if let fixture, fixture.matchweek > 0 {
            Divider().padding(.vertical, 13)
            let won = fixture.pointsThisWeek == 3
            let drawing = fixture.pointsThisWeek == 1
            let bankedWeek = Int(fixture.yourBanked.rounded())
            let targetWeek = Int(fixture.weeklyTarget.rounded())
            let toWin = max(1, targetWeek - bankedWeek)
            VStack(alignment: .leading, spacing: 7) {
              HStack(spacing: 8) {
                Image(systemName: won ? "checkmark.seal.fill" : "bolt.fill")
                  .font(.system(size: 16, weight: .bold))
                  .foregroundStyle(won ? OkkleColor.brand : snapshot.division.accent)
                Text(won ? "This week won" : (drawing ? "On for a draw" : "Win this week"))
                  .font(.system(size: 16, weight: .heavy))
                  .foregroundStyle(won ? OkkleColor.brand : OkkleColor.ink)
                Spacer()
                Text(won ? "+3 pts" : "\(toWin) mi to go")
                  .font(.system(size: 15, weight: .heavy))
                  .foregroundStyle(won ? OkkleColor.brand : snapshot.division.accent)
              }
              ProgressView(value: fixture.progressToTarget)
                .tint(won ? OkkleColor.brand : snapshot.division.accent)
                .scaleEffect(x: 1, y: 1.4, anchor: .center)
              Text("\(bankedWeek) of \(targetWeek) mi · vs \(fixture.opponent)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OkkleColor.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
          }

          if !medals.isEmpty {
            Divider().padding(.vertical, 13)
            HStack(spacing: 10) {
              Image(systemName: "rosette")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(snapshot.division.accent)
              Text("\(earnedMedals) of \(medals.count) medals")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(OkkleColor.ink)
              Spacer()
              if let nextMedal {
                Text("Next: \(nextMedal.label)")
                  .font(.system(size: 14, weight: .semibold))
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

/// One consistent league card: a coloured banner header (icon · TITLE · trailing)
/// over a clean body, with an accent border and glow. Used everywhere so every
/// card shares the same shape, band height and styling.
struct NativeLeagueSection<Content: View>: View {
  let title: String
  var icon: String? = nil
  var trailing: String? = nil
  let band: LinearGradient
  var accent: Color = OkkleColor.muted
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        if let icon {
          Image(systemName: icon).font(.system(size: 13, weight: .bold))
        }
        Text(title)
          .font(.system(size: 13, weight: .heavy))
          .tracking(0.5)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
        Spacer(minLength: 8)
        if let trailing {
          Text(trailing)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(.white.opacity(0.9))
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(band)
      .fixedSize(horizontal: false, vertical: true)

      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(OkkleColor.card)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(accent.opacity(0.25), lineWidth: 1))
    .shadow(color: accent.opacity(0.28), radius: 16, y: 8)
  }
}

/// This week's fixture — you vs a past-self, scored live in real tax saved,
/// with the gaffer's team-talk underneath. The heartbeat of the league.
struct NativeMatchdayCard: View {
  let fixture: NativeFixture
  let division: NativeDivision
  var club: NativeClubIdentity? = nil

  var body: some View {
    NativeLeagueSection(
      title: "\(division.name.uppercased()) · MATCHWEEK \(fixture.matchweek) OF \(fixture.totalWeeks)",
      trailing: stateLabel,
      band: division.gradient,
      accent: division.accent
    ) {
      VStack(spacing: 11) {
        if fixture.stakes != .none {
          banner
        }
        HStack(alignment: .top, spacing: 8) {
          youTeam
          VStack(spacing: 2) {
            Text("\(fixture.yourGoals)–\(fixture.oppGoals)")
              .font(.system(size: 28, weight: .heavy, design: .rounded))
              .foregroundStyle(OkkleColor.ink)
              .frame(height: 42)          // match the crest height so the score
                                          // sits centred beside the badges
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
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
    }
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
    .padding(10)
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
      case 3: return "Hit your \(Int(fixture.weeklyTarget.rounded()))-mile target — 3 points banked."
      case 1: return "Reached the halfway mark — 1 point earned."
      default: return "Missed the target this week — no points."
      }
    }
    switch fixture.pointsThisWeek {
    case 3: return "Target smashed — the 3 points are yours. Keep logging."
    case 1: return "In the draw zone (1 pt). \(toWin) mi more this week wins it (3 pts)."
    default: return "\(toDraw) mi earns a draw (1 pt), \(toWin) mi the win (3 pts)."
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
    .background(fill.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var youTeam: some View {
    VStack(spacing: 7) {
      ZStack(alignment: .top) {
        NativeKitTile(
          kit: club?.kit ?? .solid,
          color: club?.color ?? OkkleColor.brand,
          secondary: club?.secondaryColor,
          crestShape: club?.crestShape ?? .rounded,
          trimColor: club?.trimColor ?? .white.opacity(0.30),
          trimWidth: club?.trimWidthRatio ?? 0.02,
          size: 42,
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
      Text("\(Int(fixture.yourBanked.rounded())) mi")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
    .frame(maxWidth: .infinity)
  }

  private func team(name: String, symbol: String, banked: Double, accent: Color, filled: Bool) -> some View {
    VStack(spacing: 7) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(accent.opacity(filled ? 0.16 : 0.10))
        .frame(width: 42, height: 42)
        .overlay(
          Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(accent)
        )
      Text(name)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text("\(Int(banked.rounded())) mi")
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
    .padding(10)
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

/// A classic two-handled cup silhouette — the shared shape of UK football
/// trophies (the FA Cup, the league trophy, the European cup all share it).
struct NativeCupShape: Shape {
  func path(in r: CGRect) -> Path {
    let w = r.width, h = r.height
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + w * x, y: r.minY + h * y) }
    var path = Path()
    path.move(to: p(0.22, 0.06))
    path.addLine(to: p(0.78, 0.06))                                   // rim
    path.addQuadCurve(to: p(0.58, 0.52), control: p(0.75, 0.42))      // right bowl
    path.addLine(to: p(0.56, 0.64))
    path.addLine(to: p(0.62, 0.70))                                   // stem → base
    path.addLine(to: p(0.76, 0.92))                                   // base right
    path.addLine(to: p(0.24, 0.92))                                   // base bottom
    path.addLine(to: p(0.38, 0.70))                                   // base left
    path.addLine(to: p(0.44, 0.64))
    path.addLine(to: p(0.42, 0.52))                                   // stem left
    path.addQuadCurve(to: p(0.22, 0.06), control: p(0.25, 0.42))      // left bowl
    path.closeSubpath()
    return path
  }
}

/// The two open handles of the cup.
struct NativeCupHandles: Shape {
  func path(in r: CGRect) -> Path {
    let w = r.width, h = r.height
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + w * x, y: r.minY + h * y) }
    var path = Path()
    path.move(to: p(0.24, 0.10))
    path.addQuadCurve(to: p(0.26, 0.38), control: p(0.02, 0.22))      // left handle
    path.move(to: p(0.76, 0.10))
    path.addQuadCurve(to: p(0.74, 0.38), control: p(0.98, 0.22))      // right handle
    return path
  }
}

/// A trophy — gold when earned, ghosted steel when still to be won.
struct NativeTrophyView: View {
  var earned: Bool
  var size: CGFloat = 52

  private var fill: LinearGradient {
    earned
      ? LinearGradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.42), Color(red: 0.80, green: 0.58, blue: 0.12)], startPoint: .top, endPoint: .bottom)
      : LinearGradient(colors: [Color(red: 0.80, green: 0.81, blue: 0.84), Color(red: 0.50, green: 0.51, blue: 0.55)], startPoint: .top, endPoint: .bottom)
  }
  private var handle: Color { earned ? Color(red: 0.93, green: 0.76, blue: 0.22) : Color(red: 0.62, green: 0.63, blue: 0.66) }

  var body: some View {
    ZStack {
      NativeCupHandles()
        .stroke(handle, style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
      NativeCupShape().fill(fill)
      NativeCupShape()
        .fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .topLeading, endPoint: .center))
        .blendMode(.plusLighter)
    }
    .frame(width: size, height: size)
    .opacity(earned ? 1 : 0.6)
  }
}

/// The trophy cabinet — every division won, kept forever. Styled in deep
/// Champions-League blue: the whole card is the prestige colour.
struct NativeHonoursCard: View {
  let honours: [NativeHonour]

  private static let band = LinearGradient(
    colors: [Color(red: 0.06, green: 0.10, blue: 0.40), Color(red: 0.20, green: 0.30, blue: 0.72)],
    startPoint: .leading, endPoint: .trailing)
  private static let body = LinearGradient(
    colors: [Color(red: 0.10, green: 0.16, blue: 0.52), Color(red: 0.05, green: 0.08, blue: 0.32)],
    startPoint: .top, endPoint: .bottom)
  private static let glow = Color(red: 0.20, green: 0.30, blue: 0.72)

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "trophy.fill").font(.system(size: 13, weight: .bold))
        Text("HONOURS").font(.system(size: 13, weight: .heavy)).tracking(0.5)
        Spacer()
        if !honours.isEmpty {
          Text("\(honours.count)").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white.opacity(0.9))
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(NativeHonoursCard.band)

      content
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeHonoursCard.body)
    }
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    .shadow(color: NativeHonoursCard.glow.opacity(0.45), radius: 16, y: 8)
  }

  // The cups you can win — one per promotable division.
  private static let winnable: [NativeDivision] = [.nationalLeague, .leagueTwo, .leagueOne, .championship]

  @ViewBuilder
  private var content: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 6) {
        ForEach(NativeHonoursCard.winnable, id: \.self) { division in
          let won = honours.contains { $0.divisionRaw == division.rawValue }
          VStack(spacing: 8) {
            NativeTrophyView(earned: won, size: 52)
            Text(division.shortName)
              .font(.system(size: 11, weight: .heavy))
              .foregroundStyle(.white.opacity(won ? 0.95 : 0.5))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
          }
          .frame(maxWidth: .infinity)
        }
      }
      Text(honours.isEmpty
           ? "Win your division to lift its cup and fill the cabinet."
           : "\(honours.count) trophy\(honours.count == 1 ? "" : "s") in the cabinet — win more to complete the set.")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
  @State private var confirmPurchase = false

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
      .confirmationDialog("Unlock new items?", isPresented: $confirmPurchase, titleVisibility: .visible) {
        Button("Unlock for \(lockedCost) Coins") { commitPurchaseAndSave() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("You'll spend \(lockedCost) Coins on this badge, leaving \(balance - lockedCost). This can't be undone.")
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
                      trimColor: NativeClubIdentity.trimColours[min(trimIndex, NativeClubIdentity.trimColours.count - 1)],
                      trimWidth: trimIndex == 0 ? 0.02 : 0.06,
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
              .overlay(lockBadge(owned, cost: shape.coins))
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
              .overlay(lockBadge(owned, cost: NativeClubIdentity.colourCost))
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
              .overlay(lockBadge(owned, cost: kit.coins))
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
            .overlay(lockBadge(owned, cost: NativeClubIdentity.crestCoins(index)))
            .opacity(owned ? 1 : 0.5)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var trimGrid: some View {
    LazyVGrid(columns: columns, spacing: 14) {
      ForEach(Array(NativeClubIdentity.trimColours.enumerated()), id: \.offset) { index, ring in
        let free = index < NativeClubIdentity.freeTrims
        let id = NativeClubIdentity.trimId(index)
        let owned = NativeWallet.isUnlocked(id, free: free)
        let selected = trimIndex == index
        Button { select(trimIndex: index, id: id, owned: owned) } label: {
          ZStack {
            Circle()
              .fill(NativeClubIdentity.palette[colorIndex])
              .overlay(Circle().strokeBorder(ring, lineWidth: index == 0 ? 1.5 : 4.5))
            if index == 0 {
              Image(systemName: "slash.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            }
          }
          .frame(width: 46, height: 46)
          .overlay(Circle().inset(by: 6).strokeBorder(OkkleColor.ink, lineWidth: selected ? 2.5 : 0))
          .overlay(lockBadge(owned, cost: NativeClubIdentity.trimCost))
          .opacity(owned ? 1 : 0.5)
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
  private func lockBadge(_ owned: Bool, cost: Int = 0) -> some View {
    if !owned {
      HStack(spacing: 2) {
        Image(systemName: "bitcoinsign.circle.fill").font(.system(size: 9, weight: .bold))
        Text("\(cost)").font(.system(size: 10, weight: .heavy, design: .rounded))
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(Capsule().fill(OkkleColor.amber))
      .offset(y: 16)
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
    if locked.isEmpty { persistAndClose(); return }
    guard NativeWallet.balance(store: store) >= lockedCost else { purchaseError = true; return }
    confirmPurchase = true   // ask before spending Coins
  }

  private func commitPurchaseAndSave() {
    lockedIds().forEach { _ = NativeWallet.purchase($0, store: store) }
    balance = NativeWallet.balance(store: store)
    persistAndClose()
  }

  private func persistAndClose() {
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
  private func select(trimIndex index: Int, id: String, owned: Bool) { trimIndex = index }
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
      // Deep, near-black base with only a whisper of the division hue — like
      // Apple Sports' dark canvas, so the light cards read clearly on top.
      Color.black
      division.gradientBottom.opacity(0.22)
      LinearGradient(
        colors: [division.gradientBottom.opacity(0.16), .clear, .black.opacity(0.35)],
        startPoint: .top,
        endPoint: .bottom
      )
      // A soft floodlight glow at the very top only.
      RadialGradient(
        colors: [division.gradientTop.opacity(0.32), .clear],
        center: .init(x: 0.5, y: -0.02),
        startRadius: 0,
        endRadius: 300
      )
      .blendMode(.screen)
    }
    .ignoresSafeArea()
  }
}

/// A plain-English explainer for how the solo league works.
struct NativeLeagueRulesView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          rule("figure.run", "You vs rival clubs",
               "Each week you race three AI clubs — Riverside Rovers, Parkside Athletic and Canal Street FC. Out-drive them over the season to climb the table.")
          rule("map.fill", "Hit the weekly miles",
               "Every division has one fixed weekly mileage target — the same honest distance for everyone in that tier. Log it to win the week and take 3 points; reach halfway for a draw and 1 point.")
          rule("list.number", "Climb the table",
               "Points stack over a four-week season. Finish 1st to go up automatically, 2nd–3rd play a one-week play-off final, and bottom is relegated.")
          rule("chart.line.uptrend.xyaxis", "Your division is your status",
               "Targets rise tier by tier — 50 mi/week in the National League up to 480 in the Premier League. Where you settle reflects how much you really drive: only dedicated long-range drivers hold the top, and the targets are always within a full week's shifts.")
          rule("moon.zzz.fill", "Rest days don't count",
               "Weeks you don't ride are simply skipped — the league never counts a day off against you.")
          rule("bitcoinsign.circle.fill", "Coins are cosmetic",
               "Medals and especially promotions earn Coins to spend on your club crest. They're cosmetic only and never help you win a match.")
        }
        .padding(20)
      }
      .background { NativeBackground() }
      .navigationTitle("How the league works")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") { dismiss() }.font(.system(size: 16, weight: .bold))
        }
      }
    }
  }

  private func rule(_ symbol: String, _ title: String, _ body: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: symbol)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(OkkleColor.brand)
        .frame(width: 30)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .heavy))
          .foregroundStyle(OkkleColor.ink)
        Text(body)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// League screen: a live season table (you vs your past selves, with
/// promotion/relegation zones) and a Medals tab that drills into medals.
struct NativeLeagueView: View {
  @EnvironmentObject private var store: OkkleStore
  @Environment(\.dismiss) private var dismiss
  var showsDoneButton = true
  private enum Segment: Hashable { case table, medals }
  @State private var segment: Segment = .table
  @State private var ceremony: NativeDivision?
  @State private var editingClub = false
  @State private var showingRules = false
  // Bumped when the club editor closes, to force the paging TabView to rebuild
  // and re-read the (just-saved) club crest live, without leaving the screen.
  @State private var clubRev = 0

  var body: some View {
    let snapshot = NativeSeasonEngine.snapshot(store: store)
    NavigationStack {
      VStack(spacing: 16) {
        Picker("", selection: $segment.animation(.easeInOut(duration: 0.2))) {
          Text("Table").tag(Segment.table)
          Text("Medals").tag(Segment.medals)
        }
        .pickerStyle(.segmented)
        .colorScheme(.dark)
        .padding(.horizontal, 20)

        // Swipe left/right to move between Table and Medals.
        TabView(selection: $segment) {
          leaguePage { tableTab(snapshot) }.tag(Segment.table)
          leaguePage { medalsTab(current: snapshot.division) }.tag(Segment.medals)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .id(clubRev)

        // Carousel dots — a clear cue that you can swipe between the two.
        HStack(spacing: 8) {
          ForEach([Segment.table, Segment.medals], id: \.self) { page in
            Capsule()
              .fill(segment == page ? Color.white : Color.white.opacity(0.35))
              .frame(width: segment == page ? 18 : 7, height: 7)
              .animation(.easeInOut(duration: 0.2), value: segment)
          }
        }
        .padding(.bottom, 6)
      }
      .padding(.top, 20)
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
        ToolbarItem(placement: .navigationBarLeading) {
          Button { showingRules = true } label: {
            Image(systemName: "questionmark.circle")
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(.white)
          }
          .accessibilityLabel("How the league works")
        }
        if showsDoneButton {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button("Done") { dismiss() }
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(.white)
          }
        }
      }
    }
    .sheet(isPresented: $editingClub, onDismiss: { clubRev += 1 }) {
      NativeClubEditorView().environmentObject(store)
    }
    .sheet(isPresented: $showingRules) {
      NativeLeagueRulesView()
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
      // First visit: open the rules so a new driver understands the league.
      let seenKey = "uk.okkle.native.league.rulesSeen.v1"
      if snapshot.ceremonyTo == nil, !UserDefaults.standard.bool(forKey: seenKey) {
        UserDefaults.standard.set(true, forKey: seenKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showingRules = true }
      }
      guard let promoted = snapshot.ceremonyTo else { return }
      NativeSeasonEngine.clearCeremony(store: store)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { ceremony = promoted }
      }
    }
  }

  // MARK: Table tab

  /// One swipe page — content pinned to the top, padded so card glows aren't
  /// clipped by the paging view's edges.
  private func leaguePage<V: View>(@ViewBuilder _ content: () -> V) -> some View {
    VStack(spacing: 12) {
      content()
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.horizontal, 20)
    .padding(.top, 6)
  }

  private func tableTab(_ snapshot: NativeSeasonSnapshot) -> some View {
    VStack(spacing: 16) {
      NativeMatchdayCard(
        fixture: NativeSeasonEngine.fixture(store: store),
        division: snapshot.division,
        club: NativeSeasonEngine.clubIdentity(store: store)
      )
      leagueTableCard(snapshot)
    }
  }

  /// The division identity and the standings, combined into one card.
  private func leagueTableCard(_ s: NativeSeasonSnapshot) -> some View {
    NativeLeagueSection(
      title: s.division.name.uppercased(),
      trailing: "TABLE",
      band: s.division.gradient,
      accent: s.division.accent
    ) {
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          NativeDivisionCrest(division: s.division, size: 36)
          VStack(alignment: .leading, spacing: 2) {
            Text("£\(Int(s.bankedThisSeason.rounded())) banked · MW \(min(s.matchweek + 1, s.totalWeeks)) of \(s.totalWeeks)")
              .font(.system(size: 13, weight: .heavy))
              .foregroundStyle(OkkleColor.ink)
            Text("\(Int(s.winBar.rounded())) mi/week is a win")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
          }
          Spacer()
          if !s.yourRow.form.isEmpty { NativeFormGuide(form: s.yourRow.form, size: 8) }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 10)

        Divider()
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
        .padding(.top, 9)
        .padding(.bottom, 7)
        Divider()
        ForEach(Array(s.rows.enumerated()), id: \.element.id) { index, row in
          standingRow(row: row, index: index, total: s.rows.count, division: s.division)
          if index != s.rows.count - 1 {
            Divider().padding(.leading, 40)
          }
        }
        zonesLegend(s.division)
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
      }
    }
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
    .padding(.vertical, 9)
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
      NativeMedalSummaryCard(earned: earned, total: all.count, completion: all.isEmpty ? 0 : Double(earned) / Double(all.count), coins: NativeWallet.balance(store: store))
      ladder(current: current)
    }
  }


  private func ladder(current: NativeDivision) -> some View {
    let rows = NativeDivision.allCases.reversed()
    return NativeLeagueSection(
      title: "THE PYRAMID",
      icon: "trophy.fill",
      trailing: current.name.uppercased(),
      band: current.gradient,
      accent: current.accent
    ) {
      VStack(spacing: 0) {
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
    }
  }

  private func row(_ division: NativeDivision, current: NativeDivision) -> some View {
    HStack(spacing: 14) {
      NativeDivisionCrest(division: division, size: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(division.name)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(OkkleColor.ink)
        Text(division == .nationalLeague ? "Starting tier" : "\(division.mileTarget) mi/week to hold")
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
