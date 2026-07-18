import Foundation

@MainActor
enum NativeProgressSummary {
  static func weekly(store: OkkleStore, now: Date = Date(), calendar: Calendar = .current) -> NativeProgressTotals {
    let interval = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(
      start: calendar.startOfDay(for: now),
      duration: 7 * 24 * 60 * 60
    )
    return totals(
      records: store.records.filter { interval.contains($0.date) },
      trips: store.trips.filter { interval.contains($0.startedAt) }
    )
  }

  static func yearToDate(store: OkkleStore) -> NativeProgressTotals {
    totals(records: store.yearRecords, trips: store.yearTrips)
  }

  static func allTime(store: OkkleStore) -> NativeProgressTotals {
    totals(records: store.records, trips: store.trips)
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
