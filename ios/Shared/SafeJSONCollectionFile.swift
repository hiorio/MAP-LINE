import Foundation

/// 사람이 만든 배열형 데이터를 JSON 파일 하나에 안전하게 보관한다.
///
/// 원자적 쓰기만으로는 앱과 공유 익스텐션이 동시에 `읽기 -> 수정 -> 쓰기`를 할 때
/// 나중 쓰기가 먼저 쓰인 내용을 덮는 문제를 막지 못한다. 갱신 전체를
/// `NSFileCoordinator` 안에서 수행하고, 새 값을 쓰기 전에 마지막 정상 파일을 백업한다.
struct SafeJSONCollectionFile<Element: Codable> {
    let fileURL: URL
    let displayName: String

    func read() throws -> [Element] {
        do {
            return try readUnlocked(at: fileURL)
        } catch let error as LocalDataStoreError {
            throw error
        } catch {
            throw LocalDataStoreError.readFailed(displayName)
        }
    }

    /// 현재 값을 읽고 고친 뒤 쓰는 전 과정을 한 번의 조정된 파일 접근으로 처리한다.
    func update(_ transform: @escaping (inout [Element]) throws -> Void) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw LocalDataStoreError.writeFailed(displayName)
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationResult: Result<Void, Error>?

        coordinator.coordinate(
            writingItemAt: fileURL,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            operationResult = Result {
                var values = try readUnlocked(at: coordinatedURL)
                try transform(&values)
                try writeUnlocked(values, at: coordinatedURL)
            }
        }

        if coordinationError != nil {
            throw LocalDataStoreError.writeFailed(displayName)
        }
        guard let operationResult else {
            throw LocalDataStoreError.writeFailed(displayName)
        }
        do {
            try operationResult.get()
        } catch let error as LocalDataStoreError {
            throw error
        } catch {
            throw LocalDataStoreError.writeFailed(displayName)
        }
    }

    private func readUnlocked(at primaryURL: URL) throws -> [Element] {
        let manager = FileManager.default
        let backupURL = primaryURL.appendingPathExtension("bak")
        let primaryExists = manager.fileExists(atPath: primaryURL.path)

        if primaryExists {
            do {
                return try decode(primaryURL)
            } catch {
                // 쓰기 도중의 외부 종료나 예전 앱의 손상 파일은 마지막 정상본으로 복구한다.
                if manager.fileExists(atPath: backupURL.path),
                   let recovered = try? decode(backupURL) {
                    return recovered
                }
                throw LocalDataStoreError.corrupted(displayName)
            }
        }

        if manager.fileExists(atPath: backupURL.path) {
            do {
                return try decode(backupURL)
            } catch {
                throw LocalDataStoreError.corrupted(displayName)
            }
        }
        return []
    }

    private func decode(_ url: URL) throws -> [Element] {
        try JSONDecoder().decode([Element].self, from: Data(contentsOf: url))
    }

    private func writeUnlocked(_ values: [Element], at primaryURL: URL) throws {
        let manager = FileManager.default
        let backupURL = primaryURL.appendingPathExtension("bak")
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(values)
        } catch {
            throw LocalDataStoreError.writeFailed(displayName)
        }

        // 손상된 현재 파일로 정상 백업을 덮지 않는다. 디코딩 가능한 파일만 백업한다.
        if manager.fileExists(atPath: primaryURL.path),
           let current = try? Data(contentsOf: primaryURL),
           (try? JSONDecoder().decode([Element].self, from: current)) != nil {
            do {
                try current.write(to: backupURL, options: .atomic)
            } catch {
                throw LocalDataStoreError.writeFailed(displayName)
            }
        }

        do {
            try encoded.write(to: primaryURL, options: .atomic)
        } catch {
            throw LocalDataStoreError.writeFailed(displayName)
        }
    }
}

enum LocalDataStoreError: LocalizedError {
    case unavailable(String)
    case corrupted(String)
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let name):
            return "\(name) 저장 공간을 열 수 없습니다. 앱을 다시 실행해 주세요."
        case .corrupted(let name):
            return "\(name) 파일과 백업을 읽을 수 없습니다. 기존 파일은 덮어쓰지 않았습니다."
        case .readFailed(let name):
            return "\(name)을(를) 읽지 못했습니다. 기존 파일은 덮어쓰지 않았습니다."
        case .writeFailed(let name):
            return "\(name)을(를) 기기에 저장하지 못했습니다. 저장 공간을 확인하고 다시 시도해 주세요."
        }
    }
}
