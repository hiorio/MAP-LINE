import UIKit
import XCTest
@testable import MapLine

/// 단계와 후보의 규칙.
///
/// 웹(`lib/map/types.ts`)과 같은 답을 내야 한다. 한쪽만 바뀌면 같은 지도가 두 곳에서
/// 다르게 그려지는데, 그건 링크를 열어 보기 전까지 아무도 모른다.
final class StopTests: XCTestCase {
    private func place(_ name: String, lat: Double = 37.5, lng: Double = 127.0) -> MapPlace {
        MapPlace(name: name, location: GeoPoint(lat: lat, lng: lng))
    }

    func test_후보가하나면그것이대표다() {
        // 고를 것이 없으므로 사람에게 묻지 않는다.
        let only = place("강남역")
        XCTAssertEqual(Stop(candidates: [only]).anchor, only)
    }

    func test_후보가여럿인데대표를안정했으면기준이없다() {
        // 첫 후보를 말없이 쓰면 나머지가 동선에서 빠진 것처럼 보인다.
        // nil을 주는 것이 정직하고, 그때는 경로를 그리지 않는다.
        let stop = Stop(candidates: [place("가"), place("나")])
        XCTAssertNil(stop.anchor)
    }

    func test_대표를정하면그후보가기준이다() {
        let first = place("가")
        let second = place("나")
        let stop = Stop(candidates: [first, second], primaryId: second.id)
        XCTAssertEqual(stop.anchor, second)
    }

    func test_없는후보를대표로가리키면기준이없다() {
        // 후보를 지웠는데 대표 id만 남은 경우다. 그 상태로 경로를 그리면 안 된다.
        let stop = Stop(candidates: [place("가"), place("나")], primaryId: "사라진-id")
        XCTAssertNil(stop.anchor)
    }

    func test_대표위치는후보들의평균이다() {
        // 후보 하나에서 선을 뽑으면 나머지가 빠진 것처럼 보인다. 무리의 가운데를 쓴다.
        let stop = Stop(candidates: [
            place("가", lat: 37.0, lng: 127.0),
            place("나", lat: 38.0, lng: 128.0),
        ])
        XCTAssertEqual(stop.centroid?.lat ?? 0, 37.5, accuracy: 1e-9)
        XCTAssertEqual(stop.centroid?.lng ?? 0, 127.5, accuracy: 1e-9)
    }

    func test_후보가없으면대표위치도없다() {
        XCTAssertNil(Stop(candidates: []).centroid)
    }

    func test_번호는배열순서다() {
        // 단계에 번호를 따로 저장하지 않는다. 순서가 유일한 근거라 재배치해도 어긋나지 않는다.
        let first = place("가")
        let second = place("나")
        let third = place("다")
        let stops = [Stop(candidates: [first, second]), Stop(candidates: [third])]

        XCTAssertEqual(stops.flattened().map(\.stopNumber), [1, 1, 2])
        XCTAssertEqual(stops.stopNumber(ofCandidate: second.id), 1)
        XCTAssertEqual(stops.stopNumber(ofCandidate: third.id), 2)
        XCTAssertNil(stops.stopNumber(ofCandidate: "없는-id"))
    }

    func test_기존단계에후보를더해도단계수와id는그대로다() {
        let first = place("국밥집")
        let second = place("칼국수집")
        let stop = Stop(candidates: [first])
        var stops = [stop]

        XCTAssertTrue(stops.addCandidates([second], toStopID: stop.id))
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops[0].id, stop.id)
        XCTAssertEqual(stops[0].candidates.map(\.name), ["국밥집", "칼국수집"])
        XCTAssertEqual(stops.flattened().map(\.stopNumber), [1, 1])
    }

    func test_후보를더해도이미정한대표는유지한다() {
        let first = place("국밥집")
        let second = place("칼국수집")
        let third = place("냉면집")
        var stops = [Stop(candidates: [first, second], primaryId: second.id)]

        XCTAssertTrue(stops.addCandidates([third], toStopID: stops[0].id))
        XCTAssertEqual(stops[0].primaryId, second.id)
        XCTAssertEqual(stops[0].anchor, second)
    }

    func test_없는단계나빈후보목록은바꾸지않는다() {
        let original = [Stop(candidates: [place("국밥집")])]
        var stops = original

        XCTAssertFalse(stops.addCandidates([], toStopID: original[0].id))
        XCTAssertFalse(stops.addCandidates([place("칼국수집")], toStopID: "없는-id"))
        XCTAssertEqual(stops, original)
    }

    func test_서버와같은키로오간다() throws {
        // 웹이 저장한 지도를 앱이 열어야 한다. 키 이름이 하나만 달라도 못 연다.
        let encoded = try JSONEncoder().encode(
            MapPlace(
                id: "p1",
                name: "강남역",
                address: "서울 강남구",
                kakaoPlaceId: "123",
                location: GeoPoint(lat: 37.4979, lng: 127.0276)
            )
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(json["id"] as? String, "p1")
        XCTAssertEqual(json["kakaoPlaceId"] as? String, "123")
        XCTAssertEqual(json["pinColor"] as? String, "#E24B4A")
        let location = try XCTUnwrap(json["location"] as? [String: Any])
        XCTAssertEqual(location["lat"] as? Double, 37.4979)
        XCTAssertEqual(location["lng"] as? Double, 127.0276)
    }

    func test_색문자열을읽는다() {
        XCTAssertNotNil(UIColor(hex: "#E24B4A"))
        XCTAssertNotNil(UIColor(hex: "E24B4A"))
        // 읽을 수 없으면 nil이다. 검정으로 대신하면 색이 조용히 사라진다.
        XCTAssertNil(UIColor(hex: "#GGG"))
        XCTAssertNil(UIColor(hex: ""))
    }
}
