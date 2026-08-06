import Foundation

/// 개인 보관함의 장소를 지도에 그릴 때 필요한 최소 정보.
///
/// 보관함 모델 자체를 지도 SDK에 넘기지 않고 폴더의 마크·색을 미리 합쳐 둔다. 폴더가
/// 삭제됐거나 예전 파일이라 참조가 끊긴 장소는 `받은 장소` 모양으로 안전하게 표시한다.
struct SavedPlacePin: Identifiable, Equatable {
    let id: String
    let name: String
    let location: GeoPoint
    let marker: SavedPlaceMarker
    let colorHex: String
}

func makeSavedPlacePins(
    places: [SavedPlace],
    groups: [SavedPlaceGroup]
) -> [SavedPlacePin] {
    let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

    return places.map { place in
        let group = groupsByID[place.groupID] ?? SavedPlaceGroup.inbox
        return SavedPlacePin(
            id: place.id,
            name: place.name,
            location: GeoPoint(lat: place.lat, lng: place.lng),
            marker: group.marker,
            colorHex: group.colorHex
        )
    }
}
