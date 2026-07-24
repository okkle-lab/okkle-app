import MapKit
import SwiftUI
import UIKit

private struct NativeIPadPagePresentationModifier: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 18.0, *), UIDevice.current.userInterfaceIdiom == .pad {
      content.presentationSizing(.page)
    } else {
      content
    }
  }
}

extension View {
  func nativeIPadPagePresentation() -> some View {
    modifier(NativeIPadPagePresentationModifier())
  }
}

enum NativeScreenStyle {
  case standard
  case grouped

  var titleColor: Color {
    OkkleColor.ink
  }

  var subtitleColor: Color {
    OkkleColor.muted
  }

  var settingsColor: Color {
    OkkleColor.ink
  }

  var backgroundColor: Color {
    switch self {
    case .standard: return OkkleColor.surface
    case .grouped: return Color(uiColor: .systemGroupedBackground)
    }
  }
}

let nativeScreenContentCoordinateSpace = "NativeScreenContentCoordinateSpace"

private struct NativeViewportHeightKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
  var nativeViewportHeight: CGFloat {
    get { self[NativeViewportHeightKey.self] }
    set { self[NativeViewportHeightKey.self] = newValue }
  }
}

private struct NativeUsesSidebarNavigationKey: EnvironmentKey {
  static let defaultValue = false
}

private struct NativeSidebarAvoidanceInsetKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
  var nativeUsesSidebarNavigation: Bool {
    get { self[NativeUsesSidebarNavigationKey.self] }
    set { self[NativeUsesSidebarNavigationKey.self] = newValue }
  }

  var nativeSidebarAvoidanceInset: CGFloat {
    get { self[NativeSidebarAvoidanceInsetKey.self] }
    set { self[NativeSidebarAvoidanceInsetKey.self] = newValue }
  }
}

struct NativeScreen<Content: View>: View {
  @Environment(\.nativeUsesSidebarNavigation) private var nativeUsesSidebarNavigation
  let title: String
  let collapsedTitle: String?
  let subtitle: String?
  let style: NativeScreenStyle
  let onClose: (() -> Void)?
  let fillsViewport: Bool
  let scrollsContent: Bool
  let showsProfileButton: Bool
  let content: Content
  @State private var showSettings = false

  init(
    title: String,
    collapsedTitle: String? = nil,
    subtitle: String? = nil,
    style: NativeScreenStyle = .standard,
    onClose: (() -> Void)? = nil,
    fillsViewport: Bool = false,
    scrollsContent: Bool = true,
    showsProfileButton: Bool = true,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.collapsedTitle = collapsedTitle
    self.subtitle = subtitle
    self.style = style
    self.onClose = onClose
    self.fillsViewport = fillsViewport
    self.scrollsContent = scrollsContent
    self.showsProfileButton = showsProfileButton
    self.content = content()
  }

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        if scrollsContent {
          ScrollView {
            screenContent(proxy: proxy)
          }
          .scrollIndicators(.hidden)
          .scrollDismissesKeyboard(.interactively)
        } else {
          screenContent(proxy: proxy)
        }
      }
      .background { style.backgroundColor.ignoresSafeArea() }
      .navigationTitle(collapsedTitle ?? title)
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        if let onClose {
          ToolbarItem(placement: .topBarLeading) {
            Button(action: onClose) {
              Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
            }
            .accessibilityLabel("Close")
          }
        }

        if showsProfileButton && !nativeUsesSidebarNavigation {
          ToolbarItem(placement: .topBarTrailing) {
            NativeProfileToolbarButton {
              showSettings = true
            }
          }
        }
      }
      .sheet(isPresented: $showSettings) {
        NativeSettingsView()
          .presentationDetents([.large])
          .presentationDragIndicator(.hidden)
          .presentationCornerRadius(36)
      }
    }
  }

  private func screenContent(proxy: GeometryProxy) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      if let subtitle {
        Text(subtitle)
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(style.subtitleColor)
          .fixedSize(horizontal: false, vertical: true)
      }

      if fillsViewport {
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        content
      }
    }
    .frame(
      maxWidth: .infinity,
      minHeight: fillsViewport ? max(0, proxy.size.height - 36) : nil,
      alignment: .topLeading
    )
    .padding(.horizontal, 20)
    .padding(.bottom, 120)
    .coordinateSpace(name: nativeScreenContentCoordinateSpace)
    .environment(\.nativeViewportHeight, proxy.size.height)
  }
}

