import Foundation

/// 좌표가 오지 않는 구간을 곧게 잇는 선.
struct Connector: Equatable {
    let from: GeoPoint
    let to: GeoPoint
}

/// 한 구간을 어떻게 그릴지.
enum LegShape: Equatable {
    /// 실제 경로가 없다. 단계의 대표 위치를 곧게 잇는다.
    ///
    /// 후보가 여럿인데 대표를 안 정한 단계는 길찾기의 기준이 없으므로 여기로 온다.
    case straight(from: GeoPoint, to: GeoPoint)

    /// 받아 둔 실제 경로.
    ///
    /// `segments`는 좌표가 온 부분이다. 대중교통이면 탈것 구간마다 하나씩이라
    /// 그 수단의 스타일(굵은 실선)로 그린다.
    ///
    /// `connectors`는 좌표가 오지 않는 도보 구간이다. 언제나 도보 스타일(파란 점선)로
    /// 그린다. 대중교통 응답은 **탈것 구간의 좌표만** 준다. 1,682m 중 882m가 도보인데
    /// 좌표로 오는 것은 지하철 800m뿐인 경우가 있었고, 그대로 그리면 선이 신논현역에서
    /// 시작해 언주역에서 끝나 핀 어디에도 닿지 않는다. 출발지에서 첫 역까지, 환승하며
    /// 역과 역 사이, 마지막 역에서 도착지까지가 여기 들어간다. 정확한 골목까지 그리려면
    /// 도보 길찾기를 그만큼 더 불러야 하는데, 걸어간다는 사실을 전하는 데 그만한
    /// 값어치는 없다.
    case path(segments: [[GeoPoint]], connectors: [Connector], mode: TravelMode)
}

/// 길이가 사실상 0인 연결선만 걸러 낸다.
///
/// 처음에는 "핀에 가리는 짧은 것"을 지우려고 20m쯤으로 뒀는데, 그게 정확히 필요한
/// 연결선을 잘라 먹었다. 카카오 길찾기는 요청한 좌표가 아니라 **가장 가까운 도로
/// 노드**에서 시작하고 끝난다. 실제로 재 보니 25m 떨어진 곳에서 끝났고, 그래서 선이
/// 핀에 닿지 않고 허공에서 끊겼다. 그 간격이야말로 이어 줘야 하는 부분이다.
///
/// 짧은 연결선은 어차피 핀 아이콘에 덮여 보이지 않는다. 걸러야 할 것은 두 점이
/// 같은 자리일 때 생기는 길이 0짜리 도형뿐이다. 1e-7도는 1cm 남짓이다.
let connectorMinimumDeg = 1e-7

/// 단계와 구간을 지도에 그릴 모양으로 바꾼다.
///
/// 웹 `lib/render/sceneGeometry.ts`가 하는 일과 같다. 다만 화면 좌표가 아니라
/// 위경도를 그대로 낸다 — 카카오 iOS SDK는 위경도로 등록한 도형을 스스로 다시
/// 투영해 주므로, 우리가 화면 좌표로 옮길 이유가 없다.
func legShapes(stops: [Stop], legs: [StopLeg]) -> [LegShape] {
    var shapes: [LegShape] = []

    for index in 0..<max(0, stops.count - 1) {
        let leg = legs.indices.contains(index) ? legs[index] : nil

        guard let route = LegRules.drawableRoute(stops: stops, index: index, leg: leg) else {
            // 후보가 여럿인 단계는 특정 후보가 아니라 무리의 가운데에서 선을 뽑는다.
            // 한 후보에서 뽑으면 나머지가 동선에서 빠진 것처럼 보인다.
            if let from = stops[index].centroid, let to = stops[index + 1].centroid {
                shapes.append(.straight(from: from, to: to))
            }
            continue
        }

        let segments = splitSegments(route.points, legs: route.legs)
        guard let first = segments.first?.first, let last = segments.last?.last else {
            // 자를 수 없는 경로다. 통째로 하나로 두는 편이 낫다.
            if route.points.count >= 2 {
                shapes.append(
                    .path(segments: [route.points], connectors: [], mode: leg?.mode ?? .straight)
                )
            }
            continue
        }

        var connectors: [Connector] = []

        // 탈것과 탈것 사이는 환승하며 걷는 구간이다.
        for position in 1..<max(1, segments.count) {
            guard let from = segments[position - 1].last, let to = segments[position].first else { continue }
            if gap(from, to) > connectorMinimumDeg { connectors.append(Connector(from: from, to: to)) }
        }

        // 출발지에서 첫 좌표까지, 마지막 좌표에서 도착지까지.
        if let ends = LegRules.endpoints(stops: stops, index: index) {
            if gap(ends.from.location, first) > connectorMinimumDeg {
                connectors.append(Connector(from: ends.from.location, to: first))
            }
            if gap(last, ends.to.location) > connectorMinimumDeg {
                connectors.append(Connector(from: last, to: ends.to.location))
            }
        }

        shapes.append(
            .path(segments: segments, connectors: connectors, mode: leg?.mode ?? .straight)
        )
    }

    return shapes
}

/// 대중교통 경로를 탈것 구간마다 자른다.
///
/// 대중교통이 아니면 자를 것이 없어 통째로 하나다. 구간 정보가 없는 예전 지도도
/// 마찬가지로 한 줄로 둔다. 잘못 자르느니 이어진 채로 두는 편이 낫다.
func splitSegments(_ points: [GeoPoint], legs: [TransitLeg]?) -> [[GeoPoint]] {
    guard let legs, !legs.isEmpty, legs.allSatisfy({ $0.pointCount != nil }) else {
        return points.count >= 2 ? [points] : []
    }

    var segments: [[GeoPoint]] = []
    var cursor = 0
    for leg in legs {
        let count = leg.pointCount ?? 0
        let end = min(cursor + count, points.count)
        guard cursor < end else { break }
        let slice = Array(points[cursor..<end])
        cursor = end
        if slice.count >= 2 { segments.append(slice) }
    }
    return segments
}

private func gap(_ a: GeoPoint, _ b: GeoPoint) -> Double {
    ((b.lat - a.lat) * (b.lat - a.lat) + (b.lng - a.lng) * (b.lng - a.lng)).squareRoot()
}
