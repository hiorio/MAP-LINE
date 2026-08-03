import Foundation

/// 여러 지도에 걸쳐 재사용하는 개인 보관함의 한 항목.
///
/// 웹의 `lib/map/savedPlaces.ts`와 같은 모양이다. 공유되는 지도 문서에는 들어가지
/// 않는다. 보관함은 내가 모아 둔 목록이고, 링크를 받은 사람이 볼 것은 코스에 올린
/// 단계뿐이다.
struct SavedPlace: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let address: String?
    let kakaoPlaceId: String?
    let lat: Double
    let lng: Double
    let savedAt: String

    init(
        id: String = UUID().uuidString,
        name: String,
        address: String? = nil,
        kakaoPlaceId: String? = nil,
        lat: Double,
        lng: Double,
        savedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.kakaoPlaceId = kakaoPlaceId
        self.lat = lat
        self.lng = lng
        self.savedAt = savedAt
    }
}

/// 같은 곳인가.
///
/// 카카오 장소 id가 있으면 그것으로 본다. 지도를 직접 찍어 만든 지점에는 id가 없으므로
/// 이름과 좌표로 본다. 좌표는 소수점 이하가 미세하게 다를 수 있어 약 11m 안이면 같은
/// 곳으로 친다. 공유로 들어온 것과 앱에서 검색해 담은 것이 중복되면 목록이 지저분해진다.
func isSamePlace(_ a: SavedPlace, _ b: SavedPlace) -> Bool {
    if let left = a.kakaoPlaceId, let right = b.kakaoPlaceId, !left.isEmpty, !right.isEmpty {
        return left == right
    }
    return a.name == b.name
        && abs(a.lat - b.lat) < 0.0001
        && abs(a.lng - b.lng) < 0.0001
}
