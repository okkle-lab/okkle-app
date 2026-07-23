import CoreLocation
import MapKit
import SwiftUI
enum NativeOnboardingStep: Int, CaseIterable {
  case welcome
  case name
  case vehicle
  // Region (which now also picks country) comes before platforms so the
  // delivery-app list can reflect the driver's market (UK vs US).
  case region
  case platforms
  case incomeBracket
  case automaticTracking
  case locationPermission
  case iCloudSync
  case ready
}

/// Requests location access from a dedicated onboarding step, primed by an
/// explanation screen rather than a system prompt appearing unexpectedly.
/// iOS requires the When In Use grant before the user can explicitly upgrade
/// Okkle to Always, which automatic tracking needs to relaunch in background.
final class NativeOnboardingLocationRequester: NSObject, ObservableObject, CLLocationManagerDelegate {
  enum Outcome { case needsAlways, granted, denied }

  @Published var outcome: Outcome?

  private let manager = CLLocationManager()

  override init() {
    super.init()
    manager.delegate = self
  }

  func request() {
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse:
      manager.requestAlwaysAuthorization()
    case .authorizedAlways:
      outcome = .granted
    case .denied, .restricted:
      outcome = .denied
    @unknown default:
      outcome = .denied
    }
  }

  var hasAlwaysAuthorization: Bool {
    outcome == .granted
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    updateOutcome(for: manager.authorizationStatus)
  }

  private func updateOutcome(for status: CLAuthorizationStatus) {
    switch status {
    case .authorizedAlways:
      outcome = .granted
    case .authorizedWhenInUse:
      outcome = .needsAlways
    case .denied, .restricted:
      outcome = .denied
    case .notDetermined:
      outcome = nil
    @unknown default:
      outcome = .denied
    }
  }
}

