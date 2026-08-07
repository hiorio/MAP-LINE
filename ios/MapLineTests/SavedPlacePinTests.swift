import XCTest
@testable import MapLine

final class SavedPlacePinTests: XCTestCase {
    func test_보관장소는폴더의마크와색을쓴다() {
        let group = SavedPlaceGroup(
            id: "cafes",
            name: "카페",
            marker: .coffee,
            colorHex: "#8B5CF6"
        )
        let place = SavedPlace(
            id: "place",
            name: "동네 카페",
            address: "서울 성동구 연무장길 1",
            kakaoPlaceId: "1234",
            lat: 37.5,
            lng: 127.0,
            groupID: group.id
        )

        let pin = makeSavedPlacePins(places: [place], groups: [group]).first

        XCTAssertEqual(pin?.id, place.id)
        XCTAssertEqual(pin?.location, GeoPoint(lat: 37.5, lng: 127.0))
        XCTAssertEqual(pin?.marker, .coffee)
        XCTAssertEqual(pin?.colorHex, "#8B5CF6")
        XCTAssertEqual(pin?.address, "서울 성동구 연무장길 1")
        XCTAssertEqual(pin?.group.name, "카페")
        XCTAssertEqual(pin?.mapPlace.kakaoPlaceId, "1234")
        XCTAssertEqual(pin?.mapPlace.pinColor, "#8B5CF6")
    }

    func test_없어진폴더를가리키는장소는받은장소모양으로표시한다() {
        let place = SavedPlace(
            name: "예전 장소",
            lat: 37.5,
            lng: 127.0,
            groupID: "deleted-group"
        )

        let pin = makeSavedPlacePins(places: [place], groups: []).first

        XCTAssertEqual(pin?.marker, SavedPlaceGroup.inbox.marker)
        XCTAssertEqual(pin?.colorHex, SavedPlaceGroup.inbox.colorHex)
    }

    func test_동선장소와보관함장소를오가도식별정보를보존한다() {
        let mapPlace = MapPlace(
            name: "러스트베이커리",
            address: "서울 영등포구 경인로79길 15",
            kakaoPlaceId: "rust-1",
            location: GeoPoint(lat: 37.514, lng: 126.898)
        )

        let saved = mapPlace.savedPlace(groupID: "bakery")
        let restored = saved.mapPlace(pinColor: "#E24B4A")

        XCTAssertEqual(saved.groupID, "bakery")
        XCTAssertEqual(restored.name, mapPlace.name)
        XCTAssertEqual(restored.address, mapPlace.address)
        XCTAssertEqual(restored.kakaoPlaceId, mapPlace.kakaoPlaceId)
        XCTAssertEqual(restored.location, mapPlace.location)
    }
}
