import XCTest
@testable import MapLine

/// 서버에 오가는 문서의 모양.
///
/// 같은 링크를 웹과 앱이 함께 열고 함께 고친다. 키 이름이 하나만 달라도 그 부분이
/// 조용히 사라지는데, 사라진 줄은 링크를 열어 보기 전까지 아무도 모른다.
final class MapDocumentTests: XCTestCase {
    private func json(_ document: MapDocument) throws -> [String: Any] {
        let data = try JSONEncoder().encode(document)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func test_웹과같은키로내보낸다() throws {
        let encoded = try json(MapDocument())
        XCTAssertEqual(
            Set(encoded.keys),
            [
                "title", "center", "zoomLevel", "stops", "legs",
                "strokes", "labels", "showCandidateLinks", "showStopArrows",
            ]
        )
    }

    func test_획은색과굵기를함께담는다() throws {
        // 앱에서 이 값을 빼면 웹이 그 지도를 열 때 획이 기본색으로 바뀐다.
        let document = MapDocument(strokes: [
            GeoStroke(path: [GeoPoint(lat: 1, lng: 1), GeoPoint(lat: 2, lng: 2)], zoomCreated: 3),
        ])
        let stroke = try XCTUnwrap((try json(document))["strokes"] as? [[String: Any]])
        XCTAssertEqual(stroke.first?["color"] as? String, "#2D6BE4")
        XCTAssertEqual(stroke.first?["width"] as? Double, 4)
        XCTAssertEqual(stroke.first?["zoomCreated"] as? Int, 3)
        // id는 문자열로 나가야 한다. 웹의 Stroke.id가 string이다.
        XCTAssertNotNil(stroke.first?["id"] as? String)
    }

    func test_빠진칸이있어도지도를연다() throws {
        // 예전에 만든 지도에는 나중에 생긴 칸이 없다. 통째로 실패하면 그 지도를
        // 아예 못 여는데, 그건 없는 칸 하나보다 훨씬 나쁘다.
        let old = Data("""
        {"title":"옛 지도","center":{"lat":37.5,"lng":127.0},"zoomLevel":4,"stops":[]}
        """.utf8)

        let document = try JSONDecoder().decode(MapDocument.self, from: old)
        XCTAssertEqual(document.title, "옛 지도")
        XCTAssertEqual(document.zoomLevel, 4)
        XCTAssertTrue(document.legs.isEmpty)
        XCTAssertTrue(document.strokes.isEmpty)
        // 안 적힌 표시 설정은 켜진 것으로 본다. 웹의 기본값과 같다.
        XCTAssertTrue(document.showCandidateLinks)
        XCTAssertTrue(document.showStopArrows)
    }

    func test_서버가섞어보내는칸은무시한다() throws {
        // GET 응답은 문서와 updatedAt이 한 객체에 섞여 온다. 모르는 키 때문에
        // 디코딩이 실패하면 불러오기가 통째로 안 된다.
        let body = Data("""
        {"title":"","center":{"lat":37.5,"lng":127.0},"zoomLevel":3,"stops":[],
         "legs":[],"strokes":[],"labels":[],"showCandidateLinks":true,
         "showStopArrows":true,"updatedAt":"2026-08-04T00:00:00Z"}
        """.utf8)
        XCTAssertNoThrow(try JSONDecoder().decode(MapDocument.self, from: body))
    }

    func test_한바퀴돌아도같다() throws {
        let original = MapDocument(
            title: "강남 코스",
            center: GeoPoint(lat: 37.4979, lng: 127.0276),
            zoomLevel: 5,
            stops: [Stop(candidates: [MapPlace(name: "강남역", location: GeoPoint(lat: 37.5, lng: 127.0))])],
            legs: [],
            strokes: [GeoStroke(path: [GeoPoint(lat: 1, lng: 1), GeoPoint(lat: 2, lng: 2)], zoomCreated: 3)],
            labels: [MapLabel(location: GeoPoint(lat: 1, lng: 1), text: "여기")],
            showCandidateLinks: false,
            showStopArrows: false
        )

        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(MapDocument.self, from: data), original)
    }

    func test_공유링크는웹이여는주소다() {
        // 앱에서 만든 지도를 웹 링크로 열 수 있어야 한다. 링크 하나로 나눠 보는 것이
        // 이 제품의 전부라 여기가 갈라지면 안 된다.
        XCTAssertEqual(MapStore.shareURL(slug: "abc123").path, "/m/abc123")
    }

