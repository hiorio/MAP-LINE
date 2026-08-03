import SwiftUI

/// SwiftUI에서 카카오 지도를 쓰기 위한 껍데기.
///
/// 엔진을 뷰 생명주기에 맞춰 준비·정지시켜야 해서 UIViewController를 감싼다.
/// UIView만 감싸면 viewWillAppear/viewWillDisappear에 해당하는 지점이 없다.
struct KakaoMapView: UIViewControllerRepresentable {
    var isDrawing: Bool

    func makeUIViewController(context: Context) -> KakaoMapViewController {
        KakaoMapViewController()
    }

    func updateUIViewController(_ controller: KakaoMapViewController, context: Context) {
        guard controller.isDrawing != isDrawing else { return }
        controller.isDrawing = isDrawing
    }
}
