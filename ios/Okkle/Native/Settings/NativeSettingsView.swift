import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision
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

struct NativeSettingsView: View {
  @EnvironmentObject private var store: OkkleStore
  @Environment(\.dismiss) private var dismiss
  @State private var backupBusy = false
  @State private var backupMessage: String?
  @State private var backupShareItem: NativeShareItem?
  @State private var backupExportDocument: NativeBackupDocument?
  @State private var backupExportFileName = nativeBackupFileName()
  @State private var showBackupExporter = false
  @State private var showBackupImporter = false
  @State private var showClearDataWarning = false
  @State private var showDataClearedConfirmation = false

  var body: some View {
    NavigationStack {
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

          NavigationLink {
            NativeAccountantDetailsSettingsView()
          } label: {
            Label("Accountant details", systemImage: "person.text.rectangle")
          }
        }

        NativeSettingsPlatformsSection()

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
        } header: {
          Text("Tax settings")
        } footer: {
          Text("Region and band set your tax saved. Estimated tax due also uses the other income field.")
        }

        Section {
          Toggle("Automatic trip tracking", isOn: Binding(
            get: { store.settings.autoTrackTrips },
            set: { store.settings.autoTrackTrips = $0 }
          ))

          if store.settings.autoTrackTrips {
            NativeWorkingDaysPicker(days: Binding(
              get: { store.settings.workingDays },
              set: { store.settings.workingDays = $0 }
            ))
          }
        } header: {
          Text("Automatic tracking")
        } footer: {
          Text("On your working days Okkle starts tracking a trip automatically when it detects you driving, so you never forget. Turn it off to track every trip by hand.")
        }

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

          Toggle("Tax deadline reminders", isOn: Binding(
            get: { store.settings.taxDeadlineReminders },
            set: { store.settings.taxDeadlineReminders = $0 }
          ))
        } header: {
          Text("Reminders")
        } footer: {
          Text("Turn these on from the prompts in Insights, or manage them here.")
        }

        Section("Data & backup") {
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
            Label(backupBusy ? "Backing up..." : "Back up to iCloud", systemImage: "icloud.and.arrow.up")
          }
          .disabled(backupBusy)

          Text("Creates a JSON backup in iCloud Drive. If iCloud is not available, Okkle opens the native share sheet so you can save the backup to Files.")
            .font(.footnote)
            .foregroundStyle(.secondary)

          Button {
            prepareBackupExport()
          } label: {
            Label("Choose backup location", systemImage: "folder")
          }

          Text("Opens the native Files picker so you can save the backup directly into iCloud Drive or another folder.")
            .font(.footnote)
            .foregroundStyle(.secondary)

          Button {
            showBackupImporter = true
          } label: {
            Label("Load backup", systemImage: "icloud.and.arrow.down")
          }

          Text("Restores an Okkle JSON backup from iCloud Drive or Files onto this device.")
            .font(.footnote)
            .foregroundStyle(.secondary)

          Button(role: .destructive) {
            showClearDataWarning = true
          } label: {
            Label("Clear all app data", systemImage: "trash")
          }
        }

        Section("About") {
          HStack {
            Text("Version")
            Spacer()
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Settings")
      .sheet(item: $backupShareItem) { item in
        NativeShareSheet(items: [item.url])
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
          showDataClearedConfirmation = true
        }
      } message: {
        Text("This permanently deletes your profile, settings, trips, earnings, expenses, mileage entries and routes from this device. The sign-up flow will restart. Create a backup first if you might need the data later.")
      }
      .alert("Data cleared", isPresented: $showDataClearedConfirmation) {
        Button("OK", role: .cancel) {
          dismiss()
        }
      } message: {
        Text("Your data has been removed. Okkle will restart the sign-up flow.")
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
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

}

struct NativeAccountantDetailsSettingsView: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    Form {
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
    .navigationTitle("Accountant details")
    .navigationBarTitleDisplayMode(.inline)
    .nativeKeyboardDoneToolbar()
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
