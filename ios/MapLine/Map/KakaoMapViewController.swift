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
    private var longPressRecognizer: UILongPressGestureRecognizer?

    /// 지도가 준비되기 전에는 그릴 수 없다. 준비 여부를 한 곳에서 본다.
    private var kakaoMap: KakaoMap? {
        mapController?.getView(Self.viewName) as? KakaoMap
    }

    private static let viewName = "mapview"
    private static let shapeLayerID = "strokes"
    private static let strokeStyleID = "strokeStyle"
    /// 중간지점 그림은 손그림과 레이어를 나눈다. 한 레이어에 섞으면 중간지점을 지울 때
    /// 사람이 그려 둔 획까지 같이 지워진다.
    private static let midpointLabelLayerID = "midpointPins"
    private static let midpointLinkLayerID = "midpointLinks"
    private static let originStyleID = "midpointOrigin"
    private static let linkStyleID = "midpointLink"
    /// 코스의 단계 핀. 중간지점과도 레이어를 나눈다. 둘은 서로 다른 작업의 결과라
    /// 한쪽을 지운다고 다른 쪽이 사라지면 안 된다.
    private static let stopLabelLayerID = "stopPins"
    private static let legLayerID = "stopLegs"
    private static let memoLayerID = "memos"
    /// UIKit 기본값(0.5초)보다 아주 조금만 빠르게 메뉴를 연다.
    private static let longPressMinimumDuration: TimeInterval = 0.45

    /// 지도에 찍은 단계들. 순서가 곧 번호다.
    var stops: [Stop] = [] {
        didSet {
            guard stops != oldValue, let map = kakaoMap else { return }
            renderStops(on: map)
            renderLegs(on: map)
        }
    }

    /// 단계 사이 구간. `legs[i]`가 `stops[i] → stops[i+1]`이다.
    var legs: [StopLeg] = [] {
        didSet {
            guard legs != oldValue, let map = kakaoMap else { return }
            renderLegs(on: map)
        }
    }

    /// 지도 위에 남긴 메모들.
    var labels: [MapLabel] = [] {
        didSet {
            guard labels != oldValue, let map = kakaoMap else { return }
            renderLabels(on: map)
        }
    }

    /// 지도를 꾹 눌렀을 때. 누른 자리의 위경도를 준다.
    var onLongPress: ((GeoPoint) -> Void)?
    /// 찍어 둔 핀을 눌렀을 때. 그 후보의 id를 준다.
    var onTapStopPin: ((String) -> Void)?
    /// 지도 위 메모를 눌렀을 때. 메모의 id를 준다.
    var onTapMemo: ((String) -> Void)?

    /// SDK 이벤트 구독. 놓으면 구독이 끊기므로 컨트롤러가 살아 있는 동안 들고 있는다.
    private var eventHandlers: [any DisposableEventHandler] = []

    /// 그려 둔 획들.
    ///
    /// 밖에서 넣을 수도 있다. 저장해 둔 지도를 불러오면 그 획들이 여기로 들어온다.
    var strokes: [GeoStroke] = [] {
        didSet {
            guard strokes != oldValue, let map = kakaoMap else { return }
            renderStrokes(on: map)
        }
    }

    /// 손으로 하나 더 그렸을 때. 저장할 쪽이 알아야 한다.
    var onStrokesChanged: (([GeoStroke]) -> Void)?

    /// 지도에 얹은 중간지점. nil이면 아무것도 그리지 않는다.
    ///
    /// 엔진이 뜨기 전에 받을 수 있어서 들고 있는다. 준비되는 즉시 이 값을 그린다.
    private var midpointPlot: MidpointPlot?

    /// 이미 만들어 둔 번호 핀 스타일들. 같은 것을 두 번 등록하지 않기 위한 기록이다.
    private var registeredPinStyles: Set<String> = []

    /// 처음 보여 줄 자리. 엔진이 뜨기 전에 정해야 한다.
    /// 뜬 뒤에 옮기면 기본 자리가 한 번 보였다 사라져 화면이 튄다.
    var initialCenter: (lat: Double, lng: Double) = (lat: 37.4979, lng: 127.0276) // 강남역

    // MARK: - 생명주기

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let container = KMViewContainer(frame: view.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(container)
        mapContainer = container

        // KakaoMapsSDK의 terrain long-press 이벤트는 인식 시간을 바꿀 수 없다. 좌표
        // 변환은 SDK에 맡기고, 누르는 시간만 UIKit 인식기로 조절한다. 지도 이동과 함께
        // 메뉴가 뜨지 않도록 이동 허용치는 작게 두고 SDK 제스처와 동시 인식시킨다.
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleMapLongPress(_:)))
        longPress.minimumPressDuration = Self.longPressMinimumDuration
        longPress.allowableMovement = 8
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        longPress.delegate = self
        container.addGestureRecognizer(longPress)
        longPressRecognizer = longPress

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
            longPressRecognizer?.isEnabled = !isDrawing
            kakaoMap?.setGestureEnable(type: .pan, enable: !isDrawing)
            kakaoMap?.setGestureEnable(type: .zoom, enable: !isDrawing)
        }
    }

    @objc private func handleMapLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              !isDrawing,
              let container = mapContainer,
              let map = kakaoMap else { return }

        let point = recognizer.location(in: container)
        let coord = map.getPosition(point).wgsCoord
        onLongPress?(GeoPoint(lat: coord.latitude, lng: coord.longitude))
    }

    /// 이미 떠 있는 지도를 다른 자리로 옮긴다. 저장해 둔 지도를 열면 그리로 간다.
    ///
    /// 순간이동시키지 않고 미끄러지게 한다. 갑자기 다른 동네가 나오면 어디로 온 건지
    /// 알 수 없다. 움직이는 걸 보면 방향과 거리가 함께 읽힌다.
    func move(to lat: Double, lng: Double, level: Int? = nil) {
        guard let map = kakaoMap else {
            // 엔진이 아직이면 처음 자리를 바꿔 둔다. 뜰 때 거기서 시작한다.
            initialCenter = (lat: lat, lng: lng)
            return
        }
        let update = CameraUpdate.make(
            target: MapPoint(longitude: lng, latitude: lat),
            zoomLevel: level ?? map.zoomLevel,
            mapView: map
        )
        map.animateCamera(
            cameraUpdate: update,
            options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 500)
        )
    }

    /// 지금 보고 있는 자리와 배율.
    ///
    /// 저장할 때 함께 담는다. 링크를 받은 사람이 만든 사람과 다른 동네를 보고 있으면
    /// 핀을 찾으러 헤매게 된다.
    func cameraSnapshot() -> (center: GeoPoint, zoomLevel: Int)? {
        guard let map = kakaoMap else { return nil }
        let middle = map.getPosition(CGPoint(x: view.bounds.midX, y: view.bounds.midY))
        return (
            GeoPoint(lat: middle.wgsCoord.latitude, lng: middle.wgsCoord.longitude),
            map.zoomLevel
        )
    }

    /// 중간지점 결과를 지도에 얹는다. nil을 주면 지운다.
    func show(midpoint plot: MidpointPlot?) {
        midpointPlot = plot
        guard let map = kakaoMap else {
            // 엔진이 아직이면 시작 자리만 맞춰 둔다. 준비되면 addViewSucceeded가 그린다.
            // 여기서 카메라를 맞추려 해도 맞출 지도가 없다.
            if let meeting = plot?.meetings.first?.pin {
                initialCenter = (lat: meeting.lat, lng: meeting.lng)
            }
            return
        }
        renderMidpoint(on: map)
    }
}

