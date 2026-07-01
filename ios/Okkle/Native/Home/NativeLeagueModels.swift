import SwiftUI

struct NativeLeagueState: Codable {
  var divisionRaw: Int
  var seasonStart: Date
  var ceremonyToRaw: Int?
}

/// A piece of silverware for the trophy cabinet — a division won, kept forever.
struct NativeHonour: Codable, Identifiable {
  enum Kind: String, Codable { case champions, playoff }
  let seasonIndex: Int
  let divisionRaw: Int
  let kind: Kind
  let date: Date

  var id: String { "\(seasonIndex)-\(divisionRaw)-\(kind.rawValue)" }
  var division: NativeDivision { NativeDivision(rawValue: divisionRaw) ?? .nationalLeague }
  var title: String {
    kind == .champions ? "\(division.name) champions" : "Promoted from \(division.name)"
  }
  var subtitle: String {
    kind == .champions ? "Won the division outright" : "Won the play-off final"
  }
}

/// The driver's club — name, colour and crest emblem, all theirs to shape.
/// Kit patterns painted over the club colour — solid through to a diagonal sash.
enum NativeKit: Int, CaseIterable {
  case solid, gradient, stripes, hoops, sash, halves, quarters, chevron, pinstripe, checks, band, cross, diagonal, spots

  var name: String {
    switch self {
    case .solid: return "Solid"
    case .gradient: return "Fade"
    case .stripes: return "Stripes"
    case .hoops: return "Hoops"
    case .sash: return "Sash"
    case .halves: return "Halves"
    case .quarters: return "Quarters"
    case .chevron: return "Chevron"
    case .pinstripe: return "Pinstripe"
    case .checks: return "Checks"
    case .band: return "Band"
    case .cross: return "Cross"
    case .diagonal: return "Diagonal"
    case .spots: return "Spots"
    }
  }

  /// Solid + Fade free; price climbs as you go down the list.
  var coins: Int {
    rawValue < NativeClubIdentity.freeKits ? 0 : 150 + (rawValue - NativeClubIdentity.freeKits) * 30
  }
}

/// The outline of the badge — a real football-crest silhouette, not just a square.
enum NativeCrestShape: Int, CaseIterable {
  case rounded, circle, shield, hexagon, diamond, oval, octagon, pennant, spade, tudor, banner, pentagon, heater, square, star

  /// Display + difficulty order: easiest (free) at the top, hardest at the
  /// bottom. Pennant + oval retired (kept in the enum so saved badges keep
  /// their raw values). Cost climbs with position in this list.
  static let pickable: [NativeCrestShape] = [
    .rounded, .circle, .square, .hexagon, .diamond, .heater, .pentagon, .octagon, .spade, .tudor, .shield, .banner
  ]
  private static let tiers = [0, 0, 120, 160, 200, 250, 300, 350, 400, 450, 550, 800]

  /// Coins to unlock — derived from position, so it rises down the list.
  var coins: Int {
    guard let i = NativeCrestShape.pickable.firstIndex(of: self) else { return 800 }
    return i < NativeCrestShape.tiers.count ? NativeCrestShape.tiers[i] : 800
  }

  var name: String {
    switch self {
    case .rounded: return "Tile"
    case .circle: return "Roundel"
    case .shield: return "Shield"
    case .hexagon: return "Hex"
    case .diamond: return "Diamond"
    case .oval: return "Oval"
    case .octagon: return "Octagon"
    case .pennant: return "Pennant"
    case .spade: return "Spade"
    case .tudor: return "Tudor"
    case .banner: return "Banner"
    case .pentagon: return "Pentagon"
    case .heater: return "Heater"
    case .square: return "Square"
    case .star: return "Star"
    }
  }

  func anyShape() -> AnyShape {
    switch self {
    case .rounded: return AnyShape(NativeRoundedRel())
    case .circle: return AnyShape(Circle())
    case .shield: return AnyShape(NativeShieldShape())
    case .hexagon: return AnyShape(NativeHexagonShape())
    case .diamond: return AnyShape(NativeDiamondShape())
    case .oval: return AnyShape(Ellipse())
    case .octagon: return AnyShape(NativeOctagonShape())
    case .pennant: return AnyShape(NativePennantShape())
    case .spade: return AnyShape(NativeSpadeShape())
    case .tudor: return AnyShape(NativeTudorShape())
    case .banner: return AnyShape(NativeBannerShieldShape())
    case .pentagon: return AnyShape(NativePentagonShape())
    case .heater: return AnyShape(NativeHeaterShape())
    case .square: return AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    case .star: return AnyShape(NativeStarShape())
    }
  }
}

struct NativeRoundedRel: Shape {
  func path(in r: CGRect) -> Path { RoundedRectangle(cornerRadius: r.width * 0.26, style: .continuous).path(in: r) }
}

struct NativeShieldShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.04))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.04))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.55))
    p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.86))
    p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.55), control: CGPoint(x: r.minX, y: r.minY + r.height * 0.86))
    p.closeSubpath()
    return p
  }
}

struct NativeHexagonShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let cx = r.midX, cy = r.midY, rad = min(r.width, r.height) / 2
    for i in 0..<6 {
      let a = (Double(i) * 60.0 - 90.0) * .pi / 180.0
      let pt = CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
      if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
  }
}

struct NativeDiamondShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.midX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
    p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX, y: r.midY))
    p.closeSubpath()
    return p
  }
}

struct NativeOctagonShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let cx = r.midX, cy = r.midY, rad = min(r.width, r.height) / 2
    for i in 0..<8 {
      let a = (Double(i) * 45.0 - 22.5) * .pi / 180.0
      let pt = CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
      if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
  }
}

