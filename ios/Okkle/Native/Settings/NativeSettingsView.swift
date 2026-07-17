import CoreLocation
import MapKit
import SwiftUI
import UIKit
struct NativeSettingsPlatformsSection: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var newPlatform = ""
  @State private var showOtherPlatformEntry = false

  private var customPlatforms: [String] {
    store.settings.platforms.filter { platform in
      !nativeOnboardingPlatforms.contains { $0.caseInsensitiveCompare(platform) == .orderedSame }
    }
  }

  var body: some View {
    Section {
      ForEach(nativeOnboardingPlatforms.filter { $0 != "Other" }, id: \.self) { platform in
        Toggle(isOn: platformSelectionBinding(platform)) {
          Label(platform, systemImage: nativePlatformSymbol(platform))
        }
      }

      if !customPlatforms.isEmpty {
        ForEach(customPlatforms, id: \.self) { platform in
          Text(platform)
        }
        .onDelete(perform: deleteCustomPlatforms)
      }

      Toggle(isOn: $showOtherPlatformEntry) {
        Label("Other", systemImage: nativePlatformSymbol("Other"))
      }

      if showOtherPlatformEntry {
        HStack {
          TextField("Delivery app name", text: $newPlatform)
            .textInputAutocapitalization(.words)
          Button("Add", action: addCustomPlatform)
            .disabled(newPlatform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    } header: {
      Text("Platforms")
    } footer: {
      Text("Choose the platforms you use for logging. Turn on Other to add a custom delivery app.")
    }
    .onAppear(perform: removePlaceholderPlatform)
  }

  private func platformSelectionBinding(_ platform: String) -> Binding<Bool> {
    Binding(
      get: {
        store.settings.platforms.contains { $0.caseInsensitiveCompare(platform) == .orderedSame }
      },
      set: { isSelected in
        setPlatform(platform, selected: isSelected)
      }
    )
  }

  private func setPlatform(_ platform: String, selected: Bool) {
    if selected {
      store.settings.platforms = uniqueStrings(store.settings.platforms + [platform])
      return
    }

    let updated = store.settings.platforms.filter { $0.caseInsensitiveCompare(platform) != .orderedSame }
    guard !updated.isEmpty else { return }
    store.settings.platforms = updated
  }

  private func addCustomPlatform() {
    let clean = newPlatform.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    store.settings.platforms = uniqueStrings(store.settings.platforms + [clean])
    newPlatform = ""
    showOtherPlatformEntry = false
  }

  private func deleteCustomPlatforms(at offsets: IndexSet) {
    let selectedCustomPlatforms = customPlatforms
    let removed = offsets.compactMap { index in
      selectedCustomPlatforms.indices.contains(index) ? selectedCustomPlatforms[index] : nil
    }
    let updated = store.settings.platforms.filter { platform in
      !removed.contains { $0.caseInsensitiveCompare(platform) == .orderedSame }
    }
    store.settings.platforms = updated.isEmpty ? ["Uber Eats"] : updated
  }

  private func removePlaceholderPlatform() {
    let updated = store.settings.platforms.filter { $0.caseInsensitiveCompare("Other") != .orderedSame }
    guard updated.count != store.settings.platforms.count else { return }
    store.settings.platforms = updated.isEmpty ? ["Uber Eats"] : updated
  }
}

struct NativeSettingsOtherIncomeField: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var text = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Other income this tax year")
      NativeNumberDoneTextField(text: $text, placeholder: "0.00")
        .frame(height: 34)
      Text("Wages or other PAYE income. Courier profit is taxed on top of this, matching the 1.0 tax estimate model.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .onAppear {
      text = store.settings.otherIncome > 0 ? String(format: "%.2f", store.settings.otherIncome) : ""
    }
    .onChange(of: text) { value in
      store.settings.otherIncome = max(0, Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0)
    }
  }
}

/// Settings home — a menu of categories, matching version 1's structure. Each
/// row pushes to its own detail page.
struct NativeSettingsView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          NativeSettingsProfileHeader()
            .listRowInsets(EdgeInsets(top: 22, leading: 0, bottom: 16, trailing: 0))
            .listRowBackground(Color.clear)
        }

        Section {
          menuRow("Profile details") { NativeProfileSettingsView() }
        }

        Section {
          menuRow("Tax profile") { NativeTaxSettingsView() }
          menuRow("Automatic tracking") { NativeAutoTrackSettingsView() }
          menuRow("Insights and Reminders") { NativeInsightsSettingsView() }
          menuRow("Export & share") { NativeExportSettingsView() }
        } header: {
          Text("Settings")
        }

        Section {
          menuRow("Data & backup") { NativeDataSettingsView() }
        } header: {
          Text("Privacy")
        } footer: {
          Text("Your Okkle data stays on this device unless you choose to export or back it up.")
        }

        Section {
          menuRow("Help & feedback") { NativeHelpSettingsView() }
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          NativeSettingsCloseButton {
            dismiss()
          }
        }
      }
    }
  }

  private func menuRow<Destination: View>(_ title: String, @ViewBuilder destination: () -> Destination) -> some View {
    NavigationLink {
      destination()
    } label: {
      Text(title)
    }
  }
}