struct NativeProfileToolbarButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "person.crop.circle")
        .font(.system(size: 17, weight: .semibold))
    }
    .accessibilityLabel("Profile")
  }
}

struct NativeBackground: View {
  var body: some View {
    OkkleColor.surface
      .ignoresSafeArea()
  }
}

extension View {
  /// White panel that floats on the white background via a clear halo (3D depth).
  func okkleCard(cornerRadius: CGFloat = 20) -> some View {
    self
      .background(OkkleColor.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
      .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
  }
}

/// Apple News-style card: a white body lifted by a clear halo, topped by a
/// dark-green kicker band that fades into brand. Reusable across screens.
struct NativeBannerCard<Content: View>: View {
  let kicker: String
  var trailing: String? = nil
  var cornerRadius: CGFloat = 26
  var band: LinearGradient? = nil
  var content: Content

  init(kicker: String, trailing: String? = nil, cornerRadius: CGFloat = 26, band: LinearGradient? = nil, @ViewBuilder content: () -> Content) {
    self.kicker = kicker
    self.trailing = trailing
    self.cornerRadius = cornerRadius
    self.band = band
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(kicker)
          .font(.system(size: 14, weight: .heavy))
          .tracking(0.5)
          .foregroundStyle(.white)
        Spacer()
        if let trailing {
          Text(trailing)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        band ?? LinearGradient(colors: [OkkleColor.bannerDark, OkkleColor.brand], startPoint: .leading, endPoint: .trailing)
      )

      content
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OkkleColor.card)
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
  }
}

struct NativeGlassCard<Content: View>: View {
  var cornerRadius: CGFloat = 26
  var contentPadding: CGFloat = 20
  var content: Content

  init(cornerRadius: CGFloat = 26, contentPadding: CGFloat = 20, @ViewBuilder content: () -> Content) {
    self.cornerRadius = cornerRadius
    self.contentPadding = contentPadding
    self.content = content()
  }

  var body: some View {
    content
      .padding(contentPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.regularMaterial)
      // Clips content, not just the background — a child that draws its own
      // opaque/material background flush to the edge (e.g. a swipeable row)
      // would otherwise square off past this card's rounded corners at the
      // first/last row, instead of following the card's silhouette.
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .shadow(color: .black.opacity(0.07), radius: 22, y: 12)
  }
}

struct NativeAiCard<Content: View>: View {
  var banner: String? = nil
  var bannerTrailing: String? = nil
  let content: Content
  @Environment(\.colorScheme) private var colorScheme

  init(banner: String? = nil, bannerTrailing: String? = nil, @ViewBuilder content: () -> Content) {
    self.banner = banner
    self.bannerTrailing = bannerTrailing
    self.content = content()
  }

