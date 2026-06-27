import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
enum NativeOnboardingStep: Int, CaseIterable {
  case welcome
  case name
  case vehicle
  case platforms
  case region
  case ready
}

final class NativeOnboardingRegionDetector: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published var isDetecting = false
  @Published var message: String?

  private let manager = CLLocationManager()
  private var onRegion: ((NativeRegion) -> Void)?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyKilometer
  }

  func detect(onRegion: @escaping (NativeRegion) -> Void) {
    self.onRegion = onRegion
    message = nil
    isDetecting = true

    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      finish(message: "Location access is off. Choose your region below.")
    @unknown default:
      finish(message: "Choose your region below.")
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      finish(message: "Location access is off. Choose your region below.")
    case .notDetermined:
      break
    @unknown default:
      finish(message: "Choose your region below.")
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      finish(message: "Choose your region below.")
      return
    }

    CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
      let area = [
        placemarks?.first?.administrativeArea,
        placemarks?.first?.subAdministrativeArea,
        placemarks?.first?.country,
      ]
      .compactMap { $0 }
      .joined(separator: " ")
      let region: NativeRegion = area.localizedCaseInsensitiveContains("scotland") ? .scotland : .ruk
      DispatchQueue.main.async {
        self?.onRegion?(region)
        self?.finish(message: "Set to \(region.label).")
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    finish(message: "Could not detect your region. Choose it below.")
  }

  private func finish(message: String?) {
    self.message = message
    isDetecting = false
    onRegion = nil
  }
}

struct NativeOnboardingView: View {
  @EnvironmentObject private var store: OkkleStore
  @Binding var selectedTab: NativeTab
  @StateObject private var detector = NativeOnboardingRegionDetector()
  @State private var step: NativeOnboardingStep = .welcome
  @State private var name = ""
  @State private var vehicle: NativeVehicle = .car
  @State private var selectedPlatforms: Set<String> = ["Uber Eats"]
  @State private var customPlatformName = ""
  @State private var region: NativeRegion = .ruk
  @State private var didSeed = false
  @FocusState private var nameFocused: Bool
  @FocusState private var customPlatformFocused: Bool

  private var canContinue: Bool {
    switch step {
    case .name:
      return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .platforms:
      return !orderedPlatforms.isEmpty
    default:
      return true
    }
  }

  var body: some View {
    ZStack {
      NativeBackground()

      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            progressDots
            stepContent
          }
          .padding(.horizontal, 22)
          .padding(.top, 28)
          .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)