private struct NativeSettingsCloseButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 15, weight: .bold))
    }
    .accessibilityLabel("Close")
  }
}

struct NativeSettingsProfileHeader: View {
  @EnvironmentObject private var store: OkkleStore

  private var displayName: String {
    let name = store.settings.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "Profile" : name
  }

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "person.crop.circle.fill")
        .font(.system(size: 64, weight: .regular))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(OkkleColor.brand)
        .shadow(color: OkkleColor.brand.opacity(0.34), radius: 18, y: 8)
        .shadow(color: OkkleColor.brand.opacity(0.22), radius: 34, y: 14)

      Text(displayName)
        .font(.title2.weight(.semibold))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
  }
}

// MARK: Profile

struct NativeProfileSettingsView: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    Form {
      Section("Profile") {
        TextField("Name", text: Binding(
          get: { store.settings.name },
          set: { store.settings.name = $0 }
        ))

        Picker("Default vehicle", selection: Binding(
          get: { store.settings.defaultVehicle },
          set: { store.settings.defaultVehicle = $0 }
        )) {
          ForEach(NativeVehicle.allCases) { vehicle in
            Label(vehicle.label, systemImage: vehicle.symbol).tag(vehicle)
          }
        }
      }

      NativeSettingsPlatformsSection()
    }
    .navigationTitle("Profile details")
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: Tax settings

struct NativeTaxSettingsView: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    Form {
      Section {
        Picker("Region", selection: Binding(
          get: { store.settings.region },
          set: { store.settings.region = $0 }
        )) {
          ForEach(NativeRegion.allCases) { Text($0.label).tag($0) }
        }

        Picker("Income tax band", selection: Binding(
          get: { store.settings.incomeBracket },
          set: { store.settings.incomeBracket = $0 }
        )) {
          ForEach(NativeIncomeBracket.allCases) { bracket in
            Text(bracket.label).tag(bracket)
          }
        }

        NativeSettingsOtherIncomeField()
      } footer: {
        Text("Region and band set your tax saved. Estimated tax due also uses the other income field.")
      }

      Section {
        NativeNumberDoneTextField(text: Binding(
          get: { store.settings.accountantUTR },
          set: { store.settings.accountantUTR = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        ), placeholder: "10-digit HMRC reference", keyboardType: .numberPad)
        .frame(height: 34)

        TextField("QQ 12 34 56 C", text: Binding(
          get: { store.settings.accountantNINumber },
          set: { store.settings.accountantNINumber = $0.uppercased() }
        ))
        .textInputAutocapitalization(.characters)

        TextField("Home or business address", text: Binding(
          get: { store.settings.accountantAddress },
          set: { store.settings.accountantAddress = $0 }
        ), axis: .vertical)
        .lineLimit(2...4)

        TextField("Delivery courier", text: Binding(
          get: { store.settings.accountantBusinessDescription },
          set: { store.settings.accountantBusinessDescription = $0 }
        ))
      } header: {
        Text("Accountant pack details")
      } footer: {
        Text("Optional. These stay on this phone and appear on the accountant pack PDF cover page when you export it.")
      }
    }
    .navigationTitle("Tax profile")
    .navigationBarTitleDisplayMode(.inline)
    .nativeKeyboardDoneToolbar()
  }
}

// MARK: Automatic tracking

struct NativeAutoTrackSettingsView: View {
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared

  var body: some View {
    Form {
      Section {
        Toggle("Automatic trip tracking", isOn: Binding(
          get: { store.settings.autoTrackTrips },
          set: { enabled in
            store.settings.autoTrackTrips = enabled
            if enabled {
              store.settings.enhancedAutoTracking = true
              if autoTrack.locationAuthorizationStatus != .authorizedAlways {
                autoTrack.requestAlwaysLocationAuthorization()
              }
            }
          }
        ))

        if store.settings.autoTrackTrips {
          NativeWorkingDaysPicker(days: Binding(
            get: { store.settings.workingDays },
            set: { store.settings.workingDays = $0 }
          ))
        }
      } footer: {
        Text("On your working days Okkle starts tracking a trip automatically when it detects you driving, so you never forget. Turn it off to track every trip by hand.")
      }

      if store.settings.autoTrackTrips, autoTrack.locationAuthorizationStatus != .authorizedAlways {
        Section {
          Label("Automatic tracking is waiting for Always location access.", systemImage: "location.slash.fill")
          Button(autoTrack.locationAuthorizationStatus == .denied || autoTrack.locationAuthorizationStatus == .restricted
                 ? "Open Location Settings"
                 : "Allow Background Tracking") {
            if autoTrack.locationAuthorizationStatus == .denied || autoTrack.locationAuthorizationStatus == .restricted {
              if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
              }
            } else {
              autoTrack.requestAlwaysLocationAuthorization()
            }
          }
        } footer: {
          Text("Okkle does not partially run automatic tracking with While Using access because iOS cannot reliably wake a closed app for a new trip.")
        }
      }

      if store.settings.autoTrackTrips {
        Section {
          Toggle("Enhanced automatic tracking", isOn: Binding(
            get: { store.settings.enhancedAutoTracking },
            set: { store.settings.enhancedAutoTracking = $0 }
          ))
        } footer: {
          Text("Improves automatic trip accuracy using the system Car Audio route, including CarPlay audio, so headphones and speakers cannot start a trip by mistake.")
        }
      }

      Section {
        Toggle("Auto-complete stopped manual trips", isOn: Binding(
          get: { store.settings.manualTripAutoComplete },
          set: { store.settings.manualTripAutoComplete = $0 }
        ))
      } header: {
        Text("Manual trips")
      } footer: {
        Text("When a trip you started by hand has been stationary for a while, Okkle can save it automatically instead of asking you to end it.")
      }

      if store.settings.autoTrackTrips {
        NativeExcludedPlacesSection()
      }

      Section {
        NavigationLink {
          NativeAutoTrackDiagnosticsView()
        } label: {
          Label("Tracking diagnostics", systemImage: "waveform.path.ecg")
        }
      } header: {
        Text("Diagnostics")
      }
    }
    .navigationTitle("Automatic tracking")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { autoTrack.refresh() }
  }
}

private struct NativeAutoTrackDiagnosticsView: View {
  @ObservedObject private var diagnostics = NativeAutoTrackDiagnostics.shared
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared
  @State private var showClearConfirmation = false

  var body: some View {
    List {
      Section("Current status") {
        LabeledContent("Tracking", value: trackingStatus)
        LabeledContent("Location", value: authorizationStatus)
      }

      Section {
        if diagnostics.events.isEmpty {
          Label("No tracking events recorded", systemImage: "clock.badge.questionmark")
            .foregroundStyle(.secondary)
        } else {
          ForEach(diagnostics.events) { event in
            diagnosticRow(event)
          }
        }
      } header: {
        Text("Recent events")
      } footer: {
        Text("Events are kept on this device for seven days. Location coordinates are not recorded.")
      }

      if !diagnostics.events.isEmpty {
        Section {
          Button("Clear diagnostics", role: .destructive) {
            showClearConfirmation = true
          }
        }
      }
    }
    .navigationTitle("Tracking diagnostics")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        ShareLink(
          item: diagnostics.exportText,
          subject: Text("Okkle tracking diagnostics")
        ) {
          Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share diagnostics")
        .disabled(diagnostics.events.isEmpty)
      }
    }
    .confirmationDialog("Clear tracking diagnostics?", isPresented: $showClearConfirmation) {
      Button("Clear diagnostics", role: .destructive) {
        diagnostics.clear()
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private func diagnosticRow(_ event: NativeAutoTrackDiagnosticEvent) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: eventSymbol(event.kind))
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(eventColor(event.kind))
        .frame(width: 28, height: 28)
        .background(eventColor(event.kind).opacity(0.12), in: Circle())

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(event.title)
            .font(.body.weight(.semibold))
          Spacer(minLength: 8)
          Text(event.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute().second())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(event.detail)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 3)
  }

  private var trackingStatus: String {
    if autoTrack.shiftPhase != .idle {
      return autoTrack.shiftPhase.rawValue.capitalized
    }
    if autoTrack.vehicleStartArmed { return "Armed" }
    return "Idle"
  }

  private var authorizationStatus: String {
    switch autoTrack.locationAuthorizationStatus {
    case .notDetermined: return "Not determined"
    case .restricted: return "Restricted"
    case .denied: return "Denied"
    case .authorizedAlways: return "Always"
    case .authorizedWhenInUse: return "While Using"
    @unknown default: return "Unknown"
    }
  }

  private func eventSymbol(_ kind: String) -> String {
    if kind.hasPrefix("gps.error") || kind.contains("rejected") { return "exclamationmark.triangle.fill" }
    if kind.hasPrefix("vehicle") { return "car.fill" }
    if kind.hasPrefix("motion") { return "waveform.path.ecg" }
    if kind.hasPrefix("handoff") { return "arrow.left.arrow.right" }
    if kind.contains("started") || kind.contains("resumed") { return "location.fill" }
    if kind.contains("ended") { return "stop.circle.fill" }
    return "clock.arrow.circlepath"
  }

  private func eventColor(_ kind: String) -> Color {
    if kind.hasPrefix("gps.error") || kind.contains("rejected") { return OkkleColor.red }
    if kind.hasPrefix("vehicle") { return OkkleColor.brand }
    if kind.hasPrefix("motion") { return OkkleColor.blue }
    if kind.hasPrefix("handoff") { return .orange }
    return .secondary
  }
}

