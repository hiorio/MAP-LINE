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
            // 여기서 안전 영역을 없애지 않는다. 없애면 화면 전체가 상태바 아래까지
            // 밀려 올라가 조작 버튼이 시계·배터리와 겹치고, 아래에서 무엇을 해도
            // 되돌릴 수 없다. 지도만 끝까지 그리면 되는 일이라 그 처리는 ContentView가
            // 배경으로 한다.
            ContentView()
        }
    }
}
