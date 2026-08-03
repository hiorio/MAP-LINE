import SwiftUI

/// SwiftUI에서 카카오 지도를 쓰기 위한 껍데기.
///
/// 엔진을 뷰 생명주기에 맞춰 준비·정지시켜야 해서 UIViewController를 감싼다.
/// UIView만 감싸면 viewWillAppear/viewWillDisappear에 해당하는 지점이 없다.
struct KakaoMapView: UIViewControllerRepresentable {
    var isDrawing: Bool
    /// 여기로 지도를 옮긴다. 값이 바뀔 때만 움직인다.
    var focus: MapFocus?

    func makeUIViewController(context: Context) -> KakaoMapViewController {
        let controller = KakaoMapViewController()
        if let focus {
            controller.initialCenter = (lat: focus.lat, lng: focus.lng)
            context.coordinator.lastFocus = focus
        }
        return controller
    }

    func updateUIViewController(_ controller: KakaoMapViewController, context: Context) {
        if controller.isDrawing != isDrawing {
            controller.isDrawing = isDrawing
        }
        // 같은 자리를 다시 넘겨도 움직이지 않는다. 화면이 다시 그려질 때마다
        // 카메라가 튀면 사람이 손으로 옮겨 둔 위치가 계속 되돌아간다.
        if let focus, focus != context.coordinator.lastFocus {
            context.coordinator.lastFocus = focus
            controller.move(to: focus.lat, lng: focus.lng)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastFocus: MapFocus?
    }
}

/// 지도를 옮길 자리. 같은 곳을 다시 고르는 것도 구별해야 해서 고른 시각을 함께 담는다.
struct MapFocus: Equatable {
    let name: String
    let lat: Double
    let lng: Double
    let requestedAt: Date

    init(name: String, lat: Double, lng: Double, requestedAt: Date = Date()) {
        self.name = name
        self.lat = lat
        self.lng = lng
        self.requestedAt = requestedAt
    }
}
