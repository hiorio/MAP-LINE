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

/// 지도 위 메모 한 줄.
struct MapLabel: Identifiable, Equatable, Codable {
    let id: String
    var location: GeoPoint
    var text: String
    var fontSize: Double
    var color: String

    init(
        id: String = UUID().uuidString,
        location: GeoPoint,
        text: String,
        fontSize: Double = 14,
        color: String = MapPalette.label
    ) {
        self.id = id
        self.location = location
        self.text = text
        self.fontSize = fontSize
        self.color = color
    }
}

/// 지도 한 장에 담기는 전부. 서버에 이 모양 그대로 오간다.
///
/// 웹 `MapDocument`와 키 이름까지 같아야 한다. 같은 링크를 웹과 앱이 함께 열고
/// 함께 고치기 때문에, 한쪽만 키를 바꾸면 다른 쪽에서 그 부분이 조용히 사라진다.
struct MapDocument: Equatable, Codable {
    var title: String
    var center: GeoPoint
    var zoomLevel: Int
    var stops: [Stop]
    /// 단계 사이 구간. 길이는 항상 max(0, 단계 수 - 1)이다.
    var legs: [StopLeg]
    var strokes: [GeoStroke]
    var labels: [MapLabel]
    /// 자동으로 그리는 선을 켤지 끌지.
    ///
    /// 문서에 담는 이유: 만든 사람이 직접 동선을 그리고 자동 화살표를 껐다면, 링크를
    /// 받은 사람에게도 꺼져 있어야 한다. 편집기 개인 설정으로 두면 공유된 지도가
    /// 만든 사람이 의도한 모습과 달라진다.
    var showCandidateLinks: Bool
    var showStopArrows: Bool

    init(
        title: String = "",
        center: GeoPoint = MapPalette.defaultCenter,
        zoomLevel: Int = 3,
        stops: [Stop] = [],
        legs: [StopLeg] = [],
        strokes: [GeoStroke] = [],
        labels: [MapLabel] = [],
        showCandidateLinks: Bool = true,
        showStopArrows: Bool = true
    ) {
        self.title = title
        self.center = center
        self.zoomLevel = MapZoom.normalizedDocumentLevel(zoomLevel)
        self.stops = stops
        self.legs = legs
        self.strokes = strokes.map { $0.normalizingDocumentZoomLevel() }
        self.labels = labels
        self.showCandidateLinks = showCandidateLinks
        self.showStopArrows = showStopArrows
    }

    /// 서버가 예전 지도를 줄 때 없는 칸이 있을 수 있다. 그때 통째로 실패하면
    /// 지도를 아예 못 연다. 빠진 것은 기본값으로 채운다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        center = try container.decodeIfPresent(GeoPoint.self, forKey: .center) ?? MapPalette.defaultCenter
        zoomLevel = MapZoom.normalizedDocumentLevel(
            try container.decodeIfPresent(Int.self, forKey: .zoomLevel) ?? 3
        )
        stops = try container.decodeIfPresent([Stop].self, forKey: .stops) ?? []
        legs = try container.decodeIfPresent([StopLeg].self, forKey: .legs) ?? []
        let decodedStrokes = try container.decodeIfPresent([GeoStroke].self, forKey: .strokes) ?? []
        strokes = decodedStrokes.map { $0.normalizingDocumentZoomLevel() }
        labels = try container.decodeIfPresent([MapLabel].self, forKey: .labels) ?? []
        showCandidateLinks = try container.decodeIfPresent(Bool.self, forKey: .showCandidateLinks) ?? true
        showStopArrows = try container.decodeIfPresent(Bool.self, forKey: .showStopArrows) ?? true
    }
}

/// 웹과 맞춘 값들.
enum MapPalette {
    static let pin = "#E24B4A"
    static let stroke = "#2D6BE4"
    static let strokeWidth: Double = 4
    static let label = "#2C2C2A"
    /// 강남역. 위치 권한 없이 첫 화면을 채우기 위한 기본값이다.
    static let defaultCenter = GeoPoint(lat: 37.4979, lng: 127.0276)
}

extension Array where Element == Stop {
    /// 이미 있는 단계에 후보를 더한다.
    ///
    /// 웹 `useMapStore.addCandidates`와 같은 규칙이다. 단계 수와 id는 그대로 두고
    /// 후보 배열만 늘린다. 대표가 이미 정해져 있다면 그 선택도 유지한다.
    @discardableResult
    mutating func addCandidates(_ candidates: [MapPlace], toStopID stopID: String) -> Bool {
        guard !candidates.isEmpty, let index = firstIndex(where: { $0.id == stopID }) else {
            return false
        }
        self[index].candidates.append(contentsOf: candidates)
        return true
    }

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

extension Array where Element == MapLabel {
    /// 메모의 내용과 위치를 id로 고친다. 없는 id는 아무것도 바꾸지 않는다.
    @discardableResult
    mutating func updateLabel(
        id: String,
        text: String? = nil,
        location: GeoPoint? = nil
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == id }) else { return false }
        if let text { self[index].text = text }
        if let location { self[index].location = location }
        return true
    }
}