/// A bunting pennant — flat top, straight sides into a point.
struct NativePennantShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.04))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.04))
    p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
    p.closeSubpath()
    return p
  }
}

/// A heraldic spade — a peaked top centre curving down to a point.
struct NativeSpadeShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let w = r.width, h = r.height
    p.move(to: CGPoint(x: r.midX, y: r.minY))
    p.addLine(to: CGPoint(x: r.minX + w * 0.92, y: r.minY + h * 0.28))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.5))
    p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.minY + h * 0.84))
    p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.5), control: CGPoint(x: r.minX, y: r.minY + h * 0.84))
    p.addLine(to: CGPoint(x: r.minX + w * 0.08, y: r.minY + h * 0.28))
    p.closeSubpath()
    return p
  }
}

/// A Tudor shield — rounded top corners curving down to a point.
struct NativeTudorShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let w = r.width, h = r.height
    p.move(to: CGPoint(x: r.minX, y: r.minY + h * 0.16))
    p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.16, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - w * 0.16, y: r.minY))
    p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.16), control: CGPoint(x: r.maxX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.55))
    p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.minY + h * 0.86))
    p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.55), control: CGPoint(x: r.minX, y: r.minY + h * 0.86))
    p.closeSubpath()
    return p
  }
}

/// A banner-top shield — a flat scroll ledge across the top, shield below.
struct NativeBannerShieldShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let w = r.width, h = r.height
    p.move(to: CGPoint(x: r.minX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.20))
    p.addLine(to: CGPoint(x: r.maxX - w * 0.07, y: r.minY + h * 0.20))
    p.addLine(to: CGPoint(x: r.maxX - w * 0.07, y: r.minY + h * 0.56))
    p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX - w * 0.07, y: r.minY + h * 0.86))
    p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.07, y: r.minY + h * 0.56), control: CGPoint(x: r.minX + w * 0.07, y: r.minY + h * 0.86))
    p.addLine(to: CGPoint(x: r.minX + w * 0.07, y: r.minY + h * 0.20))
    p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.20))
    p.closeSubpath()
    return p
  }
}

/// A point-up pentagon.
struct NativePentagonShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let cx = r.midX, cy = r.midY, rad = min(r.width, r.height) / 2
    for i in 0..<5 {
      let a = (Double(i) * 72.0 - 90.0) * .pi / 180.0
      let pt = CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
      if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
  }
}

/// A heater shield — flat top, straight sides angling to a point.
struct NativeHeaterShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.03))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.03))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.45))
    p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.45))
    p.closeSubpath()
    return p
  }
}

/// A five-point star.
struct NativeStarShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let cx = r.midX, cy = r.midY
    let outer = min(r.width, r.height) / 2
    let inner = outer * 0.42
    for i in 0..<10 {
      let rad = i.isMultiple(of: 2) ? outer : inner
      let a = (Double(i) * 36.0 - 90.0) * .pi / 180.0
      let pt = CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
      if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
  }
}

/// Gold stars above a crest — one per division title won, like a real badge.
struct NativeTitleStars: View {
  let count: Int
  var size: CGFloat = 11
  var body: some View {
    if count > 0 {
      HStack(spacing: 3) {
        ForEach(0..<min(count, 5), id: \.self) { _ in
          Image(systemName: "star.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.20))
        }
      }
    }
  }
}

struct NativeClubIdentity: Codable {
  var name: String
  var colorIndex: Int
  var emblem: String
  var kitIndex: Int? = nil
  var shapeIndex: Int? = nil
  var secondaryIndex: Int? = nil
  var trimIndex: Int? = nil

  // First `free*` of each are free; the rest are bought with Coins.
  static let palette: [Color] = [
    Color(red: 0.12, green: 0.55, blue: 0.95),  // blue (free)
    Color(red: 0.85, green: 0.23, blue: 0.24),  // red (free)
    Color(red: 0.12, green: 0.66, blue: 0.42),  // green (free)
    Color(red: 0.55, green: 0.27, blue: 0.68),  // purple
    Color(red: 0.95, green: 0.55, blue: 0.10),  // orange
    Color(red: 0.10, green: 0.20, blue: 0.45),  // navy
    Color(red: 0.85, green: 0.65, blue: 0.13),  // gold
    Color(red: 0.83, green: 0.24, blue: 0.55),  // pink
    Color(red: 0.10, green: 0.62, blue: 0.62),  // teal
    Color(red: 0.40, green: 0.42, blue: 0.46),  // slate
    Color(red: 0.55, green: 0.75, blue: 0.20),  // lime
    Color(red: 0.90, green: 0.36, blue: 0.30),  // coral
  ]
  static let emblems = ["shield.fill", "flame.fill", "bolt.fill", "hare.fill", "crown.fill", "flag.fill", "star.fill", "pawprint.fill", "anchor", "seal.fill", "hexagon.fill", "diamond.fill", "bird.fill", "tortoise.fill", "ant.fill", "fish.fill", "leaf.fill", "drop.fill", "cat.fill", "hammer.fill", "soccerball", "sailboat.fill", "building.columns.fill", "globe.europe.africa.fill", "dog.fill", "lizard.fill", "ladybug.fill", "car.fill", "bus.fill", "bicycle", "fuelpump.fill", "steeringwheel", "airplane", "gearshape.fill"]

