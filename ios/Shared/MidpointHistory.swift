import Foundation

/// 중간지점 검색 한 번의 입력과 결과.
///
/// 후보 이름만 남기면 나중에 왜 그곳이 1순위였는지 알 수 없다. 참가자의 출발지와
/// 이동수단, 저장 가능한 경로를 함께 보관한다. 자동차 경로는 제공자 조건 때문에
/// 제외하고 다시 계산할 수 있다는 상태로 남긴다.
struct MidpointHistoryEntry: Codable, Identifiable {
    let id: String
    let searchedAt: Date
    let participants: [Midpoint.Participant]
    let result: Midpoint.Result

    init(
        id: String = UUID().uuidString,
        searchedAt: Date = Date(),
        participants: [Midpoint.Participant],
        result: Midpoint.Result
    ) {
        self.id = id
        self.searchedAt = searchedAt
        self.participants = participants
        self.result = result
    }

    var title: String {
        result.candidates.first?.place.name ?? "중간지점 검색"
    }
}

protocol MidpointHistoryStorage {
    func read() throws -> [MidpointHistoryEntry]
    func update(_ transform: @escaping (inout [MidpointHistoryEntry]) -> Void) throws
}

/// 검색 기록 규칙. 경로 좌표가 들어 있어 한 건의 크기가 작지 않으므로 최근 20건만 둔다.
struct MidpointHistoryStore {
    static let live = MidpointHistoryStore(storage: MidpointHistoryFileStorage())
    static let maximumCount = 20

    private let storage: MidpointHistoryStorage

    init(storage: MidpointHistoryStorage) {
        self.storage = storage
    }

    func all() throws -> [MidpointHistoryEntry] {
        try storage.read().sorted { $0.searchedAt > $1.searchedAt }
    }

    @discardableResult
    func add(
        participants: [Midpoint.Participant],
        result: Midpoint.Result,
        searchedAt: Date = Date()
    ) throws -> MidpointHistoryEntry {
        let entry = MidpointHistoryEntry(
            searchedAt: searchedAt,
            participants: participants,
            result: result.historySnapshot()
        )
        try storage.update { entries in
            entries.removeAll { $0.id == entry.id }
            entries.insert(entry, at: 0)
            entries.sort { $0.searchedAt > $1.searchedAt }
            if entries.count > Self.maximumCount {
                entries.removeLast(entries.count - Self.maximumCount)
            }
        }
        return entry
    }

    func remove(id: String) throws {
        try storage.update { $0.removeAll { $0.id == id } }
    }
}

/// 앱의 Application Support 폴더에 JSON으로 보관한다.
/// UserDefaults에는 실제 경로 좌표처럼 큰 배열을 넣지 않는다.
struct MidpointHistoryFileStorage: MidpointHistoryStorage {
    private static let directoryName = "MapLine"
    private static let fileName = "midpoint-history.json"

    private var fileURL: URL? {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return root.appendingPathComponent(Self.directoryName, isDirectory: true)
            .appendingPathComponent(Self.fileName)
    }

    func read() throws -> [MidpointHistoryEntry] {
        guard let url = fileURL else {
            throw LocalDataStoreError.unavailable("중간지점 검색 기록")
        }
        return try SafeJSONCollectionFile<MidpointHistoryEntry>(
            fileURL: url,
            displayName: "중간지점 검색 기록"
        ).read()
    }

    func update(_ transform: @escaping (inout [MidpointHistoryEntry]) -> Void) throws {
        guard let url = fileURL else {
            throw LocalDataStoreError.unavailable("중간지점 검색 기록")
        }
        try SafeJSONCollectionFile<MidpointHistoryEntry>(
            fileURL: url,
            displayName: "중간지점 검색 기록"
        ).update(transform)
    }
}
