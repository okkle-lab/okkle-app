import SwiftUI

struct WatchTripView: View {
  @EnvironmentObject private var connector: WatchTripConnector

  var body: some View {
    VStack(spacing: 10) {
      VStack(spacing: 2) {
        Text(connector.title)
          .font(.headline)
          .multilineTextAlignment(.center)
        Text(connector.subtitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      VStack(spacing: 0) {
        Text(connector.milesLabel)
          .font(.system(size: 32, weight: .heavy, design: .rounded))
          .minimumScaleFactor(0.7)
        Text(connector.elapsedLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)

      Button {
        connector.primaryAction()
      } label: {
        Label(connector.buttonTitle, systemImage: connector.buttonSymbol)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(connector.isTracking ? .red : Color(red: 0.03, green: 0.58, blue: 0.49))
      .disabled(connector.pendingCommand != nil)

      if !connector.permissionMessage.isEmpty {
        Text(connector.permissionMessage)
          .font(.caption2)
          .foregroundStyle(.orange)
          .multilineTextAlignment(.center)
      }
    }
    .padding(.vertical, 4)
    .onAppear {
      connector.configure()
    }
  }
}

#Preview {
  WatchTripView()
    .environmentObject(WatchTripConnector.shared)
}
