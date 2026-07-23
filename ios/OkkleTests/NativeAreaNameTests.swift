import XCTest
import MapKit
@testable import Okkle

final class NativeAreaNameTests: XCTestCase {
  func testFallsBackToThoroughfareNotLocality() {
    // subLocality is nil (typical for a generic/simulated coordinate),
    // thoroughfare present, locality "London" — should use the street,
    // never "London".
    let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1), addressDictionary: [
      "Thoroughfare": "Long Acre",
      "City": "London",
    ])
    XCTAssertEqual(nativeNeighbourhoodName(from: placemark), "Long Acre")
  }

  func testReturnsNilRatherThanLondonWhenNothingFinerResolves() {
    // Neither subLocality nor thoroughfare resolve — only city ("London")
    // does. Previously this fell back to "London"; now it should return
    // nil so the caller omits the zone instead of showing something
    // useless to a London-based driver.
    let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1), addressDictionary: [
      "City": "London",
    ])
    XCTAssertNil(nativeNeighbourhoodName(from: placemark))
  }

  func testBoroughSubLocalityFallsBackToThoroughfareNotLondon() {
    let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1), addressDictionary: [
      "SubLocality": "Wandsworth",
      "Thoroughfare": "West Hill",
      "City": "London",
    ])
    XCTAssertEqual(nativeNeighbourhoodName(from: placemark), "West Hill")
  }

  func testRealNeighbourhoodStillWins() {
    let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1), addressDictionary: [
      "SubLocality": "Soho",
      "City": "London",
    ])
    XCTAssertEqual(nativeNeighbourhoodName(from: placemark), "Soho")
  }

  // The area-naming + food-POI overlay is coordinate/placemark-driven with no
  // UK gating, so it works for US pickups too. A US neighbourhood resolves to
  // its own name, and the London-borough filter is simply inert stateside.
  func testUSNeighbourhoodResolves() {
    let manhattan = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 40.7233, longitude: -74.0030), addressDictionary: [
      "SubLocality": "SoHo",
      "City": "New York",
      "State": "NY",
    ])
    XCTAssertEqual(nativeNeighbourhoodName(from: manhattan), "SoHo")
  }

  func testUSStreetFallbackWhenNoNeighbourhood() {
    let chicago = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 41.8827, longitude: -87.6233), addressDictionary: [
      "Thoroughfare": "W Madison St",
      "City": "Chicago",
      "State": "IL",
    ])
    XCTAssertEqual(nativeNeighbourhoodName(from: chicago), "W Madison St")
  }
}
