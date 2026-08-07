import SwiftUI

/// SwiftUI에서 카카오 지도를 쓰기 위한 껍데기.
///
/// 엔진을 뷰 생명주기에 맞춰 준비·정지시켜야 해서 UIViewController를 감싼다.
/// UIView만 감싸면 viewWillAppear/viewWillDisappear에 해당하는 지점이 없다.
struct KakaoMapView: UIViewControllerRepresentable {
    var isDrawing: Bool
    /// 편집 시트의 보조 이동 모드가 켜진 동안에는 직접 메모 드래그를 시작하지 않는다.
    var isChoosingMemoMoveTarget: Bool
    /// 지도에 얹을 중간지점. nil이면 지운다.
    var plot: MidpointPlot?
    /// 지도에 찍은 단계들.
    var stops: [Stop]
    /// 단계 사이 구간.
    var legs: [StopLeg]
    /// 같은 단계에 후보가 여럿일 때 후보끼리 묶어 보이는 회색 보조선.
    var showCandidateLinks: Bool
    /// 손으로 그린 획들.
    var strokes: [GeoStroke]
    /// 지도 위에 남긴 메모들.
    var labels: [MapLabel]
    /// 개인 보관함의 장소들. 현재 문서에 넣지 않아도 지도에서는 항상 참고할 수 있다.
    var savedPins: [SavedPlacePin]
    /// 마지막으로 확인한 기기 위치. nil이면 현재 위치 표식을 지운다.
    var currentLocation: GeoPoint?
    var onLongPress: (GeoPoint) -> Void
    var onTapStopPin: (String) -> Void
    /// 개인 보관함 마커를 눌렀을 때 저장 항목 id를 준다.
    var onTapSavedPin: (String) -> Void
    var onTapMapPoi: (GeoPoint, String) -> Void
    var onTapMemo: (String) -> Void
    /// 메모를 길게 누른 채 끌고 손을 뗐을 때 확정된 위치.
    var onMoveMemo: (String, GeoPoint) -> Void
    var onStrokesChanged: ([GeoStroke]) -> Void
    /// 지금 보고 있는 자리를 물어볼 수 있게 컨트롤러를 넘겨준다. 저장할 때 쓴다.
    var onReady: (KakaoMapViewController) -> Void

    func makeUIViewController(context: Context) -> KakaoMapViewController {
        let controller = KakaoMapViewController()
        apply(to: controller, context: context)
        if let plot {
            // 엔진이 뜨기 전에 넘겨 둔다. 컨트롤러가 시작 자리를 여기에 맞추고,
            // 준비되는 즉시 그린다. 뜬 뒤에 옮기면 기본 자리가 한 번 보였다 사라진다.
            controller.show(midpoint: plot)
            context.coordinator.lastPlot = plot
        }
        onReady(controller)
        return controller
    }

    func updateUIViewController(_ controller: KakaoMapViewController, context: Context) {
        if controller.isDrawing != isDrawing {
            controller.isDrawing = isDrawing
        }
        apply(to: controller, context: context)

        // 같은 값을 다시 넘겨도 다시 그리지 않는다. 화면이 갱신될 때마다 카메라가
        // 움직이면 사람이 손으로 옮겨 둔 위치가 계속 되돌아간다. 같은 후보를 일부러
        // 다시 고른 경우는 MidpointPlot이 고른 시각을 달리 담아 여기서 구별된다.
        if plot != context.coordinator.lastPlot {
            context.coordinator.lastPlot = plot
            controller.show(midpoint: plot)
        }
    }

    private func apply(to controller: KakaoMapViewController, context: Context) {
        // 콜백은 매번 새로 만들어진 클로저라 값 비교가 안 된다. 그대로 갈아 끼운다.
        // 오래된 클로저를 들고 있으면 이미 사라진 화면 상태를 붙잡게 된다.
        controller.onLongPress = onLongPress
        controller.onTapStopPin = onTapStopPin
        controller.onTapSavedPin = onTapSavedPin
        controller.onTapMapPoi = onTapMapPoi
        controller.onTapMemo = onTapMemo
        controller.onMoveMemo = onMoveMemo
        controller.onStrokesChanged = onStrokesChanged
        controller.memoDragEnabled = !isChoosingMemoMoveTarget
        controller.showCandidateLinks = showCandidateLinks
        // 컨트롤러 쪽 didSet이 같은 값이면 다시 그리지 않는다.
        // 단계를 먼저 넣는다. 구간은 단계를 근거로 그려지므로 순서가 뒤바뀌면
        // 아직 없는 단계를 가리키는 구간을 한 번 그리게 된다.
        controller.stops = stops
        controller.legs = legs
        controller.strokes = strokes
        controller.labels = labels
        controller.savedPins = savedPins
        controller.currentLocation = currentLocation
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastPlot: MidpointPlot?
    }
}