// MARK: Insights

struct NativeInsightsSettingsView: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    Form {
      Section {
        Toggle("Insights", isOn: Binding(
          get: { store.settings.insightsEnabled },
          set: { store.settings.insightsEnabled = $0 }
        ))
      } header: {
        Text("AI insights")
      } footer: {
        Text("Shows AI guidance in the Insights tab using your trips and records.")
      }

      Section {
        Toggle("Pre-shift heads-up", isOn: Binding(
          get: { store.settings.insightsEnabled && store.settings.autoTrackTrips && store.settings.preShiftAlerts },
          set: { enabled in
            guard store.settings.insightsEnabled, store.settings.autoTrackTrips else { return }
            store.settings.preShiftAlerts = enabled
          }
        ))
        .disabled(!store.settings.insightsEnabled || !store.settings.autoTrackTrips)
        .opacity(store.settings.insightsEnabled && store.settings.autoTrackTrips ? 1 : 0.48)

        Toggle("Logging reminder", isOn: Binding(
          get: { store.settings.loggingReminder },
          set: { store.settings.loggingReminder = $0 }
        ))

        if store.settings.loggingReminder {
          Picker("Frequency", selection: Binding(
            get: { store.settings.logFrequency },
            set: { store.settings.logFrequency = $0 }
          )) {
            ForEach(NativeLogFrequency.allCases) { frequency in
              Text(frequency.label).tag(frequency)
            }
          }

          Picker("Reminder day", selection: Binding(
            get: { store.settings.reminderDay },
            set: { store.settings.reminderDay = $0 }
          )) {
            ForEach(0..<Calendar.current.shortWeekdaySymbols.count, id: \.self) { index in
              Text(Calendar.current.shortWeekdaySymbols[index]).tag(index)
            }
          }
        }

        Toggle("Tax deadline reminders", isOn: Binding(
          get: { store.settings.taxDeadlineReminders },
          set: { store.settings.taxDeadlineReminders = $0 }
        ))
      } header: {
        Text("Insight notifications")
      } footer: {
        Text(!store.settings.insightsEnabled
             ? "Turn on Insights to use pre-shift heads-up suggestions."
             : store.settings.autoTrackTrips
             ? "Pre-shift heads-up uses your trip patterns to suggest when and roughly where to head. Logging and tax reminders keep the data behind Insights fresh."
             : "Turn on automatic trip tracking to use pre-shift heads-up suggestions.")
      }

      Section {
        Toggle("Siri trip tracking", isOn: Binding(
          get: { store.settings.siriTripTrackingEnabled },
          set: { store.settings.siriTripTrackingEnabled = $0 }
        ))
      } header: {
        Text("Voice automation")
      } footer: {
        Text("Allow Siri and Shortcuts to start or resume trip tracking with your default vehicle.")
      }

      Section {
        Label("Hey Siri, track this trip with Okkle", systemImage: "quote.bubble")
        Label("Hey Siri, start tracking this trip with Okkle", systemImage: "quote.bubble")
      } header: {
        Text("Example phrases")
      }
    }
    .navigationTitle("Insights and Reminders")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Places the driver flags as not-work — home, a regular break spot — so
/// automatic tracking never mistakes a place they simply visit often (rather
/// than earn at) for a good "where to go" suggestion. Left empty, the app
/// guesses a likely home location itself from dwell patterns.
struct NativeExcludedPlacesSection: View {
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var locator = NativeOneShotLocator.shared
  @State private var label = ""
  @State private var address = ""
  @State private var isGeocoding = false
  @State private var errorMessage: String?

