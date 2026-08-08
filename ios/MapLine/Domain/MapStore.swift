import Foundation
import Security

/// 지도를 서버에 만들고, 불러오고, 저장한다.
///
/// 웹과 같은 `/api/maps`를 쓴다. 그래서 앱에서 만든 지도를 웹 링크로 열 수 있고
/// 그 반대도 된다 — 링크 하나로 나눠 보는 것이 이 제품의 전부라 이게 갈라지면 안 된다.
enum MapStore {
    /// 지도를 고칠 수 있는 자격.
    ///
    /// 로그인이 없는 제품이라, 만든 사람임을 증명하는 것은 이 토큰뿐이다. 기기에서
    /// 지워지면 그 지도는 더 이상 고칠 수 없다(웹도 브라우저 저장소를 쓰므로 같다).
    /// 사람의 비밀번호가 아니라 앱이 스스로 만들어 스스로 쓰는 값이다.
    private static let tokenPrefix = "mapline.token."

    static func editToken(for slug: String) -> String? {
        do {
            if let token = try EditTokenKeychain.read(slug: slug) { return token }
        } catch {
            // 아래의 이전 UserDefaults 저장소를 가용성 안전망으로 확인한다.
        }

        // 예전 버전의 UserDefaults 토큰을 발견하면 Keychain으로 옮긴다. Keychain이 일시적으로
        // 실패하면 기존 값을 지우지 않아 편집 권한 자체가 사라지는 일을 피한다.
        guard let legacy = UserDefaults.standard.string(forKey: tokenPrefix + slug) else {
            return nil
        }
        do {
            try EditTokenKeychain.write(legacy, slug: slug)
            UserDefaults.standard.removeObject(forKey: tokenPrefix + slug)
        } catch {
            // 기존 값을 그대로 두면 다음 읽기 때 다시 이전할 수 있다.
        }
        return legacy
    }

    static func storeEditToken(_ token: String, for slug: String) {
        do {
            try EditTokenKeychain.write(token, slug: slug)
            UserDefaults.standard.removeObject(forKey: tokenPrefix + slug)
        } catch {
            // 서버에서 토큰을 받은 뒤 저장에 실패하면 그 지도는 즉시 편집 불능이 된다.
            // Keychain 장애 시에는 예전 저장소를 가용성 안전망으로 남기고 다음 읽기 때 재이전한다.
            UserDefaults.standard.set(token, forKey: tokenPrefix + slug)
        }
    }

    // MARK: - 내가 만든 지도 목록

    /// 목록에 보여 줄 만큼만 기억한다.
    ///
    /// 슬러그만 갖고 있으면 목록을 그리려고 지도 수만큼 서버를 불러야 하고, 그동안
    /// 화면에는 알 수 없는 문자열만 늘어선다. 제목과 시각을 함께 남겨 두면 목록은
    /// 서버 없이도 바로 그려진다.
    struct Entry: Codable, Equatable, Identifiable {
        let slug: String
        var title: String
        var savedAt: String
        /// 예전 목록 파일에는 없을 수 있다. 그 경우 내 동선 화면이 서버에서 한 번 보완한다.
        var stopCount: Int?
        var id: String { slug }

        init(slug: String, title: String, savedAt: String, stopCount: Int?) {
            self.slug = slug
            self.title = title
            self.savedAt = savedAt
            self.stopCount = stopCount
        }

