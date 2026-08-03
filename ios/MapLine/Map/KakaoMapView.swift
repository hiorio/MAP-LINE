import SwiftUI

/// SwiftUI에서 카카오 지도를 쓰기 위한 껍데기.
///
/// 엔진을 뷰 생명주기에 맞춰 준비·정지시켜야 해서 UIViewController를 감싼다.
/// UIView만 감싸면 viewWillAppear/viewWillDisappear에 해당하는 지점이 없다.
struct KakaoMapView: UIViewControllerRepresentable {
    var isDrawing: Bool
    /// 처음 보여 줄 자리. 중간지점에서 고른 곳으로 시작할 때 넘어온다.
    var center: MapScreen.Center?

    func makeUIViewController(context: Context) -> KakaoMapViewController {
        let controller = KakaoMapViewController()
        // 엔진이 뜨기 전에 정해 둬야 한다. 뜬 뒤에 옮기면 처음 자리가 한 번 보였다 사라진다.
        if let center {
            controller.initialCenter = (lat: center.lat, lng: center.lng)
        }
        return controller
    }

    func updateUIViewController(_ controller: KakaoMapViewController, context: Context) {
        guard controller.isDrawing != isDrawing else { return }
        controller.isDrawing = isDrawing
    }
}
