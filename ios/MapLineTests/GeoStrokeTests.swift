import XCTest
@testable import MapLine

/// 도메인 규칙 테스트.
///
/// SDK를 부르지 않는다. 그래야 지도가 없어도 돌고, 나중에 이 규칙을 다른 플랫폼으로
/// 옮길 때 무엇이 참이어야 하는지가 여기 남는다.
final class GeoStrokeTests: XCTestCase {
    func test_점이두개면그대로둔다() {
        let points = [GeoPoint(lat: 0, lng: 0), GeoPoint(lat: 1, lng: 1)]
        XCTAssertEqual(simplifyPath(points, epsilon: 0.5), points)
    }

    func test_일직선위의중간점은버린다() {
        // 가운데 점들은 선에서 벗어나지 않으므로 그림이 달라지지 않는다.
        let points = [
            GeoPoint(lat: 0, lng: 0),
            GeoPoint(lat: 0, lng: 1),
            GeoPoint(lat: 0, lng: 2),
            GeoPoint(lat: 0, lng: 3),
        ]
        XCTAssertEqual(simplifyPath(points, epsilon: 0.1), [points[0], points[3]])
    }

    func test_크게꺾이는점은남긴다() {
        let points = [
            GeoPoint(lat: 0, lng: 0),
            GeoPoint(lat: 5, lng: 1),
            GeoPoint(lat: 0, lng: 2),
        ]
        XCTAssertEqual(simplifyPath(points, epsilon: 0.5), points)
    }

    func test_양끝은언제나남는다() {
        let points = (0...50).map { GeoPoint(lat: sin(Double($0)), lng: Double($0)) }
        let simplified = simplifyPath(points, epsilon: 100)
        XCTAssertEqual(simplified.first, points.first)
        XCTAssertEqual(simplified.last, points.last)
    }

    func test_임계값이0이하면손대지않는다() {
        let points = [
            GeoPoint(lat: 0, lng: 0),
            GeoPoint(lat: 0, lng: 1),
            GeoPoint(lat: 0, lng: 2),
        ]
        XCTAssertEqual(simplifyPath(points, epsilon: 0), points)
    }

    func test_시작과끝이같아도터지지않는다() {
        // 제자리에서 원을 그리면 첫 점과 끝 점이 같아진다. 선분이 아니라 점이 된다.
        let points = [
            GeoPoint(lat: 0, lng: 0),
            GeoPoint(lat: 1, lng: 1),
            GeoPoint(lat: 0, lng: 0),
        ]
        XCTAssertEqual(simplifyPath(points, epsilon: 0.1), points)
    }

    func test_긴획에서도재귀깊이로터지지않는다() {
        // 재귀로 짜면 여기서 스택이 넘친다. 손가락 한 번에 좌표 수백 개는 예사다.
        let points = (0..<5000).map { GeoPoint(lat: Double($0) * 0.0001, lng: Double($0) * 0.0001) }
        let simplified = simplifyPath(points, epsilon: 0.00001)
        XCTAssertEqual(simplified.first, points.first)
        XCTAssertEqual(simplified.last, points.last)
        XCTAssertLessThan(simplified.count, points.count)
    }
}
