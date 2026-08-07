import Foundation

/// 개인 보관함 장소와 지도 문서의 장소는 저장 수명이 다르지만, 사용자가 두 화면을 오갈 때
/// 같은 장소 정보가 빠지지 않아야 한다. 변환 규칙을 한곳에 두어 주소·카카오 id·좌표가
/// 흐름마다 달라지는 일을 막는다.
extension SavedPlace {
    func mapPlace(pinColor: String = MapPalette.pin) -> MapPlace {
        MapPlace(
            name: name,
            address: address,
            kakaoPlaceId: kakaoPlaceId,
            location: GeoPoint(lat: lat, lng: lng),
            pinColor: pinColor
        )
    }
}

extension MapPlace {
    func savedPlace(groupID: String = SavedPlaceGroup.inboxID) -> SavedPlace {
        SavedPlace(
            name: name,
            address: address,
            kakaoPlaceId: kakaoPlaceId,
            lat: location.lat,
            lng: location.lng,
            groupID: groupID
        )
    }
}