  /// Badge edge colours: a "none" + metallics, then the full colour palette in
  /// the same order as the Colour section.
  static let trimColours: [Color] = [
    .white.opacity(0.30),                       // 0 None (subtle)
    .white,                                      // 1 White
    Color(red: 0.12, green: 0.12, blue: 0.14),   // 2 Black
    Color(red: 0.95, green: 0.78, blue: 0.25),   // 3 Gold
    Color(red: 0.80, green: 0.82, blue: 0.86),   // 4 Silver
    Color(red: 0.80, green: 0.52, blue: 0.27),   // 5 Bronze
    Color(red: 0.36, green: 0.38, blue: 0.42),   // 6 Graphite
    Color(red: 0.90, green: 0.62, blue: 0.58),   // 7 Rose
  ] + palette

  static let freeColours = 3
  static let freeCrests = 3
  static let freeKits = 2
  static let freeShapes = 2
  static let freeTrims = 2
  static let colourCost = 300
  static let crestCost = 250
  static let kitCost = 200
  static let shapeCost = 250
  static let trimCost = 200

  /// Crest price climbs as you go down the list (first `freeCrests` are free).
  static func crestCoins(_ index: Int) -> Int {
    index < freeCrests ? 0 : 150 + (index - freeCrests) * 15
  }

  static func colourId(_ index: Int) -> String { "colour-\(index)" }
  static func crestId(_ symbol: String) -> String { "crest-\(symbol)" }
  static func kitId(_ index: Int) -> String { "kit-\(index)" }
  static func shapeId(_ index: Int) -> String { "shape-\(index)" }
  static func trimId(_ index: Int) -> String { "trim-\(index)" }

  private static func paletteColor(_ index: Int) -> Color {
    palette[max(0, min(index, palette.count - 1))]
  }

  var color: Color { NativeClubIdentity.paletteColor(colorIndex) }
  var secondaryColor: Color? { secondaryIndex.map { NativeClubIdentity.paletteColor($0) } }
  var kit: NativeKit { NativeKit(rawValue: kitIndex ?? 0) ?? .solid }
  var crestShape: NativeCrestShape { NativeCrestShape(rawValue: shapeIndex ?? 0) ?? .rounded }
  var trimColor: Color {
    let i = trimIndex ?? 0
    return NativeClubIdentity.trimColours[max(0, min(i, NativeClubIdentity.trimColours.count - 1))]
  }
  var trimWidthRatio: CGFloat { (trimIndex ?? 0) == 0 ? 0.02 : 0.06 }
}

/// A rounded tile painted in the club colour with its kit pattern and (optional)
/// crest — reused in the editor, the matchday card and the table.
struct NativeKitTile: View {
  let kit: NativeKit
  let color: Color
  var secondary: Color? = nil
  var crestShape: NativeCrestShape = .rounded
  var trimColor: Color = .white.opacity(0.30)
  var trimWidth: CGFloat = 0.02
  var size: CGFloat = 44
  var emblem: String? = nil

  private var darkAccent: Color { secondary ?? Color.black.opacity(0.20) }
  private var lightAccent: Color { secondary ?? Color.white.opacity(0.24) }

  var body: some View {
    let shape = crestShape.anyShape()
    return shape
      .fill(color)
      .frame(width: size, height: size)
      .overlay(pattern)
      .overlay(
        Group {
          if let emblem {
            Image(systemName: emblem)
              .font(.system(size: size * 0.44, weight: .semibold))
              .foregroundStyle(.white)
              .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
          }
        }
      )
      .clipShape(shape)
      .overlay(shape.stroke(trimColor, lineWidth: max(1, size * trimWidth)))
  }

  @ViewBuilder private var pattern: some View {
    switch kit {
    case .solid:
      Color.clear
    case .gradient:
      LinearGradient(colors: [.white.opacity(0.22), .black.opacity(0.20)], startPoint: .top, endPoint: .bottom)
    case .stripes:
      HStack(spacing: 0) {
        ForEach(0..<6, id: \.self) { i in
          Rectangle().fill(i % 2 == 0 ? Color.clear : darkAccent)
        }
      }
    case .hoops:
      VStack(spacing: 0) {
        ForEach(0..<6, id: \.self) { i in
          Rectangle().fill(i % 2 == 0 ? Color.clear : lightAccent)
        }
      }
    case .sash:
      GeometryReader { geo in
        Path { p in
          p.move(to: CGPoint(x: 0, y: geo.size.height))
          p.addLine(to: CGPoint(x: geo.size.width * 0.34, y: geo.size.height))
          p.addLine(to: CGPoint(x: geo.size.width, y: 0))
          p.addLine(to: CGPoint(x: geo.size.width * 0.66, y: 0))
          p.closeSubpath()
        }
        .fill(secondary ?? .white.opacity(0.30))
      }
    case .halves:
      HStack(spacing: 0) {
        Rectangle().fill(Color.clear)
        Rectangle().fill(darkAccent)
      }
    case .quarters:
      VStack(spacing: 0) {
        HStack(spacing: 0) { Rectangle().fill(Color.clear); Rectangle().fill(darkAccent) }
        HStack(spacing: 0) { Rectangle().fill(darkAccent); Rectangle().fill(Color.clear) }
      }
    case .chevron:
      GeometryReader { geo in
        Path { p in
          let w = geo.size.width, h = geo.size.height
          p.move(to: CGPoint(x: 0, y: h * 0.45))
          p.addLine(to: CGPoint(x: w / 2, y: h * 0.8))
          p.addLine(to: CGPoint(x: w, y: h * 0.45))
          p.addLine(to: CGPoint(x: w, y: h * 0.7))
          p.addLine(to: CGPoint(x: w / 2, y: h * 1.05))
          p.addLine(to: CGPoint(x: 0, y: h * 0.7))
          p.closeSubpath()
        }
        .fill(secondary ?? .white.opacity(0.28))
      }
    case .pinstripe:
      HStack(spacing: 0) {
        ForEach(0..<12, id: \.self) { i in
          Rectangle().fill(i % 2 == 0 ? Color.clear : darkAccent.opacity(0.7))
        }
      }
    case .checks:
      VStack(spacing: 0) {
        ForEach(0..<5, id: \.self) { row in
          HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { col in
              Rectangle().fill((row + col) % 2 == 0 ? Color.clear : darkAccent.opacity(0.85))
            }
          }
        }
      }
    case .band:
      VStack(spacing: 0) {
        Rectangle().fill(Color.clear)
        Rectangle().fill(secondary ?? .white.opacity(0.28)).frame(maxHeight: .infinity)
        Rectangle().fill(Color.clear)
      }
    case .cross:
      ZStack {
        Rectangle().fill(secondary ?? darkAccent).frame(width: size * 0.26)
        Rectangle().fill(secondary ?? darkAccent).frame(height: size * 0.26)
      }
    case .diagonal:
      GeometryReader { geo in
        let n = 7
        HStack(spacing: 0) {
          ForEach(0..<n, id: \.self) { i in
            Rectangle().fill(i % 2 == 0 ? Color.clear : darkAccent.opacity(0.8))
          }
        }
        .frame(width: geo.size.width * 1.6, height: geo.size.height * 1.6)
        .rotationEffect(.degrees(35))
        .position(x: geo.size.width / 2, y: geo.size.height / 2)
      }
    case .spots:
      GeometryReader { geo in
        let cols = 3, rows = 3
        ForEach(0..<rows, id: \.self) { r in
          ForEach(0..<cols, id: \.self) { c in
            Circle()
              .fill(secondary ?? .white.opacity(0.30))
              .frame(width: geo.size.width * 0.16)
              .position(x: geo.size.width * (Double(c) + 0.5) / Double(cols),
                        y: geo.size.height * (Double(r) + 0.5) / Double(rows))
          }
        }
      }
    }
  }
}

