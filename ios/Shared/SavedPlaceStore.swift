import Foundation

/// 보관함이 사는 곳.
///
/// 공유 익스텐션과 앱은 **서로 다른 프로세스**다. 익스텐션이 담은 장소를 앱이 보려면
/// 둘이 함께 볼 수 있는 저장소가 필요하고, 그것이 App Group이다.
///
/// 프로토콜로 갈라 두는 이유: App Group은 서명된 빌드에서만 붙는다. CI의 서명 없는
/// 시뮬레이터 빌드에서는 컨테이너가 없으므로, 규칙 자체를 검증하는 테스트는 메모리
/// 구현으로 돌린다. 저장 위치가 무엇이든 "중복은 담지 않는다" 같은 규칙은 같아야 한다.
protocol SavedPlaceStorage {
    func read() throws -> [SavedPlace]
    func update(_ transform: @escaping (inout [SavedPlace]) -> Void) throws
}

protocol SavedPlaceGroupStorage {
    func read() throws -> [SavedPlaceGroup]
    func update(_ transform: @escaping (inout [SavedPlaceGroup]) -> Void) throws
}

/// 보관함 규칙. 어디에 저장하든 이 규칙은 같다.
struct SavedPlaceStore {
    private let storage: SavedPlaceStorage

    init(storage: SavedPlaceStorage) {
        self.storage = storage
    }

    func all() throws -> [SavedPlace] {
        // 최근에 담은 것이 위로. 공유로 방금 넣은 것을 앱에서 바로 찾을 수 있어야 한다.
        try storage.read().sorted { $0.savedAt > $1.savedAt }
    }

    func all(in groupID: String) throws -> [SavedPlace] {
        try all().filter { $0.groupID == groupID }
    }

    /// 담는다. 이미 있는 곳이면 아무 일도 하지 않는다.
    /// - Returns: 실제로 담겼으면 true.
    @discardableResult
    func add(_ place: SavedPlace) throws -> Bool {
        try add([place]) == 1
    }

    /// 공유로 고른 여러 장소를 한 번의 조정된 파일 갱신으로 담는다.
    /// 앱과 익스텐션이 동시에 저장해도 중간 항목이 사라지지 않는다.
    @discardableResult
    func add(_ newPlaces: [SavedPlace]) throws -> Int {
        var addedCount = 0
        try storage.update { places in
            for place in newPlaces where !places.contains(where: { isSamePlace($0, place) }) {
                places.append(place)
                addedCount += 1
            }
        }
        return addedCount
    }

    func remove(id: String) throws {
        try storage.update { $0.removeAll { $0.id == id } }
    }

    func move(id: String, to groupID: String) throws {
        try move(ids: Set([id]), to: groupID)
    }

    /// 선택한 여러 장소를 한 번의 파일 쓰기로 옮긴다. 한 곳씩 쓸 경우 공유 익스텐션이
    /// 같은 파일을 읽는 사이에 절반만 이동한 상태가 보일 수 있다.
    func move(ids: Set<String>, to groupID: String) throws {
        guard !ids.isEmpty else { return }
        try storage.update { places in
            places = places.map { place in
                ids.contains(place.id) ? place.assigned(to: groupID) : place
            }
        }
    }

    func moveAll(from sourceGroupID: String, to targetGroupID: String) throws {
        try storage.update { places in
            places = places.map { place in
                place.groupID == sourceGroupID ? place.assigned(to: targetGroupID) : place
            }
        }
    }

    /// 앱 안 검색으로 장소를 특정 폴더에 담는다. 이미 다른 폴더에 있으면 복제하지 않고
    /// 그 항목을 옮긴다. 공유 익스텐션의 `add`는 기존 분류를 받은 장소로 되돌리지 않는다.
    @discardableResult
    func addOrMove(_ place: SavedPlace, to groupID: String) throws -> Bool {
        var changed = false
        try storage.update { places in
            if let index = places.firstIndex(where: { isSamePlace($0, place) }) {
                guard places[index].groupID != groupID else { return }
                places[index] = places[index].assigned(to: groupID)
            } else {
                places.append(place.assigned(to: groupID))
            }
            changed = true
        }
        return changed
    }
}

struct SavedPlaceGroupStore {
    private let storage: SavedPlaceGroupStorage

    init(storage: SavedPlaceGroupStorage) {
        self.storage = storage
    }

