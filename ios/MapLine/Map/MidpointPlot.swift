import Foundation

/// 지도에 함께 얹을 중간지점 후보들과 참가자별 실제 이동 경로.
struct MidpointPlot: Equatable {
    struct Pin: Equatable {
        let id: String
        let title: String
        let lat: Double
        let lng: Double
    }

    struct Route: Equatable {
        let participantID: String
        let meetingID: String
        let mode: TravelMode
        let points: [GeoPoint]
        let transitLegs: [TransitLeg]?
        let distanceM: Int?
        let durationS: Int?
    }

    struct Meeting: Equatable {
        let pin: Pin
        let rank: Int
        let routes: [Route]
    }

    /// 사람들이 출발하는 자리. 여러 후보를 선택해도 한 번만 그린다.
    var origins: [Pin]
    /// 지도에서 함께 비교할 후보들.
    var meetings: [Meeting]
    /// 같은 선택을 다시 눌러도 카메라를 다시 맞추게 하는 값.
    var pickedAt: Date

    var everyPoint: [Pin] { origins + meetings.map(\.pin) }

    init(
        origins: [Pin],
        meetings: [Meeting],
        pickedAt: Date = Date()
    ) {
        self.origins = origins
        self.meetings = meetings
        self.pickedAt = pickedAt
    }
}

extension MidpointPlot {
    /// 선택한 후보를 한 판으로 묶고, 서버 경로 응답을 앱의 공통 경로 타입으로 옮긴다.
    init(
        participants: [Midpoint.Participant],
        selections: [(rank: Int, candidate: Midpoint.Candidate)],
        pickedAt: Date = Date()
    ) {
        origins = participants.map {
            Pin(id: $0.id, title: $0.name, lat: $0.place.lat, lng: $0.place.lng)
        }
        meetings = selections.map { selection in
            let candidate = selection.candidate
            let meetingID = candidate.id
            let routes = candidate.legs.compactMap { leg -> Route? in
                guard
                    let mode = TravelMode(rawValue: leg.mode),
                    let points = leg.points,
                    points.count >= 2
                else { return nil }

                return Route(
                    participantID: leg.participantId,
                    meetingID: meetingID,
                    mode: mode,
                    points: points.map { GeoPoint(lat: $0.lat, lng: $0.lng) },
                    transitLegs: leg.transitLegs?.map {
                        TransitLeg(type: $0.type, guidance: $0.guidance, pointCount: $0.pointCount)
                    },
                    distanceM: leg.distanceM,
                    durationS: leg.durationS
                )
            }
            return Meeting(
                pin: Pin(
                    id: meetingID,
                    title: candidate.place.name,
                    lat: candidate.place.location.lat,
                    lng: candidate.place.location.lng
                ),
                rank: selection.rank,
                routes: routes
            )
        }
        self.pickedAt = pickedAt
    }

    /// 참가자와 선택한 후보가 모두 보이도록 하는 사각형.
    func viewport(
        paddingRatio: Double = 0.10,
        minimumPaddingDeg: Double = 0.002
    ) -> (south: Double, west: Double, north: Double, east: Double) {
        let points = everyPoint
        let fallback = points.first ?? Pin(id: "fallback", title: "", lat: 0, lng: 0)
        let lats = points.map(\.lat)
        let lngs = points.map(\.lng)
        let minLat = lats.min() ?? fallback.lat
        let maxLat = lats.max() ?? fallback.lat
        let minLng = lngs.min() ?? fallback.lng
        let maxLng = lngs.max() ?? fallback.lng

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
