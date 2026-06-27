import AppIntents
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

struct ToggleTripWidgetIntent: AppIntent {
  static var title: LocalizedStringResource = "Toggle trip"
  static var description = IntentDescription("Starts or ends an Okkle trip from the widget.")
  static var openAppWhenRun = true

  @Parameter(title: "Trip is active")
  var tripIsActive: Bool

  init() {
    tripIsActive = false
  }

  init(tripIsActive: Bool) {
    self.tripIsActive = tripIsActive
  }

  func perform() async throws -> some IntentResult {
    if tripIsActive {
      NativeTripWidgetStore.requestEndFromWidget()
    } else {
      NativeTripWidgetStore.requestStartFromWidget()
    }
    return .result()
  }
}

struct OkkleTripWidgetView: View {
  let entry: OkkleTripWidgetEntry

  private var buttonTitle: String {
    entry.state.isTripActive ? "End Trip" : "Start Trip"
  }

  private var buttonSymbol: String {
    entry.state.isTripActive ? "stop.fill" : "location.north.fill"
  }

  var body: some View {
    Button(intent: ToggleTripWidgetIntent(tripIsActive: entry.state.isTripActive)) {
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

@main
struct OkkleWidgetBundle: WidgetBundle {
  var body: some Widget {
    OkkleTripWidget()
  }
}