    func all() throws -> [SavedPlaceGroup] {
        // JSON 배열 순서가 사용자가 정한 폴더 순서다. 예전 파일도 생성 순서대로
        // 저장돼 있으므로 별도 마이그레이션 없이 그대로 이어진다.
        let custom = try storage.read()
            .filter { $0.id != SavedPlaceGroup.inboxID }
        return [SavedPlaceGroup.inbox] + custom
    }

    @discardableResult
    func add(_ group: SavedPlaceGroup) throws -> Bool {
        let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        var added = false
        try storage.update { groups in
            groups.removeAll { $0.id == SavedPlaceGroup.inboxID }
            guard !groups.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
            else { return }
            var stored = group
            stored.name = name
            groups.append(stored)
            added = true
        }
        return added
    }

    func update(_ group: SavedPlaceGroup) throws {
        guard group.id != SavedPlaceGroup.inboxID else { return }
        let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        try storage.update { groups in
            groups.removeAll { $0.id == SavedPlaceGroup.inboxID }
            guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
            groups[index].name = name
            groups[index].marker = group.marker
            groups[index].colorHex = group.colorHex
        }
    }

    func remove(id: String) throws {
        guard id != SavedPlaceGroup.inboxID else { return }
        try storage.update { groups in
            groups.removeAll { $0.id == id || $0.id == SavedPlaceGroup.inboxID }
        }
    }

    /// 받은 장소는 항상 맨 위에 고정하고 사용자 폴더만 원하는 순서로 저장한다.
    func reorder(customGroupIDs: [String]) throws {
        try storage.update { groups in
            let current = groups.filter { $0.id != SavedPlaceGroup.inboxID }
            let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            var seen = Set<String>()
            var reordered = customGroupIDs.compactMap { id -> SavedPlaceGroup? in
                guard seen.insert(id).inserted else { return nil }
                return byID[id]
            }
            // 동시에 다른 프로세스가 만든 폴더가 목록에서 사라지지 않게 뒤에 보존한다.
            reordered.append(contentsOf: current.filter { !seen.contains($0.id) })
            groups = reordered
        }
    }
}

/// App Group 컨테이너에 JSON 파일로 남긴다.
///
/// UserDefaults가 아니라 파일인 이유: 보관함은 목록이라 커질 수 있고, 익스텐션과 앱이
/// 번갈아 쓰는 값이다. UserDefaults의 App Group 공유는 프로세스 간 갱신 시점이
/// 미묘해서 방금 담은 것이 앱에서 안 보이는 일이 생긴다. 파일은 읽는 순간의 내용이 확실하다.
struct AppGroupPlaceStorage: SavedPlaceStorage {
    /// 앱과 익스텐션이 같은 값을 써야 한다. 다르면 서로의 저장소를 못 본다.
    static let appGroupID = "group.com.hiorio.mapline"
    private static let fileName = "saved-places.json"

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent(Self.fileName)
    }

    func read() throws -> [SavedPlace] {
        guard let url = fileURL else {
            throw LocalDataStoreError.unavailable("보관함")
        }
        return try SafeJSONCollectionFile<SavedPlace>(
            fileURL: url,
            displayName: "보관함"
        ).read()
    }

    func update(_ transform: @escaping (inout [SavedPlace]) -> Void) throws {
        guard let url = fileURL else {
            throw LocalDataStoreError.unavailable("보관함")
        }
        try SafeJSONCollectionFile<SavedPlace>(
            fileURL: url,
            displayName: "보관함"
        ).update(transform)
    }
}

struct AppGroupSavedPlaceGroupStorage: SavedPlaceGroupStorage {
    private static let fileName = "saved-place-groups.json"

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroupPlaceStorage.appGroupID)?
            .appendingPathComponent(Self.fileName)
    }

    func read() throws -> [SavedPlaceGroup] {
        guard let url = fileURL else {
            throw LocalDataStoreError.unavailable("보관함 폴더")
        }
        return try SafeJSONCollectionFile<SavedPlaceGroup>(
            fileURL: url,
            displayName: "보관함 폴더"
        ).read()
    }

    func update(_ transform: @escaping (inout [SavedPlaceGroup]) -> Void) throws {
        guard let url = fileURL else {
            throw LocalDataStoreError.unavailable("보관함 폴더")
        }
        try SafeJSONCollectionFile<SavedPlaceGroup>(
            fileURL: url,
            displayName: "보관함 폴더"
        ).update(transform)
    }
}
