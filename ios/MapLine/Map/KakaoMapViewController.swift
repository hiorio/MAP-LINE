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
    /// 중간지점 그림은 손그림과 레이어를 나눈다. 한 레이어에 섞으면 중간지점을 지울 때
    /// 사람이 그려 둔 획까지 같이 지워진다.
    private static let midpointLabelLayerID = "midpointPins"
    private static let midpointLinkLayerID = "midpointLinks"
    private static let originStyleID = "midpointOrigin"
    private static let linkStyleID = "midpointLink"
    /// 코스의 단계 핀. 중간지점과도 레이어를 나눈다. 둘은 서로 다른 작업의 결과라
    /// 한쪽을 지운다고 다른 쪽이 사라지면 안 된다.
    private static let stopLabelLayerID = "stopPins"

    /// 지도에 찍은 단계들. 순서가 곧 번호다.
    var stops: [Stop] = [] {
        didSet {
            guard stops != oldValue, let map = kakaoMap else { return }
            renderStops(on: map)
        }
    }

    /// 지도를 꾹 눌렀을 때. 누른 자리의 위경도를 준다.
    var onLongPress: ((GeoPoint) -> Void)?
    /// 찍어 둔 핀을 눌렀을 때. 그 후보의 id를 준다.
    var onTapStopPin: ((String) -> Void)?

    /// SDK 이벤트 구독. 놓으면 구독이 끊기므로 컨트롤러가 살아 있는 동안 들고 있는다.
    private var eventHandlers: [any DisposableEventHandler] = []

    /// 그려 둔 획들. 저장·공유는 다음 단계이고 지금은 메모리에만 둔다.
    private(set) var strokes: [GeoStroke] = []

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

    /// 중간지점 결과를 지도에 얹는다. nil을 주면 지운다.
    func show(midpoint plot: MidpointPlot?) {
        midpointPlot = plot
        guard let map = kakaoMap else {
            // 엔진이 아직이면 시작 자리만 맞춰 둔다. 준비되면 addViewSucceeded가 그린다.
            // 여기서 카메라를 맞추려 해도 맞출 지도가 없다.
            if let plot { initialCenter = (lat: plot.meeting.lat, lng: plot.meeting.lng) }
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
        registerStrokeStyle(on: map)

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
        registerMidpointStyles(on: map)
        subscribeToMapEvents(on: map)

        // 엔진이 뜨기 전에 받아 둔 것들이 있으면 지금 그린다.
        renderMidpoint(on: map)
        renderStops(on: map)

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

// MARK: - 단계 핀

private extension KakaoMapViewController {
    /// 지도가 주는 꾹 누르기와 핀 터치를 받는다.
    ///
    /// UILongPressGestureRecognizer를 직접 달지 않는다. 직접 달면 팬·줌 제스처와 누가
    /// 이길지 우리가 조정해야 하고, 화면 좌표를 위경도로 되돌리는 일도 우리 몫이 된다.
    /// SDK 이벤트는 이미 지도 제스처와 조정된 뒤에 위경도로 온다. 웹에서 직접 만든
    /// 꾹 누르기가 겪은 문제들(터치만 해도 뜨는 메뉴, 확대 후 손 떼면 뜨는 메뉴)이
    /// 여기서는 아예 생기지 않는다.
    func subscribeToMapEvents(on map: KakaoMap) {
        eventHandlers.append(
            map.addTerrainLongPressedEventHandler(target: self) { controller in
                { event in
                    // 그리는 중에는 꾹 누르기가 획의 일부다. 메뉴가 뜨면 안 된다.
                    guard !controller.isDrawing else { return }
                    let coord = event.position.wgsCoord
                    controller.onLongPress?(GeoPoint(lat: coord.latitude, lng: coord.longitude))
                }
            }
        )

        eventHandlers.append(
            map.addPoisTappedEventHandler(target: self) { controller in
                { event in
                    guard event.layerID == Self.stopLabelLayerID else { return }
                    // poiID를 후보 id로 쓴다. 눌린 것이 무엇인지 그대로 알 수 있다.
                    controller.onTapStopPin?(event.poiID)
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
                    diameter: 32,
                    fontSize: 22
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

// MARK: - 중간지점

private extension KakaoMapViewController {
    /// 출발지 핀, 도착지 핀, 둘을 잇는 선을 다시 그린다.
    ///
    /// 매번 전부 지우고 다시 그린다. 후보를 바꿔 가며 눌러 보는 것이 이 기능의 쓰임새라
    /// 무엇이 바뀌었는지 따지는 것보다 통째로 새로 그리는 편이 틀릴 여지가 없다.
    /// 핀은 많아야 사람 수 + 1개다.
    func renderMidpoint(on map: KakaoMap) {
        let labels = map.getLabelManager().getLabelLayer(layerID: Self.midpointLabelLayerID)
        let links = map.getShapeManager().getShapeLayer(layerID: Self.midpointLinkLayerID)
        labels?.clearAllItems()
        links?.clearAllShapes()

        guard let plot = midpointPlot else { return }

        let meetingPoint = MapPoint(longitude: plot.meeting.lng, latitude: plot.meeting.lat)

        for origin in plot.origins {
            let point = MapPoint(longitude: origin.lng, latitude: origin.lat)

            let options = PoiOptions(styleID: Self.originStyleID, poiID: "origin-\(origin.id)")
            options.rank = 0
            // 누를 것이 없다. 켜 두면 지도를 끌려다 핀을 눌러 버린다.
            options.clickable = false
            options.addText(PoiText(text: origin.title, styleIndex: 0))
            labels?.addPoi(option: options, at: point)?.show()

            // 출발지에서 모이는 자리로 곧게 긋는다. **실제 이동 경로가 아니다.**
            // 서버는 구간마다 걸리는 시간과 거리만 주고 선의 모양은 주지 않는다.
            // 곧은 선은 "이 사람은 저기서 온다"로 읽히지 "이 길로 온다"로 읽히지 않으므로
            // 없는 정보를 지어내지 않는다. 손그림 동선과 헷갈리지 않게 가늘고 흐리게 둔다.
            let link = MapPolylineShapeOptions(
                shapeID: "link-\(origin.id)",
                styleID: Self.linkStyleID,
                zOrder: 0
            )
            link.polylines = [MapPolyline(line: [point, meetingPoint], styleIndex: 0)]
            links?.addMapPolylineShape(link)?.show()
        }

        let meeting = PoiOptions(styleID: meetingStyleID(rank: plot.rank), poiID: "meeting")
        // 겹치면 모이는 자리가 이긴다. 이 화면에서 제일 중요한 한 점이다.
        meeting.rank = 10
        meeting.clickable = false
        meeting.addText(PoiText(text: plot.meeting.title, styleIndex: 0))
        labels?.addPoi(option: meeting, at: meetingPoint)?.show()

        fitCamera(to: plot, on: map)
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
        let ring: CGFloat = 3
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
