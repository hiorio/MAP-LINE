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
            lat: 37.5,
            lng: 127.0,
            groupID: group.id
        )

        let pin = makeSavedPlacePins(places: [place], groups: [group]).first

        XCTAssertEqual(pin?.id, place.id)
        XCTAssertEqual(pin?.location, GeoPoint(lat: 37.5, lng: 127.0))
        XCTAssertEqual(pin?.marker, .coffee)
        XCTAssertEqual(pin?.colorHex, "#8B5CF6")
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
}