  var body: some View {
    Section {
      if !store.settings.excludedPlaces.isEmpty {
        ForEach(store.settings.excludedPlaces) { place in
          VStack(alignment: .leading, spacing: 6) {
            NativeExcludedPlaceMapRepresentable(
              coordinate: place.coordinate,
              onDragEnd: { moved(place.id, to: $0) }
            )
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
              Text(place.label)
                .font(.subheadline.weight(.semibold))
              Spacer(minLength: 10)
              Button(role: .destructive) {
                removePlace(place.id)
              } label: {
                Label("Remove \(place.label)", systemImage: "trash")
                  .labelStyle(.iconOnly)
              }
              .buttonStyle(.borderless)
              .accessibilityLabel("Remove \(place.label)")
            }
            if let address = place.address {
              Text(address).font(.footnote).foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 4)
        }
        .onDelete { offsets in
          store.settings.excludedPlaces.remove(atOffsets: offsets)
        }
      }

      TextField("Label, e.g. Home", text: $label)
        .textInputAutocapitalization(.words)
      TextField("Address", text: $address)
        .textInputAutocapitalization(.words)

      if let errorMessage {
        Text(errorMessage).font(.footnote).foregroundStyle(.red)
      }

      HStack {
        Button("Add", action: addByAddress)
          .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isGeocoding)
        Spacer()
        Button("Use current location", action: addByCurrentLocation)
          .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || locator.coordinate == nil)
      }
    } header: {
      Text("Places to leave out")
    } footer: {
      Text("Add home or anywhere you stop often that isn't work — they'll never be suggested as a place to go and earn. Drag the pin if it lands somewhere off.")
    }
    .onAppear { locator.request() }
  }

  private func addByAddress() {
    let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanLabel.isEmpty, !cleanAddress.isEmpty else { return }
    isGeocoding = true
    errorMessage = nil
    CLGeocoder().geocodeAddressString(cleanAddress) { placemarks, _ in
      Task { @MainActor in
        isGeocoding = false
        guard let placemark = placemarks?.first, let coordinate = placemark.location?.coordinate else {
          errorMessage = "Couldn't find that address."
          return
        }
        save(label: cleanLabel, coordinate: coordinate, address: Self.formattedAddress(placemark))
      }
    }
  }

  private func addByCurrentLocation() {
    let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanLabel.isEmpty, let coordinate = locator.coordinate else { return }
    save(label: cleanLabel, coordinate: coordinate, address: nil)
    resolveAddress(for: coordinate) { resolved in
      guard let resolved, let index = store.settings.excludedPlaces.lastIndex(where: { $0.label == cleanLabel }) else { return }
      store.settings.excludedPlaces[index].address = resolved
    }
  }

  private func save(label: String, coordinate: CLLocationCoordinate2D, address: String?) {
    // "Home" is treated as a singleton — matching by anything at all keyed
    // off it (auto-detection, area-suggestion origin) only makes sense if
    // there's exactly one. Saving a new one replaces the old rather than
    // quietly stacking up a second "Home" pin at a different address.
    if label.caseInsensitiveCompare("Home") == .orderedSame {
      store.settings.excludedPlaces.removeAll { $0.label.caseInsensitiveCompare("Home") == .orderedSame }
    }
    store.settings.excludedPlaces.append(NativeExcludedPlace(
      label: label, latitude: coordinate.latitude, longitude: coordinate.longitude, address: address
    ))
    self.label = ""
    self.address = ""
  }

  private func removePlace(_ id: UUID) {
    store.settings.excludedPlaces.removeAll { $0.id == id }
  }

  /// Dragging the pin corrects the coordinate directly — geocoding can land a
  /// little off, and re-resolving the address confirms the new spot matched.
  private func moved(_ id: UUID, to coordinate: CLLocationCoordinate2D) {
    guard let index = store.settings.excludedPlaces.firstIndex(where: { $0.id == id }) else { return }
    store.settings.excludedPlaces[index].latitude = coordinate.latitude
    store.settings.excludedPlaces[index].longitude = coordinate.longitude
    resolveAddress(for: coordinate) { resolved in
      guard let resolved, let index = store.settings.excludedPlaces.firstIndex(where: { $0.id == id }) else { return }
      store.settings.excludedPlaces[index].address = resolved
    }
  }

  private func resolveAddress(for coordinate: CLLocationCoordinate2D, completion: @escaping (String?) -> Void) {
    CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
      Task { @MainActor in completion(placemarks?.first.flatMap(Self.formattedAddress)) }
    }
  }

  private static func formattedAddress(_ placemark: CLPlacemark) -> String? {
    let line1 = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
    let line2 = [placemark.locality ?? placemark.subLocality, placemark.postalCode].compactMap { $0 }.joined(separator: " ")
    let combined = [line1, line2].filter { !$0.isEmpty }.joined(separator: ", ")
    return combined.isEmpty ? nil : combined
  }
}

