#if DEBUG
import Foundation

/// 심사용 캡처를 매번 같은 내용으로 만드는 UI 테스트 전용 문서.
/// 실제 사용자 실행과 Release 빌드에는 포함되지 않는다.
enum AppStorePreview {
    static let seongsuDate: MapDocument = {
        let places = [
            MapPlace(id: "30000000-0000-4000-8000-000000000001", name: "왕십리역", location: point(37.5611, 127.0375)),
            MapPlace(id: "30000000-0000-4000-8000-000000000002", name: "서울숲", location: point(37.5444, 127.0374)),
            MapPlace(id: "30000000-0000-4000-8000-000000000003", name: "성수동 카페거리", location: point(37.5446, 127.0558)),
            MapPlace(id: "30000000-0000-4000-8000-000000000004", name: "뚝섬한강공원", location: point(37.5293, 127.0730)),
        ]
        let stops = places.enumerated().map { index, place in
            Stop(id: "31000000-0000-4000-8000-00000000000\(index + 1)", candidates: [place])
        }
        let routePoints: [[GeoPoint]] = [
            [places[0].location, point(37.5555, 127.0380), point(37.5498, 127.0378), places[1].location],
            [places[1].location, point(37.5447, 127.0435), point(37.5448, 127.0498), places[2].location],
            [places[2].location, point(37.5395, 127.0610), point(37.5345, 127.0670), places[3].location],
        ]
        let distances = [2_200, 1_600, 3_300]
        let durations = [31, 23, 18].map { $0 * 60 }
        let modes: [TravelMode] = [.walk, .walk, .transit]
        let fetchedAt = "2026-08-06T00:00:00Z"
        let legs = routePoints.indices.map { index in
            StopLeg(
                mode: modes[index],
                route: RoutePath(
                    points: routePoints[index],
                    distanceM: distances[index],
                    durationS: durations[index],
                    legs: nil,
                    fromPlaceId: places[index].id,
                    toPlaceId: places[index + 1].id,
                    fetchedAt: fetchedAt
                )
            )
        }

        return MapDocument(
            title: "성수 데이트 코스",
            center: point(37.5450, 127.0530),
            zoomLevel: 6,
            stops: stops,
            legs: legs,
            labels: [
                MapLabel(id: "32000000-0000-4000-8000-000000000001", location: point(37.5635, 127.0500), text: "오후 1시 · 왕십리역에서 만나기"),
                MapLabel(id: "32000000-0000-4000-8000-000000000002", location: point(37.5485, 127.0280), text: "서울숲 산책하며 사진 찍기"),
                MapLabel(id: "32000000-0000-4000-8000-000000000003", location: point(37.5500, 127.0660), text: "카페에서 다음 여행 계획"),
                MapLabel(id: "32000000-0000-4000-8000-000000000004", location: point(37.5260, 127.0590), text: "저녁 먹고 한강 노을 보기"),
            ]
        )
    }()

    static let gangwonTrip: MapDocument = {
        let places = [
            MapPlace(id: "00000000-0000-4000-8000-000000000001", name: "속초아이", location: point(38.1907, 128.6020)),
            MapPlace(id: "00000000-0000-4000-8000-000000000002", name: "속초관광수산시장", location: point(38.2045, 128.5900)),
            MapPlace(id: "00000000-0000-4000-8000-000000000003", name: "설악산국립공원", location: point(38.1730, 128.4890)),
            MapPlace(id: "00000000-0000-4000-8000-000000000004", name: "낙산사", location: point(38.1253, 128.6277)),
            MapPlace(id: "00000000-0000-4000-8000-000000000005", name: "하조대 전망대", location: point(38.0264, 128.7349)),
            MapPlace(id: "00000000-0000-4000-8000-000000000006", name: "주문진항", location: point(37.8928, 128.8290)),
            MapPlace(id: "00000000-0000-4000-8000-000000000007", name: "경포대", location: point(37.7950, 128.8966)),
        ]
        let stops = places.enumerated().map { index, place in
            Stop(id: "10000000-0000-4000-8000-00000000000\(index + 1)", candidates: [place])
        }

        let routePoints: [[GeoPoint]] = [
            [places[0].location, point(38.1960, 128.5990), point(38.2020, 128.5930), places[1].location],
            [places[1].location, point(38.2020, 128.5710), point(38.1910, 128.5400), point(38.1800, 128.5060), places[2].location],
            [places[2].location, point(38.1610, 128.5230), point(38.1470, 128.5650), point(38.1350, 128.6030), places[3].location],
            [places[3].location, point(38.0980, 128.6580), point(38.0630, 128.6960), places[4].location],
            [places[4].location, point(37.9880, 128.7600), point(37.9440, 128.7900), places[5].location],
            [places[5].location, point(37.8550, 128.8520), point(37.8240, 128.8760), places[6].location],
        ]
        let distances = [2_800, 17_600, 27_400, 15_900, 20_300, 18_100]
        let durations = [12, 42, 52, 31, 38, 34].map { $0 * 60 }
        let fetchedAt = "2026-08-06T00:00:00Z"
        let legs = routePoints.indices.map { index in
            StopLeg(
                mode: .transit,
                route: RoutePath(
                    points: routePoints[index],
                    distanceM: distances[index],
                    durationS: durations[index],
                    legs: nil,
                    fromPlaceId: places[index].id,
                    toPlaceId: places[index + 1].id,
                    fetchedAt: fetchedAt
                )
            )
        }

        return MapDocument(
            title: "강원 동해안 2박 3일",
            center: point(38.0000, 128.7000),
            zoomLevel: 9,
            stops: stops,
            legs: legs,
            labels: [
                MapLabel(
                    id: "20000000-0000-4000-8000-000000000001",
                    location: point(37.9580, 128.7950),
                    text: "바다 보며 쉬어가기"
                ),
            ]
        )
    }()

    /// 개인 보관함 마커의 색·심볼이 지도에서 서로 구별되는지 보는 고정 자료.
    static let savedPlaceGroups: [SavedPlaceGroup] = [
        SavedPlaceGroup(
            id: "preview-cafes",
            name: "가고 싶은 카페",
            marker: .coffee,
            colorHex: "#9B5DE5",
            createdAt: "2026-08-06T00:00:00Z"
        ),
        SavedPlaceGroup(
            id: "preview-food",
            name: "데이트 맛집",
            marker: .food,
            colorHex: "#F08A24",
            createdAt: "2026-08-06T00:00:00Z"
        ),
        SavedPlaceGroup(
            id: "preview-favorites",
            name: "다시 갈 곳",
            marker: .heart,
            colorHex: "#E84A5F",
            createdAt: "2026-08-06T00:00:00Z"
        ),
    ]

    static let savedPlaces: [SavedPlace] = [
        SavedPlace(
            id: "preview-place-cafe",
            name: "서울숲 카페",
            lat: 37.5488,
            lng: 127.0432,
            savedAt: "2026-08-06T00:00:03Z",
            groupID: "preview-cafes"
        ),
        SavedPlace(
            id: "preview-place-food",
            name: "성수 저녁식사",
            lat: 37.5403,
            lng: 127.0572,
            savedAt: "2026-08-06T00:00:02Z",
            groupID: "preview-food"
        ),
        SavedPlace(
            id: "preview-place-favorite",
            name: "한강 노을 자리",
            lat: 37.5325,
            lng: 127.0670,
            savedAt: "2026-08-06T00:00:01Z",
            groupID: "preview-favorites"
        ),
    ]

    private static func point(_ lat: Double, _ lng: Double) -> GeoPoint {
        GeoPoint(lat: lat, lng: lng)
    }
}
#endif
