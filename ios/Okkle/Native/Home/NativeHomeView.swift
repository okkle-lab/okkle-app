import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
struct NativeHomeView: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    NativeScreen(
      title: homeGreetingTitle,
      collapsedTitle: store.settings.name.isEmpty ? nil : "Home",
      subtitle: "Your tax saved this year and progress."
    ) {
      NativeGlassCard(cornerRadius: 32) {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Label("Tax saved this year", systemImage: "chart.line.uptrend.xyaxis")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(OkkleColor.brandDark)
            Spacer()
            Text(taxYearLabel(for: store.taxYear))
              .font(.caption.weight(.semibold))
              .foregroundStyle(OkkleColor.muted)
          }
          Text(headlineGbp(store.taxSaved))
            .font(.system(size: 58, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
            .minimumScaleFactor(0.55)
          Text("From \(miles(store.yearMiles)) and \(gbp(store.yearMileageDeduction, whole: true)) of mileage deductions.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
          ProgressView(value: min(1, store.yearMiles / 10_000))
            .tint(OkkleColor.brand)
        }
      }

      HStack(spacing: 12) {
        NativeMetricTile(title: "Mileage", value: miles(store.yearMiles), symbol: "road.lanes")
        NativeMetricTile(title: "Earnings", value: gbp(store.yearIncome, whole: true), symbol: "sterlingsign.circle.fill", color: .green)
      }

      NativeSectionTitle(title: "Progress", symbol: "sparkles")
      NativeGlassCard {
        VStack(alignment: .leading, spacing: 16) {
          progressRow("First 10k mileage band", value: min(1, store.yearMiles / 10_000), trailing: "\(Int(min(10_000, store.yearMiles)).formatted()) / 10,000 mi")
          progressRow("Records logged", value: min(1, Double(store.records.count) / 24), trailing: "\(store.records.count) entries")
          progressRow("Trips tracked", value: min(1, Double(store.trips.count) / 20), trailing: "\(store.trips.count) trips")
        }
      }

      NativeSectionTitle(title: "Recent activity", symbol: "clock")
      if store.history.isEmpty {
        NativeEmptyState(symbol: "tray", title: "No records yet", message: "Track a trip or log earnings and expenses to see your history here.")
      } else {
        NativeGlassCard {
          VStack(spacing: 0) {
            ForEach(store.history.prefix(4)) { item in
              NativeHistoryRow(item: item)
              if item.id != store.history.prefix(4).last?.id {
                Divider().padding(.leading, 52)
              }
            }
          }
        }
      }
    }
  }

  private var homeGreetingTitle: String {
    store.settings.name.isEmpty ? "Home" : "Hi, \(store.settings.name)"
  }

  @ViewBuilder
  private func progressRow(_ title: String, value: Double, trailing: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Text(trailing)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
      }
      ProgressView(value: value)
        .tint(OkkleColor.brand)
    }
  }

  private func taxYearLabel(for interval: DateInterval) -> String {
    let start = Calendar.current.component(.year, from: interval.start)
    let end = Calendar.current.component(.year, from: interval.end)
    return "\(start)/\(String(end).suffix(2))"
  }
}

let nativeExpenseCategories = [
  "Fuel",
  "Charging",
  "Parking",
  "Phone / data",
  "Insurance",
  "Maintenance / repairs",
  "Tyres",
  "Congestion charge",
  "ULEZ charge",
  "Insulated bag",
  "Waterproof gear",
  "Helmet / safety",
  "Phone mount",
  "App subscription",
]