// MARK: - 엔진 준비

extension KakaoMapViewController: MapControllerDelegate {
    func addViews() {
        let info = MapviewInfo(
            viewName: Self.viewName,
            viewInfoName: "map",
            defaultPosition: MapPoint(longitude: initialCenter.lng, latitude: initialCenter.lat),
            defaultLevel: 17
        )
        mapController?.addView(info)
    }

    func addViewSucceeded(_ viewName: String, viewInfoName: String) {
        guard let map = kakaoMap else { return }
        map.viewRect = view.bounds
        // 획을 담을 레이어와 스타일을 미리 만들어 둔다. zOrder는 기본 지물보다 위다.
        _ = map.getShapeManager().addShapeLayer(layerID: Self.shapeLayerID, zOrder: 10_001)

        // 중간지점 그림. 잇는 선은 손그림보다 아래에 둔다. 사람이 그린 것이 위여야 한다.
        _ = map.getShapeManager().addShapeLayer(layerID: Self.midpointLinkLayerID, zOrder: 10_000)
        _ = map.getLabelManager().addLabelLayer(
            option: LabelLayerOptions(
                layerID: Self.midpointLabelLayerID,
                // 우리 핀끼리도, 지도의 기본 지물과도 경쟁시키지 않는다. 경쟁을 켜면
                // 출발지 이름표가 상가 이름에 밀려 사라진다. 사람이 방금 넣은 정보가
                // 지도가 원래 알던 것에 밀리면 안 된다.
                // 타입을 적어 둔다. `.none`만 쓰면 Optional.none으로도 읽혀 애매해진다.
                competitionType: CompetitionType.none,
                competitionUnit: CompetitionUnit.symbolFirst,
                orderType: OrderingType.rank,
                zOrder: 10_002
            )
        )
        // 단계 핀은 중간지점보다 위에 둔다. 사람이 직접 찍은 것이 위여야 한다.
        _ = map.getLabelManager().addLabelLayer(
            option: LabelLayerOptions(
                layerID: Self.stopLabelLayerID,
                competitionType: CompetitionType.none,
                competitionUnit: CompetitionUnit.symbolFirst,
                orderType: OrderingType.rank,
                zOrder: 10_003
            )
        )
        // 구간 선은 핀보다 아래, 손그림보다도 아래다. 사람이 그린 것이 제일 위여야 한다.
        _ = map.getShapeManager().addShapeLayer(layerID: Self.legLayerID, zOrder: 9_999)
        // 메모는 핀보다 위. 사람이 직접 쓴 글자가 가려지면 안 된다.
        _ = map.getLabelManager().addLabelLayer(
            option: LabelLayerOptions(
                layerID: Self.memoLayerID,
                competitionType: CompetitionType.none,
                competitionUnit: CompetitionUnit.symbolFirst,
                orderType: OrderingType.rank,
                zOrder: 10_004
            )
        )
        registerMidpointStyles(on: map)
        registerLegStyles(on: map)
        subscribeToMapEvents(on: map)

        // 엔진이 뜨기 전에 받아 둔 것들이 있으면 지금 그린다.
        renderMidpoint(on: map)
        renderStops(on: map)
        renderLegs(on: map)
        renderStrokes(on: map)
        renderLabels(on: map)

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
        // didSet이 방금 그린 것까지 포함해 다시 그린다. 여기서 따로 그리면 두 번 그려진다.
        strokes.append(stroke)
        onStrokesChanged?(strokes)
    }

