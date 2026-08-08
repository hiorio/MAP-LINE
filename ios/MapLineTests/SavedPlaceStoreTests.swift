import XCTest
@testable import MapLine

/// 보관함 규칙 테스트.
///
/// App Group은 서명된 빌드에서만 붙어서 CI의 시뮬레이터 빌드에서는 컨테이너가 없다.
/// 저장 위치가 무엇이든 규칙은 같아야 하므로 메모리 구현으로 규칙만 검증한다.
private final class MemoryStorage: SavedPlaceStorage {
    var places: [SavedPlace] = []
    func read() throws -> [SavedPlace] { places }
    func update(_ transform: @escaping (inout [SavedPlace]) -> Void) throws { transform(&places) }
}

private final class MemoryGroupStorage: SavedPlaceGroupStorage {
    var groups: [SavedPlaceGroup] = []
    func read() throws -> [SavedPlaceGroup] { groups }
    func update(_ transform: @escaping (inout [SavedPlaceGroup]) -> Void) throws { transform(&groups) }
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
        savedAt: String = "2026-08-01T00:00:00Z",
        groupID: String = SavedPlaceGroup.inboxID
    ) -> SavedPlace {
        SavedPlace(
            id: id,
            name: name,
            kakaoPlaceId: kakaoPlaceId,
            lat: lat,
            lng: lng,
            savedAt: savedAt,
            groupID: groupID
        )
    }

    func test_담으면_목록에_들어간다() throws {
        XCTAssertTrue(try store.add(place("스타벅스")))
        XCTAssertEqual(try store.all().map(\.name), ["스타벅스"])
    }

    func test_같은_카카오_장소는_두_번_담기지_않는다() throws {
        // 공유로 담은 것과 앱에서 검색해 담은 것이 겹치면 목록이 지저분해진다.
        XCTAssertTrue(try store.add(place("스타벅스", kakaoPlaceId: "111")))
        XCTAssertFalse(try store.add(place("스타벅스 강남점", kakaoPlaceId: "111")))
        XCTAssertEqual(try store.all().count, 1)
    }

    func test_id가_없으면_이름과_좌표로_같은_곳을_가린다() throws {
        // 지도를 직접 찍어 만든 지점에는 카카오 장소 id가 없다.
        XCTAssertTrue(try store.add(place("우리집", lat: 37.5, lng: 127.0)))
        XCTAssertFalse(try store.add(place("우리집", lat: 37.50001, lng: 127.00001)))
        XCTAssertEqual(try store.all().count, 1)
    }

    func test_이름이_같아도_먼_곳이면_다른_곳이다() throws {
        XCTAssertTrue(try store.add(place("스타벅스", lat: 37.5, lng: 127.0)))
        XCTAssertTrue(try store.add(place("스타벅스", lat: 37.6, lng: 127.1)))
        XCTAssertEqual(try store.all().count, 2)
    }

    func test_최근에_담은_것이_위로_온다() throws {
        // 공유로 방금 넣은 것을 앱에서 바로 찾을 수 있어야 한다.
        try store.add(place("먼저", savedAt: "2026-08-01T00:00:00Z"))
        try store.add(place("나중", savedAt: "2026-08-02T00:00:00Z"))
        XCTAssertEqual(try store.all().map(\.name), ["나중", "먼저"])
    }

    func test_뺄_수_있다() throws {
        let target = place("뺄곳", id: "target")
        try store.add(target)
        try store.add(place("남을곳"))
        try store.remove(id: "target")
        XCTAssertEqual(try store.all().map(\.name), ["남을곳"])
    }

    func test_예전보관함파일은받은장소폴더로읽는다() throws {
        let oldJSON = Data(
            """
            {"id":"old","name":"옛 장소","lat":37.5,"lng":127.0,"savedAt":"2026-08-01T00:00:00Z"}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(SavedPlace.self, from: oldJSON)
        XCTAssertEqual(decoded.groupID, SavedPlaceGroup.inboxID)
    }

    func test_장소를다른폴더로옮긴다() throws {
        try store.add(place("카페", id: "cafe"))
        try store.move(id: "cafe", to: "favorites")

        XCTAssertTrue(try store.all(in: SavedPlaceGroup.inboxID).isEmpty)
        XCTAssertEqual(try store.all(in: "favorites").map(\.name), ["카페"])
    }

    func test_고른여러장소를한번에다른폴더로옮긴다() throws {
        try store.add(place("A", id: "a"))
        try store.add(place("B", id: "b", lat: 37.6))
        try store.add(place("남을 곳", id: "stay", lat: 37.7))

        try store.move(ids: ["a", "b"], to: "trip")

        XCTAssertEqual(Set(try store.all(in: "trip").map(\.id)), Set(["a", "b"]))
        XCTAssertEqual(try store.all(in: SavedPlaceGroup.inboxID).map(\.id), ["stay"])
    }

    func test_앱검색으로이미있는장소를새폴더에담으면복제하지않고옮긴다() throws {
        try store.add(place("카페", kakaoPlaceId: "111"))

        XCTAssertTrue(try store.addOrMove(place("카페 강남점", kakaoPlaceId: "111"), to: "cafe"))
        XCTAssertEqual(try store.all().count, 1)
        XCTAssertEqual(try store.all().first?.groupID, "cafe")
    }

    func test_폴더를지우기전에장소를미분류로모두옮긴다() throws {
        try store.add(place("A", groupID: "trip"))
        try store.add(place("B", lat: 37.6, groupID: "trip"))

        try store.moveAll(from: "trip", to: SavedPlaceGroup.inboxID)

        XCTAssertEqual(try store.all(in: SavedPlaceGroup.inboxID).count, 2)
        XCTAssertTrue(try store.all(in: "trip").isEmpty)
    }
}

final class SavedPlaceGroupStoreTests: XCTestCase {
    private var storage: MemoryGroupStorage!
    private var store: SavedPlaceGroupStore!

    override func setUp() {
        super.setUp()
        storage = MemoryGroupStorage()
        store = SavedPlaceGroupStore(storage: storage)
    }

    func test_복구용미분류폴더가저장데이터와호환된다() throws {
        XCTAssertEqual(try store.all(), [SavedPlaceGroup.inbox])
        XCTAssertEqual(SavedPlaceGroup.inbox.name, "미분류")
    }

    func test_폴더마크선택지가18종이다() {
        XCTAssertEqual(SavedPlaceMarker.allCases.count, 18)
        XCTAssertEqual(SavedPlaceMarker.nature.symbolName, "leaf.fill")
        XCTAssertEqual(SavedPlaceMarker.stay.title, "숙소")
    }

    func test_마크와색을가진폴더를만든다() throws {
        let cafe = SavedPlaceGroup(
            id: "cafe",
            name: "가고 싶은 카페",
            marker: .coffee,
            colorHex: "#7A55C7",
            createdAt: "2026-08-06T00:00:00Z"
        )

        XCTAssertTrue(try store.add(cafe))
        XCTAssertEqual(try store.all().map(\.id), [SavedPlaceGroup.inboxID, "cafe"])
        XCTAssertEqual(try store.all().last?.marker, .coffee)
        XCTAssertEqual(try store.all().last?.colorHex, "#7A55C7")
    }

    func test_같은이름폴더는대소문자와공백을무시하고중복생성하지않는다() throws {
        XCTAssertTrue(try store.add(SavedPlaceGroup(name: " 여행 ")))
        XCTAssertFalse(try store.add(SavedPlaceGroup(name: "여행")))
        XCTAssertEqual(try store.all().count, 2)
    }

    func test_기본폴더는지울수없다() throws {
        try store.remove(id: SavedPlaceGroup.inboxID)
        XCTAssertEqual(try store.all(), [SavedPlaceGroup.inbox])
    }

    func test_사용자가정한폴더순서를저장한다() throws {
        XCTAssertTrue(try store.add(SavedPlaceGroup(id: "a", name: "A")))
        XCTAssertTrue(try store.add(SavedPlaceGroup(id: "b", name: "B")))
        XCTAssertTrue(try store.add(SavedPlaceGroup(id: "c", name: "C")))

        try store.reorder(customGroupIDs: ["c", "a", "b"])

        XCTAssertEqual(try store.all().map(\.id), [SavedPlaceGroup.inboxID, "c", "a", "b"])
    }
}

final class SafeJSONCollectionFileTests: XCTestCase {
    func test_현재파일이손상되면마지막정상백업을읽는다() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafeJSONCollectionFileTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("places.json")
        let file = SafeJSONCollectionFile<SavedPlace>(fileURL: url, displayName: "테스트 보관함")
        let first = SavedPlace(name: "첫 장소", lat: 37.5, lng: 127.0)
        let second = SavedPlace(name: "둘째 장소", lat: 37.6, lng: 127.1)

        try file.update { $0.append(first) }
        try file.update { $0.append(second) }
        try Data("손상".utf8).write(to: url, options: .atomic)

        XCTAssertEqual(try file.read().map(\.name), ["첫 장소"])
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

    func test_여러공유장소응답을묶음으로읽는다() throws {
        let response = try JSONDecoder().decode(
            ShareIntake.Response.self,
            from: Data(
                """
                {"parsed":{"name":"A","address":"서울 강남구 길 1","region":"강남구","query":"A 강남구"},
                "groups":[{"parsed":{"name":"A","address":"서울 강남구 길 1","region":"강남구","query":"A 강남구"},
                "places":[{"kakaoPlaceId":"","name":"A","address":"서울 강남구 길 1","roadAddress":null,
                "category":null,"location":{"lat":37.5,"lng":127.0}}]}],"places":[]}
                """.utf8
            )
        )

        XCTAssertEqual(response.groups?.count, 1)
        XCTAssertEqual(response.groups?.first?.places.first?.name, "A")
        XCTAssertFalse(response.groups?.first?.places.first?.id.isEmpty ?? true)
    }
}
