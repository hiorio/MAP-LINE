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
