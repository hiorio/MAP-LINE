import CoreLocation
import XCTest
@testable import MapLine

final class CurrentLocationProviderTests: XCTestCase {
    func test_유효한위치중가장최근값을고른다() {
        let now = Date(timeIntervalSince1970: 1_000)
        let older = location(lat: 37.4, timestamp: now.addingTimeInterval(-20))
        let newest = location(lat: 37.5, timestamp: now.addingTimeInterval(-2))

        let picked = mostRecentUsableLocation([newest, older], now: now)

        XCTAssertEqual(picked?.coordinate.latitude ?? 0, 37.5, accuracy: 0.000_001)
    }

    func test_오래됐거나정확도가유효하지않은위치는쓰지않는다() {
        let now = Date(timeIntervalSince1970: 1_000)
        let stale = location(lat: 37.4, timestamp: now.addingTimeInterval(-121))
        let invalidAccuracy = location(
            lat: 37.5,
            horizontalAccuracy: -1,
            timestamp: now.addingTimeInterval(-1)
        )

        XCTAssertNil(mostRecentUsableLocation([stale, invalidAccuracy], now: now))
    }

    func test_위치준비중오류만임시오류로본다() {
        XCTAssertTrue(isTransientLocationError(CLError(.locationUnknown)))
        XCTAssertFalse(isTransientLocationError(CLError(.denied)))
    }

    private func location(
        lat: Double,
        horizontalAccuracy: CLLocationAccuracy = 10,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: 127.0),
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 10,
            timestamp: timestamp
        )
    }
}