    /// 획을 전부 다시 그린다.
    ///
    /// 하나 더할 때도 통째로 다시 그린다. 불러오기·되돌리기까지 생각하면 무엇이
    /// 바뀌었는지 따지는 쪽이 더 틀리기 쉽고, 획은 많아야 수십 개다.
    private func renderStrokes(on map: KakaoMap) {
        guard let layer = map.getShapeManager().getShapeLayer(layerID: Self.shapeLayerID) else { return }
        layer.clearAllShapes()
        for stroke in strokes { render(stroke, on: map) }
    }

    /// 획을 SDK 도형으로 등록한다.
    ///
    /// `PolylineShape`이 아니라 **`MapPolylineShape`**을 쓴다. 앞의 것은 기준점 대비
    /// 모델 좌표(CGPoint)를 받아서 지도를 옮기면 같이 움직이지 않는다. 위경도로 이루어진
    /// 선은 `Map`이 붙은 쪽이다. 이걸 헷갈리면 컴파일은 되는데 그림이 지도에 안 붙는다.
    private func render(_ stroke: GeoStroke, on map: KakaoMap) {
        guard let layer = map.getShapeManager().getShapeLayer(layerID: Self.shapeLayerID) else { return }

        let points = stroke.path.map(\.mapPoint)
        let options = MapPolylineShapeOptions(
            shapeID: stroke.id.uuidString,
            styleID: strokeStyleID(color: stroke.color, width: stroke.width, on: map),
            zOrder: 1
        )
        options.polylines = [MapPolyline(line: points, styleIndex: 0)]

        let shape = layer.addMapPolylineShape(options)
        shape?.show()
    }

