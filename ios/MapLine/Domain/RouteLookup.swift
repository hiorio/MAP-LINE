import Foundation

/// 두 지점 사이의 실제 경로를 서버에 묻는다.
///
/// 카카오 REST 키는 서버 전용이라 앱이 직접 길찾기를 부를 수 없다. 키가 앱에 들어가면
/// 뜯어내서 남이 우리 쿼터를 태운다. 웹과 같은 `/api/route`를 쓰므로 두 곳이 같은
/// 경로를 그린다.
enum RouteLookup {
    /// 서버가 주는 것. 끝점 id와 받은 시각은 부르는 쪽이 안다.
    private struct Response: Decodable {
        let points: [GeoPoint]?
        let distanceM: Int?
        let durationS: Int?
        let legs: [TransitLeg]?
        let error: String?
    }

    /// 그 수단으로는 갈 수 없다는 답.
    ///
    /// 실패와 구별해야 한다. 서버가 잠깐 죽은 것이면 다시 부르면 되지만, 이건 다시
    /// 불러도 같은 답일 가능성이 높다. 선택 수단은 유지하고 이유를 보여 줘야 사용자가
    /// 직선 경로로 오해하지 않으며, 일시적인 데이터 갱신에 대비해 재시도할 수 있다.
    struct NoRoute: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func find(
        mode: TravelMode,
        from: MapPlace,
        to: MapPlace,
        now: Date = Date()
    ) async throws -> RoutePath {
        guard mode.needsRoute else {
            throw AppError.message("직선은 길찾기를 부르지 않습니다.")
        }

        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent("api/route"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "from_lat", value: String(from.location.lat)),
            URLQueryItem(name: "from_lng", value: String(from.location.lng)),
            URLQueryItem(name: "to_lat", value: String(to.location.lat)),
            URLQueryItem(name: "to_lng", value: String(to.location.lng)),
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.message("응답을 읽지 못했습니다.")
        }
        let decoded = try? JSONDecoder().decode(Response.self, from: data)

        // 422는 "이 수단으로는 갈 수 없다"는 답이다. 서버가 그렇게 구별해 준다.
        if http.statusCode == 422 {
            throw NoRoute(message: decoded?.error ?? "이 수단으로는 갈 수 없습니다.")
        }
        guard http.statusCode == 200, let points = decoded?.points, points.count >= 2 else {
            throw AppError.message(decoded?.error ?? "경로를 가져오지 못했습니다.")
        }

        return RoutePath(
            points: points,
            distanceM: decoded?.distanceM ?? 0,
            durationS: decoded?.durationS ?? 0,
            legs: decoded?.legs,
            // 어떤 두 지점을 언제 기준으로 구한 것인지 여기서 새긴다.
            // 이게 없으면 끝점이 바뀐 뒤에도 옛 경로를 계속 그린다.
            fromPlaceId: from.id,
            toPlaceId: to.id,
            fetchedAt: ISO8601DateFormatter().string(from: now)
        )
    }
}
