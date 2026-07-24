import ActivityKit
import SwiftUI
import WidgetKit

struct OkkleTripWidgetEntry: TimelineEntry {
  let date: Date
  let state: NativeTripWidgetState
}

struct OkkleTripWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> OkkleTripWidgetEntry {
    OkkleTripWidgetEntry(date: Date(), state: .inactive)
  }

  func getSnapshot(in context: Context, completion: @escaping (OkkleTripWidgetEntry) -> Void) {
    completion(OkkleTripWidgetEntry(date: Date(), state: NativeTripWidgetStore.read()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<OkkleTripWidgetEntry>) -> Void) {
    let entry = OkkleTripWidgetEntry(date: Date(), state: NativeTripWidgetStore.read())
    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
  }
}

struct OkkleTripWidgetView: View {
  let entry: OkkleTripWidgetEntry

  private var widgetAction: NativeTripWidgetAction {
    entry.state.isTripActive ? .end : .start
  }

  private var buttonTitle: String {
    entry.state.isTripActive ? "End Trip" : "Start Trip"
  }

  private var buttonSymbol: String {
    entry.state.isTripActive ? "stop.fill" : "location.north.fill"
  }

  var body: some View {
    Link(destination: NativeTripWidgetStore.widgetURL(for: widgetAction)) {
      VStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(.white.opacity(0.16))
            .frame(width: 52, height: 52)
          Image(systemName: buttonSymbol)
            .font(.system(size: 25, weight: .heavy))
            .symbolRenderingMode(.hierarchical)
        }

        Text(buttonTitle)
          .font(.system(size: 22, weight: .heavy, design: .rounded))
          .multilineTextAlignment(.center)
          .minimumScaleFactor(0.72)
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .widgetURL(NativeTripWidgetStore.widgetURL(for: widgetAction))
    .buttonStyle(.plain)
    .accessibilityLabel(buttonTitle)
    .containerBackground(for: .widget) {
      LinearGradient(
        colors: [
          Color(red: 0.33, green: 0.88, blue: 0.68),
          Color(red: 0.00, green: 0.66, blue: 0.49),
          Color(red: 0.00, green: 0.48, blue: 0.36)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }
}

struct OkkleTripWidget: Widget {
  let kind = "OkkleTripWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: OkkleTripWidgetProvider()) { entry in
      OkkleTripWidgetView(entry: entry)
    }
    .configurationDisplayName("Trip Button")
    .description("Start or end an Okkle trip.")
    .supportedFamilies([.systemSmall])
  }
}

// MARK: - Live Activity (Lock Screen + Dynamic Island)

private func okkleLiveActivityMiles(_ miles: Double) -> String {
  String(format: "%.1f mi", miles)
}

private func okkleLiveActivityElapsed(_ seconds: TimeInterval) -> String {
  let total = Int(seconds)
  let hours = total / 3600
  let minutes = (total % 3600) / 60
  if hours > 0 { return "\(hours)h \(minutes)m" }
  return "\(minutes)m"
}

private struct OkkleTripActivityButtons: View {
  let isDriving: Bool

  var body: some View {
    if #available(iOS 17.0, *) {
      HStack(spacing: 8) {
        if isDriving {
          Button(intent: OkklePauseTrackingLiveActivityIntent()) {
            Label("Pause", systemImage: "pause.fill")
              .font(.system(size: 15, weight: .bold))
              .frame(maxWidth: .infinity)
          }
          .tint(.white.opacity(0.16))
          .foregroundStyle(.white)
        } else {
          Button(intent: OkkleResumeTrackingLiveActivityIntent()) {
            Label("Resume", systemImage: "play.fill")
              .font(.system(size: 15, weight: .bold))
              .frame(maxWidth: .infinity)
          }
          .tint(.white.opacity(0.16))
          .foregroundStyle(.white)
        }

        Button(intent: OkkleStopTrackingLiveActivityIntent()) {
          Label("End", systemImage: "stop.fill")
            .font(.system(size: 15, weight: .bold))
            .frame(maxWidth: .infinity)
        }
        .tint(Color(red: 0.00, green: 0.66, blue: 0.49))
        .foregroundStyle(.white)
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)
    }
    // Pre-iOS 17: no interactive buttons (LiveActivityIntent needs 17+) —
    // tapping the banner still opens the app to control tracking there.
  }
}