/// A small draggable-pin map for correcting an excluded place's coordinate —
/// geocoding (from a typed address, or the device's current fix) can land a
/// little off, so the driver can drag it right rather than re-typing.
struct NativeExcludedPlaceMapRepresentable: UIViewRepresentable {
  var coordinate: CLLocationCoordinate2D
  var onDragEnd: (CLLocationCoordinate2D) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onDragEnd: onDragEnd) }

  func makeUIView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator
    mapView.isPitchEnabled = false
    mapView.showsCompass = false
    mapView.showsScale = false
    let annotation = MKPointAnnotation()
    annotation.coordinate = coordinate
    mapView.addAnnotation(annotation)
    mapView.setRegion(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)), animated: false)
    context.coordinator.annotation = annotation
    return mapView
  }

  func updateUIView(_ mapView: MKMapView, context: Context) {
    // Only move the pin from an external coordinate change (e.g. switching
    // rows) — not after a drag, which already updated the model to match.
    guard let annotation = context.coordinator.annotation,
          annotation.coordinate.latitude != coordinate.latitude || annotation.coordinate.longitude != coordinate.longitude else { return }
    annotation.coordinate = coordinate
  }

  final class Coordinator: NSObject, MKMapViewDelegate {
    let onDragEnd: (CLLocationCoordinate2D) -> Void
    weak var annotation: MKPointAnnotation?

    init(onDragEnd: @escaping (CLLocationCoordinate2D) -> Void) { self.onDragEnd = onDragEnd }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
      guard !(annotation is MKUserLocation) else { return nil }
      let identifier = "excludedPlacePin"
      let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
        ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
      view.annotation = annotation
      view.isDraggable = true
      view.markerTintColor = .systemGreen
      return view
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
      guard newState == .ending, let coordinate = view.annotation?.coordinate else { return }
      onDragEnd(coordinate)
    }
  }
}

// MARK: Siri & Shortcuts

struct NativeSiriSettingsView: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    Form {
      Section {
        Toggle("Siri trip tracking", isOn: Binding(
          get: { store.settings.siriTripTrackingEnabled },
          set: { store.settings.siriTripTrackingEnabled = $0 }
        ))
      } header: {
        Text("Voice automation")
      } footer: {
        Text("Allow Siri and Shortcuts to start or resume trip tracking with your default vehicle. Okkle opens when the shortcut runs and still needs location permission.")
      }

      Section {
        Label("Hey Siri, track this trip with Okkle", systemImage: "quote.bubble")
        Label("Hey Siri, start tracking this trip with Okkle", systemImage: "quote.bubble")
      } header: {
        Text("Example phrases")
      }
    }
    .navigationTitle("Siri & Shortcuts")
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: Reminders

struct NativeRemindersSettingsView: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    Form {
      Section {
        Toggle("Logging reminder", isOn: Binding(
          get: { store.settings.loggingReminder },
          set: { store.settings.loggingReminder = $0 }
        ))

        if store.settings.loggingReminder {
          Picker("Frequency", selection: Binding(
            get: { store.settings.logFrequency },
            set: { store.settings.logFrequency = $0 }
          )) {
            ForEach(NativeLogFrequency.allCases) { frequency in
              Text(frequency.label).tag(frequency)
            }
          }

          Picker("Reminder day", selection: Binding(
            get: { store.settings.reminderDay },
            set: { store.settings.reminderDay = $0 }
          )) {
            ForEach(0..<Calendar.current.shortWeekdaySymbols.count, id: \.self) { index in
              Text(Calendar.current.shortWeekdaySymbols[index]).tag(index)
            }
          }
        }
      } header: {
        Text("Logging")
      } footer: {
        Text("A gentle nudge to log your miles and pay so nothing slips through the week.")
      }

      Section {
        Toggle("Tax deadline reminders", isOn: Binding(
          get: { store.settings.taxDeadlineReminders },
          set: { store.settings.taxDeadlineReminders = $0 }
        ))
      } header: {
        Text("Deadlines")
      } footer: {
        Text("Alerts ahead of the key HMRC Self Assessment dates.")
      }
    }
    .navigationTitle("Reminders")
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: Export & share

