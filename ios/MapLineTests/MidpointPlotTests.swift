import XCTest
@testable import MapLine

/// 중간지점을 지도에 얹을 때의 규칙.
///
/// 카메라를 어디에 맞추는지는 지도 SDK 없이 정해지는 계산이라 여기서 붙든다.
/// 시뮬레이터에서 눈으로 보는 것으로는 "가장자리가 잘리지 않는다" 같은 것을
/// 매번 확인할 수 없다.
final class MidpointPlotTests: XCTestCase {
    private func plot(
        origins: [(Double, Double)],
        meeting: (Double, Double)
    ) -> MidpointPlot {
        MidpointPlot(
            origins: origins.enumerated().map {
                .init(id: "\($0.offset)", title: "사람\($0.offset)", lat: $0.element.0, lng: $0.element.1)
            },
            meetings: [
                .init(
                    pin: .init(id: "m", title: "모이는 곳", lat: meeting.0, lng: meeting.1),
                    rank: 1,
                    routes: []
                ),
            ],
            pickedAt: Date()
        )
    }

    func test_모이는자리도카메라에담는다() {
        // 출발지만 담으면 정작 답이 화면 밖에 있을 수 있다.
        let subject = plot(origins: [(37.50, 127.02), (37.55, 127.10)], meeting: (37.40, 126.90))
        let box = subject.viewport()

        XCTAssertLessThan(box.south, 37.40)
        XCTAssertLessThan(box.west, 126.90)
        XCTAssertGreaterThan(box.north, 37.55)
        XCTAssertGreaterThan(box.east, 127.10)
    }

    func test_가장자리에여백을준다() {
        // 점에 딱 맞추면 핀 아래 이름표가 잘린다.
        let subject = plot(origins: [(37.00, 127.00)], meeting: (38.00, 128.00))
        let box = subject.viewport(paddingRatio: 0.2, minimumPaddingDeg: 0)

        // 위아래로 1도 폭이니 여백은 0.2도씩이다.
        XCTAssertEqual(box.south, 36.8, accuracy: 1e-9)
        XCTAssertEqual(box.north, 38.2, accuracy: 1e-9)
        XCTAssertEqual(box.west, 126.8, accuracy: 1e-9)
        XCTAssertEqual(box.east, 128.2, accuracy: 1e-9)
    }

    func test_모두같은자리여도폭이생긴다() {
        // 한 건물에서 다 같이 출발하는 경우. 비율만 쓰면 여백이 0이 되고 사각형이
        // 한 점으로 무너져 카메라가 갈 곳을 잃는다.
        let subject = plot(origins: [(37.5, 127.0), (37.5, 127.0)], meeting: (37.5, 127.0))
        let box = subject.viewport(paddingRatio: 0.18, minimumPaddingDeg: 0.002)

        XCTAssertEqual(box.north - box.south, 0.004, accuracy: 1e-9)
        XCTAssertEqual(box.east - box.west, 0.004, accuracy: 1e-9)
    }

    func test_참가자이름과후보순위를옮겨담는다() throws {
        // 응답의 leg에는 참가자 id뿐이라, 이름은 화면이 들고 있는 참가자에서 와야 한다.
        let participants: [Midpoint.Participant] = [
            .init(
                id: "a",
                name: "민수",
                place: .init(name: "강남역", address: nil, lat: 37.4979, lng: 127.0276),
                mode: .transit
            ),
        ]
        let candidate = try JSONDecoder().decode(
            Midpoint.Candidate.self,
            from: Data(
                """
                {"place":{"kakaoPlaceId":"1","name":"옥수역","address":null,
                "location":{"lat":37.54,"lng":127.01}},
                "legs":[{"participantId":"a","mode":"transit","durationS":900,"distanceM":5000,
                "points":[{"lat":37.4979,"lng":127.0276},{"lat":37.54,"lng":127.01}],
                "transitLegs":[{"type":"SUBWAY","guidance":"2호선","pointCount":2}]}],
                "maxDurationS":900,"totalDurationS":900,"spreadS":0,"complete":true}
                """.utf8
            )
        )

        let subject = MidpointPlot(participants: participants, selections: [(rank: 2, candidate: candidate)])

        XCTAssertEqual(subject.origins.map(\.title), ["민수"])
        XCTAssertEqual(subject.meetings.first?.pin.title, "옥수역")
        XCTAssertEqual(subject.meetings.first?.rank, 2)
        XCTAssertEqual(subject.meetings.first?.routes.first?.mode, .transit)
        XCTAssertEqual(subject.meetings.first?.routes.first?.points.count, 2)
        XCTAssertEqual(subject.everyPoint.count, 2)
    }
}
