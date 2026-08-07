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

    private var backupURL: URL {
        fileURL.appendingPathExtension("bak")
    }

    static var live: MapDraftStore {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return MapDraftStore(fileURL: base.appendingPathComponent("mapline-current-draft.json"))
    }

    /// 현재 초안을 읽는다. 현재 파일이 손상됐으면 마지막 정상 백업을 사용한다.
    /// 둘 다 읽지 못할 때는 빈 지도라고 가장하지 않고 오류를 돌려 기존 파일을 보호한다.
    func load() throws -> MapDraft? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else {
            guard manager.fileExists(atPath: backupURL.path) else { return nil }
            return try decode(backupURL)
        }

        do {
            return try decode(fileURL)
        } catch {
            guard manager.fileExists(atPath: backupURL.path),
                  let recovered = try? decode(backupURL)
            else {
                throw LocalDataStoreError.corrupted("편집 중인 지도")
            }
            return recovered
        }
    }

    func save(_ draft: MapDraft) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(draft)

        // 정상적으로 읽히는 현재 파일만 백업한다. 손상된 파일로 정상 백업을 덮지 않는다.
        if FileManager.default.fileExists(atPath: fileURL.path),
           let current = try? Data(contentsOf: fileURL),
           (try? JSONDecoder().decode(MapDraft.self, from: current)) != nil {
            try current.write(to: backupURL, options: .atomic)
        }
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: fileURL.path) {
            try manager.removeItem(at: fileURL)
        }
        if manager.fileExists(atPath: backupURL.path) {
            try manager.removeItem(at: backupURL)
        }
    }

    /// 현재 파일과 백업을 덮지 않고 별도 이름으로 옮긴다. 복구할 수 없는 손상 때문에
    /// 이후의 모든 새 초안 저장까지 막히지 않게 하면서, 진단용 원본은 남긴다.
    func quarantineCorruptFiles() throws {
        let manager = FileManager.default
        for source in [fileURL, backupURL] where manager.fileExists(atPath: source.path) {
            let destination = source.deletingLastPathComponent().appendingPathComponent(
                source.lastPathComponent + ".corrupt-" + UUID().uuidString
            )
            try manager.moveItem(at: source, to: destination)
        }
    }

    private func decode(_ url: URL) throws -> MapDraft {
        try JSONDecoder().decode(MapDraft.self, from: Data(contentsOf: url))
    }
}
