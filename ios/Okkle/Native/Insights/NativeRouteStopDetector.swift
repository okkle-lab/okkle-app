import CoreLocation
import Foundation

struct NativeRouteDetectedStop {
  var boundaryIndex: Int
  var startIndex: Int
  var endIndex: Int
  var coordinate: CLLocationCoordinate2D
  var arrival: Date
  var departure: Date

  var visit: NativeVisit {
    var visit = NativeVisit(
      id: nativeRouteStopDeterministicUUID(seed: visitSeed),
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      arrival: arrival,
      departure: departure
    )
    visit.kind = NativeVisit.Kind.other
    visit.placeName = "Detected from movement"
    return visit
  }

  private var visitSeed: String {
    let lat = Int((coordinate.latitude * 100_000).rounded())
    let lon = Int((coordinate.longitude * 100_000).rounded())
    return "\(lat)-\(lon)-\(Int(arrival.timeIntervalSince1970))-\(Int(departure.timeIntervalSince1970))"
  }
}

enum NativeRouteStopDetector {
  private static let stationaryRadius: CLLocationDistance = 90
  private static let mergeRadius: CLLocationDistance = 120
  private static let minimumDwell: TimeInterval = 90
  private static let mergeGap: TimeInterval = 5 * 60

  static func detectStops(in points: [RoutePoint]) -> [NativeRouteDetectedStop] {
    guard points.count > 2 else { return [] }
    var stops: [NativeRouteDetectedStop] = []
    var runStart = 0

    while runStart < points.count {
      var runEnd = runStart
      while runEnd + 1 < points.count && !points[runEnd + 1].breakBefore {
        runEnd += 1
      }

      stops.append(contentsOf: detectStops(in: points, runStart: runStart, runEnd: runEnd))
      runStart = runEnd + 1
    }

    return mergedDetectedStops(stops)
  }

  static func detectStops(in points: [RoutePoint], runStart: Int, runEnd: Int) -> [NativeRouteDetectedStop] {
    guard runEnd - runStart >= 2 else { return [] }
    var stops: [NativeRouteDetectedStop] = []

    for index in runStart..<runEnd {
      guard let arrival = points[index].timestamp,
            let departure = points[index + 1].timestamp else {
        continue
      }
      let dwell = departure.timeIntervalSince(arrival)
      guard dwell >= minimumDwell else { continue }

      let startLocation = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
      let endLocation = CLLocation(latitude: points[index + 1].latitude, longitude: points[index + 1].longitude)
      guard startLocation.distance(from: endLocation) <= stationaryRadius else { continue }

      let coordinate = CLLocationCoordinate2D(
        latitude: (points[index].latitude + points[index + 1].latitude) / 2,
        longitude: (points[index].longitude + points[index + 1].longitude) / 2
      )
      stops.append(NativeRouteDetectedStop(
        boundaryIndex: index + 1,
        startIndex: index,
        endIndex: index + 1,
        coordinate: coordinate,
        arrival: arrival,
        departure: departure
      ))
    }

    return mergedDetectedStops(stops)
  }

  static func mergedStops(recordedStops: [NativeVisit], detectedStops: [NativeVisit]) -> [NativeVisit] {
    var merged = recordedStops
    for detected in detectedStops where !containsSameStop(recordedStops, detected) {
      merged.append(detected)
    }
    return merged.sorted { $0.arrival < $1.arrival }
  }

  static func containsSameStop(_ stops: [NativeVisit], _ candidate: NativeVisit) -> Bool {
    stops.contains { isSameStop($0, candidate) }
  }

  private static func mergedDetectedStops(_ stops: [NativeRouteDetectedStop]) -> [NativeRouteDetectedStop] {
    var merged: [NativeRouteDetectedStop] = []
    for stop in stops.sorted(by: { $0.arrival < $1.arrival }) {
      guard var previous = merged.last,
            previous.departure.addingTimeInterval(mergeGap) >= stop.arrival,
            distance(from: previous.coordinate, to: stop.coordinate) <= mergeRadius else {
        merged.append(stop)
        continue
      }

      previous.endIndex = max(previous.endIndex, stop.endIndex)
      previous.boundaryIndex = max(previous.boundaryIndex, stop.boundaryIndex)
      previous.departure = max(previous.departure, stop.departure)
      previous.coordinate = CLLocationCoordinate2D(
        latitude: (previous.coordinate.latitude + stop.coordinate.latitude) / 2,
        longitude: (previous.coordinate.longitude + stop.coordinate.longitude) / 2
      )
      merged[merged.count - 1] = previous
    }
    return merged
  }

  private static func isSameStop(_ lhs: NativeVisit, _ rhs: NativeVisit) -> Bool {
    let timeOverlap = lhs.arrival <= rhs.departure && rhs.arrival <= lhs.departure
    let timeNear = abs(lhs.arrival.timeIntervalSince(rhs.arrival)) < 180 ||
      abs(lhs.departure.timeIntervalSince(rhs.departure)) < 180
    let distance = lhs.location.distance(from: rhs.location)
    return distance <= 100 && (timeOverlap || timeNear)
  }

  private static func distance(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> CLLocationDistance {
    CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
      .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
  }

}

private func nativeRouteStopDeterministicUUID(seed: String) -> UUID {
  var first: UInt64 = 0xcbf29ce484222325
  var second: UInt64 = 0x84222325cbf29ce4
  for byte in seed.utf8 {
    first ^= UInt64(byte)
    first &*= 0x100000001b3
    second &+= UInt64(byte) &* 0x9e3779b185ebca87
    second = (second << 7) | (second >> 57)
  }
  let uuidString = String(
    format: "%08x-%04x-%04x-%04x-%012llx",
    UInt32((first >> 32) & 0xffffffff),
    UInt16((first >> 16) & 0xffff),
    UInt16(first & 0xffff),
    UInt16((second >> 48) & 0xffff),
    second & 0x0000ffffffffffff
  )
  return UUID(uuidString: uuidString) ?? UUID()
}