/// The Coins wallet — earned from medals, wins and promotions, spent only on
/// club customisation. Cosmetic by design: Coins never help you win a match.
@MainActor
enum NativeWallet {
  // v2: reset purchases after the Coin rebalance, so everything past the free
  // tier (Stripes/Hoops/Sash/Halves included) is locked again under new pricing.
  private static let unlockedKey = "uk.okkle.native.wallet.unlocked.v2"

  /// Deterministic: total Coins earned to date from real achievements.
  static func earned(store: OkkleStore) -> Int {
    var total = 0
    for medal in NativeMedalEngine.achievements(store: store) where medal.unlocked {
      switch medal.tier {
      // Easy medals pay little; the real Coins come from hard, sustained play —
      // gold medals and (above all) climbing the league — so premium crests
      // stay earned rather than handed out.
      case .bronze:  total += 4
      case .silver:  total += 12
      case .gold:    total += 50
      case .special: total += 20
      }
    }
    for honour in NativeSeasonEngine.honours() {
      total += honour.kind == .champions ? 300 : 200
    }
    return total
  }

  static func unlocked() -> Set<String> {
    Set(UserDefaults.standard.array(forKey: unlockedKey) as? [String] ?? [])
  }

  static func cost(for id: String) -> Int {
    if id.hasPrefix("colour-") { return NativeClubIdentity.colourCost }
    if id.hasPrefix("crest-") {
      let symbol = String(id.dropFirst("crest-".count))
      let index = NativeClubIdentity.emblems.firstIndex(of: symbol) ?? NativeClubIdentity.freeCrests
      return NativeClubIdentity.crestCoins(index)
    }
    if id.hasPrefix("kit-") {
      let raw = Int(id.dropFirst("kit-".count)) ?? 0
      return NativeKit(rawValue: raw)?.coins ?? NativeClubIdentity.kitCost
    }
    if id.hasPrefix("shape-") {
      let raw = Int(id.dropFirst("shape-".count)) ?? 0
      return NativeCrestShape(rawValue: raw)?.coins ?? NativeClubIdentity.shapeCost
    }
    if id.hasPrefix("trim-") { return NativeClubIdentity.trimCost }
    return 0
  }

  static func spent() -> Int { unlocked().reduce(0) { $0 + cost(for: $1) } }
  static func balance(store: OkkleStore) -> Int { max(0, earned(store: store) - spent()) }

  static func isUnlocked(_ id: String, free: Bool) -> Bool { free || unlocked().contains(id) }

  /// Buy an item if it isn't owned and the balance covers it. Returns success.
  static func purchase(_ id: String, store: OkkleStore) -> Bool {
    var set = unlocked()
    guard !set.contains(id), balance(store: store) >= cost(for: id) else { return false }
    set.insert(id)
    UserDefaults.standard.set(Array(set), forKey: unlockedKey)
    return true
  }
}

/// One row of the division table — the driver plus the fictional rival clubs.
struct NativeClubRow: Identifiable {
  let id: Int
  let name: String
  let isYou: Bool
  let played: Int
  let points: Int
  let form: [Int] // 3 = win, 1 = draw, 0 = loss
}

struct NativeSeasonSnapshot {
  let division: NativeDivision
  let matchweek: Int
  let totalWeeks: Int
  let rows: [NativeClubRow]
  let yourRow: NativeClubRow
  let yourPosition: Int
  let ceremonyTo: NativeDivision?
  let bankedThisSeason: Double   // real tax £ you've banked this season
  let winBar: Double             // real £/week needed for a "win" this division
}

/// This week's match — you versus one past-self ghost, scored in real tax saved.
struct NativeFixture {
  enum State { case kickoff, live, fullTime }
  /// What the final week is worth, based on where you sit in the table.
  enum Stakes { case none, title, playoff, survival }
  let opponent: String
  let opponentSymbol: String
  let yourBanked: Double
  let oppBanked: Double
  let yourGoals: Int
  let oppGoals: Int
  let matchweek: Int
  let totalWeeks: Int
  let isFinalDay: Bool
  let state: State
  let stakes: Stakes
  let weeklyTarget: Double   // £ tax saved this week that earns the win (3 pts)