        footer
          .padding(.horizontal, 22)
          .padding(.top, 14)
          .padding(.bottom, 18)
          .background(.ultraThinMaterial)
      }
    }
    .onAppear(perform: seedFromStore)
    .onChange(of: step) { newStep in
      if newStep == .name {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          nameFocused = true
        }
      } else {
        nameFocused = false
      }
      if newStep != .platforms {
        customPlatformFocused = false
      }
    }
    .nativeKeyboardDoneToolbar()
  }

  private var progressDots: some View {
    HStack(spacing: 7) {
      ForEach(NativeOnboardingStep.allCases.indices, id: \.self) { index in
        Capsule()
          .fill(index <= step.rawValue ? OkkleColor.brand : OkkleColor.muted.opacity(0.22))
          .frame(width: index == step.rawValue ? 24 : 8, height: 8)
          .animation(.spring(response: 0.28, dampingFraction: 0.86), value: step)
      }
    }
    .padding(.top, 10)
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .welcome:
      VStack(alignment: .leading, spacing: 22) {
        Image(systemName: "location.north.circle.fill")
          .font(.system(size: 62, weight: .bold))
          .foregroundStyle(OkkleColor.brand)
        NativeOnboardingHeader(
          eyebrow: "Okkle",
          title: "Drive smarter.\nKeep more of it.",
          subtitle: "Built for UK delivery couriers. Track trips, log pay, and stay ready for tax without the spreadsheet."
        )

        NativeGlassCard {
          VStack(alignment: .leading, spacing: 14) {
            NativeOnboardingBullet(symbol: "location.fill", title: "Track every trip with GPS")
            NativeOnboardingBullet(symbol: "chart.line.uptrend.xyaxis", title: "See where your work performs best")
            NativeOnboardingBullet(symbol: "shield.lefthalf.filled", title: "Keep tax-ready records on your phone")
            NativeOnboardingBullet(symbol: "medal.fill", title: "Build streaks and progress")
          }
        }
      }

    case .name:
      VStack(alignment: .leading, spacing: 18) {
        NativeOnboardingHeader(
          eyebrow: "Profile",
          title: "First, what should we call you?",
          subtitle: "This personalises your home screen and settings."
        )
        TextField("Your first name", text: $name)
          .font(.system(size: 22, weight: .bold))
          .textInputAutocapitalization(.words)
          .submitLabel(.next)
          .focused($nameFocused)
          .padding(18)
          .background(OkkleColor.fieldBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
          .onSubmit {
            if canContinue {
              advance()
            }
          }
      }

    case .vehicle:
      VStack(alignment: .leading, spacing: 18) {
        NativeOnboardingHeader(
          eyebrow: "Mileage",
          title: "What do you usually drive?",
          subtitle: "This sets your default mileage rate. You can still choose a different vehicle for each trip."
        )
        VStack(spacing: 10) {
          ForEach(NativeVehicle.allCases) { item in
            let band = item.rateBand(on: Date())
            NativeOnboardingOptionButton(
              title: item.label,
              subtitle: String(format: "%.0fp/mi first 10k", band.first * 100),
              symbol: item.symbol,
              selected: vehicle == item
            ) {
              vehicle = item
            }
          }
        }
      }

    case .platforms:
      VStack(alignment: .leading, spacing: 18) {
        NativeOnboardingHeader(
          eyebrow: "Work",
          title: "Who do you deliver for?",
          subtitle: "Pick all that apply. Okkle uses this to keep your logs quick and compare performance later."
        )
        VStack(spacing: 10) {
          ForEach(nativeOnboardingPlatforms, id: \.self) { platform in
            NativeOnboardingOptionButton(
              title: platform,
              subtitle: nil,
              symbol: nativePlatformSymbol(platform),
              selected: selectedPlatforms.contains(platform)
            ) {
              togglePlatform(platform)
            }
          }
        }

        if selectedPlatforms.contains("Other") {
          HStack(spacing: 10) {
            TextField("Delivery app name", text: $customPlatformName)
              .textInputAutocapitalization(.words)
              .submitLabel(.done)
              .focused($customPlatformFocused)
              .padding(16)
              .background(OkkleColor.fieldBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
              .onSubmit(addCustomPlatform)

            Button("Add", action: addCustomPlatform)
              .font(.system(size: 15, weight: .bold))
              .buttonStyle(.borderedProminent)
              .tint(OkkleColor.brand)
              .disabled(customPlatformName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }

        let customPlatforms = customSelectedPlatforms
        if !customPlatforms.isEmpty {
          VStack(spacing: 10) {
            ForEach(customPlatforms, id: \.self) { platform in
              NativeOnboardingOptionButton(
                title: platform,
                subtitle: "Custom platform",
                symbol: "plus.circle.fill",
                selected: true
              ) {
                selectedPlatforms.remove(platform)
              }
            }
          }
        }
      }

    case .region:
      VStack(alignment: .leading, spacing: 18) {
        NativeOnboardingHeader(
          eyebrow: "Tax region",
          title: "Where are you based?",
          subtitle: "Scotland has different income-tax bands. This is where you live, not where you drive."
        )

        Button {
          detector.detect { detectedRegion in
            region = detectedRegion
          }
        } label: {
          HStack(spacing: 10) {
            if detector.isDetecting {
              ProgressView()
                .tint(OkkleColor.brand)
            } else {
              Image(systemName: "location.magnifyingglass")
            }
            Text(detector.isDetecting ? "Detecting location" : "Detect from my location")
              .font(.system(size: 16, weight: .bold))
            Spacer()
          }
          .foregroundStyle(OkkleColor.brandDark)
          .padding(16)
          .background(OkkleColor.mint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(detector.isDetecting)

        if let message = detector.message {
          Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
        }

        VStack(spacing: 10) {
          ForEach(NativeRegion.allCases) { item in
            NativeOnboardingOptionButton(
              title: item.label,
              subtitle: item == .scotland ? "Scottish income-tax bands" : "Rest of UK income-tax bands",
              symbol: item == .scotland ? "mountain.2.fill" : "map.fill",
              selected: region == item
            ) {
              region = item
            }
          }
        }
      }

    case .ready:
      VStack(alignment: .leading, spacing: 22) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 62, weight: .bold))
          .foregroundStyle(OkkleColor.brand)
        NativeOnboardingHeader(
          eyebrow: "Ready",
          title: "You're set, \(displayName).",
          subtitle: "The quickest way to get value is to track one trip, then log your next payout."
        )

        NativeGlassCard {
          VStack(alignment: .leading, spacing: 16) {
            NativeOnboardingBullet(symbol: "location.north.fill", title: "Start a trip when you set off")
            NativeOnboardingBullet(symbol: "sterlingsign.circle.fill", title: "Log pay when it arrives")
            NativeOnboardingBullet(symbol: "sparkles", title: "Check Insights once you have data")
          }
        }
      }
    }
  }

  private var footer: some View {
    VStack(spacing: 12) {
      if step == .ready {
        NativeOnboardingPrimaryButton(title: "Start my first trip", symbol: "location.north.fill") {
          finish(destination: .trip)
        }
        Button {
          finish(destination: .home)
        } label: {
          Text("Explore the app first")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(OkkleColor.brandDark)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
      } else {
        NativeOnboardingPrimaryButton(title: step == .welcome ? "Get started" : "Continue", symbol: "arrow.right", disabled: !canContinue) {
          advance()
        }
        if step.rawValue > 0 {
          Button {
            goBack()
          } label: {
            Text("Back")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(OkkleColor.muted)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 8)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var displayName: String {
    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? "let's go" : clean
  }

  private var orderedPlatforms: [String] {
    let standard = nativeOnboardingPlatforms.filter { platform in
      platform != "Other" && selectedPlatforms.contains(platform)
    }
    return uniqueStrings(standard + customSelectedPlatforms)
  }

  private var customSelectedPlatforms: [String] {
    selectedPlatforms
      .filter { platform in
        !nativeOnboardingPlatforms.contains { $0.caseInsensitiveCompare(platform) == .orderedSame }
      }
      .sorted()
  }

  private func seedFromStore() {
    guard !didSeed else { return }
    didSeed = true
    name = store.settings.name
    vehicle = store.settings.defaultVehicle
    region = store.settings.region
    selectedPlatforms = Set(store.settings.platforms.isEmpty ? ["Uber Eats"] : store.settings.platforms)
  }

  private func advance() {
    guard canContinue,
          let next = NativeOnboardingStep(rawValue: step.rawValue + 1) else { return }
    hideKeyboard()
    step = next
  }

  private func goBack() {
    guard let previous = NativeOnboardingStep(rawValue: step.rawValue - 1) else { return }
    hideKeyboard()
    step = previous
  }

  private func finish(destination: NativeTab) {
    hideKeyboard()
    selectedTab = destination
    store.completeOnboarding(
      name: name,
      defaultVehicle: vehicle,
      platforms: orderedPlatforms,
      region: region
    )
  }

  private func togglePlatform(_ platform: String) {
    if selectedPlatforms.contains(platform) {
      selectedPlatforms.remove(platform)
      if platform == "Other" {
        customPlatformName = ""
        customPlatformFocused = false
      }
    } else {
      selectedPlatforms.insert(platform)
      if platform == "Other" {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
          customPlatformFocused = true
        }
      }
    }
  }

  private func addCustomPlatform() {
    let clean = customPlatformName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    selectedPlatforms.insert(clean)
    selectedPlatforms.remove("Other")
    customPlatformName = ""
    customPlatformFocused = false
  }

}

struct NativeOnboardingHeader: View {
  let eyebrow: String
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(eyebrow.uppercased())
        .font(.system(size: 13, weight: .heavy))
        .foregroundStyle(OkkleColor.brandDark)
      Text(title)
        .font(.system(size: 42, weight: .heavy, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .fixedSize(horizontal: false, vertical: true)
        .minimumScaleFactor(0.82)
      Text(subtitle)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct NativeOnboardingBullet: View {
  let symbol: String
  let title: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(OkkleColor.brandDark)
        .frame(width: 32, height: 32)
        .background(OkkleColor.mint, in: Circle())
      Text(title)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct NativeOnboardingOptionButton: View {
  let title: String
  let subtitle: String?
  let symbol: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(selected ? OkkleColor.brandDark : OkkleColor.muted)
          .frame(width: 38, height: 38)
          .background(selected ? OkkleColor.mint : Color(uiColor: .tertiarySystemBackground), in: Circle())

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(OkkleColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
          if let subtitle {
            Text(subtitle)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
              .lineLimit(2)
          }
        }

        Spacer(minLength: 0)

        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(selected ? OkkleColor.brand : OkkleColor.muted.opacity(0.45))
      }
      .padding(14)
      .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
      .background(
        selected ? OkkleColor.mint.opacity(0.95) : Color(uiColor: .secondarySystemBackground).opacity(0.86),
        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
      )
    }
    .buttonStyle(.plain)
  }
}

struct NativeOnboardingPrimaryButton: View {
  let title: String
  let symbol: String
  var disabled = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(disabled ? OkkleColor.muted.opacity(0.35) : OkkleColor.brand, in: Capsule())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
  }
}
