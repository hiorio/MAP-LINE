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

        XCTAssertEqual(store.load(), draft)
    }

    func test_초안을지우면다음실행에서복원하지않는다() throws {
        try store.save(MapDraft(document: MapDocument(title: "임시"), slug: nil, updatedAt: nil))
        try store.clear()
        XCTAssertNil(store.load())
    }
}
