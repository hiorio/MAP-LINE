import Foundation

/// 앱과 공유 익스텐션이 함께 쓰는 설정.
///
/// 익스텐션은 앱과 다른 프로세스이고 자기 번들을 갖는다. 그래서 앱 타깃에만 두면
/// 익스텐션에서 못 읽는다. 값은 각 타깃의 Info.plist에 같은 키로 심는다.
enum AppConfig {
    /// 카카오 네이티브 앱 키.
    ///
    /// 저장소에 넣지 않는다. 맥에서는 Config.xcconfig(gitignore), CI에서는 저장소
    /// Secrets가 Info.plist로 흘려보낸 값을 읽는다.
    static var kakaoNativeAppKey: String {
        string("KakaoNativeAppKey") ?? ""
    }

    /// 우리 서버. 공유로 들어온 장소를 여기에 물어 후보를 받는다.
    ///
    /// 파싱 규칙을 앱에 다시 구현하지 않기 위해서다. 같은 규칙을 두 곳에 두면 반드시
    /// 어긋난다. 서버 하나만 진실로 둔다.
    static var apiBaseURL: URL {
        if let value = string("ApiBaseURL"), let url = URL(string: value) { return url }
        return URL(string: "https://map-line-production.up.railway.app")!
    }

    private static func string(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
