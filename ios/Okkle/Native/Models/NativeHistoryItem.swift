import SwiftUI
import UIKit
enum NativeHistoryItem: Identifiable, Equatable {
  case trip(NativeTrip)
  case record(NativeRecord)

  var id: UUID {
    switch self {
    case .trip(let trip): return trip.id
    case .record(let record): return record.id
    }
  }

  var date: Date {
    switch self {
    case .trip(let trip): return trip.startedAt
    case .record(let record): return record.date
    }
  }

  var trip: NativeTrip? {
    if case .trip(let trip) = self { return trip }
    return nil
  }
}
