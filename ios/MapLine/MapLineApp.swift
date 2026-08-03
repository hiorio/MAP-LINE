import SwiftUI
import KakaoMapsSDK

@main
struct MapLineApp: App {
    init() {
        // 엔진이 뜨기 전에 불러야 한다고 문서에 명시돼 있다.
        SDKInitializer.InitSDK(appKey: AppConfig.kakaoNativeAppKey)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
        }
    }
}

enum AppConfig {
    /// 카카오 네이티브 앱 키.
    ///
    /// 저장소에 넣지 않는다. Config.xcconfig(gitignore)나 CI 시크릿이 Info.plist로
    /// 흘려보낸 값을 읽는다. 비어 있으면 지도 타일이 뜨지 않고 addViewFailed가 온다.
    static var kakaoNativeAppKey: String {
        let key = Bundle.main.object(forInfoDictionaryKey: "KakaoNativeAppKey") as? String
        return key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
