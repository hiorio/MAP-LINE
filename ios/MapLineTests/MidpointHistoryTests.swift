import XCTest
@testable import MapLine

private final class MemoryMidpointHistoryStorage: MidpointHistoryStorage {
    var entries: [MidpointHistoryEntry] = []
    func read() throws -> [MidpointHistoryEntry] { entries }
    func update(_ transform: @escaping (inout [MidpointHistoryEntry]) -> Void) throws {
        transform(&entries)
    }
}

final class MidpointHistoryTests: XCTestCase {
    private var storage: MemoryMidpointHistoryStorage!
    private var store: MidpointHistoryStore!

    override func setUp() {
        super.setUp()
        storage = MemoryMidpointHistoryStorage()
        store = MidpointHistoryStore(storage: storage)
    }

    func test_검색하면_참가자_이동수단_결과경로를_함께_남긴다() throws {
        let participants = [participant(id: "a", mode: .walk), participant(id: "b", mode: .transit)]
        try store.add(participants: participants, result: result(name: "신용산역"))

        let entries = try store.all()
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.title, "신용산역")
        XCTAssertEqual(entry.participants.map(\.mode), [.walk, .transit])
        XCTAssertEqual(entry.result.candidates.first?.legs.first?.points?.count, 2)
    }

    func test_최근_검색이_위로_온다() throws {
        try store.add(
            participants: participants,
            result: result(name: "먼저"),
            searchedAt: Date(timeIntervalSince1970: 1)
        )
        try store.add(
            participants: participants,
            result: result(name: "나중"),
            searchedAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(try store.all().map(\.title), ["나중", "먼저"])
    }

    func test_최근_20건만_남긴다() throws {
        for index in 0..<25 {
            try store.add(
                participants: participants,
                result: result(name: "후보 \(index)"),
                searchedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        XCTAssertEqual(try store.all().count, MidpointHistoryStore.maximumCount)
        XCTAssertEqual(try store.all().first?.title, "후보 24")
        XCTAssertEqual(try store.all().last?.title, "후보 5")
    }

    func test_기록을_삭제할_수_있다() throws {
        let target = try store.add(participants: participants, result: result(name: "지울 곳"))
        try store.add(participants: participants, result: result(name: "남을 곳"))

        try store.remove(id: target.id)

        XCTAssertEqual(try store.all().map(\.title), ["남을 곳"])
    }

    func test_JSON으로_왕복해도_경로가_보존된다() throws {
        let original = MidpointHistoryEntry(participants: participants, result: result(name: "왕복"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MidpointHistoryEntry.self, from: data)

        XCTAssertEqual(decoded.participants.map(\.mode), [.walk, .transit])
        XCTAssertEqual(decoded.result.candidates.first?.legs.first?.points?.last?.lng, 127.01)
    }

    private var participants: [Midpoint.Participant] {
        [participant(id: "a", mode: .walk), participant(id: "b", mode: .transit)]
    }

    private func participant(id: String, mode: Midpoint.Participant.Mode) -> Midpoint.Participant {
        Midpoint.Participant(
            id: id,
            name: id.uppercased(),
            place: .init(name: "출발 \(id)", address: nil, lat: 37.5, lng: 127.0),
            mode: mode
        )
    }

    private func result(name: String) -> Midpoint.Result {
        let points = [
            PlaceCandidate.Coordinate(lat: 37.5, lng: 127.0),
            PlaceCandidate.Coordinate(lat: 37.51, lng: 127.01),
        ]
        let legs = participants.map { person in
            Midpoint.Candidate.Leg(
                participantId: person.id,
                mode: person.mode.rawValue,
                durationS: 600,
                distanceM: 1_000,
                points: points,
                transitLegs: nil
            )
        }
        return Midpoint.Result(
            center: .init(lat: 37.5, lng: 127.0),
            searchRadiusM: 3_000,
            candidates: [
                Midpoint.Candidate(
                    place: .init(
                        kakaoPlaceId: name,
                        name: name,
                        address: "서울",
                        location: .init(lat: 37.51, lng: 127.01)
                    ),
                    legs: legs,
                    maxDurationS: 600,
                    totalDurationS: 1_200,
                    spreadS: 0,
                    complete: true
                ),
            ]
        )
    }
}
