import Foundation

/// 지도에 얹을 중간지점 한 판.
///
/// 결과를 목록으로만 보여 주면 "옥수역"이라는 글자가 어디쯤인지 알 수 없다. 누가
/// 어디서 오고 어디로 모이는지는 지도 위에서만 한눈에 읽힌다.
///
/// 서버 응답(`Midpoint.Result`)을 지도에 그대로 넘기지 않는다. 지도는 중간지점 API의
/// 생김새를 알 필요가 없고, 그리는 데 필요한 것은 점 몇 개와 이름뿐이다. 사이에 이
/// 타입을 두면 API가 바뀌어도 고칠 곳이 여기 하나다.
struct MidpointPlot: Equatable {
    struct Pin: Equatable {
        let id: String
        let title: String
        let lat: Double
        let lng: Double
    }

    /// 사람들이 출발하는 자리.
    var origins: [Pin]
    /// 모이기로 한 자리.
    var meeting: Pin
    /// 몇 번째 후보인가. 지도 위 번호가 목록의 번호와 같아야 옮겨 보며 헷갈리지 않는다.
    var rank: Int
    /// 고른 시각.
    ///
    /// 값이 같으면 다시 그리지 않는데, 그것만으로는 지도를 손으로 옮겨 둔 뒤 같은
    /// 후보를 다시 눌렀을 때 아무 일도 일어나지 않는다. "다시 보여 달라"는 뜻이
    /// 전달되도록 고른 순간을 함께 담는다.
    var pickedAt: Date

    /// 카메라가 담아야 할 전부.
    var everyPoint: [Pin] { origins + [meeting] }
}

extension MidpointPlot {
    /// 서버 응답과 화면에 입력된 사람들을 지도가 아는 형태로 옮긴다.
    ///
    /// 이름은 참가자 쪽에서 가져온다. 응답의 leg에는 참가자 id만 있어서, 그대로 쓰면
    /// 지도에 "친구 2" 대신 UUID가 뜬다.
    init(
        participants: [Midpoint.Participant],
        candidate: Midpoint.Candidate,
        rank: Int,
        pickedAt: Date = Date()
    ) {
        origins = participants.map {
            Pin(id: $0.id, title: $0.name, lat: $0.place.lat, lng: $0.place.lng)
        }
        meeting = Pin(
            id: candidate.id,
            title: candidate.place.name,
            lat: candidate.place.location.lat,
            lng: candidate.place.location.lng
        )
        self.rank = rank
        self.pickedAt = pickedAt
    }

    /// 카메라가 맞춰야 할 사각형.
    ///
    /// 점들에 딱 맞추면 가장자리 핀의 이름표가 화면 밖으로 잘린다. 여백을 준다.
    /// 두 사람이 같은 건물에서 오는 경우처럼 폭이 0이 될 수 있어서, 비율만으로는
    /// 여백이 0이 된다. 최소값을 함께 둔다. 0.002도는 대략 220m다.
    ///
    /// 지도 SDK를 부르지 않는 순수 계산이라 시뮬레이터 없이 검증할 수 있다.
    func viewport(
        paddingRatio: Double = 0.10,
        minimumPaddingDeg: Double = 0.002
    ) -> (south: Double, west: Double, north: Double, east: Double) {
        let points = everyPoint
        // meeting이 항상 있으므로 비지 않는다. 그래도 min()은 옵셔널이라 기본값을 둔다.
        let lats = points.map(\.lat)
        let lngs = points.map(\.lng)
        let minLat = lats.min() ?? meeting.lat
        let maxLat = lats.max() ?? meeting.lat
        let minLng = lngs.min() ?? meeting.lng
        let maxLng = lngs.max() ?? meeting.lng

        let padLat = max((maxLat - minLat) * paddingRatio, minimumPaddingDeg)
        let padLng = max((maxLng - minLng) * paddingRatio, minimumPaddingDeg)

        return (
            south: minLat - padLat,
            west: minLng - padLng,
            north: maxLat + padLat,
            east: maxLng + padLng
        )
    }
}
