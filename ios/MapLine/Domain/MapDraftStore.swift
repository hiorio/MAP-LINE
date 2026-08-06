import Foundation

/// 지금 편집 중인 지도 한 장을 기기에 보관한다.
///
/// 서버 저장은 네트워크가 필요하지만 임시 저장은 언제나 성공해야 한다. 앱이 종료되거나
/// 백그라운드에서 정리돼도 마지막 손질을 복원할 수 있도록 Application Support에 둔다.
struct MapDraft: Codable, Equatable {
    var document: MapDocument
    var slug: String?
    var updatedAt: String?
}

struct MapDraftStore {
    let fileURL: URL

    static var live: MapDraftStore {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return MapDraftStore(fileURL: base.appendingPathComponent("mapline-current-draft.json"))
    }

    func load() -> MapDraft? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(MapDraft.self, from: data)
    }

    func save(_ draft: MapDraft) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(draft)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
