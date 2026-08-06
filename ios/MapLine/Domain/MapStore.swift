import Foundation

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
        UserDefaults.standard.string(forKey: tokenPrefix + slug)
    }

    static func storeEditToken(_ token: String, for slug: String) {
        UserDefaults.standard.set(token, forKey: tokenPrefix + slug)
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
        /// 예전 목록 파일에는 없을 수 있다. 그 경우 내 지도 화면이 서버에서 한 번 보완한다.
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

    static func rememberedMaps() -> [Entry] {
        guard
            let data = UserDefaults.standard.data(forKey: indexKey),
            let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        // 최근에 저장한 것이 위로.
        return entries.sorted { $0.savedAt > $1.savedAt }
    }

    static func remember(
        slug: String,
        title: String,
        stopCount: Int? = nil,
        savedAt: Date = Date()
    ) {
        let current = rememberedMaps()
        let existingCount = current.first { $0.slug == slug }?.stopCount
        var entries = current.filter { $0.slug != slug }
        entries.append(
            Entry(
                slug: slug,
                title: title,
                savedAt: ISO8601DateFormatter().string(from: savedAt),
                stopCount: stopCount ?? existingCount
            )
        )
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: indexKey)
    }

    static func forget(slug: String) {
        let entries = rememberedMaps().filter { $0.slug != slug }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: indexKey)
        // 편집 토큰도 함께 버린다. 목록에서 지웠는데 자격만 남아 있을 이유가 없다.
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

    // MARK: - 복제와 썸네일

    /// 서버의 OG 이미지가 지도 한 장을 이미 렌더링하므로 내 지도 목록도 같은 그림을 쓴다.
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
}

/// 복제본은 내용과 카메라를 그대로 두고 사람에게 구별되는 이름만 붙인다.
func duplicatedMapDocument(_ source: MapDocument) -> MapDocument {
    var copy = source
    let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.title = title.isEmpty ? "새 지도 복사본" : "\(title) 복사본"
    return copy
}
