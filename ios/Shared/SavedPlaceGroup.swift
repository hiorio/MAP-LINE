import Foundation

/// 보관함 폴더를 구별하는 마크. SF Symbol 이름만 저장하므로 앱 버전이 바뀌어도 가볍고,
/// 공유 익스텐션 타깃에서도 UIKit 없이 같은 모델을 읽을 수 있다.
enum SavedPlaceMarker: String, Codable, CaseIterable, Identifiable {
    case pin, star, heart, food, coffee, trip, shopping, home
    case nature, culture, walk, car, stay, school, work, hospital, photo, music

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .pin: return "mappin"
        case .star: return "star.fill"
        case .heart: return "heart.fill"
        case .food: return "fork.knife"
        case .coffee: return "cup.and.saucer.fill"
        case .trip: return "airplane"
        case .shopping: return "bag.fill"
        case .home: return "house.fill"
        case .nature: return "leaf.fill"
        case .culture: return "theatermasks.fill"
        case .walk: return "figure.walk"
        case .car: return "car.fill"
        case .stay: return "bed.double.fill"
        case .school: return "graduationcap.fill"
        case .work: return "briefcase.fill"
        case .hospital: return "cross.case.fill"
        case .photo: return "camera.fill"
        case .music: return "music.note"
        }
    }

    var title: String {
        switch self {
        case .pin: return "핀"
        case .star: return "별"
        case .heart: return "하트"
        case .food: return "맛집"
        case .coffee: return "카페"
        case .trip: return "여행"
        case .shopping: return "쇼핑"
        case .home: return "생활"
        case .nature: return "자연"
        case .culture: return "문화"
        case .walk: return "산책"
        case .car: return "자동차"
        case .stay: return "숙소"
        case .school: return "학교"
        case .work: return "업무"
        case .hospital: return "병원"
        case .photo: return "사진"
        case .music: return "음악"
        }
    }
}

/// 개인 보관함의 하위 폴더. 마크와 색은 폴더 안 모든 장소의 시각적 분류가 된다.
struct SavedPlaceGroup: Codable, Equatable, Identifiable {
    static let inboxID = "inbox"
    static let inbox = SavedPlaceGroup(
        id: inboxID,
        // 예전 버전이 폴더 없이 저장한 장소의 식별자는 그대로 보존한다. 새 공유는
        // 사용자가 고른 폴더로만 들어가며, 이 이름은 실제 미분류 데이터가 있을 때만 보인다.
        name: "미분류",
        marker: .pin,
        colorHex: "#2D6BE4",
        createdAt: ""
    )

    let id: String
    var name: String
    var marker: SavedPlaceMarker
    var colorHex: String
    let createdAt: String

    init(
        id: String = UUID().uuidString,
        name: String,
        marker: SavedPlaceMarker = .star,
        colorHex: String = "#E24B4A",
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.name = name
        self.marker = marker
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}
