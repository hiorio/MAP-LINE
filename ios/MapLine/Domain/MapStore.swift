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

    /// 이 기기가 고칠 수 있는 지도들. 보관함이 목록을 만들 때 쓴다.
    static func editableSlugs() -> [String] {
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(tokenPrefix) }
            .map { String($0.dropFirst(tokenPrefix.count)) }
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
        return decoded?.updatedAt
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
