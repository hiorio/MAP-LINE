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
            case walk, transit, bicycle
            var id: String { rawValue }

            var label: String {
                switch self {
                case .walk: return "도보"
                case .transit: return "대중교통"
                case .bicycle: return "자전거"
                }
            }

            var symbol: String {
                switch self {
                case .walk: return "figure.walk"
                case .transit: return "tram.fill"
                case .bicycle: return "bicycle"
                }
            }
        }
    }

    // MARK: - 서버 응답

    struct Result: Decodable {
        /// 참고용 기하 중심. 이건 답이 아니라 후보를 찾은 출발점이다.
        let center: Coordinate
        let searchRadiusM: Int
        let candidates: [Candidate]

        struct Coordinate: Decodable { let lat: Double; let lng: Double }
    }

    struct Candidate: Decodable, Identifiable {
        let place: Place
        let legs: [Leg]
        /// 가장 오래 걸리는 사람의 시간. 순위의 기준이다.
        let maxDurationS: Int
        let totalDurationS: Int
        /// 모두의 경로를 구했을 때만 있다. 한 명이라도 빠지면 알 수 없는 값이다.
        let spreadS: Int?
        let complete: Bool

        struct Place: Decodable {
            let kakaoPlaceId: String?
            let name: String
            let address: String?
            let location: PlaceCandidate.Coordinate
        }

        struct Leg: Decodable, Identifiable {
            let participantId: String
            let mode: String
            /// 길찾기가 실패하면 없다. 그 수단으로는 갈 수 없다는 뜻이다.
            let durationS: Int?
            let distanceM: Int?
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

/// 초를 사람이 읽는 시간으로.
func formatDuration(_ seconds: Int) -> String {
    let minutes = Int((Double(seconds) / 60).rounded())
    if minutes < 60 { return "\(minutes)분" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
}
