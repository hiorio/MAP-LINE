import XCTest
@testable import MapLine

/// 내가 만든 지도 목록의 규칙.
///
/// 로그인이 없는 제품이라 "내 지도"는 이 기기가 편집 토큰을 가진 지도를 뜻한다.
/// 목록이 어긋나면 저장은 됐는데 다시 못 여는 상태가 되고, 그건 잃어버린 것과 같다.
final class MapStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        for entry in MapStore.rememberedMaps() + MapStore.hiddenMaps() {
            MapStore.discardLocalData(slug: entry.slug)
        }
    }

    override func tearDown() {
        for entry in MapStore.rememberedMaps() + MapStore.hiddenMaps() {
            MapStore.discardLocalData(slug: entry.slug)
        }
        super.tearDown()
    }

    func test_저장한지도가목록에남는다() {
        MapStore.remember(slug: "abc123", title: "강남 코스", stopCount: 3)
        XCTAssertEqual(MapStore.rememberedMaps().map(\.slug), ["abc123"])
        XCTAssertEqual(MapStore.rememberedMaps().first?.title, "강남 코스")
        XCTAssertEqual(MapStore.rememberedMaps().first?.stopCount, 3)
    }

    func test_같은지도를두번담지않는다() {
        // 저장할 때마다 목록에 올리므로, 겹쳐 쌓이면 한 지도가 여러 줄로 보인다.
        MapStore.remember(slug: "abc123", title: "처음 제목")
        MapStore.remember(slug: "abc123", title: "고친 제목")

        XCTAssertEqual(MapStore.rememberedMaps().count, 1)
        XCTAssertEqual(MapStore.rememberedMaps().first?.title, "고친 제목")
    }

    func test_예전내지도목록은단계수없이도읽는다() throws {
        let data = Data("""
        {"slug":"old","title":"옛 지도","savedAt":"2026-08-01T00:00:00Z"}
        """.utf8)

        let entry = try JSONDecoder().decode(MapStore.Entry.self, from: data)

        XCTAssertEqual(entry.title, "옛 지도")
        XCTAssertNil(entry.stopCount)
    }

    func test_최근에저장한것이위로온다() {
        let old = Date(timeIntervalSinceNow: -3600)
        MapStore.remember(slug: "오래된", title: "가", savedAt: old)
        MapStore.remember(slug: "최근", title: "나")

        XCTAssertEqual(MapStore.rememberedMaps().map(\.slug), ["최근", "오래된"])
    }

    func test_목록에서숨겨도편집자격을보존하고복원할수있다() {
        MapStore.storeEditToken("토큰", for: "abc123")
        MapStore.remember(slug: "abc123", title: "가")

        MapStore.hide(slug: "abc123")

        XCTAssertTrue(MapStore.rememberedMaps().isEmpty)
        XCTAssertEqual(MapStore.hiddenMaps().map(\.slug), ["abc123"])
        XCTAssertEqual(MapStore.editToken(for: "abc123"), "토큰")

        MapStore.restoreHidden(slug: "abc123")
        XCTAssertEqual(MapStore.rememberedMaps().map(\.slug), ["abc123"])
        XCTAssertTrue(MapStore.hiddenMaps().isEmpty)
    }

    func test_서버삭제확인뒤로컬자료를버린다() {
        MapStore.storeEditToken("토큰", for: "abc123")
        MapStore.remember(slug: "abc123", title: "가")

        MapStore.discardLocalData(slug: "abc123")

        XCTAssertTrue(MapStore.rememberedMaps().isEmpty)
        XCTAssertTrue(MapStore.hiddenMaps().isEmpty)
        XCTAssertNil(MapStore.editToken(for: "abc123"))
    }

    func test_편집자격이없으면저장을시도하지않는다() async {
        // 남의 지도에 저장을 보내면 서버가 401로 막지만, 그 전에 여기서 끝낸다.
        do {
            _ = try await MapStore.save(
                slug: "남의지도",
                document: MapDocument(),
                expectedUpdatedAt: nil
            )
            XCTFail("자격이 없는데 저장이 진행되었다")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("고칠 수 없는"),
                "왜 안 되는지 사람이 읽을 수 있어야 한다: \(error.localizedDescription)"
            )
        }
    }

    func test_복제본은이름만바꾸고지도내용을그대로둔다() {
        let source = MapDocument(
            title: "서울 하루",
            center: GeoPoint(lat: 37.5, lng: 127.0),
            stops: [Stop(candidates: [MapPlace(name: "카페", location: GeoPoint(lat: 37.5, lng: 127.0))])],
            labels: [MapLabel(location: GeoPoint(lat: 37.51, lng: 127.01), text: "약속")]
        )

        let copy = duplicatedMapDocument(source)

        XCTAssertEqual(copy.title, "서울 하루 복사본")
        XCTAssertEqual(copy.stops, source.stops)
        XCTAssertEqual(copy.labels, source.labels)
        XCTAssertEqual(copy.center, source.center)
    }

    func test_선택한단계만원래순서대로새동선으로분리한다() throws {
        let first = Stop(
            id: "first",
            candidates: [MapPlace(name: "강남", location: GeoPoint(lat: 37.50, lng: 127.02))]
        )
        let second = Stop(
            id: "second",
            candidates: [MapPlace(name: "신도림역", location: GeoPoint(lat: 37.51, lng: 126.89))]
        )
        let third = Stop(
            id: "third",
            candidates: [MapPlace(name: "공연장", location: GeoPoint(lat: 37.52, lng: 126.90))]
        )
        let source = MapDocument(
            title: "서울 하루",
            stops: [first, second, third],
            legs: [StopLeg(mode: .walk), StopLeg(mode: .transit)],
            strokes: [GeoStroke(path: [first.candidates[0].location], zoomCreated: 3)],
            labels: [MapLabel(location: first.candidates[0].location, text: "강남 메모")]
        )

        let extracted = try XCTUnwrap(
            extractedRouteDocument(
                from: source,
                selectedStopIDs: ["second", "third"],
                title: "신도림 동선"
            )
        )

        XCTAssertEqual(extracted.title, "신도림 동선")
        XCTAssertEqual(extracted.stops.map(\.id), ["second", "third"])
        XCTAssertEqual(extracted.legs.map(\.mode), [.transit])
        XCTAssertTrue(extracted.strokes.isEmpty)
        XCTAssertTrue(extracted.labels.isEmpty)
        XCTAssertEqual(extracted.center.lat, 37.515, accuracy: 0.000_001)
        XCTAssertEqual(extracted.center.lng, 126.895, accuracy: 0.000_001)
    }

    func test_떨어진단계끼리분리하면옛경로를잘못재사용하지않는다() throws {
        let stops = [
            Stop(id: "a", candidates: [MapPlace(name: "A", location: GeoPoint(lat: 1, lng: 1))]),
            Stop(id: "b", candidates: [MapPlace(name: "B", location: GeoPoint(lat: 2, lng: 2))]),
            Stop(id: "c", candidates: [MapPlace(name: "C", location: GeoPoint(lat: 3, lng: 3))]),
        ]
        let source = MapDocument(
            stops: stops,
            legs: [StopLeg(mode: .walk), StopLeg(mode: .transit)]
        )

        let extracted = try XCTUnwrap(
            extractedRouteDocument(from: source, selectedStopIDs: ["a", "c"], title: "새 동선")
        )

        XCTAssertEqual(extracted.legs.count, 1)
        XCTAssertEqual(extracted.legs.first?.mode, .straight)
        XCTAssertNil(extracted.legs.first?.route)
    }
}
