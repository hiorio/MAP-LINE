import XCTest
@testable import MapLine

/// 구간을 어떻게 그릴지 정하는 규칙.
///
/// 웹 `lib/map/legs.ts`·`lib/render/sceneGeometry.ts`와 같은 답을 내야 한다.
/// 여기가 어긋나면 같은 지도가 웹과 앱에서 다른 선으로 그려진다.
final class LegTests: XCTestCase {
    private func place(_ id: String, lat: Double = 37.5, lng: Double = 127.0) -> MapPlace {
        MapPlace(id: id, name: id, location: GeoPoint(lat: lat, lng: lng))
    }

    private func route(from: String, to: String, points: [GeoPoint], legs: [TransitLeg]? = nil) -> RoutePath {
        RoutePath(
            points: points,
            distanceM: 1000,
            durationS: 600,
            legs: legs,
            fromPlaceId: from,
            toPlaceId: to,
            fetchedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - 구간 길이

    func test_구간수는단계수보다하나적다() {
        let stops = [Stop(candidates: [place("a")]), Stop(candidates: [place("b")])]
        XCTAssertEqual(LegRules.synced(stops: stops, legs: []).count, 1)
        // 단계가 하나뿐이면 갈 곳이 없다.
        XCTAssertEqual(LegRules.synced(stops: [stops[0]], legs: []).count, 0)
        XCTAssertEqual(LegRules.synced(stops: [], legs: []).count, 0)
    }

    func test_길이를맞출때기존값을잃지않는다() {
        // 단계를 하나 더 담았다고 앞 구간의 이동수단이 초기화되면 안 된다.
        let stops = (0..<3).map { Stop(candidates: [place("\($0)")]) }
        let kept = LegRules.synced(stops: stops, legs: [StopLeg(mode: .walk)])
        XCTAssertEqual(kept.map(\.mode), [.walk, .straight])
    }

    func test_단계순서를바꾸면그대로남은인접구간만보존한다() {
        let a = Stop(id: "a", candidates: [place("pa")])
        let b = Stop(id: "b", candidates: [place("pb")])
        let c = Stop(id: "c", candidates: [place("pc")])
        let old = [a, b, c]
        let oldLegs = [StopLeg(mode: .walk), StopLeg(mode: .transit)]

        let reordered = LegRules.reordered(
            oldStops: old,
            newStops: [b, c, a],
            oldLegs: oldLegs
        )

        // b→c는 그대로지만 c→a는 새 구간이다.
        XCTAssertEqual(reordered.map(\.mode), [.transit, .straight])
    }

    // MARK: - 그려도 되는 경로인가

    func test_끝점이바뀌면경로를버린다() {
        // 후보를 갈아 끼웠는데 옛 경로를 계속 그리면 조용히 틀린 그림이 된다.
        let stops = [Stop(candidates: [place("a")]), Stop(candidates: [place("b")])]
        let stale = StopLeg(
            mode: .walk,
            route: route(from: "a", to: "다른곳", points: [GeoPoint(lat: 1, lng: 1), GeoPoint(lat: 2, lng: 2)])
        )
        XCTAssertNil(LegRules.drawableRoute(stops: stops, index: 0, leg: stale))
    }

    func test_대표를안정한단계로가는경로는그리지않는다() {
        let stops = [
            Stop(candidates: [place("a")]),
            Stop(candidates: [place("b"), place("c")]),
        ]
        let leg = StopLeg(
            mode: .walk,
            route: route(from: "a", to: "b", points: [GeoPoint(lat: 1, lng: 1), GeoPoint(lat: 2, lng: 2)])
        )
        XCTAssertNil(LegRules.drawableRoute(stops: stops, index: 0, leg: leg))
    }

    func test_낡은경로도일단그린다() {
        // 낡았다고 버리면 링크를 받은 사람 화면에서 선이 사라진다. 직선보다는 사실에 가깝다.
        let stops = [Stop(candidates: [place("a")]), Stop(candidates: [place("b")])]
        var old = route(from: "a", to: "b", points: [GeoPoint(lat: 1, lng: 1), GeoPoint(lat: 2, lng: 2)])
        old.fetchedAt = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -60 * 60 * 24 * 30))

        XCTAssertNotNil(LegRules.drawableRoute(stops: stops, index: 0, leg: StopLeg(mode: .walk, route: old)))
        // 다만 다시 받아야 할 대상으로는 잡힌다.
        XCTAssertTrue(LegRules.isStale(old))
        XCTAssertEqual(LegRules.needingRoute(stops: stops, legs: [StopLeg(mode: .walk, route: old)]), [0])
    }

    func test_읽을수없는시각은낡은것으로본다() {
        var broken = route(from: "a", to: "b", points: [])
        broken.fetchedAt = "언젠가"
        XCTAssertTrue(LegRules.isStale(broken))
    }

    // MARK: - 그릴 모양

