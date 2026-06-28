import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
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

struct NativeSettingsView: View {
  @EnvironmentObject private var store: OkkleStore
  @Environment(\.dismiss) private var dismiss
  @State private var backupBusy = false
  @State private var backupMessage: String?
  @State private var backupShareItem: NativeShareItem?
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

          Text("Used for tax saved and estimated tax due. Choose Higher if courier profit sits on top of higher-rate income.")
            .font(.footnote)
            .foregroundStyle(.secondary)

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

        Section("Data") {
          Button {
            backupBusy = true
            switch nativeCreateBackup(store: store) {
            case .iCloud(let url):
              backupMessage = "Backed up to iCloud Drive as \(url.lastPathComponent)."
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

          Button(role: .destructive) {
            showClearDataWarning = true
          } label: {
            Label("Clear all app data", systemImage: "trash")
          }
        }

        Section("Build") {
          HStack {
            Text("Version")
            Spacer()
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4")
              .foregroundStyle(.secondary)
          }
          Text("Native SwiftUI iPhone rebuild for the 0.4 branch.")
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Settings")
      .sheet(item: $backupShareItem) { item in
        NativeShareSheet(items: [item.url])
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

}

struct NativeAccountantDetailsSettingsView: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    Form {
      Section {
        TextField("10-digit HMRC reference", text: Binding(
          get: { store.settings.accountantUTR },
          set: { store.settings.accountantUTR = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        ))
        .keyboardType(.numberPad)

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