    /// 획의 색·굵기 조합마다 스타일 하나. 처음 쓸 때 한 번만 만든다.
    ///
    /// 획마다 등록하면 같은 ID를 계속 덮어쓰게 되고, 하나로 고정하면 불러온 지도의
    /// 색이 전부 같아진다. 조합을 ID에 넣어 둘 다 피한다.
    private func strokeStyleID(color: String, width: Double, on map: KakaoMap) -> String {
        let styleID = "\(Self.strokeStyleID)-\(color)-\(Int(width))"
        guard !registeredPinStyles.contains(styleID) else { return styleID }

        map.getShapeManager().addPolylineStyleSet(
            PolylineStyleSet(
                styleSetID: styleID,
                styles: [
                    PolylineStyle(styles: [
                        PerLevelPolylineStyle(
                            bodyColor: UIColor(hex: color) ?? .systemBlue,
                            // 웹의 굵기는 화면 픽셀 기준이라 손맛이 얇게 느껴진다.
                            // 손가락으로 그은 선은 조금 굵어야 그린 것처럼 보인다.
                            bodyWidth: UInt(max(2, width * 1.5)),
                            level: 0
                        ),
                    ]),
                ]
            )
        )
        registeredPinStyles.insert(styleID)
        return styleID
    }

    /// 화면 픽셀 몇 개에 해당하는 각도. RDP 임계값을 줌에 맞추기 위해 쓴다.
    private func angularEpsilon(map: KakaoMap, pixels: CGFloat) -> Double {
        let origin = map.getPosition(CGPoint(x: 0, y: 0))
        let shifted = map.getPosition(CGPoint(x: pixels, y: 0))
        return abs(shifted.wgsCoord.longitude - origin.wgsCoord.longitude)
    }
}

// MARK: - 단계 핀

private extension KakaoMapViewController {
    /// 핀 터치와 카메라 정지 이벤트를 받는다.
    ///
    /// terrain 꾹 누르기는 SDK가 시간을 노출하지 않아 `viewDidLoad`에서 UIKit 인식기로
    /// 받는다. 최종 좌표는 여전히 SDK의 `getPosition`으로 구한다.
    func subscribeToMapEvents(on map: KakaoMap) {
        eventHandlers.append(
            map.addPoisTappedEventHandler(target: self) { controller in
                { event in
                    switch event.layerID {
                    case Self.stopLabelLayerID:
                        // poiID를 후보 id로 쓴다. 눌린 것이 무엇인지 그대로 알 수 있다.
                        controller.onTapStopPin?(event.poiID)
                    case Self.memoLayerID:
                        controller.onTapMemo?(event.poiID)
                    default:
                        return
                    }
                }
            }
        )

        // 점선 간격은 화면 배율에서 구한다. 줌이 바뀌면 그 값도 바뀌므로 다시 그린다.
        // 줌이 끝난 뒤에만 다시 그린다 — 움직이는 동안 매 프레임 다시 만들면 무겁고,
        // 그 사이에도 선은 SDK가 알아서 따라 그려 준다.
        eventHandlers.append(
            map.addCameraStoppedEventHandler(target: self) { controller in
                { _ in
                    guard let map = controller.kakaoMap else { return }
                    controller.renderLegs(on: map)
                }
            }
        )
    }

    /// 단계 핀을 다시 그린다.
    ///
    /// 중간지점과 같은 이유로 매번 전부 지우고 다시 그린다. 단계를 지우거나 순서를
    /// 바꾸면 남은 모든 핀의 번호가 달라지므로, 무엇이 바뀌었는지 따지는 것이 통째로
    /// 새로 그리는 것보다 어렵고 틀리기 쉽다.
    func renderStops(on map: KakaoMap) {
        guard let layer = map.getLabelManager().getLabelLayer(layerID: Self.stopLabelLayerID) else { return }
        layer.clearAllItems()
        // 핀을 눌러야 상세를 볼 수 있다. 레이어 단위로 켜 둔다.
        layer.setClickable(true)

        for (place, number) in stops.flattened() {
            let options = PoiOptions(
                styleID: numberedPinStyleID(
                    prefix: "stop",
                    number: number,
                    color: UIColor(hex: place.pinColor) ?? .systemRed,
                    diameter: 20,
                    fontSize: 16
                ),
                // 눌렸을 때 무엇인지 알아야 하므로 후보 id를 그대로 쓴다.
                poiID: place.id
            )
            // 번호가 클수록 위로. 겹쳤을 때 나중 단계가 가려지면 순서를 못 읽는다.
            options.rank = number
            options.clickable = true
            options.addText(PoiText(text: place.name, styleIndex: 0))
            layer.addPoi(
                option: options,
                at: MapPoint(longitude: place.location.lng, latitude: place.location.lat)
            )?.show()
        }
    }
}

