import Foundation

/// 공유 시트로 들어온 것을 서버에 물어 장소 후보로 바꾼다.
///
/// 파싱을 앱에서 다시 구현하지 않는다. 웹의 `lib/kakao/parseShareText.ts`가 이미
/// 카카오맵·네이버지도의 공유 문구를 다루고 있고, 거기서 뽑은 이름으로 카카오 Local에
/// 정식 재검색을 건다. 같은 규칙을 두 곳에 두면 반드시 어긋난다. 서버 하나만 둔다.
///
/// 단축 URL을 직접 푸는 방식은 쓰지 않는다. 기술적으로는 쉽지만 타사 약관상 회색지대다.
/// 서버가 URL을 버리고 이름으로 재검색하는 것도 같은 이유다.
enum ShareIntake {
    /// 서버가 돌려준 장소 후보 하나.
    struct Candidate: Decodable, Identifiable {
        let kakaoPlaceId: String?
        let name: String
        let address: String?
        let roadAddress: String?
        let category: String?
        let location: Location

        struct Location: Decodable {
            let lat: Double
            let lng: Double
        }

        var id: String {
            if let kakaoPlaceId, !kakaoPlaceId.isEmpty { return kakaoPlaceId }
            return "\(name)-\(location.lat)-\(location.lng)"
        }

        func asSavedPlace(groupID: String = SavedPlaceGroup.inboxID) -> SavedPlace {
            SavedPlace(
                name: name,
                address: roadAddress ?? address,
                kakaoPlaceId: kakaoPlaceId,
                lat: location.lat,
                lng: location.lng,
                groupID: groupID
            )
        }
    }

    struct Parsed: Decodable {
        let name: String
        let address: String?
        let region: String?
        let query: String
    }

    struct Group: Decodable, Identifiable {
        let parsed: Parsed
        let places: [Candidate]

        var id: String { "\(parsed.name)|\(parsed.address ?? "")" }
    }

    struct Response: Decodable {
        let parsed: Parsed?
        let groups: [Group]?
        let places: [Candidate]?
        let error: String?
    }

    enum IntakeError: LocalizedError {
        case noName
        case server(String)

        var errorDescription: String? {
            switch self {
            case .noName:
                // 공유한 앱이 링크만 넘겼을 때 여기로 온다. 이름이 없으면 재검색할 것이 없다.
                return "장소 이름을 찾지 못했습니다. 이름이나 주소가 함께 공유되는지 확인해 주세요."
            case .server(let message):
                return message
            }
        }
    }

    /// 공유 시트가 준 조각들을 한 덩어리 텍스트로 합친다.
    ///
    /// 앱마다 무엇을 넘기는지 다르다. 텍스트만, 링크만, 둘 다 오는 경우가 모두 있어서
    /// 골라내지 않고 전부 붙여 보낸다. 서버가 URL을 버리고 쓸 만한 줄만 추린다.
    static func combine(_ pieces: [String]) -> String {
        pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func lookUp(text: String, baseURL: URL) async throws -> [Group] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/parse-share"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded = try? JSONDecoder().decode(Response.self, from: data)

        guard let http = response as? HTTPURLResponse else {
            throw IntakeError.server("응답을 읽지 못했습니다.")
        }
        // 422는 "이름을 못 찾았다"는 답이다. 통신 실패와 구별해서 안내해야 고칠 수 있다.
        if http.statusCode == 422 { throw IntakeError.noName }
        guard http.statusCode == 200 else {
            throw IntakeError.server(decoded?.error ?? "검색에 실패했습니다 (\(http.statusCode))")
        }

        let groups = decoded?.groups ?? {
            guard let parsed = decoded?.parsed, let places = decoded?.places else { return [] }
            return [Group(parsed: parsed, places: places)]
        }()
        if groups.flatMap(\.places).isEmpty { throw IntakeError.noName }
        return groups
    }
}
