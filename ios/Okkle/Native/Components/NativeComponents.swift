import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
enum NativeScreenStyle {
  case standard

  var titleColor: Color {
    OkkleColor.ink
  }

  var subtitleColor: Color {
    OkkleColor.muted
  }

  var settingsColor: Color {
    OkkleColor.ink
  }

}

struct NativeScreen<Content: View>: View {
  let title: String
  let collapsedTitle: String?
  let subtitle: String?
  let style: NativeScreenStyle
  let content: Content
  @State private var showSettings = false
  @State private var showCollapsedTitle = false
  @State private var scrollTopY: CGFloat?

  init(title: String, collapsedTitle: String? = nil, subtitle: String? = nil, style: NativeScreenStyle = .standard, @ViewBuilder content: () -> Content) {
    self.title = title
    self.collapsedTitle = collapsedTitle
    self.subtitle = subtitle
    self.style = style
    self.content = content()
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if collapsedTitle != nil {
            Color.clear
              .frame(height: 1)
              .background {
                GeometryReader { proxy in
                  Color.clear.preference(
                    key: NativeScreenScrollOffsetKey.self,
                    value: proxy.frame(in: .global).minY
                  )
                }
              }
          }

          if collapsedTitle != nil {
            Text(title)
              .font(.system(size: 42, weight: .heavy, design: .rounded))
              .foregroundStyle(style.titleColor)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.top, 4)
          }

          if let subtitle {
            Text(subtitle)
              .font(.system(size: 17, weight: .medium))
              .foregroundStyle(style.subtitleColor)
              .padding(.top, collapsedTitle == nil ? 2 : -10)
          }

          content
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 120)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .background { NativeBackground() }
      .navigationTitle(navigationBarTitle)
      .navigationBarTitleDisplayMode(collapsedTitle == nil ? .large : .inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button { showSettings = true } label: {
            Image(systemName: "gearshape")
              .font(.system(size: 17, weight: .semibold))
          }
          .accessibilityLabel("Settings")
        }
      }
      .sheet(isPresented: $showSettings) {
        NativeSettingsView()
      }
      .onPreferenceChange(NativeScreenScrollOffsetKey.self) { offset in
        guard collapsedTitle != nil else { return }
        if scrollTopY == nil {
          scrollTopY = offset
        }
        let scrollDistance = (scrollTopY ?? offset) - offset
        let shouldShow = scrollDistance > 28
        guard shouldShow != showCollapsedTitle else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
          showCollapsedTitle = shouldShow
        }
      }
    }
  }

  private var navigationBarTitle: String {
    if let collapsedTitle {
      return showCollapsedTitle ? collapsedTitle : ""
    }
    return title
  }
}

private struct NativeScreenScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
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
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .shadow(color: .black.opacity(0.07), radius: 22, y: 12)
  }
}

struct NativeAiCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    NativeGlassCard(cornerRadius: 30) {
      content
    }
    .shadow(color: Color(red: 0.32, green: 0.78, blue: 1.0).opacity(0.20), radius: 36, x: -18, y: 18)
    .shadow(color: Color(red: 0.58, green: 0.36, blue: 1.0).opacity(0.16), radius: 44, x: 20, y: 20)
    .shadow(color: Color(red: 1.0, green: 0.56, blue: 0.67).opacity(0.14), radius: 50, x: 0, y: -8)
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
