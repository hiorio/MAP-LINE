import Foundation

/// 단계에서 단계로 어떻게 이동하는가.
///
/// `straight`가 기본이다. 후보가 아직 여럿이라 어디로 갈지 안 정한 단계에까지 정확한
/// 경로를 그리면 정해진 것처럼 보인다. 웹 `TravelMode`와 같은 값이어야 한다.
///
/// 자동차는 없다. 카카오모빌리티의 자동차 길찾기는 결과를 저장할 수 없어, 링크를
/// 나중에 여는 이 제품과 맞지 않는다.
enum TravelMode: String, Codable, CaseIterable, Identifiable {
    case straight, walk, transit, bicycle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .straight: return "직선"
        case .walk: return "도보"
        case .transit: return "대중교통"
        case .bicycle: return "자전거"
        }
    }

    var symbol: String {
        switch self {
        case .straight: return "arrow.right"
        case .walk: return "figure.walk"
        case .transit: return "tram.fill"
        case .bicycle: return "bicycle"
        }
    }

    /// 길찾기를 불러야 하는가. 직선은 부를 것이 없다.
    var needsRoute: Bool { self != .straight }
}

/// 대중교통 경로를 이루는 한 구간. 노선 배지로 보여 준다.
struct TransitLeg: Codable, Equatable {
    let type: String
    /// "2호선 (강남 > 역삼)" 같은 카카오가 준 안내 문구.
    let guidance: String
    /// 이 구간이 `RoutePath.points`에서 차지하는 좌표 개수.
    ///
    /// 대중교통 경로는 탈것 구간의 좌표만 이어 붙인 한 줄이다. 어디까지가 지하철이고
    /// 어디부터 버스인지 모르면 사이의 환승 도보를 구분해 그릴 수 없다.
    let pointCount: Int?
}

/// 길찾기로 받아 온 실제 경로.
///
/// 끝점 id와 받아 온 시각을 함께 담는다. 끝점이 바뀌었는데 옛 경로를 계속 그리면
/// 조용히 틀린 그림이 된다. 어떤 두 지점을 언제 기준으로 구한 것인지 남겨 두면
/// 다시 구해야 하는지 스스로 판단할 수 있다.
struct RoutePath: Codable, Equatable {
    var points: [GeoPoint]
    var distanceM: Int
    var durationS: Int
    /// 대중교통일 때만 있다.
    var legs: [TransitLeg]?
    var fromPlaceId: String
    var toPlaceId: String
    var fetchedAt: String
}

/// 단계 사이 한 구간. `legs[i]`가 `stops[i] → stops[i+1]`에 대응한다.
struct StopLeg: Codable, Equatable {
    var mode: TravelMode
    /// 직선이거나 아직 못 구했으면 없다.
    var route: RoutePath?

    init(mode: TravelMode = .straight, route: RoutePath? = nil) {
        self.mode = mode
        self.route = route
    }
}

/// 구간을 다루는 규칙. 웹 `lib/map/legs.ts`와 같은 답을 내야 한다.
enum LegRules {
    /// 카카오 운영정책이 요구하는 "캐시 후 최신 데이터로 유지"의 기한.
    static let routeTTLDays = 7.0

    /// 구간 배열을 단계 수에 맞춘다. 길이는 항상 max(0, 단계 수 - 1)이다.
    static func synced(stops: [Stop], legs: [StopLeg]) -> [StopLeg] {
        let wanted = max(0, stops.count - 1)
        if legs.count == wanted { return legs }
        return (0..<wanted).map { legs.indices.contains($0) ? legs[$0] : StopLeg() }
    }

    /// 단계 순서를 바꾼 뒤에도 그대로 남은 인접 구간은 이동수단과 경로를 보존한다.
    /// 새로 맞닿은 단계는 이전 경로를 재사용하면 틀린 선이 되므로 직선으로 시작한다.
    static func reordered(
        oldStops: [Stop],
        newStops: [Stop],
        oldLegs: [StopLeg]
    ) -> [StopLeg] {
        let syncedOld = synced(stops: oldStops, legs: oldLegs)
        var byPair: [String: StopLeg] = [:]
        for index in syncedOld.indices where oldStops.indices.contains(index + 1) {
            byPair["\(oldStops[index].id)\u{0}\(oldStops[index + 1].id)"] = syncedOld[index]
        }

        return (0..<max(0, newStops.count - 1)).map { index in
            let key = "\(newStops[index].id)\u{0}\(newStops[index + 1].id)"
            return byPair[key] ?? StopLeg()
        }
    }

    /// 이 구간의 출발·도착 장소. 어느 한쪽이라도 대표가 없으면 경로를 그릴 수 없다.
    static func endpoints(stops: [Stop], index: Int) -> (from: MapPlace, to: MapPlace)? {
        guard stops.indices.contains(index), stops.indices.contains(index + 1) else { return nil }
        guard let from = stops[index].anchor, let to = stops[index + 1].anchor else { return nil }
        return (from, to)
    }

    /// 저장된 경로가 지금 이 두 지점의 것인가.
    static func matchesEndpoints(_ route: RoutePath, from: MapPlace, to: MapPlace) -> Bool {
        route.fromPlaceId == from.id && route.toPlaceId == to.id
    }

    static func isStale(_ route: RoutePath, now: Date = Date()) -> Bool {
        guard let fetched = ISO8601DateFormatter().date(from: route.fetchedAt) else {
            // 시각을 못 읽으면 낡은 것으로 본다. 다시 받는 편이 틀린 그림을 두는 것보다 낫다.
            return true
        }
        return now.timeIntervalSince(fetched) > routeTTLDays * 24 * 60 * 60
    }

    /// 지금 그려도 되는 경로. 없으면 직선으로 되돌린다는 뜻이다.
    ///
    /// 낡았는지는 보지 않는다. 낡은 경로라도 직선보다는 사실에 가깝고, 갱신은 따로
    /// 한다. 여기서 버리면 링크를 받은 사람 화면에서 선이 사라진다.
    static func drawableRoute(stops: [Stop], index: Int, leg: StopLeg?) -> RoutePath? {
        guard let leg, leg.mode != .straight, let route = leg.route else { return nil }
        guard let ends = endpoints(stops: stops, index: index) else { return nil }
        return matchesEndpoints(route, from: ends.from, to: ends.to) ? route : nil
    }

    /// 다시 받아야 하는 구간들. 모드는 정해졌는데 쓸 만한 경로가 없는 자리다.
    static func needingRoute(stops: [Stop], legs: [StopLeg]) -> [Int] {
        legs.indices.filter { index in
            let leg = legs[index]
            guard leg.mode.needsRoute else { return false }
            guard endpoints(stops: stops, index: index) != nil else { return false }
            guard let route = drawableRoute(stops: stops, index: index, leg: leg) else { return true }
            return isStale(route)
        }
    }

    /// 대표가 바뀐 단계와 맞닿아 있고 실제 경로를 다시 받아야 하는 구간들.
    static func needingRoute(
        touchingStopAt stopIndex: Int,
        stops: [Stop],
        legs: [StopLeg]
    ) -> [Int] {
        let adjacent = Set([stopIndex - 1, stopIndex])
        return needingRoute(stops: stops, legs: legs).filter { adjacent.contains($0) }
    }
}
