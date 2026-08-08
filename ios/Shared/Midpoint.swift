import Foundation

/// 여러 곳에서 오는 사람들이 모이기 좋은 자리를 서버에 묻는다.
///
/// 계산은 전부 서버가 한다. 카카오 검색과 길찾기가 필요하고 둘 다 서버 전용 키인
/// 데다, 웹과 앱이 같은 답을 내야 하기 때문이다. 앱은 사람을 모아 보내고 결과를
/// 그리는 일만 한다.
enum Midpoint {
    /// 모임에 오는 한 사람.
    struct Participant: Identifiable, Equatable, Codable {
        let id: String
        var name: String
        var place: Place
        var mode: Mode

        struct Place: Equatable, Codable {
            var name: String
            var address: String?
            var lat: Double
            var lng: Double
        }

        enum Mode: String, Codable, CaseIterable, Identifiable {
            case walk, transit, bicycle, car
            var id: String { rawValue }

            var label: String {
                switch self {
                case .walk: return "도보"
                case .transit: return "대중교통"
                case .bicycle: return "자전거"
                case .car: return "자동차"
                }
            }

            var symbol: String {
                switch self {
                case .walk: return "figure.walk"
                case .transit: return "tram.fill"
                case .bicycle: return "bicycle"
                case .car: return "car.fill"
                }
            }
        }
    }

    // MARK: - 서버 응답

    struct Result: Codable {
        /// 참고용 기하 중심. 이건 답이 아니라 후보를 찾은 출발점이다.
        let center: Coordinate
        let searchRadiusM: Int
        let candidates: [Candidate]

        struct Coordinate: Codable { let lat: Double; let lng: Double }
    }

    struct Candidate: Codable, Identifiable {
        let place: Place
        let legs: [Leg]
        /// 가장 오래 걸리는 사람의 시간. 순위의 기준이다.
        /// 실시간 결과에는 항상 있고, 저장 정책상 자동차 경로를 제거한 기록에는 없다.
        let maxDurationS: Int?
        let totalDurationS: Int?
        /// 모두의 경로를 구했을 때만 있다. 한 명이라도 빠지면 알 수 없는 값이다.
        let spreadS: Int?
        let complete: Bool

        struct Place: Codable {
            let kakaoPlaceId: String?
            let name: String
            let address: String?
            let location: PlaceCandidate.Coordinate
        }

        struct Leg: Codable, Identifiable {
            let participantId: String
            let mode: String
            /// 길찾기가 실패하면 없다. 그 수단으로는 갈 수 없다는 뜻이다.
            let durationS: Int?
            let distanceM: Int?
            /// 실제 이동 경로. 없으면 해당 수단으로 경로를 찾지 못한 것이다.
            let points: [PlaceCandidate.Coordinate]?
            /// 대중교통 탈것 구간. 구간 사이는 도보 연결선으로 그린다.
            let transitLegs: [TransitSection]?

            struct TransitSection: Codable {
                let type: String
                let guidance: String
                let pointCount: Int?
            }

            var id: String { participantId }
        }

        var id: String { place.kakaoPlaceId ?? place.name }
    }

    struct ErrorBody: Decodable { let error: String? }

    // MARK: - 호출

    static func find(_ participants: [Participant]) async throws -> Result {
        let body: [String: Any] = [
            "participants": participants.map { person in
                [
                    "id": person.id,
                    "name": person.name,
                    "location": ["lat": person.place.lat, "lng": person.place.lng],
                    "mode": person.mode.rawValue,
                ]
            },
        ]

        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("api/midpoint"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // 참가자 수만큼 길찾기가 나가므로 검색보다 오래 걸린다.
        request.timeoutInterval = 40

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.message("응답을 읽지 못했습니다.")
        }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw AppError.message(message ?? "중간지점을 찾지 못했습니다 (\(http.statusCode))")
        }
        return try JSONDecoder().decode(Result.self, from: data)
    }
}

extension Midpoint.Result {
    /// 기기에 남겨도 되는 중간지점 기록.
    ///
    /// 자동차 길찾기 좌표·거리·시간은 제공자 저장 조건에 따라 현재 검색 세션에서만 쓴다.
    /// 참가자의 `car` 선택과 후보 순서는 사용자 데이터이므로 남기되, 자동차 leg와 그 시간에서
    /// 계산된 후보 요약값은 제거한다. 기록을 다시 열면 사용자가 직접 재계산할 수 있다.
    func historySnapshot() -> Midpoint.Result {
        Midpoint.Result(
            center: center,
            searchRadiusM: searchRadiusM,
            candidates: candidates.map { candidate in
                guard candidate.legs.contains(where: {
                    $0.mode == Midpoint.Participant.Mode.car.rawValue
                }) else { return candidate }

                return Midpoint.Candidate(
                    place: candidate.place,
                    legs: candidate.legs.map { leg in
                        guard leg.mode == Midpoint.Participant.Mode.car.rawValue else { return leg }
                        return Midpoint.Candidate.Leg(
                            participantId: leg.participantId,
                            mode: leg.mode,
                            durationS: nil,
                            distanceM: nil,
                            points: nil,
                            transitLegs: nil
                        )
                    },
                    maxDurationS: nil,
                    totalDurationS: nil,
                    spreadS: nil,
                    complete: false
                )
            }
        )
    }
}

/// 초를 사람이 읽는 시간으로.
func formatDuration(_ seconds: Int) -> String {
    let minutes = Int((Double(seconds) / 60).rounded())
    if minutes < 60 { return "\(minutes)분" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
}
