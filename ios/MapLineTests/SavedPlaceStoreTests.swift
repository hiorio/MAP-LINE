import XCTest
@testable import MapLine

/// 보관함 규칙 테스트.
///
/// App Group은 서명된 빌드에서만 붙어서 CI의 시뮬레이터 빌드에서는 컨테이너가 없다.
/// 저장 위치가 무엇이든 규칙은 같아야 하므로 메모리 구현으로 규칙만 검증한다.
private final class MemoryStorage: SavedPlaceStorage {
    var places: [SavedPlace] = []
    func read() -> [SavedPlace] { places }
    func write(_ places: [SavedPlace]) { self.places = places }
}

final class SavedPlaceStoreTests: XCTestCase {
    private var storage: MemoryStorage!
    private var store: SavedPlaceStore!

    override func setUp() {
        super.setUp()
        storage = MemoryStorage()
        store = SavedPlaceStore(storage: storage)
    }

    private func place(
        _ name: String,
        id: String = UUID().uuidString,
        kakaoPlaceId: String? = nil,
        lat: Double = 37.5,
        lng: Double = 127.0,
        savedAt: String = "2026-08-01T00:00:00Z"
    ) -> SavedPlace {
        SavedPlace(id: id, name: name, kakaoPlaceId: kakaoPlaceId, lat: lat, lng: lng, savedAt: savedAt)
    }

    func test_담으면_목록에_들어간다() {
        XCTAssertTrue(store.add(place("스타벅스")))
        XCTAssertEqual(store.all().map(\.name), ["스타벅스"])
    }

    func test_같은_카카오_장소는_두_번_담기지_않는다() {
        // 공유로 담은 것과 앱에서 검색해 담은 것이 겹치면 목록이 지저분해진다.
        XCTAssertTrue(store.add(place("스타벅스", kakaoPlaceId: "111")))
        XCTAssertFalse(store.add(place("스타벅스 강남점", kakaoPlaceId: "111")))
        XCTAssertEqual(store.all().count, 1)
    }

    func test_id가_없으면_이름과_좌표로_같은_곳을_가린다() {
        // 지도를 직접 찍어 만든 지점에는 카카오 장소 id가 없다.
        XCTAssertTrue(store.add(place("우리집", lat: 37.5, lng: 127.0)))
        XCTAssertFalse(store.add(place("우리집", lat: 37.50001, lng: 127.00001)))
        XCTAssertEqual(store.all().count, 1)
    }

    func test_이름이_같아도_먼_곳이면_다른_곳이다() {
        XCTAssertTrue(store.add(place("스타벅스", lat: 37.5, lng: 127.0)))
        XCTAssertTrue(store.add(place("스타벅스", lat: 37.6, lng: 127.1)))
        XCTAssertEqual(store.all().count, 2)
    }

    func test_최근에_담은_것이_위로_온다() {
        // 공유로 방금 넣은 것을 앱에서 바로 찾을 수 있어야 한다.
        store.add(place("먼저", savedAt: "2026-08-01T00:00:00Z"))
        store.add(place("나중", savedAt: "2026-08-02T00:00:00Z"))
        XCTAssertEqual(store.all().map(\.name), ["나중", "먼저"])
    }

    func test_뺄_수_있다() {
        let target = place("뺄곳", id: "target")
        store.add(target)
        store.add(place("남을곳"))
        store.remove(id: "target")
        XCTAssertEqual(store.all().map(\.name), ["남을곳"])
    }
}

final class ShareIntakeTests: XCTestCase {
    func test_조각을_줄바꿈으로_잇는다() {
        // 앱마다 제목·본문·링크를 따로 넘긴다. 골라내지 않고 전부 붙여 서버에 맡긴다.
        let combined = ShareIntake.combine(["[카카오맵] 스타벅스", "서울 강남구", "http://kko.to/x"])
        XCTAssertEqual(combined, "[카카오맵] 스타벅스\n서울 강남구\nhttp://kko.to/x")
    }

    func test_빈_조각은_버린다() {
        XCTAssertEqual(ShareIntake.combine(["  ", "이름", ""]), "이름")
    }

    func test_아무것도_없으면_빈_문자열() {
        XCTAssertEqual(ShareIntake.combine([]), "")
        XCTAssertEqual(ShareIntake.combine(["", "   "]), "")
    }
}
