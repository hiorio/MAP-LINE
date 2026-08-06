import UIKit

/// 이동수단별 선 모양. 웹 `lib/render/sceneGeometry.ts`의 `MODE_STYLE`과 같은 값이다.
///
/// 직선은 "아직 정하지 않았다"에 가까우므로 회색으로 물러나 있는다. 실제 경로는 사람이
/// 수단까지 정해 확정한 동선이라 눈에 들어와야 한다. 회색으로 뒀더니 지도의 도로에 묻혔다.
///
/// 도보와 대중교통은 같은 파랑을 쓰되 선 모양으로 가른다. 둘 다 "이동"이라 색이 따로
/// 놀 이유가 없고, 촘촘한 점선과 굵은 실선은 멀리서도 구분된다.
struct LegStyle {
    /// SDK에 등록할 스타일 세트의 이름. 그리는 쪽이 이 값으로 찾아 쓴다.
    let name: String
    let color: UIColor
    let width: UInt
    /// 점선의 (선, 빈칸) 길이. 화면 기준 포인트다. nil이면 실선이다.
    let dash: (on: Double, off: Double)?

    static func of(_ mode: TravelMode) -> LegStyle {
        switch mode {
        case .straight:
            return LegStyle(name: "straight", color: UIColor(hex: "#8A8A83") ?? .gray, width: 3, dash: nil)
        case .walk:
            return walk
        case .transit:
            return LegStyle(name: "transit", color: UIColor(hex: "#2D6BE4") ?? .systemBlue, width: 9, dash: nil)
        case .bicycle:
            return LegStyle(name: "bicycle", color: UIColor(hex: "#2FA35B") ?? .systemGreen, width: 8, dash: (8, 5))
        }
    }

    /// 좌표가 오지 않는 도보 구간에도 이 모양을 쓴다.
    ///
    /// 대중교통 응답은 탈것 구간의 좌표만 준다. 그 사이를 이어 주는 선은 걸어가는
    /// 구간이므로 도보와 같이 보여야 한다.
    static let walk = LegStyle(
        name: "walk",
        color: UIColor(hex: "#2D6BE4") ?? .systemBlue,
        width: 7,
        dash: (3, 7)
    )
}

/// 선을 점선으로 자른다.
///
/// 카카오 SDK의 폴리라인에는 점선 기능이 없다(`PerLevelPolylineStyle`에 색과 굵기뿐).
/// 그래서 짧은 조각 여러 개로 직접 만든다. 조각 길이는 각도 단위로 받는데, 그 값을
/// 화면 배율에서 구해 넘기면 어느 줌에서 봐도 같은 간격으로 보인다.
///
/// 순수 계산이라 지도 없이 검증할 수 있다.
func dashedSegments(
    _ path: [GeoPoint],
    onLength: Double,
    offLength: Double
) -> [[GeoPoint]] {
    guard path.count >= 2, onLength > 0, offLength > 0 else { return path.isEmpty ? [] : [path] }

    var dashes: [[GeoPoint]] = []
    var current: [GeoPoint] = []
    // 지금 그리는 중인가, 띄우는 중인가. 남은 길이가 0이 되면 뒤바뀐다.
    var drawing = true
    var remaining = onLength

    var cursor = path[0]
    current.append(cursor)

    for next in path.dropFirst() {
        var toNext = distance(cursor, next)

        while toNext > remaining {
            // 이 변 안에서 상태가 바뀐다. 바뀌는 지점을 끼워 넣는다.
            let ratio = remaining / toNext
            let cut = GeoPoint(
                lat: cursor.lat + (next.lat - cursor.lat) * ratio,
                lng: cursor.lng + (next.lng - cursor.lng) * ratio
            )

            if drawing {
                current.append(cut)
                dashes.append(current)
                current = []
            } else {
                current = [cut]
            }

            drawing.toggle()
            toNext -= remaining
            remaining = drawing ? onLength : offLength
            cursor = cut
        }

        remaining -= toNext
        if drawing { current.append(next) }
        cursor = next
    }

    if drawing, current.count >= 2 {
        dashes.append(current)
    } else {
        // 빈칸 차례에 길이 끝나면 선이 끝점에 못 닿는다. 핀 바로 앞에서 끊긴 것처럼
        // 보이는데, 이건 그림의 사실이 아니라 점선을 자른 방식의 부작용이다.
        // 실제로 CI 스크린샷에서 한쪽 핀은 닿고 다른 쪽은 안 닿았다 — 어느 차례에
        // 끝나느냐가 갈랐을 뿐이다. 마지막은 언제나 그린 조각으로 끝낸다.
        let closing = tail(path, length: onLength)
        if closing.count >= 2 { dashes.append(closing) }
    }
    return dashes
}

/// 길의 마지막 `length`만큼. 끝점에서 거슬러 올라가며 모은다.
private func tail(_ path: [GeoPoint], length: Double) -> [GeoPoint] {
    guard let end = path.last, path.count >= 2 else { return [] }

    var backwards: [GeoPoint] = [end]
    var remaining = length

    for index in stride(from: path.count - 1, through: 1, by: -1) {
        let previous = path[index - 1]
        let step = distance(previous, path[index])
        guard step > 0 else { continue }

        if step >= remaining {
            let ratio = remaining / step
            backwards.append(
                GeoPoint(
                    lat: path[index].lat + (previous.lat - path[index].lat) * ratio,
                    lng: path[index].lng + (previous.lng - path[index].lng) * ratio
                )
            )
            break
        }
        backwards.append(previous)
        remaining -= step
    }

    return backwards.reversed()
}

/// 두 점 사이 거리. 각도 단위다.
///
/// 위경도 1도의 실제 길이는 위도마다 다르지만, 여기서 쓰는 곳은 한 화면 안의 점선
/// 간격이라 그 차이가 눈에 보이지 않는다. 화면 배율에서 구한 값과 같은 단위이기만 하면 된다.
private func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
    ((b.lat - a.lat) * (b.lat - a.lat) + (b.lng - a.lng) * (b.lng - a.lng)).squareRoot()
}
