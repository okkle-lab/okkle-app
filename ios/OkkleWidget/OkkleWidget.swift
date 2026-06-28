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

@main
struct OkkleWidgetBundle: WidgetBundle {
  var body: some Widget {
    OkkleTripWidget()
  }
}