// 지도 SDK의 팬·줌 인식기를 막지 않는다. 손가락이 8pt보다 움직이면 위의 롱프레스가
// 먼저 실패하고 지도 이동만 남는다.
extension KakaoMapViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === longPressRecognizer
    }
}

// MARK: - 메모

private extension KakaoMapViewController {
    /// 지도 위 메모를 다시 그린다.
    ///
    /// 아이콘 없이 글자만 있는 POI다. 메모는 "여기에 무엇이 있다"가 아니라 "여기에
    /// 대해 할 말이 있다"라서, 점을 찍으면 단계 핀과 헷갈린다.
    func renderLabels(on map: KakaoMap) {
        guard let layer = map.getLabelManager().getLabelLayer(layerID: Self.memoLayerID) else { return }
        layer.clearAllItems()
        layer.setClickable(true)

        for label in labels where !label.text.isEmpty {
            let options = PoiOptions(
                styleID: memoStyleID(color: label.color, fontSize: label.fontSize, on: map),
                poiID: label.id
            )
            options.clickable = true
            options.addText(PoiText(text: label.text, styleIndex: 0))
            layer.addPoi(option: options, at: label.location.mapPoint)?.show()
        }
    }

    /// 색·크기 조합마다 스타일 하나.
    func memoStyleID(color: String, fontSize: Double, on map: KakaoMap) -> String {
        let styleID = "memo-\(color)-\(Int(fontSize))"
        guard !registeredPinStyles.contains(styleID) else { return styleID }

        let style = PoiTextStyle(textLineStyles: [
            PoiTextLineStyle(
                textStyle: TextStyle(
                    // 화면 배율을 감안해 키운다. 웹의 14pt를 그대로 넘기면 지도 위에서
                    // 읽기 어려울 만큼 작다.
                    fontSize: UInt(max(14, fontSize * 1.6)),
                    fontColor: UIColor(hex: color) ?? .darkGray,
                    strokeThickness: 4,
                    strokeColor: .white
                )
            ),
        ])
        style.textLayouts = [.center]

        map.getLabelManager().addPoiStyle(
            PoiStyle(styleID: styleID, styles: [PerLevelPoiStyle(textStyle: style, level: 0)])
        )
        registeredPinStyles.insert(styleID)
        return styleID
    }
}

// MARK: - 구간 선

private extension KakaoMapViewController {
    /// 이동수단마다 스타일을 하나씩. 값이 고정이라 처음에 한 번만 만든다.
    func registerLegStyles(on map: KakaoMap) {
        let manager = map.getShapeManager()
        for style in TravelMode.allCases.map(LegStyle.of) {
            manager.addPolylineStyleSet(
                PolylineStyleSet(
                    styleSetID: Self.legStyleID(style.name),
                    styles: [
                        PolylineStyle(styles: [
                            PerLevelPolylineStyle(bodyColor: style.color, bodyWidth: style.width, level: 0),
                        ]),
                    ]
                )
            )
        }
    }

    static func legStyleID(_ name: String) -> String { "leg-\(name)" }

    /// 단계 사이 선을 다시 그린다.
    ///
    /// 줌이 바뀔 때도 불린다. 점선 조각의 길이가 화면 배율에 달려 있어서, 같은 간격으로
    /// 보이게 하려면 줌마다 다시 잘라야 한다.
    func renderLegs(on map: KakaoMap) {
        guard let layer = map.getShapeManager().getShapeLayer(layerID: Self.legLayerID) else { return }
        layer.clearAllShapes()

        // 화면에서 1pt에 해당하는 각도. 점선을 화면 기준으로 만들기 위한 환산값이다.
        let perPoint = angularEpsilon(map: map, pixels: 1)
        var index = 0
        var drawnSegments = 0
        var drawnConnectors = 0

        for shape in legShapes(stops: stops, legs: legs) {
            switch shape {
            case .straight(let from, let to):
                draw([from, to], style: LegStyle.of(.straight), id: "leg-\(index)", perPoint: perPoint, on: layer)
            case .path(let segments, let connectors, let mode):
                let style = LegStyle.of(mode)
                for (position, segment) in segments.enumerated() {
                    draw(segment, style: style, id: "leg-\(index)-\(position)", perPoint: perPoint, on: layer)
                }
                // 좌표가 오지 않은 부분은 언제나 도보로 그린다. 대중교통이라도 그 사이는 걷는다.
                for (position, connector) in connectors.enumerated() {
                    draw(
                        [connector.from, connector.to],
                        style: LegStyle.walk,
                        id: "leg-\(index)-c\(position)",
                        perPoint: perPoint,
                        on: layer
                    )
                }
                drawnSegments += segments.count
                drawnConnectors += connectors.count
            }
            index += 1
        }

        // 무엇을 그렸는지 화면 밖으로 내건다.
        //
        // 스크린샷만으로는 "선이 핀에 안 닿는다"의 원인을 좁힐 수 없었다. 연결선을
        // 안 만든 것인지, 만들었는데 안 그려진 것인지, 그려졌는데 짧은 것인지가
        // 그림에서는 똑같아 보인다. 맥이 없어 디버거를 붙일 수 없으니 UI 테스트가
        // 읽어 갈 수 있게 값으로 남긴다.
        view.accessibilityValue = "legs:\(index) segs:\(drawnSegments) conns:\(drawnConnectors) perPt:\(perPoint)"
    }

