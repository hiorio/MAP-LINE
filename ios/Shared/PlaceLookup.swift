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

    struct Coordinate: Codable, Equatable {
        let lat: Double
        let lng: Double
    }

    var id: String { kakaoPlaceId ?? "\(name)-\(location.lat)-\(location.lng)" }
    var displayAddress: String? { roadAddress ?? address }

    func asSavedPlace(groupID: String = SavedPlaceGroup.inboxID) -> SavedPlace {
        SavedPlace(
            name: name,
            address: displayAddress,
            kakaoPlaceId: kakaoPlaceId,
            lat: location.lat,
            lng: location.lng,
            groupID: groupID
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
/// 카카오 지도 SDK는 기본 POI의 id와 좌표는 주지만 이름·주소는 주지 않는다. 기본 POI를
/// 탭한 경우 id도 서버에 보내 Local API 후보 전체에서 정확히 일치하는 장소를 먼저 찾는다.
enum NearbyLookup {
    struct Result: Decodable {
        /// 그 지점의 주소. 주변에 아무 장소가 없어도 이건 보여 줄 수 있다.
        let address: String?
        /// SDK POI id와 Local API 장소 id가 정확히 일치한 경우에만 온다.
        let tappedPlace: PlaceCandidate?
        let places: [PlaceCandidate]?
        let error: String?
    }

    static func find(
        lat: Double,
        lng: Double,
        preferredKakaoPlaceId: String? = nil
    ) async throws -> (
        address: String?,
        tappedPlace: PlaceCandidate?,
        places: [PlaceCandidate]
    ) {
        #if DEBUG
        // 지도 기본 POI 탭 UI 테스트는 실제 SDK 탭 이벤트까지는 그대로 통과시키되,
        // 아직 배포되지 않은 서버 응답이나 외부 검색 결과 순서에는 기대지 않는다.
        // 다른 테스트와 실제 앱에는 이 인자가 없으므로 네트워크 경로가 그대로 실행된다.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingTappedPlace"),
           let preferredKakaoPlaceId {
            let tappedPlace = PlaceCandidate(
                kakaoPlaceId: preferredKakaoPlaceId,
                name: "지도에서 누른 테스트 장소",
                address: "서울특별시 강남구",
                roadAddress: nil,
                category: "테스트 장소",
                location: .init(lat: lat, lng: lng),
                distanceM: 0
            )
            return (tappedPlace.displayAddress, tappedPlace, [tappedPlace])
        }
        #endif

        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent("api/nearby"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
        ]
        if let preferredKakaoPlaceId, !preferredKakaoPlaceId.isEmpty {
            queryItems.append(URLQueryItem(name: "poiId", value: preferredKakaoPlaceId))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded = try? JSONDecoder().decode(Result.self, from: data)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.message(decoded?.error ?? "주변을 찾지 못했습니다.")
        }
        return (decoded?.address, decoded?.tappedPlace, decoded?.places ?? [])
    }
}

/// 화면에 그대로 보여 줄 수 있는 오류.
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
