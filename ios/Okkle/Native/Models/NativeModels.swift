import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
enum NativeVehicle: String, CaseIterable, Identifiable, Codable {
  case car
  case motorbike
  case bike
  case van

  var id: String { rawValue }

  var label: String {
    switch self {
    case .car: return "Car"
    case .motorbike: return "Motorbike"
    case .bike: return "E-bike / Bicycle"
    case .van: return "Van"
    }
  }

  var symbol: String {
    switch self {
    case .car: return "car.fill"
    case .motorbike: return "scooter"
    case .bike: return "bicycle"
    case .van: return "shippingbox.fill"
    }
  }

  func rateBand(on date: Date) -> (first: Double, after: Double) {
    let isNewRate = Calendar.current.compare(date, to: DateComponents(calendar: .current, year: 2026, month: 4, day: 6).date ?? date, toGranularity: .day) != .orderedAscending
    switch self {
    case .car, .van:
      return (isNewRate ? 0.55 : 0.45, 0.25)
    case .motorbike:
      return (0.24, 0.24)
    case .bike:
      return (0.20, 0.20)
    }
  }
}

enum NativeRegion: String, CaseIterable, Identifiable, Codable {
  case ruk
  case scotland

  var id: String { rawValue }

  var label: String {
    switch self {
    case .ruk: return "England, Wales or NI"
    case .scotland: return "Scotland"
    }
  }
}

enum NativeIncomeBracket: String, CaseIterable, Identifiable, Codable {
  case basic
  case higher

  var id: String { rawValue }

  var label: String {
    switch self {
    case .basic: return "Basic rate"
    case .higher: return "Higher rate"
    }
  }

  func marginalRate(region: NativeRegion) -> Double {
    switch (self, region) {
    case (.basic, _): return 0.20
    case (.higher, .ruk): return 0.40
    case (.higher, .scotland): return 0.42
    }
  }

  func assumedOtherIncome(region: NativeRegion) -> Double {
    switch self {
    case .basic:
      return 12_570
    case .higher:
      return region == .scotland ? 43_663 : 50_270
    }
  }
}

enum NativeLogKind: String, CaseIterable, Identifiable, Codable {
  case income
  case expense
  case mileage

  var id: String { rawValue }

  var label: String {
    switch self {
    case .income: return "Earnings"
    case .expense: return "Expense"
    case .mileage: return "Mileage"
    }
  }

  var symbol: String {
    switch self {
    case .income: return "sterlingsign.circle.fill"
    case .expense: return "receipt.fill"
    case .mileage: return "map.fill"
    }
  }
}

struct RoutePoint: Identifiable, Codable, Equatable {
  var id = UUID()
  var latitude: Double
  var longitude: Double

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

struct NativeRecord: Identifiable, Codable, Equatable {
  var id = UUID()
  var legacyID: String? = nil
  var kind: NativeLogKind
  var platform: String?
  var vehicle: NativeVehicle?
  var amount: Double?
  var miles: Double?
  var deduction: Double?
  var category: String?
  var merchant: String? = nil
  var date: Date
  var period: NativePayPeriod
  var periodStart: Date? = nil
  var periodEnd: Date? = nil
  var receiptImageData: Data?
}

struct NativeTrip: Identifiable, Codable, Equatable {
  var id = UUID()
  var legacyID: String? = nil
  var vehicle: NativeVehicle
  var miles: Double
  var deduction: Double
  var startedAt: Date
  var endedAt: Date
  var points: [RoutePoint]
}

enum NativePayPeriod: String, CaseIterable, Identifiable, Codable {
  case day
  case week

  var id: String { rawValue }
  var label: String { rawValue.capitalized }
}

enum NativeLogFrequency: String, CaseIterable, Identifiable, Codable {
  case weekly
  case monthly

  var id: String { rawValue }
  var label: String { rawValue.capitalized }
}

struct NativeSettings: Codable, Equatable {
  var name = ""
  var defaultVehicle: NativeVehicle = .car
  var region: NativeRegion = .ruk
  var incomeBracket: NativeIncomeBracket = .basic
  var platforms = ["Uber Eats", "Deliveroo", "Just Eat"]
  var accountantUTR = ""
  var accountantNINumber = ""
  var accountantAddress = ""
  var accountantBusinessDescription = ""
  var loggingReminder = true
  var reminderDay = 1
  var logFrequency: NativeLogFrequency = .weekly
  var taxDeadlineReminders = true
  var tripNudges = false
  var hasCompletedOnboarding = false

  init() {}

  private enum CodingKeys: String, CodingKey {
    case name
    case defaultVehicle
    case region
    case incomeBracket
    case platforms
    case accountantUTR
    case accountantNINumber
    case accountantAddress
    case accountantBusinessDescription
    case loggingReminder
    case reminderDay
    case logFrequency
    case taxDeadlineReminders
    case tripNudges
    case hasCompletedOnboarding
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    defaultVehicle = try container.decodeIfPresent(NativeVehicle.self, forKey: .defaultVehicle) ?? .car
    region = try container.decodeIfPresent(NativeRegion.self, forKey: .region) ?? .ruk
    incomeBracket = try container.decodeIfPresent(NativeIncomeBracket.self, forKey: .incomeBracket) ?? .basic
    platforms = try container.decodeIfPresent([String].self, forKey: .platforms) ?? ["Uber Eats", "Deliveroo", "Just Eat"]
    accountantUTR = try container.decodeIfPresent(String.self, forKey: .accountantUTR) ?? ""
    accountantNINumber = try container.decodeIfPresent(String.self, forKey: .accountantNINumber) ?? ""
    accountantAddress = try container.decodeIfPresent(String.self, forKey: .accountantAddress) ?? ""
    accountantBusinessDescription = try container.decodeIfPresent(String.self, forKey: .accountantBusinessDescription) ?? ""
    loggingReminder = try container.decodeIfPresent(Bool.self, forKey: .loggingReminder) ?? true
    reminderDay = try container.decodeIfPresent(Int.self, forKey: .reminderDay) ?? 1
    logFrequency = try container.decodeIfPresent(NativeLogFrequency.self, forKey: .logFrequency) ?? .weekly
    taxDeadlineReminders = try container.decodeIfPresent(Bool.self, forKey: .taxDeadlineReminders) ?? true
    tripNudges = try container.decodeIfPresent(Bool.self, forKey: .tripNudges) ?? false
    hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
  }
}

struct NativeSnapshot: Codable {
  var settings: NativeSettings
  var records: [NativeRecord]
  var trips: [NativeTrip]
}

struct NativeBackupPayload: Codable {
  var app: String
  var version: Int
  var exportedAt: Date
  var snapshot: NativeSnapshot
}
