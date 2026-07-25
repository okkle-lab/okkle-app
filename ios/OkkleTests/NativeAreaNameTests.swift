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
}