private struct OkkleTripActivityLockScreenView: View {
  let attributes: OkkleTripActivityAttributes
  let state: OkkleTripActivityAttributes.ContentState

  private var status: String {
    if state.isDriving {
      return attributes.isAutomatic ? "Automatically tracking" : "Tracking trip"
    }
    if state.isPausedByUser == true {
      return attributes.isAutomatic ? "Automatic trip paused" : "Trip paused"
    }
    return "Checking if trip ended"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: "location.north.fill")
          .font(.system(size: 14, weight: .heavy))
        Text("Okkle")
          .font(.system(size: 14, weight: .heavy, design: .rounded))
        Spacer()
        Text(status)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
      }

      if attributes.isAutomatic {
        Label(
          "Automatic tracking enabled · \(attributes.automaticStartReason ?? "Driving detected")",
          systemImage: "sparkles"
        )
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color(red: 0.33, green: 0.88, blue: 0.68))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      }

      HStack {
        VStack(alignment: .leading, spacing: 1) {
          Text(okkleLiveActivityMiles(state.miles))
            .font(.system(size: 24, weight: .heavy, design: .rounded))
          Text("Distance")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 1) {
          Text(okkleLiveActivityElapsed(state.elapsed))
            .font(.system(size: 24, weight: .heavy, design: .rounded))
          Text(state.vehicleLabel)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }

      OkkleTripActivityButtons(isDriving: state.isDriving)
    }
    .padding(16)
  }
}

@available(iOS 16.1, *)
struct OkkleTripLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: OkkleTripActivityAttributes.self) { context in
      OkkleTripActivityLockScreenView(attributes: context.attributes, state: context.state)
        .activityBackgroundTint(Color(red: 0.02, green: 0.20, blue: 0.16))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 1) {
            Text(okkleLiveActivityMiles(context.state.miles))
              .font(.system(size: 18, weight: .heavy, design: .rounded))
            Text("Distance")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(.secondary)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 1) {
            Text(okkleLiveActivityElapsed(context.state.elapsed))
              .font(.system(size: 18, weight: .heavy, design: .rounded))
            Text(context.state.isDriving ? "Tracking" : (context.state.isPausedByUser == true ? "Paused" : "Checking"))
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(.secondary)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 8) {
            if context.attributes.isAutomatic {
              Label(
                "Automatic · \(context.attributes.automaticStartReason ?? "Driving detected")",
                systemImage: "sparkles"
              )
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Color(red: 0.33, green: 0.88, blue: 0.68))
              .lineLimit(1)
            }
            OkkleTripActivityButtons(isDriving: context.state.isDriving)
          }
        }
      } compactLeading: {
        Image(systemName: "location.north.fill")
      } compactTrailing: {
        Text(okkleLiveActivityMiles(context.state.miles))
          .font(.system(size: 13, weight: .bold, design: .rounded))
      } minimal: {
        Image(systemName: "location.north.fill")
      }
      // Just opens the app — ending the trip is what the "End" button is
      // for; a stray tap on the compact/minimal presentation
      // shouldn't end tracking by accident.
      .widgetURL(URL(string: "\(NativeTripWidgetStore.urlScheme)://")!)
      .keylineTint(Color(red: 0.00, green: 0.66, blue: 0.49))
    }
  }
}

@main
struct OkkleWidgetBundle: WidgetBundle {
  var body: some Widget {
    OkkleTripWidget()
    if #available(iOS 16.1, *) {
      OkkleTripLiveActivity()
    }
  }
}