    /// 한 줄을 그린다. 점선이면 조각으로 잘라 한 도형에 담는다.
    func draw(
        _ path: [GeoPoint],
        style: LegStyle,
        id: String,
        perPoint: Double,
        on layer: ShapeLayer
    ) {
        guard path.count >= 2 else { return }

        let pieces: [[GeoPoint]]
        if let dash = style.dash, perPoint > 0 {
            pieces = dashedSegments(path, onLength: dash.on * perPoint, offLength: dash.off * perPoint)
        } else {
            pieces = [path]
        }
        guard !pieces.isEmpty else { return }

        let options = MapPolylineShapeOptions(
            shapeID: id,
            styleID: Self.legStyleID(style.name),
            zOrder: 0
        )
        // 조각을 도형 하나에 다 담는다. 점선 하나가 도형 수백 개가 되면 안 된다.
        options.polylines = pieces.map { MapPolyline(line: $0.map(\.mapPoint), styleIndex: 0) }
        layer.addMapPolylineShape(options)?.show()
    }
}

extension GeoPoint {
    var mapPoint: MapPoint { MapPoint(longitude: lng, latitude: lat) }
}

// MARK: - 중간지점

private extension KakaoMapViewController {
    /// 출발지 핀, 선택한 후보 핀, 실제 이동 경로를 다시 그린다.
    ///
    /// 매번 전부 지우고 다시 그린다. 후보를 바꿔 가며 눌러 보는 것이 이 기능의 쓰임새라
    /// 무엇이 바뀌었는지 따지는 것보다 통째로 새로 그리는 편이 틀릴 여지가 없다.
    /// 핀은 많아야 사람 수 + 1개다.
    func renderMidpoint(on map: KakaoMap) {
        let labels = map.getLabelManager().getLabelLayer(layerID: Self.midpointLabelLayerID)
        guard let links = map.getShapeManager().getShapeLayer(layerID: Self.midpointLinkLayerID) else {
            return
        }
        labels?.clearAllItems()
        links.clearAllShapes()

        guard let plot = midpointPlot, !plot.meetings.isEmpty else { return }
        let perPoint = angularEpsilon(map: map, pixels: 1)

        for origin in plot.origins {
            let point = MapPoint(longitude: origin.lng, latitude: origin.lat)

            let options = PoiOptions(styleID: Self.originStyleID, poiID: "origin-\(origin.id)")
            options.rank = 0
            // 누를 것이 없다. 켜 두면 지도를 끌려다 핀을 눌러 버린다.
            options.clickable = false
            options.addText(PoiText(text: origin.title, styleIndex: 0))
            labels?.addPoi(option: options, at: point)?.show()
        }

        for meeting in plot.meetings {
            let meetingPoint = meeting.pin

            for origin in plot.origins {
                if let route = meeting.routes.first(where: { $0.participantID == origin.id }) {
                    let segments = splitSegments(route.points, legs: route.transitLegs)
                    for (index, segment) in segments.enumerated() {
                        draw(
                            segment,
                            style: LegStyle.of(route.mode),
                            id: "midpoint-\(meeting.pin.id)-\(origin.id)-\(index)",
                            perPoint: perPoint,
                            on: links
                        )
                    }
                    for (index, connector) in midpointConnectors(
                        origin: origin,
                        meeting: meetingPoint,
                        segments: segments
                    ).enumerated() {
                        draw(
                            [connector.from, connector.to],
                            style: LegStyle.walk,
                            id: "midpoint-\(meeting.pin.id)-\(origin.id)-c\(index)",
                            perPoint: perPoint,
                            on: links
                        )
                    }
                } else {
                    // 해당 수단의 경로를 못 받은 경우에만 관계를 알리는 흐린 직선으로 대체한다.
                    let fallback = MapPolylineShapeOptions(
                        shapeID: "midpoint-fallback-\(meeting.pin.id)-\(origin.id)",
                        styleID: Self.linkStyleID,
                        zOrder: 0
                    )
                    fallback.polylines = [MapPolyline(
                        line: [
                            MapPoint(longitude: origin.lng, latitude: origin.lat),
                            MapPoint(longitude: meetingPoint.lng, latitude: meetingPoint.lat),
                        ],
                        styleIndex: 0
                    )]
                    links.addMapPolylineShape(fallback)?.show()
                }
            }

            let options = PoiOptions(
                styleID: meetingStyleID(rank: meeting.rank),
                poiID: "meeting-\(meeting.pin.id)"
            )
            options.rank = 10
            options.clickable = false
            options.addText(PoiText(text: meeting.pin.title, styleIndex: 0))
            labels?.addPoi(
                option: options,
                at: MapPoint(longitude: meetingPoint.lng, latitude: meetingPoint.lat)
            )?.show()
        }

        fitCamera(to: plot, on: map)
    }