        private enum CodingKeys: String, CodingKey { case slug, title, savedAt, stopCount }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            slug = try values.decode(String.self, forKey: .slug)
            title = try values.decode(String.self, forKey: .title)
            savedAt = try values.decode(String.self, forKey: .savedAt)
            stopCount = try values.decodeIfPresent(Int.self, forKey: .stopCount)
        }
    }

    private static let indexKey = "mapline.maps"
    private static let indexBackupKey = "mapline.maps.backup"
    private static let hiddenIndexKey = "mapline.maps.hidden"
    private static let hiddenIndexBackupKey = "mapline.maps.hidden.backup"

    static func rememberedMaps() -> [Entry] {
        // 최근에 저장한 것이 위로.
        readEntries(key: indexKey, backupKey: indexBackupKey)
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// 목록에서 잠시 숨겼지만 편집 자격은 기기에 남아 있는 지도들.
    static func hiddenMaps() -> [Entry] {
        readEntries(key: hiddenIndexKey, backupKey: hiddenIndexBackupKey)
            .sorted { $0.savedAt > $1.savedAt }
    }

    static func remember(
        slug: String,
        title: String,
        stopCount: Int? = nil,
        savedAt: Date = Date()
    ) {
        let current = rememberedMaps()
        let hidden = hiddenMaps()
        let existingCount = (current + hidden).first { $0.slug == slug }?.stopCount
        var entries = current.filter { $0.slug != slug }
        entries.append(
            Entry(
                slug: slug,
                title: title,
                savedAt: ISO8601DateFormatter().string(from: savedAt),
                stopCount: stopCount ?? existingCount
            )
        )
        writeEntries(entries, key: indexKey, backupKey: indexBackupKey)
        writeEntries(
            hidden.filter { $0.slug != slug },
            key: hiddenIndexKey,
            backupKey: hiddenIndexBackupKey
        )
    }

    /// 목록에서만 숨긴다. 서버 지도·공유 링크·편집 토큰은 그대로 둔다.
    static func hide(slug: String) {
        guard let entry = rememberedMaps().first(where: { $0.slug == slug }) else { return }
        var hidden = hiddenMaps().filter { $0.slug != slug }
        hidden.append(entry)

        // 숨긴 쪽을 먼저 써서 두 UserDefaults 갱신 사이에 앱이 끝나도 항목을 잃지 않는다.
        writeEntries(hidden, key: hiddenIndexKey, backupKey: hiddenIndexBackupKey)
        writeEntries(
            rememberedMaps().filter { $0.slug != slug },
            key: indexKey,
            backupKey: indexBackupKey
        )
    }

    static func restoreHidden(slug: String) {
        guard let entry = hiddenMaps().first(where: { $0.slug == slug }) else { return }
        var visible = rememberedMaps().filter { $0.slug != slug }
        visible.append(entry)

        // 복원할 때도 보이는 쪽을 먼저 써서 중간 종료가 데이터 손실이 아닌 중복으로 끝나게 한다.
        writeEntries(visible, key: indexKey, backupKey: indexBackupKey)
        writeEntries(
            hiddenMaps().filter { $0.slug != slug },
            key: hiddenIndexKey,
            backupKey: hiddenIndexBackupKey
        )
    }

    /// 서버 삭제가 확인된 뒤에만 로컬 목록과 편집 자격을 함께 버린다.
    static func discardLocalData(slug: String) {
        writeEntries(
            rememberedMaps().filter { $0.slug != slug },
            key: indexKey,
            backupKey: indexBackupKey
        )
        writeEntries(
            hiddenMaps().filter { $0.slug != slug },
            key: hiddenIndexKey,
            backupKey: hiddenIndexBackupKey
        )
        try? EditTokenKeychain.delete(slug: slug)
        UserDefaults.standard.removeObject(forKey: tokenPrefix + slug)
    }

    // MARK: - 만들기

    private struct CreateResponse: Decodable {
        let slug: String?
        let editToken: String?
        let error: String?
    }

    /// 빈 지도를 만들고 슬러그를 받는다. 편집 토큰은 받는 즉시 기기에 남긴다.
    static func create(title: String, center: GeoPoint, zoomLevel: Int) async throws -> String {
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("api/maps"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": title,
            "center": ["lat": center.lat, "lng": center.lng],
            "zoomLevel": zoomLevel,
        ])
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded = try? JSONDecoder().decode(CreateResponse.self, from: data)
        guard
            let http = response as? HTTPURLResponse, http.statusCode == 201,
            let slug = decoded?.slug, let token = decoded?.editToken
        else {
            throw AppError.message(decoded?.error ?? "지도를 만들지 못했습니다.")
        }

        storeEditToken(token, for: slug)
        return slug
    }

    // MARK: - 불러오기

    struct Loaded {
        let document: MapDocument
        /// 낙관적 잠금 기준. 저장할 때 이 값을 그대로 돌려보낸다.
        let updatedAt: String?
        /// 이 기기가 고칠 수 있는 지도인가.
        var canEdit: Bool
    }

    private struct LoadedEnvelope: Decodable {
        let updatedAt: String?
        let error: String?
    }

    static func load(slug: String) async throws -> Loaded {
        var request = URLRequest(
            url: AppConfig.apiBaseURL.appendingPathComponent("api/maps/\(slug)")
        )
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(LoadedEnvelope.self, from: data))?.error
            throw AppError.message(message ?? "지도를 불러오지 못했습니다.")
        }

        // 문서와 updatedAt이 같은 객체에 섞여 온다. 문서 쪽은 모르는 키를 무시한다.
        let document = try JSONDecoder().decode(MapDocument.self, from: data)
        let envelope = try? JSONDecoder().decode(LoadedEnvelope.self, from: data)

        return Loaded(
            document: document,
            updatedAt: envelope?.updatedAt,
            canEdit: editToken(for: slug) != nil
        )
    }

    // MARK: - 저장

    /// 다른 곳에서 먼저 저장돼 이번 저장을 버린 경우.
    ///
    /// 조용히 덮어쓰지 않는다. 한 지도를 웹과 앱에서 같이 고칠 수 있으므로, 늦게 온
    /// 저장이 남의 작업을 지우면 무엇이 사라졌는지 아무도 모른다.
    struct Conflict: LocalizedError {
        var errorDescription: String? { "다른 곳에서 먼저 저장되었습니다. 불러온 뒤 다시 저장하세요." }
    }

    private struct SaveResponse: Decodable {
        let updatedAt: String?
        let error: String?
    }

    /// 저장하고 새 기준 시각을 돌려준다.
    @discardableResult
    static func save(
        slug: String,
        document: MapDocument,
        expectedUpdatedAt: String?
    ) async throws -> String? {
        guard let token = editToken(for: slug) else {
            throw AppError.message("이 기기에서는 고칠 수 없는 지도입니다.")
        }

        var request = URLRequest(
            url: AppConfig.apiBaseURL.appendingPathComponent("api/maps/\(slug)")
        )
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Edit-Token")
        request.timeoutInterval = 20

        var body: [String: Any] = [
            "document": try documentAsJSON(document),
            "expectedUpdatedAt": NSNull(),
        ]
        if let expectedUpdatedAt { body["expectedUpdatedAt"] = expectedUpdatedAt }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.message("응답을 읽지 못했습니다.")
        }
        if http.statusCode == 409 { throw Conflict() }

        let decoded = try? JSONDecoder().decode(SaveResponse.self, from: data)
        guard http.statusCode == 200 else {
            throw AppError.message(decoded?.error ?? "저장하지 못했습니다 (\(http.statusCode))")
        }

        // 저장에 성공했을 때만 목록에 올린다. 실패한 지도가 목록에 있으면
        // 눌렀을 때 없는 지도를 불러오게 된다.
        remember(slug: slug, title: document.title, stopCount: document.stops.count)
        return decoded?.updatedAt
    }

    // MARK: - 완전 삭제

    /// 서버의 지도와 공유 링크를 지운다. 서버가 성공을 확인하기 전에는 로컬 편집 토큰을
    /// 건드리지 않으므로 네트워크 실패가 편집권 상실로 이어지지 않는다.
    static func delete(slug: String) async throws {
        guard let token = editToken(for: slug) else {
            throw AppError.message("이 기기에서는 삭제할 수 없는 지도입니다.")
        }

        var request = URLRequest(
            url: AppConfig.apiBaseURL.appendingPathComponent("api/maps/\(slug)")
        )
        request.httpMethod = "DELETE"
        request.setValue(token, forHTTPHeaderField: "X-Edit-Token")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.message("삭제 응답을 읽지 못했습니다.")
        }
        guard http.statusCode == 200 else {
            let decoded = try? JSONDecoder().decode(SaveResponse.self, from: data)
            throw AppError.message(decoded?.error ?? "지도를 삭제하지 못했습니다 (\(http.statusCode))")
        }

        discardLocalData(slug: slug)
    }

    // MARK: - 복제와 썸네일

    /// 서버의 OG 이미지가 지도 한 장을 이미 렌더링하므로 내 동선 목록도 같은 그림을 쓴다.
    static func thumbnailURL(slug: String) -> URL {
        AppConfig.apiBaseURL.appendingPathComponent("api/og/\(slug)")
    }

    /// 원본 링크와 편집 토큰은 건드리지 않고 새 지도·새 편집 토큰을 만든다.
    static func duplicate(slug: String) async throws -> String {
        let loaded = try await load(slug: slug)
        let copy = duplicatedMapDocument(loaded.document)
        let newSlug = try await create(
            title: copy.title,
            center: copy.center,
            zoomLevel: copy.zoomLevel
        )
        _ = try await save(slug: newSlug, document: copy, expectedUpdatedAt: nil)
        return newSlug
    }

    /// 문서를 JSON 객체로. 서버가 본문 안에 중첩해서 받으므로 한 번 풀어야 한다.
    private static func documentAsJSON(_ document: MapDocument) throws -> [String: Any] {
        let data = try JSONEncoder().encode(document)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.message("지도를 보낼 형태로 바꾸지 못했습니다.")
        }
        return object
    }

    /// 나눠 볼 주소. 웹이 여는 것과 같은 링크다.
    static func shareURL(slug: String) -> URL {
        AppConfig.apiBaseURL.appendingPathComponent("m/\(slug)")
    }

    private static func readEntries(key: String, backupKey: String) -> [Entry] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            return entries
        }
        if let data = defaults.data(forKey: backupKey),
           let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            return entries
        }
        return []
    }

    private static func writeEntries(_ entries: [Entry], key: String, backupKey: String) {
        let defaults = UserDefaults.standard
        guard let encoded = try? JSONEncoder().encode(entries) else { return }
        if let current = defaults.data(forKey: key),
           (try? JSONDecoder().decode([Entry].self, from: current)) != nil {
            defaults.set(current, forKey: backupKey)
        }
        defaults.set(encoded, forKey: key)
    }
}

/// 익명 편집 토큰은 서버 지도를 고칠 수 있는 유일한 자격이므로 일반 설정값과 분리한다.
private enum EditTokenKeychain {
    private static let service = "com.hiorio.mapline.edit-token"

    static func read(slug: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: slug,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw osStatusError(status) }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw LocalDataStoreError.corrupted("지도 편집 권한")
        }
        return token
    }

    static func write(_ token: String, slug: String) throws {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: slug,
        ]
        let value: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(key as CFDictionary, value as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw osStatusError(updateStatus) }

        var insert = key
        value.forEach { insert[$0.key] = $0.value }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw osStatusError(addStatus) }
    }

    static func delete(slug: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: slug,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw osStatusError(status)
        }
    }

    private static func osStatusError(_ status: OSStatus) -> Error {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}

/// 복제본은 내용과 카메라를 그대로 두고 사람에게 구별되는 이름만 붙인다.
func duplicatedMapDocument(_ source: MapDocument) -> MapDocument {
    var copy = source
    let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.title = title.isEmpty ? "새 지도 복사본" : "\(title) 복사본"
    return copy
}
