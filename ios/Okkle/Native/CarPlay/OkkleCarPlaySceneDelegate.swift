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
    let controller = OkkleCarPlayTripController(interfaceController: interfaceController)
    tripController = controller
    controller.connect()
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
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
  private var completedTrip: NativeTrip?

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

    interfaceController?.setRootTemplate(tripTemplate, animated: true)
    updateTripTemplate()
  }

  private func showSignupRequired() {
    let item = CPListItem(text: "Finish setup on iPhone", detailText: "Open Okkle on your phone before using CarPlay trip tracking.")
    let section = CPListSection(items: [item])
    let template = CPListTemplate(title: "Okkle", sections: [section])
    interfaceController?.setRootTemplate(template, animated: true)
  }

  private func updateTripTemplate() {
    guard store.settings.hasCompletedOnboarding else {
      showSignupRequired()
      return
    }

    tripTemplate.updateSections(tripSections)
  }

  private func startTrip() {
    completedTrip = nil
    session.start(vehicle: store.settings.defaultVehicle)
    updateTripTemplate()
    showPermissionIfNeeded()
  }

  private func pauseTrip() {
    session.pause()
    updateTripTemplate()
  }

  private func resumeTrip() {
    session.resume()
    updateTripTemplate()
  }

  private func endTrip() {
    completedTrip = session.end(store: store)
    updateTripTemplate()
    guard completedTrip != nil else { return }
    showEndTripConfirmation()
  }

  private func showPermissionIfNeeded() {
    guard let message = session.permissionMessage else { return }
    let alert = CPAlertTemplate(
      titleVariants: [message],
      actions: [
        CPAlertAction(title: "OK", style: .cancel) { _ in }
      ]
    )
    interfaceController?.presentTemplate(alert, animated: true)
  }

  private func showEndTripConfirmation() {
    let alert = CPAlertTemplate(
      titleVariants: ["Save this trip?", completedTripSummary],
      actions: [
        CPAlertAction(title: "Save", style: .default) { [weak self] _ in
          self?.saveCompletedTrip()
        },
        CPAlertAction(title: "Continue", style: .cancel) { [weak self] _ in
          self?.continueTrip()
        },
        CPAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
          self?.discardTrip()
        }
      ]
    )
    interfaceController?.presentTemplate(alert, animated: true)
  }

  private func saveCompletedTrip() {
    if let completedTrip {
      store.addTrip(completedTrip)
    }
    completedTrip = nil
    session.discard()
    updateTripTemplate()
  }

  private func continueTrip() {
    completedTrip = nil
    session.continueTrackingAfterEndReview()
    updateTripTemplate()
  }

  private func discardTrip() {
    completedTrip = nil
    session.discard()
    updateTripTemplate()
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
    let stats = [
      detailItem("Status", detail: templateTitle),
      detailItem("Miles", detail: miles(session.miles)),
      detailItem("Deduction", detail: gbp(store.calcDeduction(miles: session.miles, vehicle: session.vehicle), whole: true)),
      detailItem("Elapsed", detail: elapsedLabel(session.elapsed)),
      detailItem("Vehicle", detail: session.vehicle.label)
    ]

    return [
      CPListSection(items: stats, header: "Trip", sectionIndexTitle: nil),
      CPListSection(items: tripActionItems, header: "Controls", sectionIndexTitle: nil)
    ]
  }

  private var tripActionItems: [CPListItem] {
    switch session.phase {
    case .setup, .summary:
      return [
        actionItem("Start Trip", detail: "Begin mileage tracking") { [weak self] in
          self?.startTrip()
        }
      ]
    case .live:
      return [
        actionItem("Pause Trip", detail: "Keep this trip open") { [weak self] in
          self?.pauseTrip()
        },
        actionItem("End Trip", detail: "Review before saving") { [weak self] in
          self?.endTrip()
        }
      ]
    case .paused:
      return [
        actionItem("Resume Trip", detail: "Continue tracking") { [weak self] in
          self?.resumeTrip()
        },
        actionItem("End Trip", detail: "Review before saving") { [weak self] in
          self?.endTrip()
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

  private var completedTripSummary: String {
    guard let completedTrip else { return "No trip distance recorded." }
    return "\(miles(completedTrip.miles)) with \(gbp(completedTrip.deduction, whole: true)) deduction."
  }

  private func elapsedLabel(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
  }
}