  /// How you earn league points each week, from real tax saved vs your target.
  var pointsThisWeek: Int { yourBanked >= weeklyTarget ? 3 : (yourBanked >= weeklyTarget * 0.5 ? 1 : 0) }
  var drawTarget: Double { weeklyTarget * 0.5 }
  var progressToTarget: Double { weeklyTarget <= 0 ? 0 : min(1, yourBanked / weeklyTarget) }

  var youAreWinning: Bool { yourGoals > oppGoals }
  var isLevel: Bool { yourGoals == oppGoals }
  var lead: Double { yourBanked - oppBanked }
}

/// The gaffer — a plain-spoken British manager who narrates the week. The solo
/// stand-in for a crowd: motivation comes from his team-talk, not other users.
enum NativeGaffer {
  static func teamTalk(for f: NativeFixture) -> String {
    let opp = f.opponent
    let toWin = max(0, Int((f.oppBanked - f.yourBanked).rounded())) + 1

    switch f.stakes {
    case .title:
      switch f.state {
      case .kickoff: return "Title decider, this. Beat \(opp) and the trophy's ours. Let's not leave it to chance."
      case .live:
        if f.youAreWinning { return "We're champions if this holds — \(Int(f.lead.rounded())) mi clear of \(opp). See it home." }
        if f.isLevel { return "Level with \(opp) and the title on the line. One more shift wins it." }
        return "We've slipped behind \(opp) with the trophy at stake. \(toWin) mi snatches it back — go."
      case .fullTime:
        return f.youAreWinning ? "Champions! Saw off \(opp) when it mattered most. Up we go." : "So close. \(opp) pipped us — we'll settle for the play-offs."
      }
    case .playoff:
      switch f.state {
      case .kickoff: return "Play-off final. Win this one match against \(opp) and we're promoted. Everything on it."
      case .live:
        if f.youAreWinning { return "We're going up — \(Int(f.lead.rounded())) mi ahead of \(opp) in the final. Hold your nerve." }
        if f.isLevel { return "Dead level in the play-off final. Next shift could be the one that sends us up." }
        return "Behind in the play-off final. \(toWin) mi beats \(opp) and books promotion — dig in."
      case .fullTime:
        return f.youAreWinning ? "We've done it! Beat \(opp) in the final — promotion through the play-offs!" : "Heartbreak. \(opp) won the final. We dust ourselves down and go again."
      }
    case .survival:
      switch f.state {
      case .kickoff: return "Must not lose this. Avoid defeat to \(opp) and we stay up. Roll your sleeves up."
      case .live:
        if f.youAreWinning { return "This keeps us up — \(Int(f.lead.rounded())) mi clear of \(opp). Don't switch off." }
        if f.isLevel { return "A draw with \(opp) keeps us safe. Hold it together." }
        return "We're going down as it stands. \(toWin) mi beats \(opp) and saves our season — fight."
      case .fullTime:
        return f.youAreWinning || f.isLevel ? "Survived! Held off \(opp) when it counted. We live to fight another season." : "Relegated. \(opp) sent us down. We bounce straight back."
      }
    case .none:
      switch f.state {
      case .kickoff:
        return "\(opp) up next. \(Int(f.oppBanked.rounded())) mi beats them — log your shifts and it's ours."
      case .live:
        if f.youAreWinning { return "Tidy. \(Int(f.lead.rounded())) mi clear of \(opp). Keep logging and the points are ours." }
        if f.isLevel { return "Neck and neck with \(opp). One more decent shift nicks it." }
        return "We're chasing \(opp) — \(toWin) mi this week flips the result."
      case .fullTime:
        if f.youAreWinning { return "Three points. Saw off \(opp) — that's how we climb." }
        if f.isLevel { return "A point apiece with \(opp). Take it and kick on." }
        return "\(opp) had our number this week. Reset, go harder."
      }
    }
  }
}

@MainActor
enum NativeSeasonEngine {
  static let weeksPerSeason = 4
  static let weekSeconds: TimeInterval = 7 * 24 * 3600
  private static let storageKey = "uk.okkle.native.league.season.v1"
  private static let honoursKey = "uk.okkle.native.league.honours.v1"
  private static let clubKey = "uk.okkle.native.league.club.v1"
  private static let epoch = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01

  /// Your rivals are your own past selves — no fictional clubs, every result real.
  /// Each ghost replays real weekly banked £ drawn from your own history.
  /// AI rival clubs. Their weekly tax-saved is pegged to YOUR target (the win
  /// bar) times a strength, so they always sit just within reach — the only way
  /// past them is to log more miles. They scale as you improve, staying a race.
  enum Ghost: Int, CaseIterable {
    case rovers, athletic, canal

    var clubName: String {
      switch self {
      case .rovers:   return "Riverside Rovers"
      case .athletic: return "Parkside Athletic"
      case .canal:    return "Canal Street FC"
      }
    }

    /// Multiple of your weekly win bar that this club banks.
    var strength: Double {
      switch self {
      case .rovers:   return 1.15   // pace-setters — win most weeks
      case .athletic: return 0.92   // mid-table
      case .canal:    return 0.62   // there to be beaten
      }
    }

    var symbol: String {
      switch self {
      case .rovers:   return "shield.fill"
      case .athletic: return "flame.fill"
      case .canal:    return "bolt.fill"
      }
    }
  }

  // MARK: Public

