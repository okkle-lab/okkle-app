import CoreLocation
import Foundation

struct NativeRouteDetectedStop {
  var boundaryIndex: Int
  var startIndex: Int
  var endIndex: Int
  var coordinate: CLLocationCoordinate2D
  var arrival: Date
  var departure: Date
  var confidence: Double

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
  private static let minimumDwell: TimeInterval = 4 * 60
  private static let strongDwell: TimeInterval = 8 * 60
  private static let mergeGap: TimeInterval = 5 * 60
  private static let minimumStopConfidence = 0.45
  private static let trafficPauseMaxDwell: TimeInterval = 7 * 60
  private static let straightThroughHeadingThreshold = 35.0
  private static let movingLegDistance: CLLocationDistance = 70
  private static let lowSpeedThreshold = 1.5

  static func routeStops(
    in points: [RoutePoint],
    startedAt: Date,
    endedAt: Date,
    recordedVisits: [NativeVisit]
  ) -> [NativeVisit] {
    let recordedStops = recordedVisits
      .filter { $0.arrival >= startedAt && $0.departure <= endedAt }
      .filter { !isEndpointVisit($0, points: points, startedAt: startedAt, endedAt: endedAt) }
      .sorted { $0.arrival < $1.arrival }
    let detectedStops = detectStops(in: points)
      .map(\.visit)
      .filter { !isEndpointVisit($0, points: points, startedAt: startedAt, endedAt: endedAt) }
    return mergedStops(recordedStops: recordedStops, detectedStops: detectedStops)
  }

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
      let confidence = stopConfidence(
        points: points,
        runStart: runStart,
        runEnd: runEnd,
        index: index,
        coordinate: coordinate,
        dwell: dwell
      )
      guard confidence >= minimumStopConfidence else { continue }
      stops.append(NativeRouteDetectedStop(
        boundaryIndex: index + 1,
        startIndex: index,
        endIndex: index + 1,
        coordinate: coordinate,
        arrival: arrival,
        departure: departure,
        confidence: confidence
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
      previous.confidence = max(previous.confidence, stop.confidence)
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

  private static func stopConfidence(
    points: [RoutePoint],
    runStart: Int,
    runEnd: Int,
    index: Int,
    coordinate: CLLocationCoordinate2D,
    dwell: TimeInterval
  ) -> Double {
    var confidence = dwell >= strongDwell ? 0.62 : dwell >= 6 * 60 ? 0.38 : 0.24
    let connectionDropped = vehicleConnectionDropped(points: points, runStart: runStart, runEnd: runEnd, index: index)
    let lowSpeed = endpointSpeedLooksStationary(points[index]) || endpointSpeedLooksStationary(points[index + 1])
    let jitter = hasRepeatedStationaryJitter(points: points, runStart: runStart, runEnd: runEnd, coordinate: coordinate, arrivalIndex: index, departureIndex: index + 1)
    let headingChange = routeHeadingChange(points: points, runStart: runStart, runEnd: runEnd, index: index)
    let likelyTraffic = looksLikeTrafficPause(
      points: points,
      runStart: runStart,
      runEnd: runEnd,
      index: index,
      dwell: dwell,
      headingChange: headingChange,
      hasRepeatedJitter: jitter,
      connectionDropped: connectionDropped
    )

    if connectionDropped { confidence += 0.50 }
    if lowSpeed { confidence += 0.10 }
    if jitter { confidence += 0.18 }
    if let headingChange, headingChange >= 55 { confidence += 0.12 }
    if likelyTraffic { confidence -= 0.38 }

    return min(max(confidence, 0), 1)
  }

  private static func endpointSpeedLooksStationary(_ point: RoutePoint) -> Bool {
    guard let speed = point.speed else { return false }
    return speed >= 0 && speed <= lowSpeedThreshold
  }

  private static func vehicleConnectionDropped(
    points: [RoutePoint],
    runStart: Int,
    runEnd: Int,
    index: Int
  ) -> Bool {
    let beforeStart = max(runStart, index - 2)
    let beforeEnd = index
    let afterStart = index + 1
    let afterEnd = min(runEnd, index + 3)
    let hadVehicle = points[beforeStart...beforeEnd].contains { $0.vehicleConnectionActive == true }
    let lostVehicle = points[afterStart...afterEnd].contains { $0.vehicleConnectionActive == false }
    return hadVehicle && lostVehicle
  }

  private static func hasRepeatedStationaryJitter(
    points: [RoutePoint],
    runStart: Int,
    runEnd: Int,
    coordinate: CLLocationCoordinate2D,
    arrivalIndex: Int,
    departureIndex: Int
  ) -> Bool {
    let windowStart = max(runStart, arrivalIndex - 2)
    let windowEnd = min(runEnd, departureIndex + 2)
    let center = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    let nearby = points[windowStart...windowEnd].filter { point in
      center.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)) <= 55
    }
    guard nearby.count >= 3 else { return false }
    let timestamps = nearby.compactMap(\.timestamp)
    guard let first = timestamps.min(), let last = timestamps.max() else { return true }
    return last.timeIntervalSince(first) >= 90
  }

  private static func looksLikeTrafficPause(
    points: [RoutePoint],
    runStart: Int,
    runEnd: Int,
    index: Int,
    dwell: TimeInterval,
    headingChange: Double?,
    hasRepeatedJitter: Bool,
    connectionDropped: Bool
  ) -> Bool {
    guard dwell <= trafficPauseMaxDwell, !hasRepeatedJitter, !connectionDropped else { return false }
    guard index > runStart, index + 2 <= runEnd else { return false }
    let approach = distance(from: points[index - 1].coordinate, to: points[index].coordinate)
    let exit = distance(from: points[index + 1].coordinate, to: points[index + 2].coordinate)
    guard approach >= movingLegDistance, exit >= movingLegDistance else { return false }
    guard let headingChange else { return true }
    return headingChange <= straightThroughHeadingThreshold
  }

  private static func routeHeadingChange(
    points: [RoutePoint],
    runStart: Int,
    runEnd: Int,
    index: Int
  ) -> Double? {
    guard index > runStart, index + 2 <= runEnd else {
      if let beforeCourse = points[index].course, let afterCourse = points[index + 1].course {
        return headingDifference(beforeCourse, afterCourse)
      }
      return nil
    }
    let before = bearing(from: points[index - 1].coordinate, to: points[index].coordinate)
    let after = bearing(from: points[index + 1].coordinate, to: points[index + 2].coordinate)
    return headingDifference(before, after)
  }

  private static func bearing(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
    let lat1 = lhs.latitude * .pi / 180
    let lat2 = rhs.latitude * .pi / 180
    let deltaLon = (rhs.longitude - lhs.longitude) * .pi / 180
    let y = sin(deltaLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
    return atan2(y, x) * 180 / .pi
  }

  private static func headingDifference(_ lhs: Double, _ rhs: Double) -> Double {
    let normalized = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
    return min(normalized, 360 - normalized)
  }

  private static func isEndpointVisit(
    _ visit: NativeVisit,
    points: [RoutePoint],
    startedAt: Date,
    endedAt: Date
  ) -> Bool {
    guard let startPoint = points.first, let endPoint = points.last else { return false }
    let nearStart = abs(visit.arrival.timeIntervalSince(startedAt)) < 180 &&
      distance(from: visit.coordinate, to: startPoint.coordinate) <= 120
    let nearEnd = abs(visit.departure.timeIntervalSince(endedAt)) < 180 &&
      distance(from: visit.coordinate, to: endPoint.coordinate) <= 120
    return nearStart || nearEnd
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
