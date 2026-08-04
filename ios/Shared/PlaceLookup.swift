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
    /// 검색 기준점에서의 거리(m). 기준점을 넘겼을 때만 온다.
    let distanceM: Double?

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

/// 지도를 꾹 누른 자리 주변에 무엇이 있는지 묻는다. 서버의 `/api/nearby`를 부른다.
///
/// 카카오 지도 SDK는 타일에 그려진 가게가 무엇인지 알려 주지 않는다. 화면에 보이는
/// "○○식당"을 눌렀다는 사실을 코드가 알 방법이 없어서, 좌표로 주변을 되짚는다.
enum NearbyLookup {
    struct Result: Decodable {
        /// 그 지점의 주소. 주변에 아무 장소가 없어도 이건 보여 줄 수 있다.
        let address: String?
        let places: [PlaceCandidate]?
        let error: String?
    }

    static func find(lat: Double, lng: Double) async throws -> (address: String?, places: [PlaceCandidate]) {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent("api/nearby"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded = try? JSONDecoder().decode(Result.self, from: data)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.message(decoded?.error ?? "주변을 찾지 못했습니다.")
        }
        return (decoded?.address, decoded?.places ?? [])
    }
}

/// 화면에 그대로 보여 줄 수 있는 오류.
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