  static func snapshot(store: OkkleStore) -> NativeSeasonSnapshot {
    var state = loadState(store: store)
    advance(&state, store: store)
    save(state)
    let division = NativeDivision(rawValue: state.divisionRaw) ?? .nationalLeague
    let rows = standings(seasonStart: state.seasonStart, divisionRaw: state.divisionRaw, store: store)
    let played = activeOffsets(seasonStart: state.seasonStart, store: store).count
    let yourRow = rows.first { $0.isYou } ?? NativeClubRow(id: 0, name: "You", isYou: true, played: 0, points: 0, form: [])
    let position = (rows.firstIndex { $0.isYou } ?? 0) + 1
    let completed = completedWeeks(since: state.seasonStart)
    var banked = 0.0
    for week in 0..<completed {
      let start = state.seasonStart.addingTimeInterval(Double(week) * weekSeconds)
      banked += weeklyBanked(start: start, end: start.addingTimeInterval(weekSeconds), store: store)
    }
    // Include the current, in-progress week so the season total is never less
    // than what you've banked this week.
    if completed < weeksPerSeason {
      let start = state.seasonStart.addingTimeInterval(Double(completed) * weekSeconds)
      banked += weeklyBanked(start: start, end: min(Date(), start.addingTimeInterval(weekSeconds)), store: store)
    }
    return NativeSeasonSnapshot(
      division: division,
      matchweek: played,
      totalWeeks: weeksPerSeason,
      rows: rows,
      yourRow: yourRow,
      yourPosition: position,
      ceremonyTo: state.ceremonyToRaw.flatMap { NativeDivision(rawValue: $0) },
      bankedThisSeason: banked,
      winBar: winBar(division, store: store)
    )
  }

  static func clearCeremony(store: OkkleStore) {
    var state = loadState(store: store)
    state.ceremonyToRaw = nil
    save(state)
  }

  /// This week's fixture: you vs one rotating past-self, live in real tax saved.
  static func fixture(store: OkkleStore) -> NativeFixture {
    var state = loadState(store: store)
    advance(&state, store: store)
    save(state)
    let division = NativeDivision(rawValue: state.divisionRaw) ?? .nationalLeague
    let total = weeksPerSeason
    let completed = completedWeeks(since: state.seasonStart)
    let offsets = activeOffsets(seasonStart: state.seasonStart, store: store)   // weeks ridden
    let played = offsets.count
    let seasonOver = completed >= total

    // The live (or last) match sits on the current calendar week, but the
    // matchweek number only counts weeks the driver actually rode.
    let weekIndex = seasonOver ? (offsets.last ?? (total - 1)) : completed
    let weekStart = state.seasonStart.addingTimeInterval(Double(weekIndex) * weekSeconds)
    let weekEnd = weekStart.addingTimeInterval(weekSeconds)
    let weekFinished = seasonOver
    let yourBanked = weeklyMiles(start: weekStart, end: weekFinished ? weekEnd : min(Date(), weekEnd), store: store)

    let matchweek = min(seasonOver ? max(1, played) : played + 1, total)
    let ghost = Ghost.allCases[max(0, matchweek - 1) % Ghost.allCases.count]
    let oppBanked = botWeekBanked(ghost, weekOffset: weekIndex, division: division, store: store)

    let goalUnit = max(1, winBar(division, store: store) / 3)
    let yourGoals = min(6, Int((yourBanked / goalUnit).rounded(.down)))
    let oppGoals = min(6, Int((oppBanked / goalUnit).rounded(.down)))

    let fxState: NativeFixture.State = weekFinished ? .fullTime : (yourBanked <= 0 ? .kickoff : .live)
    let isFinal = matchweek >= total

    var stakes: NativeFixture.Stakes = .none
    if isFinal {
      let rows = standings(seasonStart: state.seasonStart, divisionRaw: state.divisionRaw, store: store)
      let position = (rows.firstIndex { $0.isYou } ?? 0) + 1
      let canPromote = division != .premierLeague
      if position == 1, canPromote {
        stakes = .title
      } else if (position == 2 || position == 3), canPromote {
        stakes = .playoff
      } else if position >= rows.count, division != .nationalLeague {
        stakes = .survival
      }
    }

    return NativeFixture(
      opponent: ghost.clubName,
      opponentSymbol: ghost.symbol,
      yourBanked: yourBanked,
      oppBanked: oppBanked,
      yourGoals: yourGoals,
      oppGoals: oppGoals,
      matchweek: matchweek,
      totalWeeks: total,
      isFinalDay: isFinal,
      state: fxState,
      stakes: stakes,
      weeklyTarget: winBar(division, store: store)
    )
  }

  /// A rival club's tax-saved for a week: pegged to your win bar × their
  /// strength, with a little deterministic week-to-week form so they're not flat.
  static func botWeekBanked(_ ghost: Ghost, weekOffset: Int, division: NativeDivision, store: OkkleStore) -> Double {
    let bar = winBar(division, store: store)
    let variation = 0.8 + 0.4 * botSeed(ghost.rawValue + 1, weekOffset + 1)
    return bar * ghost.strength * variation
  }

  private static func botSeed(_ a: Int, _ b: Int) -> Double {
    var x = UInt64(bitPattern: Int64((a &* 73_856_093) ^ (b &* 19_349_663)))
    x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33
    return Double(x % 1000) / 1000.0
  }

  // MARK: Standings