  // A native solid panel with an extremely restrained AI tint and perimeter
  // glow. The page itself stays the same white/black surface as every other
  // tab; the effect belongs to the card instead of washing over the screen.
  var body: some View {
    cardBody
      .padding(.horizontal, 20)
      .padding(.vertical, 18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        cardShape
          .fill(OkkleColor.card)
          .overlay {
            cardShape
              .fill(aiSurfaceGradient)
              .opacity(surfaceTintOpacity)
          }
      }
      .background {
        cardShape
          .stroke(aiGlowGradient, lineWidth: 3)
          .blur(radius: 9)
          .opacity(glowOpacity)
      }
      .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.045), radius: 10, y: 5)
  }

  private var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
  }

  private var surfaceTintOpacity: Double { colorScheme == .dark ? 0.055 : 0.025 }
  private var glowOpacity: Double { colorScheme == .dark ? 0.24 : 0.14 }

  private var aiSurfaceGradient: LinearGradient {
    LinearGradient(
      colors: [
        Color(red: 1.00, green: 0.22, blue: 0.72),
        Color.clear,
        Color(red: 0.35, green: 0.43, blue: 1.00)
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var aiGlowGradient: LinearGradient {
    LinearGradient(
      colors: [
        Color(red: 1.00, green: 0.30, blue: 0.74),
        Color(red: 0.58, green: 0.35, blue: 1.00),
        Color(red: 0.30, green: 0.42, blue: 1.00)
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  @ViewBuilder private var cardBody: some View {
    if let banner {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 8) {
          Text(banner)
            .font(.caption.weight(.semibold))
          Spacer(minLength: 8)
          if let bannerTrailing {
            Text(bannerTrailing)
              .font(.caption.weight(.semibold))
          }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

        content
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    } else {
      content
    }
  }
}

struct NativeMetricTile: View {
  let title: String
  let value: String
  let symbol: String
  var color: Color = OkkleColor.brand

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(color)
      Text(value)
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
    .padding(16)
    .okkleCard()
  }
}

struct NativeFreeTextDropdown: View {
  let title: String
  let placeholder: String
  let options: [String]
  @Binding var text: String
  @FocusState private var focused: Bool
  @State private var expanded = false
  @State private var filtersSuggestions = false
  @State private var isSelectingOption = false

  private var cleanOptions: [String] {
    var seen = Set<String>()
    return options.compactMap { option in
      let clean = option.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !clean.isEmpty else { return nil }
      let key = clean.lowercased()
      guard !seen.contains(key) else { return nil }
      seen.insert(key)
      return clean
    }
  }

  private var matches: [String] {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleanOptions.filter { option in
      !filtersSuggestions || query.isEmpty || option.localizedCaseInsensitiveContains(query)
    }
    .prefix(7)
    .map { $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(OkkleColor.ink)

      HStack(spacing: 8) {
        TextField(placeholder, text: $text)
          .textInputAutocapitalization(.words)
          .focused($focused)
          .submitLabel(.done)
          .onChange(of: text) { _ in
            guard !isSelectingOption else { return }
            filtersSuggestions = true
            expanded = true
          }
          .onChange(of: focused) { isFocused in
            guard isFocused else { return }
            filtersSuggestions = false
            expanded = true
          }
          .onTapGesture {
            filtersSuggestions = false
            expanded = true
          }

        Button {
          let willExpand = !expanded
          expanded = willExpand
          filtersSuggestions = false
          focused = willExpand
        } label: {
          Image(systemName: expanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
      }
      .padding(.leading, 14)
      .padding(.trailing, 8)
      .padding(.vertical, 8)
      .background(OkkleColor.fieldBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

      if (focused || expanded) && !matches.isEmpty {
        VStack(spacing: 0) {
          ForEach(matches, id: \.self) { option in
            Button {
              isSelectingOption = true
              text = option
              expanded = false
              filtersSuggestions = false
              focused = false
              hideKeyboard()
              DispatchQueue.main.async {
                isSelectingOption = false
              }
            } label: {
              HStack {
                Text(option)
                  .font(.system(size: 15, weight: .semibold))
                  .foregroundStyle(OkkleColor.ink)
                Spacer()
                if option.caseInsensitiveCompare(text.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
                  Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(OkkleColor.brand)
                }
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            if option != (matches.last ?? "") {
              Divider().padding(.leading, 14)
            }
          }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      }
    }
  }
}

struct NativeSectionTitle: View {
  let title: String
  let symbol: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .foregroundStyle(OkkleColor.brand)
      Text(title)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
    }
  }
}
