import UIKit
import KakaoMapsSDK

/// 카카오 지도를 띄우고 그 위의 손그림을 관리한다.
///
/// SDK 구조상 `KMViewContainer`(엔진이 들어 있는 뷰)와 `KMController`(엔진 상태 관리)가
/// 짝이다. 엔진은 뷰 생명주기에 맞춰 준비·활성·정지시켜야 하므로 SwiftUI 뷰보다
/// UIViewController에 두는 편이 자연스럽다.
///
/// 그림을 SDK의 `ShapeManager`에 넘기는 것이 이 설계의 핵심이다. 화면 좌표로 직접
/// 그리면 팬·줌 때마다 우리가 다시 투영해야 하는데, iOS SDK에는 지도좌표 → 화면좌표
/// 공개 메서드가 없다. Shape로 등록하면 재투영을 SDK가 전부 맡는다. 웹에서 캔버스를
/// 손으로 따라 움직이며 겪은 문제가 여기서는 생기지 않는다.
final class KakaoMapViewController: UIViewController {
    private var mapContainer: KMViewContainer?
    private var mapController: KMController?
    private var drawingView: DrawingOverlayView?

    /// 지도가 준비되기 전에는 그릴 수 없다. 준비 여부를 한 곳에서 본다.
    private var kakaoMap: KakaoMap? {
        mapController?.getView(Self.viewName) as? KakaoMap
    }

    private static let viewName = "mapview"
    private static let shapeLayerID = "strokes"
    private static let strokeStyleID = "strokeStyle"

    /// 그려 둔 획들. 저장·공유는 다음 단계이고 지금은 메모리에만 둔다.
    private(set) var strokes: [GeoStroke] = []

    // MARK: - 생명주기

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let container = KMViewContainer(frame: view.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(container)
        mapContainer = container

        let controller = KMController(viewContainer: container)
        controller.delegate = self
        mapController = controller

        // 그리기 레이어는 지도 위에 얹되, 그리기 모드가 아닐 때는 터치를 지도로 흘린다.
        let drawing = DrawingOverlayView(frame: view.bounds)
        drawing.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        drawing.backgroundColor = .clear
        drawing.delegate = self
        view.addSubview(drawing)
        drawingView = drawing
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if mapController?.isEnginePrepared == false { mapController?.prepareEngine() }
        if mapController?.isEngineActive == false { mapController?.activateEngine() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        mapController?.pauseEngine()
    }

    deinit {
        mapController?.pauseEngine()
        mapController?.resetEngine()
    }

    // MARK: - 조작

    /// 그리기 모드에서는 지도가 움직이면 안 된다. 손가락 하나가 두 가지 뜻을 가질 수 없다.
    var isDrawing: Bool = false {
        didSet {
            drawingView?.isEnabled = isDrawing
            kakaoMap?.setGestureEnable(type: .pan, enable: !isDrawing)
            kakaoMap?.setGestureEnable(type: .zoom, enable: !isDrawing)
        }
    }
}

// MARK: - 엔진 준비

extension KakaoMapViewController: MapControllerDelegate {
    func addViews() {
        let defaultPosition = MapPoint(longitude: 127.0276, latitude: 37.4979) // 강남역
        let info = MapviewInfo(
            viewName: Self.viewName,
            viewInfoName: "map",
            defaultPosition: defaultPosition,
            defaultLevel: 17
        )
        mapController?.addView(info)
    }

    func addViewSucceeded(_ viewName: String, viewInfoName: String) {
        guard let map = kakaoMap else { return }
        map.viewRect = view.bounds
        // 획을 담을 레이어와 스타일을 미리 만들어 둔다. zOrder는 기본 지물보다 위다.
        _ = map.getShapeManager().addShapeLayer(layerID: Self.shapeLayerID, zOrder: 10_001)
        registerStrokeStyle(on: map)

        // UI 테스트가 지도 준비를 기다릴 수 있게 상태를 접근성 식별자로 내건다.
        // 고정 시간 대기는 러너가 느린 날 깨진다.
        view.accessibilityIdentifier = "mapReady"
    }

