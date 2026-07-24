import Foundation

struct NativeMileageTaxSavings {
  var miles: Double
  var mileageDeduction: Double
  var taxSaved: Double
}

@MainActor
enum NativeProgressSummary {
  static func weekly(store: OkkleStore, now: Date = Date(), calendar: Calendar = .current) -> NativeProgressTotals {
    let interval = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(
      start: calendar.startOfDay(for: now),
      duration: 7 * 24 * 60 * 60
    )
    return totals(
      records: store.records.filter { interval.contains($0.date) },
      trips: store.businessTrips.filter { interval.contains($0.startedAt) }
    )
  }

  static func yearToDate(store: OkkleStore) -> NativeProgressTotals {
    totals(records: store.yearRecords, trips: store.yearTrips)
  }

  static func allTime(store: OkkleStore) -> NativeProgressTotals {
    totals(records: store.records, trips: store.businessTrips)
  }

  static func mileageTaxSavings(store: OkkleStore, period: NativeProgressPeriod, now: Date = Date(), calendar: Calendar = .current) -> NativeMileageTaxSavings {
    switch period {
    case .weekly:
      let interval = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(
        start: calendar.startOfDay(for: now),
        duration: 7 * 24 * 60 * 60
      )
      return store.mileageTaxSavings(for: interval)
    case .yearToDate:
      return NativeMileageTaxSavings(
        miles: store.yearMiles,
        mileageDeduction: store.yearMileageDeduction,
        taxSaved: store.taxSaved
      )
    case .allTime:
      return store.mileageTaxSavings(for: nil)
    }
  }

  static func totals(records: [NativeRecord], trips: [NativeTrip]) -> NativeProgressTotals {
    let tripMiles = trips.reduce(0) { $0 + max(0, $1.miles) }
    let manualMiles = records.reduce(0) { partial, record in
      guard record.kind == .mileage else { return partial }
      return partial + max(0, record.miles ?? 0)
    }
    return NativeProgressTotals(
      mileageMiles: tripMiles + manualMiles,
      recordsLogged: records.count,
      tripsTracked: trips.count
    )
  }
}
