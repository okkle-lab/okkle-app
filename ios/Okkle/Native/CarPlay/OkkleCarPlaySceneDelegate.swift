import CarPlay
import Combine
import UIKit

@MainActor
final class OkkleCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var tripController: OkkleCarPlayTripController?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    NativeAutoTrackEngine.shared.configure(store: OkkleStore.shared)
    NativeVehicleConnectionMonitor.setCarPlayConnected(true)
    let controller = OkkleCarPlayTripController(interfaceController: interfaceController)
    tripController = controller
    controller.connect()
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    NativeVehicleConnectionMonitor.setCarPlayConnected(false)
    tripController = nil
  }
}

@MainActor
private final class OkkleCarPlayTripController {
  private weak var interfaceController: CPInterfaceController?
  private let store = OkkleStore.shared
  private let session = NativeTripSession.shared
  private let tripTemplate = CPListTemplate(title: "Okkle Trip", sections: [])
  private var cancellable: AnyCancellable?
  private var lastSavedSummary: String?

  init(interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
  }

  func connect() {
    cancellable = session.objectWillChange.sink { [weak self] _ in
      Task { @MainActor in
        self?.updateTripTemplate()
      }
    }

    guard store.settings.hasCompletedOnboarding else {
      showSignupRequired()
      return
    }

    interfaceController?.setRootTemplate(tripTemplate, animated: true, completion: nil)
    updateTripTemplate()
  }

  private func showSignupRequired() {
    let item = CPListItem(text: "Finish setup on iPhone", detailText: "Open Okkle on your phone before using CarPlay trip tracking.")
    let section = CPListSection(items: [item])
    let template = CPListTemplate(title: "Okkle", sections: [section])
    interfaceController?.setRootTemplate(template, animated: true, completion: nil)
  }

  private func updateTripTemplate() {
    guard store.settings.hasCompletedOnboarding else {
      showSignupRequired()
      return
    }

    tripTemplate.updateSections(tripSections)
  }

  private func startTrip() {
    lastSavedSummary = nil
    if session.phase == .summary {
      session.discard()
    }
    session.start(vehicle: store.settings.defaultVehicle)
    updateTripTemplate()
    showPermissionIfNeeded()
  }

  private func stopAndSaveTrip() {
    guard let trip = session.end(store: store) else {
      session.discard()
      lastSavedSummary = nil
      updateTripTemplate()
      return
    }
    store.addTrip(trip)
    lastSavedSummary = "Saved \(miles(trip.miles)) with \(gbp(trip.deduction, whole: true)) deduction."
    session.discard()
    updateTripTemplate()
  }

  private func showPermissionIfNeeded() {
    guard let message = session.permissionMessage else { return }
    let alert = CPAlertTemplate(
      titleVariants: [message],
      actions: [
        CPAlertAction(title: "OK", style: .cancel) { _ in }
      ]
    )
    interfaceController?.presentTemplate(alert, animated: true, completion: nil)
  }

  private var templateTitle: String {
    switch session.phase {
    case .setup:
      return "Okkle Trip"
    case .live:
      return "Tracking trip"
    case .paused:
      return "Trip paused"
    case .summary:
      return "Review trip"
    }
  }

  private var tripSections: [CPListSection] {
    var stats = [
      detailItem("Status", detail: templateTitle),
      detailItem("Miles", detail: miles(session.miles)),
      detailItem("Deduction", detail: gbp(store.calcDeduction(miles: session.miles, vehicle: session.vehicle), whole: true)),
      detailItem("Elapsed", detail: elapsedLabel(session.elapsed)),
      detailItem("Vehicle", detail: session.vehicle.label)
    ]
    if let lastSavedSummary {
      stats.insert(detailItem("Last trip", detail: lastSavedSummary), at: 1)
    }

    return [
      CPListSection(items: stats, header: "Trip", sectionIndexTitle: nil),
      CPListSection(items: tripActionItems, header: "Controls", sectionIndexTitle: nil)
    ]
  }

  private var tripActionItems: [CPListItem] {
    switch session.phase {
    case .setup, .summary:
      return [
        actionItem("Start Trip", detail: "Use \(store.settings.defaultVehicle.label) and begin mileage tracking") { [weak self] in
          self?.startTrip()
        }
      ]
    case .live, .paused:
      return [
        actionItem("Stop & Save Trip", detail: "Save to Records") { [weak self] in
          self?.stopAndSaveTrip()
        }
      ]
    }
  }

  private func detailItem(_ title: String, detail: String) -> CPListItem {
    let item = CPListItem(text: title, detailText: detail)
    item.isEnabled = false
    return item
  }

  private func actionItem(_ title: String, detail: String, action: @escaping () -> Void) -> CPListItem {
    let item = CPListItem(text: title, detailText: detail)
    item.accessoryType = .disclosureIndicator
    item.handler = { _, completion in
      Task { @MainActor in
        action()
        completion()
      }
    }
    return item
  }

  private func elapsedLabel(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
  }
}
