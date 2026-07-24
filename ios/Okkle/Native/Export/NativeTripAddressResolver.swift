import CoreLocation
import Foundation

/// Fills in a trip's start/end address after the fact, so the mileage
/// report can show a real journey (address to address) instead of just an
/// aggregate distance — closer to what a proper HMRC mileage log looks
/// like. Only ever narrows down what's shown: a trip with no resolved
/// address just falls back to its vehicle/miles summary, same as before.
enum NativeTripAddressResolver {
  /// Resolve one freshly-saved trip. Fire-and-forget from OkkleStore.addTrip.
  static func resolveAddresses(for tripID: UUID, store: OkkleStore) {
    Task.detached(priority: .utility) {
      guard let trip = await MainActor.run(body: { store.trips.first { $0.id == tripID } }) else { return }
      await resolve(trip: trip, store: store)
    }
  }

  /// Best-effort catch-up for trips saved before this existed, or where the
  /// initial resolve failed (no network, geocoder timeout). Call this from
  /// a screen that's about to show or export a mileage log.
  ///
  /// Scoped to the current tax year (not all-time) and given a high cap —
  /// a newest-first, low-cap backfill would let a busy driver's older trips
  /// within the SAME tax year get permanently starved: every visit re-picks
  /// the newest still-missing trips, so anything past the cap never gets a
  /// turn while it keeps competing with genuinely new trips added since.
  /// The mileage log needs the whole tax year addressed, not just the tail.
  static func backfillMissingAddresses(store: OkkleStore, limit: Int = 500) {
    Task.detached(priority: .background) {
      let candidates: [NativeTrip] = await MainActor.run {
        Array(
          store.yearTrips
            .filter { $0.startAddress == nil && !$0.points.isEmpty }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit)
        )
      }
      for trip in candidates {
        await resolve(trip: trip, store: store)
      }
    }
  }

  private static func resolve(trip: NativeTrip, store: OkkleStore) async {
    guard let first = trip.points.first else { return }
    let last = trip.points.last ?? first
    let startAddress = await address(for: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude))
    let endAddress = await address(for: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude))
    guard startAddress != nil || endAddress != nil else { return }
    await MainActor.run {
      guard var updated = store.trips.first(where: { $0.id == trip.id }) else { return }
      updated.startAddress = startAddress ?? updated.startAddress
      updated.endAddress = endAddress ?? updated.endAddress
      store.updateTrip(updated)
    }
  }

  private static func address(for coordinate: CLLocationCoordinate2D) async -> String? {
    await withCheckedContinuation { continuation in
      CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
        continuation.resume(returning: placemarks?.first.flatMap(formattedAddress))
      }
    }
  }

  private static func formattedAddress(_ placemark: CLPlacemark) -> String? {
    let line1 = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
    let line2 = [placemark.locality ?? placemark.subLocality, placemark.postalCode].compactMap { $0 }.joined(separator: " ")
    let combined = [line1, line2].filter { !$0.isEmpty }.joined(separator: ", ")
    return combined.isEmpty ? nil : combined
  }
}