struct NativeExportSettingsView: View {
  var body: some View {
    ScrollView {
      NativeExportCard()
        .padding(20)
    }
    .scrollIndicators(.hidden)
    .background { NativeBackground() }
    .navigationTitle("Export & share")
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: Data & backup

struct NativeDataSettingsView: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var backupBusy = false
  @State private var backupMessage: String?
  @State private var backupShareItem: NativeShareItem?
  @State private var backupExportDocument: NativeBackupDocument?
  @State private var backupExportFileName = nativeBackupFileName()
  @State private var showBackupExporter = false
  @State private var showBackupImporter = false
  @State private var showClearDataWarning = false

  var body: some View {
    Form {
      if let persistenceIssue = store.persistenceIssue {
        Section {
          Label {
            Text(persistenceIssue)
              .font(.footnote)
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          }

          Button {
            store.save()
          } label: {
            Label("Try saving again", systemImage: "arrow.clockwise")
          }
        } header: {
          Text("Local data")
        }
      }

      Section {
        Toggle("iCloud sync", isOn: Binding(
          get: { store.settings.iCloudSyncEnabled },
          set: { store.setICloudSyncEnabled($0) }
        ))

        HStack(alignment: .top, spacing: 12) {
          Image(systemName: iCloudSyncStatusSymbol)
            .foregroundStyle(iCloudSyncStatusTint)
          VStack(alignment: .leading, spacing: 4) {
            Text(store.iCloudSyncState.title)
              .font(.subheadline.weight(.semibold))
            Text(store.iCloudSyncState.detail)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

      } header: {
        Text("iCloud sync")
      }

      Section {
        Button {
          backupBusy = true
          switch nativeCreateBackup(store: store) {
          case .iCloud(let url):
            backupMessage = "Backed up to iCloud Drive > Okkle > Okkle Backups as \(url.lastPathComponent). It can take a moment to appear in Files."
          case .share(let item):
            backupShareItem = item
          case .failed(let message):
            backupMessage = message
          }
          backupBusy = false
        } label: {
          manualBackupLabel(
            backupBusy ? "Backing up..." : "Back up to iCloud",
            systemImage: "icloud.and.arrow.up",
            isDisabled: backupBusy || manualBackupDisabled
          )
        }
        .disabled(backupBusy || manualBackupDisabled)

        Button {
          prepareBackupExport()
        } label: {
          manualBackupLabel("Choose backup location", systemImage: "folder", isDisabled: manualBackupDisabled)
        }
        .disabled(manualBackupDisabled)

        Button {
          showBackupImporter = true
        } label: {
          manualBackupLabel("Load backup", systemImage: "icloud.and.arrow.down", isDisabled: manualBackupDisabled)
        }
        .disabled(manualBackupDisabled)
      } header: {
        Text("Backup & restore")
      } footer: {
        Text(manualBackupDisabled ? "Manual backup and restore are disabled while automatic iCloud sync is on." : "Creates a JSON backup you can save to Files or iCloud, or restore onto this device.")
      }

      Section {
        Button(role: .destructive) {
          showClearDataWarning = true
        } label: {
          Label("Clear all app data", systemImage: "trash")
        }
      } footer: {
        Text("Clearing removes everything and restarts sign-up.")
      }
    }
    .navigationTitle("Data & backup")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      store.refreshICloudSyncIfNeeded()
    }
    .sheet(item: $backupShareItem) { item in
      NativeShareSheet(items: item.urls)
    }
    .fileExporter(
      isPresented: $showBackupExporter,
      document: backupExportDocument,
      contentType: .json,
      defaultFilename: backupExportFileName
    ) { result in
      switch result {
      case .success:
        backupMessage = "Backup saved."
      case .failure(let error):
        backupMessage = "Could not save backup. \(error.localizedDescription)"
      }
    }
    .fileImporter(
      isPresented: $showBackupImporter,
      allowedContentTypes: [.json],
      allowsMultipleSelection: false
    ) { result in
      restoreBackup(from: result)
    }
    .alert("Backup", isPresented: Binding(
      get: { backupMessage != nil },
      set: { if !$0 { backupMessage = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(backupMessage ?? "")
    }
    .alert("Clear all app data?", isPresented: $showClearDataWarning) {
      Button("Cancel", role: .cancel) {}
      Button("Clear data", role: .destructive) {
        store.resetAllData()
      }
    } message: {
      Text("This permanently deletes your profile, settings, trips, earnings, expenses, mileage entries and routes from this device. The sign-up flow will restart. Create a backup first if you might need the data later.")
    }
  }

  private func prepareBackupExport() {
    do {
      backupExportFileName = nativeBackupFileName()
      backupExportDocument = NativeBackupDocument(data: try store.backupData())
      showBackupExporter = true
    } catch {
      backupMessage = "Could not prepare backup. \(error.localizedDescription)"
    }
  }

  private func restoreBackup(from result: Result<[URL], Error>) {
    guard !store.settings.iCloudSyncEnabled else {
      backupMessage = "Turn off iCloud sync before restoring a backup."
      return
    }
    do {
      guard let url = try result.get().first else { return }
      let didAccess = url.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }
      let data = try Data(contentsOf: url)
      let summary = try store.restoreBackupData(data)
      backupMessage = summary.message
    } catch {
      backupMessage = "Could not load backup. \(error.localizedDescription)"
    }
  }

  private var manualBackupDisabled: Bool {
    store.settings.iCloudSyncEnabled
  }

  private func manualBackupLabel(_ title: String, systemImage: String, isDisabled: Bool) -> some View {
    Label {
      Text(title)
        .foregroundStyle(isDisabled ? Color.secondary : Color.primary)
    } icon: {
      Image(systemName: systemImage)
        .foregroundStyle(isDisabled ? Color.secondary : OkkleColor.brand)
    }
  }

  private var iCloudSyncStatusSymbol: String {
    switch store.iCloudSyncState {
    case .disabled:
      return "icloud.slash"
    case .unavailable, .failed:
      return "exclamationmark.icloud"
    case .syncing, .waitingForDownload:
      return "icloud.and.arrow.up"
    case .synced:
      return "checkmark.icloud"
    }
  }

  private var iCloudSyncStatusTint: Color {
    switch store.iCloudSyncState {
    case .disabled:
      return .secondary
    case .unavailable, .failed:
      return .orange
    case .syncing, .waitingForDownload:
      return OkkleColor.brand
    case .synced:
      return .green
    }
  }
}

// MARK: Help & feedback

struct NativeHelpSettingsView: View {
  @Environment(\.openURL) private var openURL

  var body: some View {
    Form {
      Section {
        Button {
          openFeedback(problem: true)
        } label: {
          Label("Report a problem", systemImage: "exclamationmark.triangle")
        }
        Button {
          openFeedback(problem: false)
        } label: {
          Label("Suggest an improvement", systemImage: "lightbulb")
        }
      } footer: {
        Text("Opens your mail app to admin@okklelab.com.")
      }

      Section {
        NavigationLink {
          NativeAboutSettingsView()
        } label: {
          Label("About Okkle", systemImage: "info.circle")
        }
      }
    }
    .navigationTitle("Help & feedback")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func openFeedback(problem: Bool) {
    let subject = problem ? "[Okkle Problem]" : "[Okkle Suggestion]"
    let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
    guard let url = URL(string: "mailto:admin@okklelab.com?subject=\(encoded)") else { return }
    openURL(url)
  }
}

// MARK: About

struct NativeAboutSettingsView: View {
  var body: some View {
    Form {
      Section {
        HStack {
          Text("Version")
          Spacer()
          Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1")
            .foregroundStyle(.secondary)
        }
      }
      Section {
        Text("Okkle — mileage and tax tracking built for UK self-employed couriers. Your records stay on your device.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("About Okkle")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// A row of day chips (S M T W T F S) for choosing which weekdays auto-tracking
/// runs. Indices are 0 = Sunday … 6 = Saturday, matching Calendar's symbols.
struct NativeWorkingDaysPicker: View {
  @Binding var days: [Int]

  private let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Working days")
        .font(.subheadline.weight(.semibold))
      HStack(spacing: 6) {
        ForEach(0..<symbols.count, id: \.self) { index in
          let on = days.contains(index)
          Button {
            toggle(index)
          } label: {
            Text(symbols[index])
              .font(.system(size: 14, weight: .bold))
              .frame(maxWidth: .infinity)
              .frame(height: 38)
              .foregroundStyle(on ? Color.white : OkkleColor.muted)
              .background(on ? OkkleColor.brand : OkkleColor.brand.opacity(0.12), in: Circle())
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func toggle(_ index: Int) {
    if let at = days.firstIndex(of: index) {
      guard days.count > 1 else { return }   // keep at least one working day
      days.remove(at: at)
    } else {
      days = (days + [index]).sorted()
    }
  }
}

struct NativeEmptyState: View {
  let symbol: String
  let title: String
  let message: String

  var body: some View {
    NativeGlassCard {
      VStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 30, weight: .bold))
          .foregroundStyle(OkkleColor.brand)
          .frame(width: 68, height: 68)
          .background(OkkleColor.mint, in: Circle())
        Text(title)
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
        Text(message)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
    }
  }
}
