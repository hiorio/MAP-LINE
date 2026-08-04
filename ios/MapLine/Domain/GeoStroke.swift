import Foundation

/// 지도에 고정되는 좌표 하나.
///
/// 카카오 SDK의 `MapPoint`를 그대로 쓰지 않는 이유: 도메인 규칙이 SDK에 묶이면
/// 테스트에 시뮬레이터가 필요해지고, 나중에 지도를 바꿀 때 규칙까지 딸려 간다.
/// 경계에서만 변환한다. 웹의 `lib/map/types.ts`가 쓰는 것과 같은 모양이다.
/// Codable인 이유: 그대로 서버에 오간다. 웹이 쓰는 `{lat, lng}`와 키 이름이 같아야
/// 한 링크를 웹과 앱에서 같이 열 수 있다.
struct GeoPoint: Equatable, Codable {
    let lat: Double
    let lng: Double

    init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }
}

/// 손으로 그린 획 하나. 화면 좌표가 아니라 위경도로 남는다.
///
/// 색과 굵기를 함께 담는다. 웹 `Stroke`와 같은 모양이어야 한 링크를 두 곳에서 열 수
/// 있다. 앱에서만 값을 빼면 웹이 그 지도를 열 때 획이 기본색으로 바뀐다.
struct GeoStroke: Equatable, Codable {
    let id: UUID
    var path: [GeoPoint]
    var color: String
    var width: Double
    /// 그린 시점의 줌 레벨. 다른 줌에서 굵기를 보정하는 기준이다.
    let zoomCreated: Int

    init(
        id: UUID = UUID(),
        path: [GeoPoint],
        color: String = MapPalette.stroke,
        width: Double = MapPalette.strokeWidth,
        zoomCreated: Int
    ) {
        self.id = id
        self.path = path
        self.color = color
        self.width = width
        self.zoomCreated = zoomCreated
    }
}

/// Ramer–Douglas–Peucker 단순화.
///
/// 손가락 하나를 긋는 동안 좌표가 수백 개 쌓인다. 그대로 두면 저장도 렌더도
/// 무거워지는데, 사람 눈에는 차이가 없다. 웹(`lib/geo/rdp.ts`)과 같은 알고리즘을
/// 쓴다. 같은 획이 웹과 앱에서 다르게 보이면 안 된다.
///
/// - Parameter epsilon: 이 거리보다 덜 벗어나는 점은 버린다. 단위는 좌표계와 같다.
func simplifyPath(_ points: [GeoPoint], epsilon: Double) -> [GeoPoint] {
    guard points.count > 2, epsilon > 0 else { return points }

    var keep = [Bool](repeating: false, count: points.count)
    keep[0] = true
    keep[points.count - 1] = true
    // 재귀 대신 스택을 쓴다. 획이 길면 재귀 깊이가 수백 단계까지 간다.
    var stack: [(Int, Int)] = [(0, points.count - 1)]

    while let (first, last) = stack.popLast() {
        guard last > first + 1 else { continue }

        var farthest = first
        var maxDistance = 0.0
        for index in (first + 1)..<last {
            let distance = perpendicularDistance(points[index], points[first], points[last])
            if distance > maxDistance {
                maxDistance = distance
                farthest = index
            }
        }

        if maxDistance > epsilon {
            keep[farthest] = true
            stack.append((first, farthest))
            stack.append((farthest, last))
        }
    }

    return zip(points, keep).compactMap { $1 ? $0 : nil }
}

/// 점에서 선분까지의 수직 거리.
private func perpendicularDistance(_ point: GeoPoint, _ start: GeoPoint, _ end: GeoPoint) -> Double {
    let dx = end.lng - start.lng
    let dy = end.lat - start.lat

    // 시작과 끝이 같으면 선분이 아니라 점이다. 그냥 두 점 사이 거리다.
    if dx == 0, dy == 0 {
        return hypot(point.lng - start.lng, point.lat - start.lat)
    }

    let numerator = abs(dy * point.lng - dx * point.lat + end.lng * start.lat - end.lat * start.lng)
    return numerator / hypot(dx, dy)
}
