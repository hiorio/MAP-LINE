#if DEBUG
import Foundation

/// 심사용 캡처를 매번 같은 내용으로 만드는 UI 테스트 전용 문서.
/// 실제 사용자 실행과 Release 빌드에는 포함되지 않는다.
enum AppStorePreview {
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

    private static func point(_ lat: Double, _ lng: Double) -> GeoPoint {
        GeoPoint(lat: lat, lng: lng)
    }
}
#endif
