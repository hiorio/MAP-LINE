import SwiftUI

/// SwiftUI에서 카카오 지도를 쓰기 위한 껍데기.
///
/// 엔진을 뷰 생명주기에 맞춰 준비·정지시켜야 해서 UIViewController를 감싼다.
/// UIView만 감싸면 viewWillAppear/viewWillDisappear에 해당하는 지점이 없다.
struct KakaoMapView: UIViewControllerRepresentable {
    var isDrawing: Bool
    /// 지도에 얹을 중간지점. nil이면 지운다.
    var plot: MidpointPlot?
    /// 지도에 찍은 단계들.
    var stops: [Stop]
    var onLongPress: (GeoPoint) -> Void
    var onTapStopPin: (String) -> Void

    func makeUIViewController(context: Context) -> KakaoMapViewController {
        let controller = KakaoMapViewController()
        controller.stops = stops
        controller.onLongPress = onLongPress
        controller.onTapStopPin = onTapStopPin
        if let plot {
            // 엔진이 뜨기 전에 넘겨 둔다. 컨트롤러가 시작 자리를 여기에 맞추고,
            // 준비되는 즉시 그린다. 뜬 뒤에 옮기면 기본 자리가 한 번 보였다 사라진다.
            controller.show(midpoint: plot)
            context.coordinator.lastPlot = plot
        }
        return controller
    }

    func updateUIViewController(_ controller: KakaoMapViewController, context: Context) {
        if controller.isDrawing != isDrawing {
            controller.isDrawing = isDrawing
        }
        // 콜백은 매번 새로 만들어진 클로저라 값 비교가 안 된다. 그대로 갈아 끼운다.
        // 오래된 클로저를 들고 있으면 이미 사라진 화면 상태를 붙잡게 된다.
        controller.onLongPress = onLongPress
        controller.onTapStopPin = onTapStopPin
        // 컨트롤러 쪽 didSet이 같은 값이면 다시 그리지 않는다.
        controller.stops = stops
        // 같은 값을 다시 넘겨도 다시 그리지 않는다. 화면이 갱신될 때마다 카메라가
        // 움직이면 사람이 손으로 옮겨 둔 위치가 계속 되돌아간다. 같은 후보를 일부러
        // 다시 고른 경우는 MidpointPlot이 고른 시각을 달리 담아 여기서 구별된다.
        if plot != context.coordinator.lastPlot {
            context.coordinator.lastPlot = plot
            controller.show(midpoint: plot)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastPlot: MidpointPlot?
    }
}