    func addViewFailed(_ viewName: String, viewInfoName: String) {
        // 앱 키가 없거나 번들 ID가 콘솔에 등록되지 않으면 여기로 온다.
        NSLog("[KakaoMap] 뷰 추가 실패: \(viewName). 앱 키와 번들 ID 등록을 확인하세요.")
        // 실패도 상태로 내건다. 테스트가 "느린 것"과 "안 되는 것"을 구별해야 한다.
        view.accessibilityIdentifier = "mapFailed"
    }

    func containerDidResized(_ size: CGSize) {
        kakaoMap?.viewRect = CGRect(origin: .zero, size: size)
    }
}

// MARK: - 손그림

extension KakaoMapViewController: DrawingOverlayViewDelegate {
    /// 화면에서 찍힌 점을 그 자리의 위경도로 바꾼다.
    ///
    /// `getPosition`은 뷰 바깥 좌표를 주면 잘못된 값을 돌려준다고 문서에 명시돼 있다.
    /// 손가락이 화면을 벗어나는 경우를 여기서 걸러 낸다.
    func drawingView(_ view: DrawingOverlayView, didFinishStroke screenPoints: [CGPoint]) {
        guard let map = kakaoMap else { return }

        let bounds = view.bounds
        let coords = screenPoints
            .filter { bounds.contains($0) }
            .map { point -> GeoPoint in
                let position = map.getPosition(point)
                return GeoPoint(lat: position.wgsCoord.latitude, lng: position.wgsCoord.longitude)
            }

        // 점이 둘은 있어야 선이다.
        guard coords.count >= 2 else { return }

        // 화면 1px 남짓에 해당하는 각도를 기준으로 솎아 낸다. 줌마다 달라야 해서
        // 화면 위 두 점의 좌표 차이로 그때그때 구한다.
        let epsilon = angularEpsilon(map: map, pixels: 2)
        let stroke = GeoStroke(
            path: simplifyPath(coords, epsilon: epsilon),
            zoomCreated: map.zoomLevel
        )
        strokes.append(stroke)
        render(stroke, on: map)
    }

    /// 획을 SDK 도형으로 등록한다.
    ///
    /// `PolylineShape`이 아니라 **`MapPolylineShape`**을 쓴다. 앞의 것은 기준점 대비
    /// 모델 좌표(CGPoint)를 받아서 지도를 옮기면 같이 움직이지 않는다. 위경도로 이루어진
    /// 선은 `Map`이 붙은 쪽이다. 이걸 헷갈리면 컴파일은 되는데 그림이 지도에 안 붙는다.
    private func render(_ stroke: GeoStroke, on map: KakaoMap) {
        guard let layer = map.getShapeManager().getShapeLayer(layerID: Self.shapeLayerID) else { return }

        let points = stroke.path.map { MapPoint(longitude: $0.lng, latitude: $0.lat) }
        let options = MapPolylineShapeOptions(
            shapeID: stroke.id.uuidString,
            styleID: Self.strokeStyleID,
            zOrder: 1
        )
        options.polylines = [MapPolyline(line: points, styleIndex: 0)]

        let shape = layer.addMapPolylineShape(options)
        shape?.show()
    }

    /// 획 스타일을 한 번만 등록한다. 획마다 등록하면 같은 ID를 계속 덮어쓴다.
    private func registerStrokeStyle(on map: KakaoMap) {
        let perLevel = PerLevelPolylineStyle(bodyColor: .systemBlue, bodyWidth: 6, level: 0)
        let styleSet = PolylineStyleSet(
            styleSetID: Self.strokeStyleID,
            styles: [PolylineStyle(styles: [perLevel])]
        )
        map.getShapeManager().addPolylineStyleSet(styleSet)
    }

    /// 화면 픽셀 몇 개에 해당하는 각도. RDP 임계값을 줌에 맞추기 위해 쓴다.
    private func angularEpsilon(map: KakaoMap, pixels: CGFloat) -> Double {
        let origin = map.getPosition(CGPoint(x: 0, y: 0))
        let shifted = map.getPosition(CGPoint(x: pixels, y: 0))
        return abs(shifted.wgsCoord.longitude - origin.wgsCoord.longitude)
    }
}