  static func standings(seasonStart: Date, divisionRaw: Int, store: OkkleStore) -> [NativeClubRow] {
    let division = NativeDivision(rawValue: divisionRaw) ?? .nationalLeague
    let offsets = activeOffsets(seasonStart: seasonStart, store: store)   // only weeks you rode
    let played = offsets.count
    let bar = winBar(division, store: store)

    // You — this season's real weekly banked £, on the weeks you worked.
    var yourForm: [Int] = []
    var yourPoints = 0
    for week in offsets {
      let start = seasonStart.addingTimeInterval(Double(week) * weekSeconds)
      let result = result(forBanked: weeklyMiles(start: start, end: start.addingTimeInterval(weekSeconds), store: store), bar: bar)
      yourPoints += result
      yourForm.append(result)
    }
    let yourName = clubIdentity(store: store).name
    var rows = [NativeClubRow(id: 0, name: yourName, isYou: true, played: played, points: yourPoints, form: Array(yourForm.suffix(5)))]

    // AI rival clubs — scored on the same active weeks, pegged to your bar.
    for ghost in Ghost.allCases {
      var points = 0
      var form: [Int] = []
      for week in offsets {
        let banked = botWeekBanked(ghost, weekOffset: week, division: division, store: store)
        let r = result(forBanked: banked, bar: bar)
        points += r
        form.append(r)
      }
      rows.append(NativeClubRow(id: ghost.rawValue + 1, name: ghost.clubName, isYou: false, played: played, points: points, form: Array(form.suffix(5))))
    }

    // Ties break in your favour, then by name — deterministic, no RNG.
    return rows.sorted {
      ($0.points, $0.isYou ? 1 : 0, $1.name) > ($1.points, $1.isYou ? 1 : 0, $0.name)
    }
  }

  // MARK: Mechanics — fixed weekly mileage targets

  /// The week's win line, in miles. It's a fixed target for the division — the
  /// same honest distance for everyone in that tier — so climbing is a real
  /// status, not a goal that quietly stretches as you get fitter. Calibrated to
  /// real courier mileage and always reachable in a full week's shifts.
  static func winBar(_ division: NativeDivision, store: OkkleStore) -> Double {
    Double(division.mileTarget)
  }

  private static func result(forBanked banked: Double, bar: Double) -> Int {
    banked >= bar ? 3 : (banked >= bar * 0.5 ? 1 : 0)
  }

  /// Miles logged in a week — records plus tracked trips. This is the league's
  /// scoring unit: pure effort, the same yardstick whatever your tax rate.
  static func weeklyMiles(start: Date, end: Date, store: OkkleStore) -> Double {
    let range = start..<end
    var miles = 0.0
    for record in store.records where range.contains(record.date) {
      miles += max(0, record.miles ?? 0)
    }
    for trip in store.trips where range.contains(trip.startedAt) {
      miles += max(0, trip.miles)
    }
    return miles
  }

  /// Your typical weekly mileage across your whole history (weeks you actually
  /// drove), with a gentle floor so a brand-new driver isn't stuck at the bottom.
  static func avgWeeklyMiles(store: OkkleStore) -> Double {
    let dates = store.records.map(\.date) + store.trips.map(\.startedAt)
    guard let earliest = dates.min() else { return 0 }
    let firstWeek = floor(earliest.timeIntervalSince1970 / weekSeconds)
    let lastWeek = floor(Date().timeIntervalSince1970 / weekSeconds)
    guard lastWeek >= firstWeek else { return 0 }
    var buckets: [Double] = []
    var w = firstWeek
    while w <= lastWeek {
      let start = Date(timeIntervalSince1970: w * weekSeconds)
      buckets.append(weeklyMiles(start: start, end: start.addingTimeInterval(weekSeconds), store: store))
      w += 1
    }
    let active = buckets.filter { $0 > 0 }
    guard !active.isEmpty else { return 0 }
    return active.reduce(0, +) / Double(active.count)
  }

  /// Real tax £ banked in a week = that week's mileage deduction × your marginal rate.
  static func weeklyBanked(start: Date, end: Date, store: OkkleStore) -> Double {
    let range = start..<end
    let rate = store.settings.incomeBracket.marginalRate(region: store.settings.region)
    var deduction = 0.0
    for record in store.records where range.contains(record.date) {
      deduction += store.calcDeduction(miles: record.miles ?? 0, vehicle: record.vehicle ?? store.settings.defaultVehicle, date: record.date)
    }
    for trip in store.trips where range.contains(trip.startedAt) {
      deduction += store.calcDeduction(miles: trip.miles, vehicle: trip.vehicle, date: trip.startedAt)
    }
    return deduction * rate
  }

  /// Your typical week: all-time average banked £, with a gentle floor so brand-new
  /// drivers can still post a win in their first weeks.
  static func weeklyBenchmark(store: OkkleStore) -> Double {
    let buckets = allWeeklyBanked(store: store).filter { $0 > 0 }
    guard !buckets.isEmpty else { return 12 } // ~£12 floor before any history
    let avg = buckets.reduce(0, +) / Double(buckets.count)
    return max(8, avg)
  }

  private static func topWeeklyBanked(count: Int, store: OkkleStore) -> [Double] {
    Array(allWeeklyBanked(store: store).sorted(by: >).prefix(count))
  }

  /// Banked £ bucketed into aligned weeks across the driver's whole history.
  private static func allWeeklyBanked(store: OkkleStore) -> [Double] {
    let dates = store.records.map(\.date) + store.trips.map(\.startedAt)
    guard let earliest = dates.min() else { return [] }
    let firstWeek = floor(earliest.timeIntervalSince1970 / weekSeconds)
    let lastWeek = floor(Date().timeIntervalSince1970 / weekSeconds)
    guard lastWeek >= firstWeek else { return [] }
    var buckets: [Double] = []
    var w = firstWeek
    while w <= lastWeek {
      let start = Date(timeIntervalSince1970: w * weekSeconds)
      buckets.append(weeklyBanked(start: start, end: start.addingTimeInterval(weekSeconds), store: store))
      w += 1
    }
    return buckets
  }