    func midpointConnectors(
        origin: MidpointPlot.Pin,
        meeting: MidpointPlot.Pin,
        segments: [[GeoPoint]]
    ) -> [Connector] {
        guard let first = segments.first?.first, let last = segments.last?.last else { return [] }
        var connectors: [Connector] = []
        let start = GeoPoint(lat: origin.lat, lng: origin.lng)
        let end = GeoPoint(lat: meeting.lat, lng: meeting.lng)

        if midpointGap(start, first) > connectorMinimumDeg {
            connectors.append(Connector(from: start, to: first))
        }
        for pair in zip(segments, segments.dropFirst()) {
            guard let from = pair.0.last, let to = pair.1.first else { continue }
            if midpointGap(from, to) > connectorMinimumDeg {
                connectors.append(Connector(from: from, to: to))
            }
        }
        if midpointGap(last, end) > connectorMinimumDeg {
            connectors.append(Connector(from: last, to: end))
        }
        return connectors
    }

    func midpointGap(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        ((b.lat - a.lat) * (b.lat - a.lat) + (b.lng - a.lng) * (b.lng - a.lng)).squareRoot()
    }

    /// 참가자와 모이는 자리가 모두 보이도록 카메라를 맞춘다.
    ///
    /// 도착지로 순간이동하지 않는다. 어디서 어디로 모이는지가 이 화면의 답이라, 한 점만
    /// 크게 보여 주면 정작 "왜 거기인지"가 사라진다.
    func fitCamera(to plot: MidpointPlot, on map: KakaoMap) {
        let box = plot.viewport()
        let area = AreaRect(
            southWest: MapPoint(longitude: box.west, latitude: box.south),
            northEast: MapPoint(longitude: box.east, latitude: box.north)
        )
        // levelLimit이 없으면 사람들이 같은 동네에서 올 때 최대 배율까지 파고든다.
        map.animateCamera(
            cameraUpdate: CameraUpdate.make(area: area, levelLimit: 17),
            options: CameraAnimationOptions(
                autoElevation: false,
                consecutive: false,
                durationInMillis: 600
            )
        )
    }

    // MARK: 스타일

    func registerMidpointStyles(on map: KakaoMap) {
        let manager = map.getLabelManager()

        manager.addPoiStyle(
            PoiStyle(
                styleID: Self.originStyleID,
                styles: [
                    PerLevelPoiStyle(
                        iconStyle: PoiIconStyle(
                            symbol: circleIcon(diameter: 22, fill: .darkGray, glyph: nil),
                            anchorPoint: CGPoint(x: 0.5, y: 0.5)
                        ),
                        textStyle: labelTextStyle(fontSize: 20),
                        level: 0
                    ),
                ]
            )
        )

        // 잇는 선. 지도색을 이기되 손그림(파란 실선 6pt)보다는 물러서야 해서
        // 색을 달리하고 가늘게, 반투명하게 둔다.
        map.getShapeManager().addPolylineStyleSet(
            PolylineStyleSet(
                styleSetID: Self.linkStyleID,
                styles: [
                    PolylineStyle(styles: [
                        PerLevelPolylineStyle(
                            bodyColor: UIColor.systemIndigo.withAlphaComponent(0.5),
                            bodyWidth: 3,
                            level: 0
                        ),
                    ]),
                ]
            )
        )
    }

