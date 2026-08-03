import Foundation

/// 서버가 돌려주는 장소 하나.
///
/// `/api/search`와 `/api/parse-share`가 같은 모양을 쓴다. 카카오 REST 키는 서버 전용이라
/// 앱이 카카오를 직접 부르지 않는다 — 키가 앱에 들어가면 뜯어내서 남이 우리 쿼터를 태운다.
struct PlaceCandidate: Decodable, Identifiable, Equatable {
    let kakaoPlaceId: String?
    let name: String
    let address: String?
    let roadAddress: String?
    let category: String?
    let location: Coordinate

    struct Coordinate: Decodable, Equatable {
        let lat: Double
        let lng: Double
    }

    var id: String { kakaoPlaceId ?? "\(name)-\(location.lat)-\(location.lng)" }
    var displayAddress: String? { roadAddress ?? address }

    func asSavedPlace() -> SavedPlace {
        SavedPlace(
            name: name,
            address: displayAddress,
            kakaoPlaceId: kakaoPlaceId,
            lat: location.lat,
            lng: location.lng
        )
    }
}

/// 장소 검색. 서버의 `/api/search`를 부른다.
enum PlaceLookup {
    struct Response: Decodable {
        let places: [PlaceCandidate]?
        let error: String?
    }

    static func search(_ query: String, near: PlaceCandidate.Coordinate? = nil) async throws -> [PlaceCandidate] {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent("api/search"),
            resolvingAgainstBaseURL: false
        )!
        var items = [URLQueryItem(name: "q", value: query)]
        if let near {
            // 지금 보고 있는 곳을 넘기면 같은 이름 중 가까운 지점이 위로 온다.
            items.append(URLQueryItem(name: "lat", value: String(near.lat)))
            items.append(URLQueryItem(name: "lng", value: String(near.lng)))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded = try? JSONDecoder().decode(Response.self, from: data)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.message(decoded?.error ?? "검색에 실패했습니다.")
        }
        return decoded?.places ?? []
    }
}

/// 화면에 그대로 보여 줄 수 있는 오류.
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