final class NativeOnboardingRegionDetector: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published var isDetecting = false
  @Published var message: String?

  private let manager = CLLocationManager()
  private var onRegion: ((NativeRegion) -> Void)?
  private var onUSState: ((NativeUSState) -> Void)?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyKilometer
  }

  func detect(onRegion: @escaping (NativeRegion) -> Void) {
    self.onRegion = onRegion
    self.onUSState = nil
    startDetecting()
  }

  func detectUSState(onUSState: @escaping (NativeUSState) -> Void) {
    self.onUSState = onUSState
    self.onRegion = nil
    startDetecting()
  }

  private func startDetecting() {
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
      guard let self else { return }
      let placemark = placemarks?.first
      if let onUSState = self.onUSState {
        let state = NativeUSState.matching(administrativeArea: placemark?.administrativeArea)
        DispatchQueue.main.async {
          onUSState(state)
          self.finish(message: "Set to \(state.label).")
        }
      } else {
        let area = [
          placemark?.administrativeArea,
          placemark?.subAdministrativeArea,
          placemark?.country,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        let region: NativeRegion = area.localizedCaseInsensitiveContains("scotland") ? .scotland : .ruk
        DispatchQueue.main.async {
          self.onRegion?(region)
          self.finish(message: "Set to \(region.label).")
        }
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

private enum NativeOnboardingICloudCheckState: Equatable {
  case idle
  case checking
  case none
  case downloading
  case available
  case syncing
  case declined
  case failed(String)
}

struct NativeOnboardingView: View {
  @EnvironmentObject private var store: OkkleStore
  @Binding var selectedTab: NativeTab
  @StateObject private var detector = NativeOnboardingRegionDetector()
  @StateObject private var locationRequester = NativeOnboardingLocationRequester()
  @State private var step: NativeOnboardingStep = .welcome
  @State private var name = ""
  @State private var vehicle: NativeVehicle = .car
  @State private var selectedPlatforms: Set<String> = ["Uber Eats"]
  @State private var customPlatformName = ""
  @State private var country: NativeTaxCountry = .deviceDefault
  @State private var region: NativeRegion = .ruk
  @State private var expenseMethod: NativeExpenseMethod = .simplified
  @State private var showsSimplifiedLockConfirm = false
  @State private var usState: NativeUSState = .california
  @State private var incomeBracket: NativeIncomeBracket = .basic
  @State private var autoTrackTrips = true
  @State private var enhancedAutoTracking = true
  @State private var workingDays: [Int] = Array(0...6)
  @State private var iCloudSyncEnabled = true
  @State private var didSeed = false
  @State private var restoreMessage: String?
  @State private var iCloudCheckState: NativeOnboardingICloudCheckState = .idle
  @State private var iCloudSnapshotSummary: NativeICloudRemoteSnapshotSummary?
  @State private var showICloudSyncPrompt = false
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
    .onAppear {
      seedFromStore()
      checkForExistingICloudDataIfNeeded()
    }
    .alert("iCloud sync", isPresented: Binding(
      get: { restoreMessage != nil },
      set: { if !$0 { restoreMessage = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(restoreMessage ?? "")
    }
    .alert("Sync your iCloud data?", isPresented: $showICloudSyncPrompt, presenting: iCloudSnapshotSummary) { _ in
      Button("Sync data") {
        syncExistingICloudData()
      }
      Button("Set up as new", role: .cancel) {
        iCloudCheckState = .declined
      }
    } message: { summary in
      Text(summary.promptMessage)
    }
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
        HStack(spacing: 10) {
          Image("OkkleMark")
            .resizable()
            .scaledToFit()
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          Text("OKKLE")
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(OkkleColor.brandDark)
            .tracking(0.5)
        }

        VStack(alignment: .leading, spacing: 10) {
          Text("Drive smarter.\nKeep more of it.")
            .font(.system(size: 42, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .minimumScaleFactor(0.82)
          Text("Built for UK delivery couriers. Track trips, log pay, and stay ready for tax without the spreadsheet.")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
        }

        NativeGlassCard {
          VStack(alignment: .leading, spacing: 14) {
            NativeOnboardingBullet(symbol: "location.fill", title: "Track every trip with GPS")
            NativeOnboardingBullet(symbol: "chart.line.uptrend.xyaxis", title: "See where your work performs best")
            NativeOnboardingBullet(symbol: "shield.lefthalf.filled", title: "Keep tax-ready records on your phone")
          }
        }

        iCloudSyncOffer
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
            // No mileage-rate hint here — the country/region step (which
            // sets the actual rate, UK or US) comes right after this one.
            NativeOnboardingOptionButton(
              title: item.label,
              subtitle: nil,
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
          ForEach(nativeOnboardingPlatforms(for: country), id: \.self) { platform in
            NativeOnboardingOptionButton(
              title: platform,
              subtitle: nil,
              symbol: nativePlatformSymbol(platform),
              iconAssetName: nativePlatformIconAssetName(platform),
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
          eyebrow: "Tax location",
          title: "Where are you based?",
          subtitle: "Sets your tax year, mileage rate and delivery apps. This is where you live, not where you drive."
        )

        VStack(spacing: 10) {
          ForEach(NativeTaxCountry.allCases) { item in
            NativeOnboardingOptionButton(
              title: item.label,
              subtitle: item == .us ? "Federal + self-employment tax" : "HMRC Self Assessment",
              symbol: item == .us ? "flag.fill" : "building.columns.fill",
              selected: country == item
            ) {
              guard country != item else { return }
              country = item
              // Reset the platform selection to this market's default unless
              // the driver has already picked something bespoke.
              if selectedPlatforms.count <= 1 {
                selectedPlatforms = [nativeOnboardingPlatforms(for: item).first ?? "Uber Eats"]
              }
            }
          }
        }

        switch country {
        case .uk:
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

          Divider().padding(.top, 4)

          VStack(alignment: .leading, spacing: 10) {
            Text("How do you claim vehicle costs?")
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(OkkleColor.ink)

            ForEach(NativeExpenseMethod.allCases) { method in
              NativeOnboardingOptionButton(
                title: method.label,
                subtitle: method.subtitle,
                symbol: method == .simplified ? "gauge.with.dots.needle.50percent" : "receipt.fill",
                selected: expenseMethod == method
              ) {
                guard expenseMethod != method else { return }
                if method == .simplified {
                  showsSimplifiedLockConfirm = true
                } else {
                  expenseMethod = method
                }
              }
            }

            Text("Simplified expenses lock in once chosen — HMRC requires sticking with them for this vehicle from then on. Actual costs can be switched to Simplified later if you change your mind.")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
              .fixedSize(horizontal: false, vertical: true)
          }
        case .us:
          Button {
            detector.detectUSState { detectedState in
              usState = detectedState
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

          Picker("State", selection: $usState) {
            ForEach(NativeUSState.allCases) { Text($0.label).tag($0) }
          }
          .pickerStyle(.navigationLink)
          .padding(.horizontal, 4)
          Text("Used for state income tax. Federal and self-employment tax apply everywhere.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
        }
      }
      .alert("Use simplified expenses?", isPresented: $showsSimplifiedLockConfirm) {
        Button("Cancel", role: .cancel) {}
        Button("Confirm") { expenseMethod = .simplified }
      } message: {
        Text("Once you choose simplified expenses, HMRC requires you to keep using them for this vehicle for as long as you use it for business. You won't be able to switch to actual costs later.")
      }

    case .incomeBracket:
      VStack(alignment: .leading, spacing: 18) {
        NativeOnboardingHeader(
          eyebrow: "Tax band",
          title: "Which tax band should Okkle use?",
          subtitle: "This keeps your tax saved and estimated tax due closer when courier work sits on top of other income."
        )

        VStack(spacing: 10) {
          ForEach(NativeIncomeBracket.allCases) { bracket in
            NativeOnboardingOptionButton(
              title: bracket.label,
              subtitle: incomeBracketSubtitle(for: bracket),
              symbol: bracket == .basic ? "percent" : "chart.line.uptrend.xyaxis",
              selected: incomeBracket == bracket
            ) {
              incomeBracket = bracket
            }
          }
        }

        Text("You can change this later in Settings. Your accountant should confirm the final numbers before filing.")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }

    case .automaticTracking:
      VStack(alignment: .leading, spacing: 18) {
        NativeOnboardingHeader(
          eyebrow: "Automatic tracking",
          title: "Let Okkle catch trips for you.",
          subtitle: "Recommended for delivery work. Okkle can start trips from driving movement and keep your mileage records building in the background."
        )

        NativeGlassCard {
          VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: Binding(
              get: { autoTrackTrips },
              set: { enabled in
                autoTrackTrips = enabled
                if enabled {
                  enhancedAutoTracking = true
                }
              }
            )) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Automatic trip tracking")
                  .font(.system(size: 17, weight: .bold))
                  .foregroundStyle(OkkleColor.ink)
                Text("Starts tracking when driving is detected on your working days.")
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(OkkleColor.muted)
              }
            }
            .tint(OkkleColor.brand)

            Divider()

            Toggle(isOn: Binding(
              get: { autoTrackTrips && enhancedAutoTracking },
              set: { enabled in
                guard autoTrackTrips else { return }
                enhancedAutoTracking = enabled
              }
            )) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Enhanced automatic tracking")
                  .font(.system(size: 17, weight: .bold))
                  .foregroundStyle(autoTrackTrips ? OkkleColor.ink : OkkleColor.muted)
                Text("Uses the system Car Audio route, including CarPlay audio, to improve accuracy and end trips sooner.")
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(OkkleColor.muted)
              }
            }
            .tint(autoTrackTrips ? OkkleColor.brand : OkkleColor.muted.opacity(0.35))
            .disabled(!autoTrackTrips)
            .opacity(autoTrackTrips ? 1 : 0.48)

            if autoTrackTrips {
              Divider()

              NativeWorkingDaysPicker(days: $workingDays)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
          }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: autoTrackTrips)

        NativeGlassCard {
          VStack(alignment: .leading, spacing: 14) {
            NativeOnboardingBullet(symbol: "location.north.line.fill", title: "No need to remember every start")
            NativeOnboardingBullet(symbol: "car.fill", title: "Car signals help detect real trip endings")
            NativeOnboardingBullet(symbol: "house.fill", title: "Saved Home locations can end a shift cleanly")
          }
        }
      }

    case .locationPermission:
      VStack(alignment: .leading, spacing: 18) {
        NativeOnboardingHeader(
          eyebrow: "Location access",
          title: "Turn on location access",
          subtitle: "Okkle uses this only to detect driving and log trip mileage in the background. Never sold, never shared."
        )

        NativeGlassCard {
          VStack(alignment: .leading, spacing: 14) {
            NativeOnboardingBullet(symbol: "1.circle.fill", title: "Tap \"Allow location access\" below")
            NativeOnboardingBullet(symbol: "2.circle.fill", title: "iOS will ask to confirm - choose \"Allow While Using App\"")
            NativeOnboardingBullet(symbol: "3.circle.fill", title: "Then allow background tracking so Okkle can catch trips when closed")
          }
        }

        switch locationRequester.outcome {
        case nil:
          Button {
            locationRequester.request()
          } label: {
            HStack(spacing: 10) {
              Image(systemName: "location.fill")
              Text("Allow location access")
                .font(.system(size: 16, weight: .bold))
              Spacer()
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(OkkleColor.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
          }
          .buttonStyle(.plain)

        case .granted:
          HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(OkkleColor.brand)
            Text("Location enabled - Okkle can now catch trips automatically.")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(OkkleColor.ink)
          }
          .padding(14)
          .background(OkkleColor.mint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        case .needsAlways:
          VStack(alignment: .leading, spacing: 12) {
            Text("Background access is still needed before automatic tracking can run reliably.")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(OkkleColor.ink)
            Button {
              locationRequester.request()
            } label: {
              Label("Allow background tracking", systemImage: "location.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(OkkleColor.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("Continuing without Always access will leave automatic tracking off. Manual trip recording will still work.")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
          }
          .padding(14)
          .background(OkkleColor.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        case .denied:
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
              Image(systemName: "location.slash.fill")
                .foregroundStyle(OkkleColor.amber)
              Text("Location is off. Automatic tracking will stay off until Always access is enabled.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OkkleColor.ink)
            }
            Button {
              if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
              }
            } label: {
              Text("Open Settings")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(OkkleColor.brandDark)
            }
            .buttonStyle(.plain)
          }
          .padding(14)
          .background(OkkleColor.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
      }

    case .iCloudSync:
      VStack(alignment: .leading, spacing: 18) {
        NativeOnboardingHeader(
          eyebrow: "iCloud sync",
          title: "Keep your records backed up.",
          subtitle: "Okkle can automatically sync your trips, records, and settings through your private iCloud Drive."
        )

        NativeGlassCard {
          VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $iCloudSyncEnabled) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Enable iCloud sync")
                  .font(.system(size: 17, weight: .bold))
                  .foregroundStyle(OkkleColor.ink)
                Text("Automatically keeps this device backed up without manual export files.")
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(OkkleColor.muted)
              }
            }
            .tint(OkkleColor.brand)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
              NativeOnboardingBullet(symbol: "icloud.fill", title: "Syncs records and trips")
              NativeOnboardingBullet(symbol: "arrow.triangle.2.circlepath", title: "Runs automatically in the background")
              NativeOnboardingBullet(symbol: "lock.shield.fill", title: "Uses your private iCloud Drive")
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
            NativeOnboardingBullet(symbol: autoTrackTrips ? "location.north.line.fill" : "location.north.fill",
                                   title: autoTrackTrips ? "Automatic tracking is ready" : "Start a trip when you set off")
            NativeOnboardingBullet(symbol: iCloudSyncEnabled ? "icloud.fill" : "internaldrive.fill",
                                   title: iCloudSyncEnabled ? "iCloud sync is ready" : "Records will stay on this device")
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
          finish(destination: .trip)
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
    let standard = nativeOnboardingPlatforms(for: country).filter { platform in
      platform != "Other" && selectedPlatforms.contains(platform)
    }
    return uniqueStrings(standard + customSelectedPlatforms)
  }

  private var customSelectedPlatforms: [String] {
    selectedPlatforms
      .filter { platform in
        !nativeAllKnownPlatforms.contains { $0.caseInsensitiveCompare(platform) == .orderedSame }
      }
      .sorted()
  }

  private func seedFromStore() {
    guard !didSeed else { return }
    didSeed = true
    name = store.settings.name
    vehicle = store.settings.defaultVehicle
    // Onboarding only ever shows before hasCompletedOnboarding is set, so a
    // fresh NativeSettings() here always has taxCountry at its hardcoded
    // .uk default — trusting it would silently overwrite the device-locale
    // guess this view starts with. Only respect stored settings if this is
    // somehow a repeat onboarding for an account that already finished it.
    country = store.settings.hasCompletedOnboarding ? store.settings.taxCountry : .deviceDefault
    region = store.settings.region
    expenseMethod = store.settings.expenseMethod
    usState = store.settings.usState
    incomeBracket = store.settings.incomeBracket
    autoTrackTrips = store.settings.autoTrackTrips
    enhancedAutoTracking = store.settings.autoTrackTrips ? store.settings.enhancedAutoTracking : true
    workingDays = store.settings.workingDays.isEmpty ? Array(0...6) : store.settings.workingDays
    iCloudSyncEnabled = store.settings.iCloudSyncEnabled
    selectedPlatforms = Set(store.settings.platforms.isEmpty ? ["Uber Eats"] : store.settings.platforms)
  }

  @ViewBuilder
  private var iCloudSyncOffer: some View {
    switch iCloudCheckState {
    case .idle, .none, .declined, .failed(_):
      EmptyView()
    case .checking:
      NativeGlassCard {
        HStack(spacing: 12) {
          ProgressView()
            .tint(OkkleColor.brand)
          VStack(alignment: .leading, spacing: 3) {
            Text("Checking iCloud")
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(OkkleColor.brandDark)
            Text("Looking for existing Okkle data")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(OkkleColor.muted)
          }
        }
      }
    case .available:
      Button {
        showICloudSyncPrompt = true
      } label: {
        iCloudSyncOfferContent(
          symbol: "icloud.and.arrow.down.fill",
          title: "Sync iCloud data",
          subtitle: iCloudSnapshotSummary.map(iCloudSummaryText) ?? "Found existing Okkle data",
          showsChevron: true
        )
      }
      .buttonStyle(.plain)
    case .syncing:
      iCloudSyncOfferContent(
        symbol: "arrow.triangle.2.circlepath.icloud.fill",
        title: "Syncing iCloud data",
        subtitle: "Loading your records onto this device",
        showsChevron: false
      )
      .allowsHitTesting(false)
    case .downloading:
      Button {
        checkForExistingICloudDataIfNeeded(force: true)
      } label: {
        iCloudSyncOfferContent(
          symbol: "icloud.and.arrow.down",
          title: "iCloud is still downloading",
          subtitle: "Tap to check again in a moment",
          showsChevron: true
        )
      }
      .buttonStyle(.plain)
    }
  }

  private func iCloudSyncOfferContent(symbol: String, title: String, subtitle: String, showsChevron: Bool) -> some View {
    NativeGlassCard {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 38, height: 38)
          .background(OkkleColor.brand, in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 17, weight: .bold))
          Text(subtitle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .lineLimit(2)
        }
        Spacer()
        if showsChevron {
          Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
        }
      }
      .foregroundStyle(OkkleColor.brandDark)
    }
  }

  private func iCloudSummaryText(_ summary: NativeICloudRemoteSnapshotSummary) -> String {
    let itemSummary = [
      summary.recordCount == 1 ? "1 record" : "\(summary.recordCount) records",
      summary.tripCount == 1 ? "1 trip" : "\(summary.tripCount) trips"
    ].joined(separator: " and ")
    if summary.name.isEmpty {
      return "Found \(itemSummary) in iCloud"
    }
    return "Found \(summary.name)'s \(itemSummary) in iCloud"
  }

  private func checkForExistingICloudDataIfNeeded(force: Bool = false) {
    guard force || iCloudCheckState == .idle else { return }
    guard store.isFreshInstallForICloudOffer else { return }
    iCloudCheckState = .checking
    Task { @MainActor in
      switch await store.existingICloudDataCheck() {
      case .none:
        iCloudCheckState = .none
      case .downloading:
        iCloudCheckState = .downloading
      case .available(let summary):
        iCloudSnapshotSummary = summary
        iCloudCheckState = .available
        showICloudSyncPrompt = true
      case .unavailable:
        iCloudCheckState = .none
      }
    }
  }

  private func syncExistingICloudData() {
    iCloudCheckState = .syncing
    Task { @MainActor in
      do {
        try await store.restoreExistingICloudData()
        selectedTab = .trip
      } catch {
        iCloudCheckState = .failed(error.localizedDescription)
        restoreMessage = error.localizedDescription
      }
    }
  }

  private func advance() {
    guard canContinue,
          var next = NativeOnboardingStep(rawValue: step.rawValue + 1) else { return }
    // The income-tax-band step is UK-only (basic/higher rate); the US engine
    // works from actual profit and wages instead.
    if next == .incomeBracket, country == .us,
       let skipped = NativeOnboardingStep(rawValue: next.rawValue + 1) {
      next = skipped
    }
    if step == .locationPermission, !locationRequester.hasAlwaysAuthorization {
      autoTrackTrips = false
      enhancedAutoTracking = false
    }
    // No point asking for location access for a feature the driver just
    // turned off on the step before.
    if next == .locationPermission, !autoTrackTrips,
       let skipped = NativeOnboardingStep(rawValue: next.rawValue + 1) {
      next = skipped
    }
    hideKeyboard()
    step = next
  }

  private func goBack() {
    guard var previous = NativeOnboardingStep(rawValue: step.rawValue - 1) else { return }
    if previous == .incomeBracket, country == .us,
       let skipped = NativeOnboardingStep(rawValue: previous.rawValue - 1) {
      previous = skipped
    }
    if previous == .locationPermission, !autoTrackTrips,
       let skipped = NativeOnboardingStep(rawValue: previous.rawValue - 1) {
      previous = skipped
    }
    hideKeyboard()
    step = previous
  }

  private func finish(destination: NativeTab) {
    hideKeyboard()
    selectedTab = destination
    let automaticTrackingEnabled = autoTrackTrips && locationRequester.hasAlwaysAuthorization
    store.completeOnboarding(
      name: name,
      defaultVehicle: vehicle,
      platforms: orderedPlatforms,
      taxCountry: country,
      region: region,
      expenseMethod: expenseMethod,
      usState: usState,
      incomeBracket: incomeBracket,
      autoTrackTrips: automaticTrackingEnabled,
      enhancedAutoTracking: automaticTrackingEnabled && enhancedAutoTracking,
      workingDays: workingDays
    )
    if iCloudSyncEnabled {
      store.setICloudSyncEnabled(true)
    }
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

  private func incomeBracketSubtitle(for bracket: NativeIncomeBracket) -> String {
    switch bracket {
    case .basic:
      return "Uses a 20% marginal estimate"
    case .higher:
      return region == .scotland ? "Uses a 42% Scottish higher-rate estimate" : "Uses a 40% higher-rate estimate"
    }
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
  var iconAssetName: String? = nil
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        iconView

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

  @ViewBuilder
  private var iconView: some View {
    if let iconAssetName {
      Image(iconAssetName)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    } else {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(selected ? OkkleColor.brandDark : OkkleColor.muted)
        .frame(width: 38, height: 38)
        .background(selected ? OkkleColor.mint : Color(uiColor: .tertiarySystemBackground), in: Circle())
    }
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
