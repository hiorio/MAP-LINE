import Foundation

/// 개인 보관함의 장소를 지도에서 그리고 눌렀을 때 보여 줄 정보.
///
/// 마크만 그리던 때는 이름과 좌표로 충분했지만, 이제 마커를 누르면 주소·폴더와 동선 추가
/// 동작을 보여 준다. 원본 장소와 폴더를 함께 들고 있어 지도에서 다시 파일을 읽지 않는다.
struct SavedPlacePin: Identifiable, Equatable {
    let place: SavedPlace
    let group: SavedPlaceGroup

    var id: String { place.id }
    var name: String { place.name }
    var address: String? { place.address }
    var location: GeoPoint { GeoPoint(lat: place.lat, lng: place.lng) }
    var marker: SavedPlaceMarker { group.marker }
    var colorHex: String { group.colorHex }
    var mapPlace: MapPlace { place.mapPlace(pinColor: group.colorHex) }
}

func makeSavedPlacePins(
    places: [SavedPlace],
    groups: [SavedPlaceGroup]
) -> [SavedPlacePin] {
    let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

    return places.map { place in
        let group = groupsByID[place.groupID] ?? SavedPlaceGroup.inbox
        return SavedPlacePin(
            place: place,
            group: group
        )
    }
}
