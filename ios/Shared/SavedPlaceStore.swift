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
    func read() -> [SavedPlace]
    func write(_ places: [SavedPlace])
}

/// 보관함 규칙. 어디에 저장하든 이 규칙은 같다.
struct SavedPlaceStore {
    private let storage: SavedPlaceStorage

    init(storage: SavedPlaceStorage) {
        self.storage = storage
    }

    func all() -> [SavedPlace] {
        // 최근에 담은 것이 위로. 공유로 방금 넣은 것을 앱에서 바로 찾을 수 있어야 한다.
        storage.read().sorted { $0.savedAt > $1.savedAt }
    }

    /// 담는다. 이미 있는 곳이면 아무 일도 하지 않는다.
    /// - Returns: 실제로 담겼으면 true.
    @discardableResult
    func add(_ place: SavedPlace) -> Bool {
        var places = storage.read()
        guard !places.contains(where: { isSamePlace($0, place) }) else { return false }
        places.append(place)
        storage.write(places)
        return true
    }

    func remove(id: String) {
        storage.write(storage.read().filter { $0.id != id })
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

    func read() -> [SavedPlace] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SavedPlace].self, from: data)) ?? []
    }

    func write(_ places: [SavedPlace]) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(places) else { return }
        // 쓰다가 앱이 죽어도 반쪽짜리 파일이 남지 않게 원자적으로 바꾼다.
        try? data.write(to: url, options: .atomic)
    }
}