    func test_경로가없으면단계의가운데를곧게잇는다() {
        let stops = [
            Stop(candidates: [place("a", lat: 37.0, lng: 127.0)]),
            Stop(candidates: [place("b", lat: 38.0, lng: 128.0)]),
        ]
        let shapes = legShapes(stops: stops, legs: [StopLeg(mode: .straight)])
        XCTAssertEqual(
            shapes,
            [.straight(from: GeoPoint(lat: 37.0, lng: 127.0), to: GeoPoint(lat: 38.0, lng: 128.0))]
        )
    }

    func test_대중교통은탈것구간마다자른다() {
        // 응답은 탈것 구간의 좌표만 이어 붙인 한 줄이다. 개수로 되잘라야
        // 어디부터 걷는 구간인지 알 수 있다.
        let points = (0..<5).map { GeoPoint(lat: 37.0 + Double($0) * 0.1, lng: 127.0) }
        let split = splitSegments(points, legs: [
            TransitLeg(type: "SUBWAY", guidance: "2호선", pointCount: 2),
            TransitLeg(type: "BUS", guidance: "146번", pointCount: 3),
        ])
        XCTAssertEqual(split.count, 2)
        XCTAssertEqual(split[0].count, 2)
        XCTAssertEqual(split[1].count, 3)
    }

    func test_구간정보가없으면통째로한줄이다() {
        // 잘못 자르느니 이어진 채로 두는 편이 낫다.
        let points = [GeoPoint(lat: 1, lng: 1), GeoPoint(lat: 2, lng: 2)]
        XCTAssertEqual(splitSegments(points, legs: nil).count, 1)
        XCTAssertEqual(
            splitSegments(points, legs: [TransitLeg(type: "BUS", guidance: "", pointCount: nil)]).count,
            1
        )
    }

    func test_좌표가안온부분을이어붙인다() {
        // 대중교통은 역과 역 사이만 온다. 출발지에서 첫 역까지가 비어 있으면
        // 선이 핀에 닿지 않는다. 그 사이를 연결선으로 채운다.
        let from = place("a", lat: 37.50, lng: 127.00)
        let to = place("b", lat: 37.60, lng: 127.00)
        let stops = [Stop(candidates: [from]), Stop(candidates: [to])]

        // 경로 좌표는 가운데 토막뿐이다.
        let leg = StopLeg(
            mode: .transit,
            route: route(
                from: "a",
                to: "b",
                points: [GeoPoint(lat: 37.53, lng: 127.0), GeoPoint(lat: 37.57, lng: 127.0)]
            )
        )

        guard case .path(let segments, let connectors, let mode) = legShapes(stops: stops, legs: [leg]).first
        else { return XCTFail("실제 경로로 그려져야 한다") }

        XCTAssertEqual(mode, .transit)
        XCTAssertEqual(segments.count, 1)
        // 앞뒤로 하나씩. 출발지→첫 좌표, 마지막 좌표→도착지.
        XCTAssertEqual(connectors.count, 2)
        XCTAssertEqual(connectors.first?.from, from.location)
        XCTAssertEqual(connectors.last?.to, to.location)
    }

    func test_끝점이딱맞으면연결선이없다() {
        // 이을 것이 없는데 길이 0짜리 도형을 만들면 안 된다.
        let from = place("a", lat: 37.5, lng: 127.0)
        let to = place("b", lat: 37.6, lng: 127.0)
        let stops = [Stop(candidates: [from]), Stop(candidates: [to])]
        let leg = StopLeg(
            mode: .walk,
            route: route(from: "a", to: "b", points: [from.location, to.location])
        )

        guard case .path(_, let connectors, _) = legShapes(stops: stops, legs: [leg]).first
        else { return XCTFail("실제 경로로 그려져야 한다") }
        XCTAssertTrue(connectors.isEmpty)
    }

    func test_도로에스냅된끝점까지이어붙인다() {
        // 카카오 길찾기는 요청한 좌표가 아니라 가장 가까운 도로 노드에서 끝난다.
        // 실측 25m. 처음엔 20m 미만을 걸러 냈는데 그게 바로 이 구간을 잘라 먹어,
        // 선이 핀에 닿지 않고 허공에서 끊겼다.
        let from = place("a", lat: 37.4995, lng: 127.0276)
        let to = place("b", lat: 37.4955, lng: 127.0245)
        let stops = [Stop(candidates: [from]), Stop(candidates: [to])]

        let snapped = GeoPoint(lat: 37.49558199, lng: 127.02476595) // 도착지에서 25m
        let leg = StopLeg(
            mode: .walk,
            route: route(from: "a", to: "b", points: [from.location, snapped])
        )

        guard case .path(_, let connectors, _) = legShapes(stops: stops, legs: [leg]).first
        else { return XCTFail("실제 경로로 그려져야 한다") }

        XCTAssertEqual(connectors.count, 1, "도로 노드에서 핀까지 이어져야 한다")
        XCTAssertEqual(connectors.first?.from, snapped)
        XCTAssertEqual(connectors.first?.to, to.location)
    }

