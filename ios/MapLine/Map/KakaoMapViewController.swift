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
    /// 롱프레스가 끝날 때 같은 손가락을 POI 탭으로 한 번 더 해석하는 것을 막는다.
    private var lastLongPressAt: TimeInterval = 0
    /// 메모를 길게 누른 채 끌고 있는 동안의 상태. 모델은 손을 뗄 때 한 번만 고친다.
    private var memoDrag: MemoDrag?

    private struct MemoDrag {
        let id: String
        let originalLocation: GeoPoint
        let latitudeOffset: Double
        let longitudeOffset: Double
        var currentLocation: GeoPoint
    }

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
    private static let candidateLinkLayerID = "candidateLinks"
    private static let candidateHubLabelLayerID = "candidateHubs"
    private static let candidateLinkStyleID = "candidate-link-v1"
    private static let candidateHubStyleID = "candidate-hub-v1"
    private static let legLayerID = "stopLegs"
    private static let legLabelLayerID = "legLabels"
    private static let memoLayerID = "memos"
    private static let savedPlaceLabelLayerID = "savedPlaces"
    private static let currentLocationLabelLayerID = "currentLocation"
    private static let currentLocationStyleID = "currentLocation-v1"
    /// UIKit 기본값(0.5초)보다 아주 조금만 빠르게 메뉴를 연다.
    private static let longPressMinimumDuration: TimeInterval = 0.45

    /// 지도에 찍은 단계들. 순서가 곧 번호다.
    var stops: [Stop] = [] {
        didSet {
            guard stops != oldValue, let map = kakaoMap else { return }
            renderStops(on: map)
            renderCandidateLinks(on: map)
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
    /// 개인 보관함 마커를 눌렀을 때. 저장 항목의 id를 준다.
    var onTapSavedPin: ((String) -> Void)?
    /// 카카오 기본 지도에 그려진 장소 마커를 눌렀을 때. 마커 좌표와 카카오 POI id를 준다.
    var onTapMapPoi: ((GeoPoint, String) -> Void)?
    /// 지도 위 메모를 눌렀을 때. 메모의 id를 준다.
    var onTapMemo: ((String) -> Void)?
    /// 메모를 길게 눌러 끈 뒤 손을 뗐을 때. 중간 프레임은 지도 POI만 움직인다.
    var onMoveMemo: ((String, GeoPoint) -> Void)?
    /// 편집 시트의 보조 이동 모드와 직접 드래그가 한 손가락을 두고 경쟁하지 않게 한다.
    var memoDragEnabled = true

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
    /// 문서의 웹 공통 레벨 3은 네이티브 SDK의 레벨 17과 같은 축척이다.
    private var initialZoomLevel = 17
    /// 엔진 준비 전에 전체 동선을 맞춰 달라는 요청이 오면 준비 직후 적용한다.
    private var pendingFitPoints: [GeoPoint] = []

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
        guard !isDrawing,
              let container = mapContainer,
              let map = kakaoMap else { return }

        let point = clampedMapPoint(recognizer.location(in: container), bounds: container.bounds)
        let fingerLocation = geoPoint(at: point, on: map)

        switch recognizer.state {
        case .began:
            lastLongPressAt = ProcessInfo.processInfo.systemUptime

            if memoDragEnabled,
               let label = memoHitTarget(at: point, on: map, bounds: container.bounds) {
                // 누른 글자의 어느 부분에서 시작해도 손가락과 메모 사이의 간격을 유지한다.
                memoDrag = MemoDrag(
                    id: label.id,
                    originalLocation: label.location,
                    latitudeOffset: label.location.lat - fingerLocation.lat,
                    longitudeOffset: label.location.lng - fingerLocation.lng,
                    currentLocation: label.location
                )
                setMapGesturesEnabled(false, on: map)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                return
            }

            onLongPress?(fingerLocation)

        case .changed:
            guard var drag = memoDrag else { return }
            let location = GeoPoint(
                lat: fingerLocation.lat + drag.latitudeOffset,
                lng: fingerLocation.lng + drag.longitudeOffset
            )
            drag.currentLocation = location
            memoDrag = drag
            moveMemoPoi(id: drag.id, to: location, on: map)

        case .ended:
            lastLongPressAt = ProcessInfo.processInfo.systemUptime
            guard let drag = memoDrag else { return }
            finishMemoDrag(on: map)
            onMoveMemo?(drag.id, drag.currentLocation)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        case .cancelled, .failed:
            lastLongPressAt = ProcessInfo.processInfo.systemUptime
            guard let drag = memoDrag else { return }
            moveMemoPoi(id: drag.id, to: drag.originalLocation, on: map)
            finishMemoDrag(on: map)

        default:
            break
        }
    }

    /// 웹 문서의 같은 설정을 그대로 따른다. 사용자가 자동 후보선을 껐던 지도라면
    /// 앱에서 열어도 다시 생기지 않아야 한다.
    var showCandidateLinks = true {
        didSet {
            guard showCandidateLinks != oldValue, let map = kakaoMap else { return }
            renderCandidateLinks(on: map)
        }
    }

    /// SDK가 그린 결과를 UI 테스트가 그림 외에도 수치로 확인할 수 있게 남긴다.
    private var renderedCandidateSpokes = 0
    private var renderedLegCount = 0
    private var renderedLegSegments = 0
    private var renderedLegConnectors = 0
    private var renderedLegLabels = 0
    private var renderedPerPoint = 0.0

    /// 개인 보관함의 장소. 코스 단계보다 아래에 작은 폴더 마크로 보인다.
    var savedPins: [SavedPlacePin] = [] {
        didSet {
            guard savedPins != oldValue, let map = kakaoMap else { return }
            renderSavedPins(on: map)
        }
    }

    /// 마지막으로 확인한 현재 위치. 위치 버튼의 결과를 카메라 이동뿐 아니라 점으로도
    /// 보여 주어 사용자가 기능이 동작했는지 즉시 알 수 있게 한다.
    var currentLocation: GeoPoint? {
        didSet {
            guard currentLocation != oldValue, let map = kakaoMap else { return }
            renderCurrentLocation(on: map)
        }
    }

    private func finishMemoDrag(on map: KakaoMap) {
        memoDrag = nil
        setMapGesturesEnabled(!isDrawing, on: map)
    }

    private func setMapGesturesEnabled(_ enabled: Bool, on map: KakaoMap) {
        map.setGestureEnable(type: .pan, enable: enabled)
        map.setGestureEnable(type: .zoom, enable: enabled)
    }

    private func geoPoint(at point: CGPoint, on map: KakaoMap) -> GeoPoint {
        let coord = map.getPosition(point).wgsCoord
        return GeoPoint(lat: coord.latitude, lng: coord.longitude)
    }

    private func clampedMapPoint(_ point: CGPoint, bounds: CGRect) -> CGPoint {
        let safe = bounds.insetBy(dx: 1, dy: 1)
        return CGPoint(
            x: min(max(point.x, safe.minX), safe.maxX),
            y: min(max(point.y, safe.minY), safe.maxY)
        )
    }

    /// SDK에는 지도좌표 → 화면좌표 변환이 없으므로, 손가락 주위의 화면 사각형을
    /// `getPosition`으로 지도 범위로 바꾸고 그 안에서 가장 가까운 메모를 고른다.
    private func memoHitTarget(at point: CGPoint, on map: KakaoMap, bounds: CGRect) -> MapLabel? {
        let touch = geoPoint(at: point, on: map)

        return labels.compactMap { label -> (label: MapLabel, score: Double)? in
            let hitSize = memoDragHitSize(label)
            let left = geoPoint(
                at: clampedMapPoint(CGPoint(x: point.x - hitSize.width / 2, y: point.y), bounds: bounds),
                on: map
            )
            let right = geoPoint(
                at: clampedMapPoint(CGPoint(x: point.x + hitSize.width / 2, y: point.y), bounds: bounds),
                on: map
            )
            let top = geoPoint(
                at: clampedMapPoint(CGPoint(x: point.x, y: point.y - hitSize.height / 2), bounds: bounds),
                on: map
            )
            let bottom = geoPoint(
                at: clampedMapPoint(CGPoint(x: point.x, y: point.y + hitSize.height / 2), bounds: bounds),
                on: map
            )

            let lngTolerance = max(
                max(abs(left.lng - touch.lng), abs(right.lng - touch.lng)),
                0.000_000_1
            )
            let latTolerance = max(
                max(abs(top.lat - touch.lat), abs(bottom.lat - touch.lat)),
                0.000_000_1
            )
            let normalizedX = abs(label.location.lng - touch.lng) / lngTolerance
            let normalizedY = abs(label.location.lat - touch.lat) / latTolerance
            guard normalizedX <= 1, normalizedY <= 1 else { return nil }
            return (label, normalizedX * normalizedX + normalizedY * normalizedY)
        }
        .min { $0.score < $1.score }?
        .label
    }

    private func moveMemoPoi(id: String, to location: GeoPoint, on map: KakaoMap) {
        guard let poi = map.getLabelManager()
            .getLabelLayer(layerID: Self.memoLayerID)?
            .getPoi(poiID: id) else { return }
        poi.position = location.mapPoint
    }

    /// 이미 떠 있는 지도를 다른 자리로 옮긴다. 저장해 둔 지도를 열면 그리로 간다.
    ///
    /// 순간이동시키지 않고 미끄러지게 한다. 갑자기 다른 동네가 나오면 어디로 온 건지
    /// 알 수 없다. 움직이는 걸 보면 방향과 거리가 함께 읽힌다.
    func move(to lat: Double, lng: Double, level: Int? = nil) {
        guard let map = kakaoMap else {
            // 엔진이 아직이면 처음 자리를 바꿔 둔다. 뜰 때 거기서 시작한다.
            initialCenter = (lat: lat, lng: lng)
            if let level { initialZoomLevel = MapZoom.nativeLevel(fromDocumentLevel: level) }
            return
        }
        let update = CameraUpdate.make(
            target: MapPoint(longitude: lng, latitude: lat),
            zoomLevel: level.map { MapZoom.nativeLevel(fromDocumentLevel: $0) } ?? map.zoomLevel,
            mapView: map
        )
        map.animateCamera(
            cameraUpdate: update,
            options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 500)
        )
    }

    /// 현재 위치 버튼은 일반 문서 이동과 다르게 즉시 확실한 피드백을 줘야 한다.
    ///
    /// 전국 단위로 축소한 상태를 그대로 보존하면 좌표가 바뀌어도 화면이 거의 같아 보여
    /// 버튼이 고장 난 것처럼 느껴진다. 기존 배율이 충분히 가까우면 유지하되, 최소한 동네가
    /// 보이는 공통 레벨 5까지는 확대하고 진행 중인 애니메이션도 즉시 끝낸다.
    func focusOnCurrentLocation(_ point: GeoPoint) {
        currentLocation = point
        let minimumNativeZoom = MapZoom.nativeLevel(fromDocumentLevel: 5)
        guard let map = kakaoMap else {
            initialCenter = (lat: point.lat, lng: point.lng)
            initialZoomLevel = max(initialZoomLevel, minimumNativeZoom)
            return
        }

        let update = CameraUpdate.make(
            target: point.mapPoint,
            zoomLevel: max(map.zoomLevel, minimumNativeZoom),
            mapView: map
        )
        // moveCamera는 진행 중인 카메라 애니메이션을 종료하고 반드시 새 위치를 적용한다.
        map.moveCamera(update)
        renderCurrentLocation(on: map)
    }

    /// 여러 장소가 한 화면에 모두 들어오도록 카메라를 맞춘다.
    func fit(points: [GeoPoint]) {
        guard !points.isEmpty else { return }
        pendingFitPoints = points
        let south = points.map(\.lat).min() ?? points[0].lat
        let north = points.map(\.lat).max() ?? points[0].lat
        let west = points.map(\.lng).min() ?? points[0].lng
        let east = points.map(\.lng).max() ?? points[0].lng
        let center = GeoPoint(
            lat: (south + north) / 2,
            lng: (west + east) / 2
        )
        initialCenter = (lat: center.lat, lng: center.lng)
        guard let map = kakaoMap else { return }

        let latPadding = max((north - south) * 0.12, 0.003)
        let lngPadding = max((east - west) * 0.12, 0.003)
        let area = AreaRect(
            southWest: MapPoint(longitude: west - lngPadding, latitude: south - latPadding),
            northEast: MapPoint(longitude: east + lngPadding, latitude: north + latPadding)
        )
        map.animateCamera(
            cameraUpdate: CameraUpdate.make(area: area, levelLimit: 17),
            options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 600)
        )
        pendingFitPoints = []
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
            MapZoom.documentLevel(fromNativeLevel: map.zoomLevel)
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
            defaultLevel: initialZoomLevel
        )
        mapController?.addView(info)
    }

    func addViewSucceeded(_ viewName: String, viewInfoName: String) {
        guard let map = kakaoMap else { return }
        map.viewRect = view.bounds
        // 기본값은 false라 스타벅스처럼 지도 타일에 원래 그려진 POI를 눌러도 이벤트가
        // 오지 않는다. 우리가 추가한 단계 핀의 clickable 설정과는 별개의 옵션이다.
        map.poiClickable = true
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
        // 같은 단계의 후보를 묶는 보조선은 실제 이동 경로보다 아래에 둔다. 작은 회색
        // 점선과 중심점은 후보가 한 무리라는 것만 설명하고 동선보다 눈에 띄면 안 된다.
        _ = map.getShapeManager().addShapeLayer(layerID: Self.candidateLinkLayerID, zOrder: 9_998)
        _ = map.getLabelManager().addLabelLayer(
            option: LabelLayerOptions(
                layerID: Self.candidateHubLabelLayerID,
                competitionType: CompetitionType.none,
                competitionUnit: CompetitionUnit.symbolFirst,
                orderType: OrderingType.rank,
                zOrder: 9_998
            )
        )
        // 구간 선은 핀보다 아래, 손그림보다도 아래다. 사람이 그린 것이 제일 위여야 한다.
        _ = map.getShapeManager().addShapeLayer(layerID: Self.legLayerID, zOrder: 9_999)
        // 구간 요약은 선 위, 단계 핀 아래다. 핀 번호와 장소 이름을 덮으면 안 된다.
        _ = map.getLabelManager().addLabelLayer(
            option: LabelLayerOptions(
                layerID: Self.legLabelLayerID,
                competitionType: CompetitionType.none,
                competitionUnit: CompetitionUnit.symbolFirst,
                orderType: OrderingType.rank,
                zOrder: 10_001
            )
        )
        // 보관함 장소는 코스나 중간지점의 결과가 아니라 배경 참고 정보다. 같은 자리에
        // 단계 핀이 있으면 단계 번호가 위에서 읽히도록 더 낮은 레이어에 둔다.
        _ = map.getLabelManager().addLabelLayer(
            option: LabelLayerOptions(
                layerID: Self.savedPlaceLabelLayerID,
                competitionType: CompetitionType.none,
                competitionUnit: CompetitionUnit.symbolFirst,
                orderType: OrderingType.rank,
                zOrder: 10_001
            )
        )
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
        // 현재 위치는 사용자가 방금 요청한 피드백이라 모든 사용자 마킹보다 위에 둔다.
        _ = map.getLabelManager().addLabelLayer(
            option: LabelLayerOptions(
                layerID: Self.currentLocationLabelLayerID,
                competitionType: CompetitionType.none,
                competitionUnit: CompetitionUnit.symbolFirst,
                orderType: OrderingType.rank,
                zOrder: 10_005
            )
        )
        registerMidpointStyles(on: map)
        registerCandidateLinkStyles(on: map)
        registerLegStyles(on: map)
        registerCurrentLocationStyle(on: map)
        subscribeToMapEvents(on: map)

        // 엔진이 뜨기 전에 받아 둔 것들이 있으면 지금 그린다.
        renderMidpoint(on: map)
        renderStops(on: map)
        renderCandidateLinks(on: map)
        renderLegs(on: map)
        renderStrokes(on: map)
        renderLabels(on: map)
        renderSavedPins(on: map)
        renderCurrentLocation(on: map)
        if !pendingFitPoints.isEmpty { fit(points: pendingFitPoints) }

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
            zoomCreated: MapZoom.documentLevel(fromNativeLevel: map.zoomLevel)
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
                    // 롱프레스를 놓는 순간 SDK가 같은 입력을 탭으로도 보내는 경우가 있다.
                    // 이미 핀 메뉴를 열었으므로 두 번째 시트는 만들지 않는다.
                    guard ProcessInfo.processInfo.systemUptime - controller.lastLongPressAt > 0.7 else {
                        return
                    }

                    switch event.layerID {
                    case Self.stopLabelLayerID:
                        // poiID를 후보 id로 쓴다. 눌린 것이 무엇인지 그대로 알 수 있다.
                        controller.onTapStopPin?(event.poiID)
                    case Self.savedPlaceLabelLayerID:
                        controller.onTapSavedPin?(event.poiID)
                    case Self.memoLayerID:
                        controller.onTapMemo?(event.poiID)
                    case Self.midpointLabelLayerID,
                         Self.currentLocationLabelLayerID:
                        return
                    default:
                        // 우리가 만든 레이어가 아니면 카카오 기본 지도 POI다. SDK가
                        // 제공하는 객체 좌표를 그대로 써야 손가락 좌표의 오차가 없다.
                        let coord = event.position.wgsCoord
                        controller.onTapMapPoi?(
                            GeoPoint(lat: coord.latitude, lng: coord.longitude),
                            event.poiID
                        )
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
                    controller.renderCandidateLinks(on: map)
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

    /// 보관함 폴더의 마크와 색을 작은 아이콘으로 지도에 표시한다. 한 번 누르면 장소명·주소와
    /// 폴더를 확인하고 동선으로 보낼 수 있어야 하므로 별도 클릭 레이어로 둔다.
    func renderSavedPins(on map: KakaoMap) {
        guard let layer = map.getLabelManager()
            .getLabelLayer(layerID: Self.savedPlaceLabelLayerID) else { return }
        layer.clearAllItems()
        layer.setClickable(true)

        for (index, pin) in savedPins.enumerated() {
            let options = PoiOptions(
                styleID: savedPlaceStyleID(marker: pin.marker, colorHex: pin.colorHex, on: map),
                poiID: pin.id
            )
            options.rank = index
            options.clickable = true
            layer.addPoi(option: options, at: pin.location.mapPoint)?.show()
        }
    }

    func renderCurrentLocation(on map: KakaoMap) {
        guard let layer = map.getLabelManager()
            .getLabelLayer(layerID: Self.currentLocationLabelLayerID) else { return }
        layer.clearAllItems()
        layer.setClickable(false)
        guard let currentLocation else { return }

        let options = PoiOptions(styleID: Self.currentLocationStyleID, poiID: "device-location")
        options.clickable = false
        layer.addPoi(option: options, at: currentLocation.mapPoint)?.show()
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
        let styleID = "memo-v4-\(color)-\(Int(fontSize))"
        guard !registeredPinStyles.contains(styleID) else { return styleID }

        let style = PoiTextStyle(textLineStyles: [
            PoiTextLineStyle(
                textStyle: TextStyle(
                    // 화면 배율을 감안해 키운다. 웹의 14pt를 그대로 넘기면 지도 위에서
                    // 읽기 어려울 만큼 작다.
                    fontSize: UInt(max(14, fontSize * 1.8)),
                    fontColor: UIColor(hex: color) ?? .darkGray,
                    // 지도 글자·도로 위에서도 메모가 묻히지 않도록 흰 테두리를 두껍게 둔다.
                    strokeThickness: 7,
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

/// 글자 크기와 길이를 반영하되 최소 44pt 터치 영역을 보장한다.
/// 실제 메모는 가운데 정렬된 텍스트 POI라 이 크기를 중심 기준으로 쓴다.
func memoDragHitSize(_ label: MapLabel) -> CGSize {
    let renderedFontSize = CGFloat(max(14, label.fontSize * 1.8))
    let estimatedTextWidth = CGFloat(label.text.count) * renderedFontSize * 0.92
    return CGSize(
        width: min(260, max(52, estimatedTextWidth + 24)),
        height: max(48, renderedFontSize + 22)
    )
}

// MARK: - 같은 단계 후보 보조선

private extension KakaoMapViewController {
    /// 웹의 작은 회색 점선과 같은 모양이다. 카카오 iOS 폴리라인에는 점선 속성이 없어
    /// 실제 선 조각은 `dashedSegments`로 잘라 그린다.
    func registerCandidateLinkStyles(on map: KakaoMap) {
        guard !registeredPinStyles.contains(Self.candidateLinkStyleID) else { return }

        let gray = UIColor(hex: "#8A8A83") ?? .systemGray
        map.getShapeManager().addPolylineStyleSet(
            PolylineStyleSet(
                styleSetID: Self.candidateLinkStyleID,
                styles: [
                    PolylineStyle(styles: [
                        PerLevelPolylineStyle(bodyColor: gray, bodyWidth: 2, level: 0),
                    ]),
                ]
            )
        )
        map.getLabelManager().addPoiStyle(
            PoiStyle(
                styleID: Self.candidateHubStyleID,
                styles: [
                    PerLevelPoiStyle(
                        iconStyle: PoiIconStyle(
                            symbol: candidateHubIcon(diameter: 6, color: gray),
                            anchorPoint: CGPoint(x: 0.5, y: 0.5)
                        ),
                        level: 0
                    ),
                ]
            )
        )
        registeredPinStyles.insert(Self.candidateLinkStyleID)
        registeredPinStyles.insert(Self.candidateHubStyleID)
    }

    /// 후보가 둘 이상인 단계마다 각 후보를 단계 중심점으로 잇는다. 후보가 둘이면 두
    /// 점선이 중심에서 만나므로 결과적으로 두 핀을 잇는 점선 하나처럼 보인다.
    func renderCandidateLinks(on map: KakaoMap) {
        guard
            let lineLayer = map.getShapeManager().getShapeLayer(layerID: Self.candidateLinkLayerID),
            let hubLayer = map.getLabelManager().getLabelLayer(layerID: Self.candidateHubLabelLayerID)
        else { return }

        lineLayer.clearAllShapes()
        hubLayer.clearAllItems()
        hubLayer.setClickable(false)
        renderedCandidateSpokes = 0

        guard showCandidateLinks else {
            updateRenderAccessibilityValue()
            return
        }

        let perPoint = angularEpsilon(map: map, pixels: 1)
        guard perPoint > 0 else {
            updateRenderAccessibilityValue()
            return
        }

        for (stopIndex, stop) in stops.enumerated() where stop.candidates.count >= 2 {
            guard let hub = stop.centroid else { continue }

            var pieces: [[GeoPoint]] = []
            for candidate in stop.candidates {
                let differs = abs(candidate.location.lat - hub.lat) > 1e-12
                    || abs(candidate.location.lng - hub.lng) > 1e-12
                guard differs else { continue }
                pieces.append(
                    contentsOf: dashedSegments(
                        [candidate.location, hub],
                        onLength: 2 * perPoint,
                        offLength: 5 * perPoint
                    )
                )
                renderedCandidateSpokes += 1
            }

            if !pieces.isEmpty {
                let options = MapPolylineShapeOptions(
                    shapeID: "candidate-links-\(stopIndex)",
                    styleID: Self.candidateLinkStyleID,
                    zOrder: 0
                )
                options.polylines = pieces.map {
                    MapPolyline(line: $0.map(\.mapPoint), styleIndex: 0)
                }
                lineLayer.addMapPolylineShape(options)?.show()
            }

            let hubOptions = PoiOptions(
                styleID: Self.candidateHubStyleID,
                poiID: "candidate-hub-\(stop.id)"
            )
            hubOptions.clickable = false
            hubLayer.addPoi(option: hubOptions, at: hub.mapPoint)?.show()
        }

        updateRenderAccessibilityValue()
    }

    func updateRenderAccessibilityValue() {
        view.accessibilityValue =
            "candidateSpokes:\(renderedCandidateSpokes) legs:\(renderedLegCount) " +
            "segs:\(renderedLegSegments) conns:\(renderedLegConnectors) " +
            "labels:\(renderedLegLabels) perPt:\(renderedPerPoint)"
    }
}

// MARK: - 구간 선

private extension KakaoMapViewController {
    /// 이동수단마다 스타일을 하나씩. 값이 고정이라 처음에 한 번만 만든다.
    func registerLegStyles(on map: KakaoMap) {
        let manager = map.getShapeManager()
        for mode in TravelMode.allCases {
            let style = LegStyle.of(mode)
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
            registerRouteLabelStyle(mode: mode, on: map)
        }
    }

    static func legStyleID(_ name: String) -> String { "leg-\(name)" }
    static func legLabelStyleID(_ mode: TravelMode) -> String { "leg-label-\(mode.rawValue)" }

    func registerRouteLabelStyle(mode: TravelMode, on map: KakaoMap) {
        let styleID = Self.legLabelStyleID(mode)
        guard !registeredPinStyles.contains(styleID) else { return }

        let textStyle = PoiTextStyle(textLineStyles: [
            PoiTextLineStyle(
                textStyle: TextStyle(
                    fontSize: 20,
                    fontColor: LegStyle.of(mode).color,
                    strokeThickness: 7,
                    strokeColor: .white
                )
            ),
        ])
        textStyle.textLayouts = [.center]
        map.getLabelManager().addPoiStyle(
            PoiStyle(
                styleID: styleID,
                styles: [PerLevelPoiStyle(textStyle: textStyle, level: 0)]
            )
        )
        registeredPinStyles.insert(styleID)
    }

    /// 단계 사이 선을 다시 그린다.
    ///
    /// 줌이 바뀔 때도 불린다. 점선 조각의 길이가 화면 배율에 달려 있어서, 같은 간격으로
    /// 보이게 하려면 줌마다 다시 잘라야 한다.
    func renderLegs(on map: KakaoMap) {
        let labelLayer = map.getLabelManager().getLabelLayer(layerID: Self.legLabelLayerID)
        labelLayer?.clearAllItems()
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

        let annotations = legRouteAnnotations(stops: stops, legs: legs)
        for annotation in annotations {
            addRouteLabel(
                text: annotation.text,
                id: "leg-label-\(annotation.legIndex)",
                location: annotation.location,
                mode: annotation.mode,
                to: labelLayer
            )
        }

        // 무엇을 그렸는지 화면 밖으로 내건다.
        //
        // 스크린샷만으로는 "선이 핀에 안 닿는다"의 원인을 좁힐 수 없었다. 연결선을
        // 안 만든 것인지, 만들었는데 안 그려진 것인지, 그려졌는데 짧은 것인지가
        // 그림에서는 똑같아 보인다. 맥이 없어 디버거를 붙일 수 없으니 UI 테스트가
        // 읽어 갈 수 있게 값으로 남긴다.
        renderedLegCount = index
        renderedLegSegments = drawnSegments
        renderedLegConnectors = drawnConnectors
        renderedLegLabels = annotations.count
        renderedPerPoint = perPoint
        updateRenderAccessibilityValue()
    }

    func addRouteLabel(
        text: String,
        id: String,
        location: GeoPoint,
        mode: TravelMode,
        to layer: LabelLayer?
    ) {
        let options = PoiOptions(styleID: Self.legLabelStyleID(mode), poiID: id)
        options.clickable = false
        options.addText(PoiText(text: text, styleIndex: 0))
        layer?.addPoi(option: options, at: location.mapPoint)?.show()
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
                    if
                        let distanceM = route.distanceM,
                        let durationS = route.durationS,
                        let middle = routeMidpoint(
                            [GeoPoint(lat: origin.lat, lng: origin.lng)]
                                + route.points
                                + [GeoPoint(lat: meetingPoint.lat, lng: meetingPoint.lng)]
                        )
                    {
                        addRouteLabel(
                            text: routeAnnotationText(
                                mode: route.mode,
                                distanceM: distanceM,
                                durationS: durationS,
                                prefix: origin.title
                            ),
                            id: "midpoint-label-\(meeting.pin.id)-\(origin.id)",
                            location: middle,
                            mode: route.mode,
                            to: labels
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

    func registerCurrentLocationStyle(on map: KakaoMap) {
        guard !registeredPinStyles.contains(Self.currentLocationStyleID) else { return }
        map.getLabelManager().addPoiStyle(
            PoiStyle(
                styleID: Self.currentLocationStyleID,
                styles: [
                    PerLevelPoiStyle(
                        iconStyle: PoiIconStyle(
                            symbol: currentLocationIcon(diameter: 28),
                            anchorPoint: CGPoint(x: 0.5, y: 0.5)
                        ),
                        level: 0
                    ),
                ]
            )
        )
        registeredPinStyles.insert(Self.currentLocationStyleID)
    }

    func savedPlaceStyleID(marker: SavedPlaceMarker, colorHex: String, on map: KakaoMap) -> String {
        let colorToken = colorHex
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
        let styleID = "saved-v1-\(marker.rawValue)-\(colorToken)"
        guard !registeredPinStyles.contains(styleID) else { return styleID }

        map.getLabelManager().addPoiStyle(
            PoiStyle(
                styleID: styleID,
                styles: [
                    PerLevelPoiStyle(
                        iconStyle: PoiIconStyle(
                            symbol: savedPlaceIcon(
                                diameter: 22,
                                fill: UIColor(hex: colorHex) ?? .systemBlue,
                                systemName: marker.symbolName
                            ),
                            anchorPoint: CGPoint(x: 0.5, y: 0.5)
                        ),
                        level: 0
                    ),
                ]
            )
        )
        registeredPinStyles.insert(styleID)
        return styleID
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

    func savedPlaceIcon(diameter: CGFloat, fill: UIColor, systemName: String) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let ring: CGFloat = 2
            let circle = UIBezierPath(
                ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: ring / 2, dy: ring / 2)
            )
            fill.setFill()
            circle.fill()
            UIColor.white.setStroke()
            circle.lineWidth = ring
            circle.stroke()

            let configuration = UIImage.SymbolConfiguration(
                pointSize: diameter * 0.45,
                weight: .bold
            )
            guard let symbol = UIImage(systemName: systemName, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            let symbolSize = symbol.size
            symbol.draw(
                at: CGPoint(
                    x: (diameter - symbolSize.width) / 2,
                    y: (diameter - symbolSize.height) / 2
                )
            )
        }
    }

    func candidateHubIcon(diameter: CGFloat, color: UIColor) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        return UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }
    }

    func currentLocationIcon(diameter: CGFloat) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.systemBlue.withAlphaComponent(0.2).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()

            let dotRect = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            let dot = UIBezierPath(ovalIn: dotRect)
            UIColor.systemBlue.setFill()
            dot.fill()
            UIColor.white.setStroke()
            dot.lineWidth = 2
            dot.stroke()
        }
    }
}