  // MARK: Season advance + persistence

  private static func advance(_ state: inout NativeLeagueState, store: OkkleStore) {
    let seasonLength = weekSeconds * Double(weeksPerSeason)
    var guardrail = 0
    while Date().timeIntervalSince(state.seasonStart) >= seasonLength, guardrail < 240 {
      // A season needs at least 2 of 4 weeks of real driving to count. A break —
      // a holiday, illness, a quiet spell — freezes your division: no relegation
      // (and no promotion) off the back of one or two off weeks.
      guard activeOffsets(seasonStart: state.seasonStart, store: store).count >= 2 else {
        state.seasonStart = state.seasonStart.addingTimeInterval(seasonLength)
        guardrail += 1
        continue
      }
      let rows = standings(seasonStart: state.seasonStart, divisionRaw: state.divisionRaw, store: store)
      let yourRow = rows.first { $0.isYou }
      let position = (rows.firstIndex { $0.isYou } ?? 0) + 1
      let wonFinal = (yourRow?.form.last ?? 0) == 3
      let canPromote = state.divisionRaw < NativeDivision.premierLeague.rawValue
      let fromDivision = state.divisionRaw
      let season = seasonIndex(state.seasonStart)

      if position == 1, canPromote {
        // Champions — automatic promotion.
        state.divisionRaw += 1
        state.ceremonyToRaw = state.divisionRaw
        recordHonour(NativeHonour(seasonIndex: season, divisionRaw: fromDivision, kind: .champions, date: state.seasonStart.addingTimeInterval(seasonLength)))
      } else if (position == 2 || position == 3), canPromote, wonFinal {
        // Play-off final won — promoted the hard way.
        state.divisionRaw += 1
        state.ceremonyToRaw = state.divisionRaw
        recordHonour(NativeHonour(seasonIndex: season, divisionRaw: fromDivision, kind: .playoff, date: state.seasonStart.addingTimeInterval(seasonLength)))
      } else if position >= rows.count, state.divisionRaw > 0 {
        // Bottom of the table — relegated.
        state.divisionRaw -= 1
      }
      state.seasonStart = state.seasonStart.addingTimeInterval(seasonLength)
      guardrail += 1
    }
  }

  private static func seasonIndex(_ seasonStart: Date) -> Int {
    Int(floor(seasonStart.timeIntervalSince(epoch) / (weekSeconds * Double(weeksPerSeason))))
  }

  private static func loadState(store: OkkleStore) -> NativeLeagueState {
    if let data = UserDefaults.standard.data(forKey: storageKey),
       let state = try? JSONDecoder().decode(NativeLeagueState.self, from: data) {
      return state
    }
    let division = NativeLeagueEngine.status(store: store).division
    let state = NativeLeagueState(divisionRaw: division.rawValue, seasonStart: alignedSeasonStart(for: Date()), ceremonyToRaw: nil)
    save(state)
    return state
  }

  private static func save(_ state: NativeLeagueState) {
    if let data = try? JSONEncoder().encode(state) {
      UserDefaults.standard.set(data, forKey: storageKey)
    }
  }

  // MARK: Honours (the trophy cabinet)

  static func honours() -> [NativeHonour] {
    guard let data = UserDefaults.standard.data(forKey: honoursKey),
          let list = try? JSONDecoder().decode([NativeHonour].self, from: data) else { return [] }
    return list.sorted { $0.date > $1.date }
  }

  private static func recordHonour(_ honour: NativeHonour) {
    var list = honours()
    guard !list.contains(where: { $0.id == honour.id }) else { return }
    list.append(honour)
    if let data = try? JSONEncoder().encode(list) {
      UserDefaults.standard.set(data, forKey: honoursKey)
    }
  }

  // MARK: Club identity

  static func clubIdentity(store: OkkleStore) -> NativeClubIdentity {
    if let data = UserDefaults.standard.data(forKey: clubKey),
       let club = try? JSONDecoder().decode(NativeClubIdentity.self, from: data) {
      return club
    }
    let base = store.settings.name.isEmpty ? "Your club" : "\(store.settings.name) FC"
    return NativeClubIdentity(name: base, colorIndex: 0, emblem: "shield.fill")
  }

  static func saveClubIdentity(_ club: NativeClubIdentity) {
    if let data = try? JSONEncoder().encode(club) {
      UserDefaults.standard.set(data, forKey: clubKey)
    }
  }

  // MARK: Helpers

  private static func completedWeeks(since seasonStart: Date) -> Int {
    max(0, min(weeksPerSeason, Int(floor(Date().timeIntervalSince(seasonStart) / weekSeconds))))
  }

  /// Did the driver actually ride in this aligned week? Off weeks don't count.
  static func weekActive(start: Date, store: OkkleStore) -> Bool {
    let range = start..<start.addingTimeInterval(weekSeconds)
    return store.records.contains { range.contains($0.date) } || store.trips.contains { range.contains($0.startedAt) }
  }

  /// Completed weeks this season the driver actually worked — the league only
  /// counts these, so rest days never trigger a fixture or cost you points.
  static func activeOffsets(seasonStart: Date, store: OkkleStore) -> [Int] {
    (0..<completedWeeks(since: seasonStart)).filter {
      weekActive(start: seasonStart.addingTimeInterval(Double($0) * weekSeconds), store: store)
    }
  }

  private static func alignedSeasonStart(for date: Date) -> Date {
    let blockLength = weekSeconds * Double(weeksPerSeason)
    let blocks = floor(date.timeIntervalSince(epoch) / blockLength)
    return epoch.addingTimeInterval(blocks * blockLength)
  }
}
