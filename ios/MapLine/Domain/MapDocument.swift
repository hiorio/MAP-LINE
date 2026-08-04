import Foundation

/// 코스에 담긴 장소 하나.
///
/// 웹 `lib/map/types.ts`의 `Place`와 같은 모양이다. 같은 서버에 저장하고 같은 링크로
/// 열리므로 한쪽이 달라지면 다른 쪽에서 열리지 않는다.
struct MapPlace: Identifiable, Equatable, Codable {
    let id: String
    var name: String
    var address: String?
    /// 재조회용 식별자. 지도를 직접 찍어 만든 지점에는 없다.
    var kakaoPlaceId: String?
    var location: GeoPoint
    var memo: String?
    var pinColor: String

    init(
        id: String = UUID().uuidString,
        name: String,
        address: String? = nil,
        kakaoPlaceId: String? = nil,
        location: GeoPoint,
        memo: String? = nil,
        pinColor: String = MapPalette.pin
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.kakaoPlaceId = kakaoPlaceId
        self.location = location
        self.memo = memo
        self.pinColor = pinColor
    }
}

/// 코스의 한 단계. 지도 위 번호 하나에 대응한다.
///
/// 후보를 여러 개 담을 수 있다. 모임을 짤 때 "2번은 점심인데 어디로 갈지는 아직
/// 안 정했다"가 흔하고, 후보를 함께 공유해 같이 고르는 것이 이 제품의 쓰임새다.
struct Stop: Identifiable, Equatable, Codable {
    let id: String
    var candidates: [MapPlace]
    /// 대표 후보의 id. 실제 경로를 그릴 때 출발·도착점이 된다.
    var primaryId: String?

    init(id: String = UUID().uuidString, candidates: [MapPlace], primaryId: String? = nil) {
        self.id = id
        self.candidates = candidates
        self.primaryId = primaryId
    }

    /// 길찾기의 기준이 될 장소.
    ///
    /// 후보가 하나면 고를 것이 없으므로 그것이 곧 대표다. 여럿인데 대표를 안 정했으면
    /// 기준이 없다는 뜻이고, 그때는 경로를 그리지 않는 것이 정직하다.
    /// 웹 `stopAnchor`와 같은 규칙이어야 두 곳이 같은 그림을 낸다.
    var anchor: MapPlace? {
        if candidates.count == 1 { return candidates.first }
        guard let primaryId else { return nil }
        return candidates.first { $0.id == primaryId }
    }

    /// 단계의 대표 위치. 후보들의 평균 좌표다.
    ///
    /// 단계 사이 선을 그릴 때 쓴다. 후보가 여럿일 때 특정 후보에서 선을 뽑으면 나머지
    /// 후보가 동선에서 빠진 것처럼 보인다. 무리의 가운데에서 출발시키면 어느 후보를
    /// 고르든 틀리지 않는다. 한 동네 안에 흩어진 점들이라 구면 보정 없이 충분하다.
    var centroid: GeoPoint? {
        guard !candidates.isEmpty else { return nil }
        let count = Double(candidates.count)
        return GeoPoint(
            lat: candidates.reduce(0) { $0 + $1.location.lat } / count,
            lng: candidates.reduce(0) { $0 + $1.location.lng } / count
        )
    }
}

/// 웹과 맞춘 색.
enum MapPalette {
    static let pin = "#E24B4A"
}

extension Array where Element == Stop {
    /// 지도에 찍힌 모든 후보를 단계 번호와 함께 펼친다. 렌더가 쓴다.
    func flattened() -> [(place: MapPlace, stopNumber: Int)] {
        enumerated().flatMap { index, stop in
            stop.candidates.map { (place: $0, stopNumber: index + 1) }
        }
    }

    /// 후보 id로 그것이 속한 단계의 번호를 찾는다. 핀을 눌렀을 때 쓴다.
    func stopNumber(ofCandidate id: String) -> Int? {
        firstIndex { $0.candidates.contains { $0.id == id } }.map { $0 + 1 }
    }
}