    /// 순위가 박힌 도착지 스타일.
    func meetingStyleID(rank: Int) -> String {
        numberedPinStyleID(
            prefix: "midpointMeeting",
            number: rank,
            color: .systemIndigo,
            diameter: 34,
            fontSize: 24
        )
    }

    /// 번호가 박힌 원 아이콘 스타일. 처음 쓸 때 한 번만 만든다.
    ///
    /// 아이콘에 번호가 그려져 있으니 번호마다 다른 그림이고, 따라서 스타일도 번호마다
    /// 하나씩 필요하다. 같은 ID로 덮어쓰는 대신 번호를 ID에 넣는다. 그 스타일을 쓰는
    /// 핀이 이미 화면에 있는데 밑에서 갈아 끼우는 상황을 만들지 않는다.
    func numberedPinStyleID(
        prefix: String,
        number: Int,
        color: UIColor,
        diameter: CGFloat,
        fontSize: UInt
    ) -> String {
        let styleID = "\(prefix)-\(number)"
        guard !registeredPinStyles.contains(styleID), let map = kakaoMap else { return styleID }

        map.getLabelManager().addPoiStyle(
            PoiStyle(
                styleID: styleID,
                styles: [
                    PerLevelPoiStyle(
                        iconStyle: PoiIconStyle(
                            symbol: circleIcon(diameter: diameter, fill: color, glyph: "\(number)"),
                            anchorPoint: CGPoint(x: 0.5, y: 0.5)
                        ),
                        textStyle: labelTextStyle(fontSize: fontSize),
                        level: 0
                    ),
                ]
            )
        )
        registeredPinStyles.insert(styleID)
        return styleID
    }

    /// 핀 아래 붙는 이름표.
    ///
    /// 색을 고정한다. `.label` 같은 동적 색은 다크 모드에서 흰 글씨가 되는데, 지도
    /// 타일은 밝은 채로 남아 글자가 안 보인다. 어두운 글씨에 흰 테두리면 어느 쪽이든 읽힌다.
    func labelTextStyle(fontSize: UInt) -> PoiTextStyle {
        let style = PoiTextStyle(textLineStyles: [
            PoiTextLineStyle(
                textStyle: TextStyle(
                    fontSize: fontSize,
                    fontColor: UIColor(white: 0.12, alpha: 1),
                    strokeThickness: 4,
                    strokeColor: .white
                )
            ),
        ])
        // 아이콘 아래. 가운데에 두면 아이콘의 번호를 덮는다.
        style.textLayouts = [.bottom]
        return style
    }

    /// 핀 아이콘을 코드로 그린다.
    ///
    /// 에셋으로 넣지 않는 이유: 후보 번호가 박힌 원을 몇 개나 필요할지 미리 알 수 없고,
    /// @2x/@3x를 손으로 관리할 일도 없어진다. 렌더러가 화면 배율에 맞춰 그려 준다.
    func circleIcon(diameter: CGFloat, fill: UIColor, glyph: String?) -> UIImage {
        // 작은 단계 핀에서 3pt 테두리는 안쪽 면적을 지나치게 먹는다. 중간지점처럼
        // 큰 핀은 기존 굵기를 유지하고, 22pt 이하는 2pt로 가볍게 보인다.
        let ring: CGFloat = diameter <= 22 ? 2 : 3
        let size = CGSize(width: diameter, height: diameter)

        return UIGraphicsImageRenderer(size: size).image { _ in
            // 테두리는 선 중앙에 그려지므로 절반만큼 안으로 들여야 잘리지 않는다.
            let path = UIBezierPath(
                ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: ring / 2, dy: ring / 2)
            )
            fill.setFill()
            path.fill()
            // 지도 위 어떤 색에도 원이 묻히지 않도록 흰 테두리를 두른다.
            UIColor.white.setStroke()
            path.lineWidth = ring
            path.stroke()

            guard let glyph else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: diameter * 0.5, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let bounds = glyph.size(withAttributes: attributes)
            glyph.draw(
                at: CGPoint(x: (diameter - bounds.width) / 2, y: (diameter - bounds.height) / 2),
                withAttributes: attributes
            )
        }
    }
}