    // MARK: - 구간 요약

    func test_경로요약은좌표개수가아니라선길이의중간에놓인다() throws {
        let from = place("a", lat: 0, lng: 0)
        let to = place("b", lat: 0, lng: 10)
        let stops = [Stop(candidates: [from]), Stop(candidates: [to])]
        let leg = StopLeg(
            mode: .walk,
            route: route(
                from: "a",
                to: "b",
                points: [from.location, GeoPoint(lat: 0, lng: 9), to.location]
            )
        )

        let annotation = try XCTUnwrap(legRouteAnnotations(stops: stops, legs: [leg]).first)
        XCTAssertEqual(annotation.location.lat, 0, accuracy: 1e-9)
        XCTAssertEqual(annotation.location.lng, 5, accuracy: 1e-9)
        XCTAssertEqual(annotation.text, "도보 · 1.0km · 10분")
    }

    func test_실제경로가없는직선에는시간표시를만들지않는다() {
        let stops = [Stop(candidates: [place("a")]), Stop(candidates: [place("b")])]
        XCTAssertTrue(
            legRouteAnnotations(stops: stops, legs: [StopLeg(mode: .straight)]).isEmpty
        )
    }

    // MARK: - 점선

    func test_점선은선과빈칸을번갈아낸다() {
        // 길이 10짜리 직선을 2 그리고 2 띄우면 세 조각이 나온다 (0-2, 4-6, 8-10).
        let path = [GeoPoint(lat: 0, lng: 0), GeoPoint(lat: 0, lng: 10)]
        let dashes = dashedSegments(path, onLength: 2, offLength: 2)

        XCTAssertEqual(dashes.count, 3)
        XCTAssertEqual(dashes[0].first?.lng ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(dashes[0].last?.lng ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(dashes[1].first?.lng ?? -1, 4, accuracy: 1e-9)
        XCTAssertEqual(dashes[2].first?.lng ?? -1, 8, accuracy: 1e-9)
    }

    func test_점선조각이선분경계를넘어이어진다() {
        // 꺾인 길에서 조각이 꼭짓점에 맞아떨어질 이유가 없다. 넘어가며 이어져야 한다.
        let path = [
            GeoPoint(lat: 0, lng: 0),
            GeoPoint(lat: 0, lng: 1),
            GeoPoint(lat: 0, lng: 2),
        ]
        let dashes = dashedSegments(path, onLength: 1.5, offLength: 0.5)
        // 첫 조각은 꼭짓점을 지나 1.5까지 간다. 중간 점이 살아 있어야 모양이 유지된다.
        XCTAssertEqual(dashes.first?.count, 3)
        XCTAssertEqual(dashes.first?.last?.lng ?? -1, 1.5, accuracy: 1e-9)
    }

    func test_점선은언제나끝점에닿는다() {
        // 빈칸 차례에 길이 끝나면 선이 핀 앞에서 끊긴 것처럼 보인다. 그건 그림의
        // 사실이 아니라 자른 방식의 부작용이다. CI 스크린샷에서 한쪽 핀은 닿고 다른
        // 쪽은 안 닿았는데, 어느 차례에 끝나느냐가 갈랐을 뿐이었다.
        //
        // 길이 10, 2 그리고 3 띄우면 0-2, 5-7까지 간 뒤 빈칸 차례에 끝난다.
        let path = [GeoPoint(lat: 0, lng: 0), GeoPoint(lat: 0, lng: 10)]
        let dashes = dashedSegments(path, onLength: 2, offLength: 3)

        XCTAssertEqual(dashes.last?.last?.lng ?? -1, 10, accuracy: 1e-9)
        // 마무리 조각은 끝에서 onLength만큼이다.
        XCTAssertEqual(dashes.last?.first?.lng ?? -1, 8, accuracy: 1e-9)
    }

    func test_꺾인길에서도끝점에닿는다() {
        let path = [
            GeoPoint(lat: 0, lng: 0),
            GeoPoint(lat: 0, lng: 4),
            GeoPoint(lat: 3, lng: 4),
        ]
        let dashes = dashedSegments(path, onLength: 1, offLength: 2.5)
        XCTAssertEqual(dashes.last?.last?.lat ?? -1, 3, accuracy: 1e-9)
        XCTAssertEqual(dashes.last?.last?.lng ?? -1, 4, accuracy: 1e-9)
    }

    func test_간격이없으면통째로하나다() {
        // 0이나 음수를 주면 무한 반복에 빠질 수 있다. 자르지 않고 돌려준다.
        let path = [GeoPoint(lat: 0, lng: 0), GeoPoint(lat: 0, lng: 1)]
        XCTAssertEqual(dashedSegments(path, onLength: 0, offLength: 1).count, 1)
        XCTAssertEqual(dashedSegments(path, onLength: 1, offLength: 0).count, 1)
    }
}