    func test_웹문서와네이티브지도의줌레벨을같은축척으로바꾼다() {
        XCTAssertEqual(MapZoom.nativeLevel(fromDocumentLevel: 3), 17)
        XCTAssertEqual(MapZoom.documentLevel(fromNativeLevel: 17), 3)
        XCTAssertEqual(MapZoom.nativeLevel(fromDocumentLevel: 14), 6)
        XCTAssertEqual(MapZoom.documentLevel(fromNativeLevel: 21), 1)
    }

    func test_예전앱이남긴네이티브줌레벨을문서레벨로복구한다() throws {
        let body = Data("""
        {"title":"옛 앱 지도","center":{"lat":37.5,"lng":127.0},"zoomLevel":17,
         "stops":[],"strokes":[{"id":"00000000-0000-0000-0000-000000000001",
         "path":[{"lat":37.5,"lng":127.0},{"lat":37.51,"lng":127.01}],
         "color":"#2D6BE4","width":4,"zoomCreated":17}]}
        """.utf8)

        let document = try JSONDecoder().decode(MapDocument.self, from: body)
        XCTAssertEqual(document.zoomLevel, 3)
        XCTAssertEqual(document.strokes.first?.zoomCreated, 3)
    }

    func test_메모를옮겨도id와내용은유지된다() {
        let id = UUID().uuidString
        var labels = [
            MapLabel(id: id, location: GeoPoint(lat: 37.5, lng: 127.0), text: "입구"),
        ]

        XCTAssertTrue(labels.updateLabel(id: id, location: GeoPoint(lat: 37.6, lng: 127.1)))
        XCTAssertEqual(labels.first?.id, id)
        XCTAssertEqual(labels.first?.text, "입구")
        XCTAssertEqual(labels.first?.location, GeoPoint(lat: 37.6, lng: 127.1))
    }

    func test_메모내용을고치고없는id는건드리지않는다() {
        let original = MapLabel(location: GeoPoint(lat: 37.5, lng: 127.0), text: "전")
        var labels = [original]

        XCTAssertTrue(labels.updateLabel(id: original.id, text: "후"))
        XCTAssertEqual(labels.first?.text, "후")
        XCTAssertFalse(labels.updateLabel(id: "missing", text: "바뀌면 안 됨"))
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(labels.first?.text, "후")
    }

    func test_메모드래그영역은짧은글자도손가락크기를보장하고긴글자는넓어진다() {
        let short = memoDragHitSize(
            MapLabel(location: GeoPoint(lat: 37.5, lng: 127.0), text: "A")
        )
        let long = memoDragHitSize(
            MapLabel(location: GeoPoint(lat: 37.5, lng: 127.0), text: "입구에서 만나요")
        )

        XCTAssertGreaterThanOrEqual(short.width, 44)
        XCTAssertGreaterThanOrEqual(short.height, 44)
        XCTAssertGreaterThan(long.width, short.width)
        XCTAssertLessThanOrEqual(long.width, 260)
    }

    func test_다른지도를열면핀경로손그림메모를모두카메라범위에넣는다() {
        let first = GeoPoint(lat: 37.5, lng: 127.0)
        let second = GeoPoint(lat: 37.6, lng: 127.1)
        let routeBend = GeoPoint(lat: 37.7, lng: 127.2)
        let strokePoint = GeoPoint(lat: 37.8, lng: 127.3)
        let memoPoint = GeoPoint(lat: 37.9, lng: 127.4)
        let route = RoutePath(
            points: [first, routeBend],
            distanceM: 1_000,
            durationS: 600,
            legs: nil,
            fromPlaceId: "first",
            toPlaceId: "second",
            fetchedAt: "2026-08-07T00:00:00Z"
        )
        let document = MapDocument(
            stops: [
                Stop(candidates: [MapPlace(id: "first", name: "첫 장소", location: first)]),
                Stop(candidates: [MapPlace(id: "second", name: "둘째 장소", location: second)]),
            ],
            legs: [StopLeg(mode: .walk, route: route)],
            strokes: [GeoStroke(path: [first, strokePoint], zoomCreated: 3)],
            labels: [MapLabel(location: memoPoint, text: "여기")]
        )

        let points = document.contentViewportPoints
        XCTAssertTrue(points.contains(first))
        XCTAssertTrue(points.contains(second))
        XCTAssertTrue(points.contains(routeBend))
        XCTAssertTrue(points.contains(strokePoint))
        XCTAssertTrue(points.contains(memoPoint))
    }
}
