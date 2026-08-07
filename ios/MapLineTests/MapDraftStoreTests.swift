import XCTest
@testable import MapLine

final class MapDraftStoreTests: XCTestCase {
    private var folder: URL!
    private var store: MapDraftStore!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MapDraftStoreTests-\(UUID().uuidString)")
        store = MapDraftStore(fileURL: folder.appendingPathComponent("draft.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        store = nil
        folder = nil
        super.tearDown()
    }

    func test_현재지도와서버식별자를왕복한다() throws {
        let draft = MapDraft(
            document: MapDocument(
                title: "주말 코스",
                stops: [
                    Stop(candidates: [
                        MapPlace(name: "카페", location: GeoPoint(lat: 37.5, lng: 127.0))
                    ])
                ],
                labels: [MapLabel(location: GeoPoint(lat: 37.5, lng: 127.0), text: "예약")]
            ),
            slug: "abc123",
            updatedAt: "2026-08-06T10:00:00Z"
        )

        try store.save(draft)

        XCTAssertEqual(try store.load(), draft)
    }

    func test_초안을지우면다음실행에서복원하지않는다() throws {
        try store.save(MapDraft(document: MapDocument(title: "임시"), slug: nil, updatedAt: nil))
        try store.clear()
        XCTAssertNil(try store.load())
    }

    func test_현재파일이손상되면마지막정상백업을읽는다() throws {
        let first = MapDraft(document: MapDocument(title: "정상 백업"), slug: nil, updatedAt: nil)
        let second = MapDraft(document: MapDocument(title: "최신 초안"), slug: nil, updatedAt: nil)
        try store.save(first)
        try store.save(second)
        try Data("손상".utf8).write(to: store.fileURL, options: .atomic)

        XCTAssertEqual(try store.load(), first)
    }

    func test_현재파일과백업이모두손상되면빈지도로가장하지않는다() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("손상".utf8).write(to: store.fileURL, options: .atomic)
        try Data("백업도 손상".utf8).write(
            to: store.fileURL.appendingPathExtension("bak"),
            options: .atomic
        )

        XCTAssertThrowsError(try store.load())
    }
}
