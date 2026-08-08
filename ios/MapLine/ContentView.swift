import SwiftUI
import UIKit

/// 앱의 첫 화면은 지도다.
///
/// 목록을 먼저 보여 주고 거기서 지도로 들어가는 구조였는데, 이 앱에서 사람이 보고
/// 싶은 것은 언제나 지도다. 목록은 지도를 가리는 문턱일 뿐이었다. 지도를 깔고 그 위에
/// 작은 버튼을 얹는다. 목록은 옆에서 꺼내 쓴다.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var isDrawing = false
    @State private var plot: MidpointPlot?
    @State private var menuOpen = false
    @State private var showMidpoint = false

    /// 지도에 찍은 단계들. 순서가 곧 번호다.
    @State private var stops: [Stop] = []
    /// 단계 사이 구간. 길이는 항상 max(0, 단계 수 - 1)로 맞춘다.
    @State private var legs: [StopLeg] = []
    /// 손으로 그린 획들.
    @State private var strokes: [GeoStroke] = []
    /// 지도 위에 남긴 메모들.
    @State private var labels: [MapLabel] = []
    /// 웹에서 만든 지도를 앱이 저장해도 표시 설정을 잃지 않도록 문서 상태로 보존한다.
    @State private var showCandidateLinks = true
    @State private var showStopArrows = true
    @State private var showCourse = false
    /// 동선 시트에서 여러 단계를 고르는 동안 지도 핀도 같은 선택 상태를 보여 준다.
    @State private var isSelectingCourseStops = false
    @State private var selectedCourseStopIDs: Set<String> = []
    @State private var showPlacePicker = false
    @State private var showSaved = false
    @State private var showMyMaps = false
    /// 보관함 안의 `내 동선`을 누르면 먼저 현재 시트를 완전히 닫고 목록을 연다.
    /// 두 시트를 같은 표시 주기에 겹치면 iOS가 다음 시트를 무시할 수 있다.
    @State private var openMyMapsAfterSaved = false
    /// 보관한 지도 행을 누른 뒤 시트가 완전히 내려가면 이 지도를 연다. 지도 엔진이
    /// 시트 전환 중에 멈춘 상태에서 카메라 요청을 삼키지 않게 하기 위한 대기열이다.
    @State private var pendingMapSlug: String?
    @State private var showTitleEditor = false
    @State private var confirmingNewMap = false
    /// 이름 편집 시트가 내려간 뒤 새 지도 확인창을 띄운다. 시트 위에 alert를 바로
    /// 겹치면 iOS가 둘 중 하나를 삼킬 수 있어서 다음 표시 주기로 넘긴다.
    @State private var requestNewMapAfterTitleEditor = false

    /// 사용자가 알아볼 수 있는 지도 이름. 비어 있는 제목을 자동 장소명으로 덮지 않는다.
    @State private var title = "새 지도"

    /// 서버에 저장된 지도. 아직 저장한 적 없으면 nil이다.
    @State private var slug: String?
    /// 낙관적 잠금 기준. 저장할 때 그대로 돌려보낸다.
    @State private var updatedAt: String?
    @State private var saving = false
    @State private var saveError: String?
    @State private var persistenceStatus: PersistenceStatus = .local
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var pendingServerSave = false
    @State private var consecutiveSaveFailures = 0
    @State private var saveConflict: SaveConflict?
    @State private var showingSaveConflict = false
    @State private var restoredDraft = false
    @State private var lastDraftFingerprint: EditFingerprint?
    @State private var shareLink: ShareLink?
    /// 지금 보고 있는 자리를 물어보기 위해 들고 있는다.
    @State private var mapController: KakaoMapViewController?
    @State private var pendingCamera: PendingCamera?
    /// 지도 엔진이 준비되기 전에 다른 지도를 연 경우, 준비 직후 이 점들을 한 화면에 맞춘다.
    @State private var pendingViewportPoints: [GeoPoint] = []
    @StateObject private var currentLocation = CurrentLocationProvider()
    /// 개인 보관함은 현재 문서와 별개지만 지도 위에서는 항상 보이는 참고 마커다.
    @State private var savedPins: [SavedPlacePin] = []
    /// 한 번 찾은 현재 위치를 파란 점으로 남겨 이동이 실제로 됐는지 눈으로 확인한다.
    @State private var currentLocationPoint: GeoPoint?

    private struct ShareLink: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
    /// 꾹 눌러 정한 자리. 여기에 무엇을 담을지 고르는 중이다.
    @State private var pendingPin: PendingPin?
    /// 눌러서 열어 둔 핀.
    @State private var openedPin: OpenedPin?
    /// 눌러서 열어 둔 개인 보관함 마커.
    @State private var openedSavedPin: SavedPlacePin?
    /// 눌러서 열어 둔 메모.
    @State private var openedMemo: MapLabel?
    /// 이 값이 있으면 다음 꾹 누르기는 새 핀이 아니라 해당 메모의 새 위치다.
    @State private var movingMemoID: String?
    @State private var undoState: UndoState?
    @State private var undoTask: Task<Void, Never>?

    private let draftStore: MapDraftStore

    init(draftStore: MapDraftStore = .live) {
        self.draftStore = draftStore
    }

    private enum PersistenceStatus: Equatable {
        case local, saving, saved, serverFailed, localFailed, conflict

        var text: String {
            switch self {
            case .local: return "기기에 저장됨"
            case .saving: return "저장 중…"
            case .saved: return "저장됨"
            case .serverFailed: return "기기에만 저장됨"
            case .localFailed: return "기기 저장 실패"
            case .conflict: return "저장 충돌"
            }
        }

        var needsAttention: Bool {
            self == .serverFailed || self == .localFailed || self == .conflict
        }
    }

    private struct PendingCamera {
        let center: GeoPoint
        let zoomLevel: Int
    }

    private struct SaveConflict {
        let slug: String
    }

    private struct UndoState: Identifiable {
        let id = UUID()
        let message: String
        let stops: [Stop]?
        let legs: [StopLeg]?
        let strokes: [GeoStroke]?
        let labels: [MapLabel]?
    }

    private struct EditFingerprint: Equatable {
        let title: String
        let stops: [Stop]
        let legs: [StopLeg]
        let strokes: [GeoStroke]
        let labels: [MapLabel]
        let showCandidateLinks: Bool
        let showStopArrows: Bool
    }

    /// 같은 자리를 다시 꾹 눌러도 시트가 다시 뜨도록 매번 새 id를 준다.
    private struct PendingPin: Identifiable {
        let id = UUID()
        let coordinate: GeoPoint
        /// 카카오 기본 지도 POI를 탭해 연 경우 그 POI를 주변 목록 맨 위로 올린다.
        let preferredKakaoPlaceId: String?
    }

    /// 열 때 필요한 것을 그 자리에서 다 담아 둔다.
    ///
    /// 시트 안에서 `stops`를 되짚지 않는 이유: 지우기를 누르면 `stops`에서 먼저 빠지고,
    /// 그러면 되짚기가 실패해 시트가 빈 채로 한 번 깜빡인 뒤 닫힌다.
    private struct OpenedPin: Identifiable {
        let place: MapPlace
        let stopNumber: Int
        let canChoosePrimary: Bool
        let isPrimary: Bool
        var id: String { place.id }
    }

    var body: some View {
        // 지도를 ZStack의 자식으로 두면 안 된다. ZStack은 가장 큰 자식에 맞춰 커지는데
        // 지도가 안전 영역을 넘어가므로 ZStack도 같이 넘어가고, 그 안의 버튼들이 상태바
        // 시계·배터리와 겹쳐 읽을 수 없게 된다. 배경과 오버레이는 크기를 정하지 않으므로
        // 지도는 화면 끝까지 그리면서 조작부는 안전 영역 안에 남는다.
        controls
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                KakaoMapView(
                    isDrawing: isDrawing,
                    isChoosingMemoMoveTarget: movingMemoID != nil,
                    plot: plot,
                    stops: stops,
                    legs: legs,
                    highlightedStopIDs: selectedCourseStopIDs,
                    showCandidateLinks: showCandidateLinks,
                    strokes: strokes,
                    labels: labels,
                    savedPins: savedPins,
                    currentLocation: currentLocationPoint,
                    onLongPress: { coordinate in
                        guard !isSelectingCourseStops else { return }
                        if let id = movingMemoID {
                            labels.updateLabel(id: id, location: coordinate)
                            movingMemoID = nil
                        } else {
                            pendingPin = PendingPin(
                                coordinate: coordinate,
                                preferredKakaoPlaceId: nil
                            )
                        }
                    },
                    onTapStopPin: { id in
                        if isSelectingCourseStops {
                            toggleCourseStopSelection(candidateID: id)
                        } else {
                            openedPin = resolvePin(id)
                        }
                    },
                    onTapSavedPin: { id in
                        guard !isSelectingCourseStops else { return }
                        openedSavedPin = savedPins.first { $0.id == id }
                    },
                    onTapMapPoi: { coordinate, poiID in
                        guard movingMemoID == nil, !isSelectingCourseStops else { return }
                        pendingPin = PendingPin(
                            coordinate: coordinate,
                            preferredKakaoPlaceId: poiID
                        )
                    },
                    onTapMemo: { id in
                        guard movingMemoID == nil, !isSelectingCourseStops else { return }
                        openedMemo = labels.first { $0.id == id }
                    },
                    onMoveMemo: { id, location in
                        labels.updateLabel(id: id, location: location)
                    },
                    onStrokesChanged: { strokes = $0 },
                    onReady: { controller in
                        mapController = controller
                        #if DEBUG
                        if let preview = appStorePreviewDocument {
                            controller.fit(points: preview.stops.flatMap { $0.candidates.map(\.location) })
                        }
                        #endif
                        if !pendingViewportPoints.isEmpty {
                            controller.fit(points: pendingViewportPoints)
                            pendingViewportPoints = []
                            pendingCamera = nil
                        } else if let camera = pendingCamera {
                            controller.move(
                                to: camera.center.lat,
                                lng: camera.center.lng,
                                level: camera.zoomLevel
                            )
                            pendingCamera = nil
                        }
                    }
                )
                .ignoresSafeArea()
            }
            .overlay {
                if menuOpen {
                    SideMenu(
                        isOpen: $menuOpen,
                        onDrawCourse: { startDrawing() },
                        onNewMap: { confirmingNewMap = true },
                        onRenameMap: { showTitleEditor = true },
                        onFindMidpoint: { showMidpoint = true },
                        onOpenSaved: { showSaved = true }
                    )
                }
            }
            .sheet(isPresented: $showMidpoint) {
                NavigationStack {
                    MidpointView { picked in
                        // 결과를 지도에 얹고 시트를 닫는다. 시트가 떠 있으면 지도를 가려서
                        // 정작 그린 것이 안 보인다. 목록은 답을 고르는 자리고, 답 자체는
                        // 지도에서 읽는다.
                        plot = picked
                        showMidpoint = false
                    }
                }
            }
            .sheet(item: $pendingPin) { pin in
                DropPinSheet(
                    coordinate: pin.coordinate,
                    preferredKakaoPlaceId: pin.preferredKakaoPlaceId,
                    stops: stops,
                    onPick: { stopID, place in
                        addCoursePlaces([place], toStopID: stopID)
                    },
                    onSaveToLibrary: { place, group in
                        saveToLibrary(place, group: group)
                    },
                    onWriteMemo: { text in
                        labels.append(MapLabel(location: pin.coordinate, text: text))
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showCourse, onDismiss: {
                isSelectingCourseStops = false
                selectedCourseStopIDs = []
                guard let picked = pendingMapSlug else { return }
                pendingMapSlug = nil
                Task { await open(slug: picked) }
            }) {
                CourseSheet(
                    stops: $stops,
                    legs: $legs,
                    isSelectingStops: $isSelectingCourseStops,
                    selectedStopIDs: $selectedCourseStopIDs,
                    currentTitle: title,
                    searchCenter: placeSearchCenter,
                    savedPins: savedPins,
                    onSaveToLibrary: saveToLibrary,
                    onCreateRoute: createRouteFromSelectedStops
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .modifier(
                    CourseMapSelectionBackgroundInteraction(enabled: isSelectingCourseStops)
                )
            }
            .sheet(isPresented: $showPlacePicker) {
                CoursePlacePickerSheet(stops: stops, near: placeSearchCenter) { stopID, candidates in
                    addCoursePlaces(candidates, toStopID: stopID)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $shareLink) { link in
                ActivitySheet(items: [link.url])
            }
            .sheet(isPresented: $showSaved, onDismiss: {
                // 보관함 안에서 폴더를 바꾸거나 장소를 지운 결과를 지도에도 즉시 반영한다.
                reloadSavedPins()
                guard openMyMapsAfterSaved else { return }
                openMyMapsAfterSaved = false
                DispatchQueue.main.async { showMyMaps = true }
            }) {
                SavedPlacesView(
                    stops: stops,
                    onOpenRoutes: {
                        openMyMapsAfterSaved = true
                        showSaved = false
                    },
                    onAdd: { stopID, places in
                        addCoursePlaces(places, toStopID: stopID)
                    }
                )
            }
            .sheet(isPresented: $showMyMaps, onDismiss: {
                guard let picked = pendingMapSlug else { return }
                pendingMapSlug = nil
                Task { await open(slug: picked) }
            }) {
                MyMapsView(
                    onOpen: { pendingMapSlug = $0 },
                    onDelete: { deleted in resetAfterDeletedMap(slug: deleted) }
                )
            }
            .sheet(isPresented: $showTitleEditor, onDismiss: {
                guard requestNewMapAfterTitleEditor else { return }
                requestNewMapAfterTitleEditor = false
                confirmingNewMap = true
            }) {
                MapTitleSheet(
                    currentTitle: title,
                    onSave: { title = $0 },
                    onCreateNew: { requestNewMapAfterTitleEditor = true }
                )
                    .presentationDetents([.medium])
            }
            .alert(
                "문제가 생겼습니다",
                isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
            ) {
                Button("확인", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .confirmationDialog(
                "저장 충돌을 해결해 주세요",
                isPresented: $showingSaveConflict,
                titleVisibility: .visible
            ) {
                if saveConflict != nil {
                    Button("내 작업을 복사본으로 저장") {
                        Task { await saveConflictAsCopy() }
                    }
                    Button("서버 버전 불러오기", role: .destructive) {
                        Task { await loadServerAfterConflict() }
                    }
                }
                Button("기기에만 유지", role: .cancel) {}
            } message: {
                Text("같은 지도가 다른 곳에서 먼저 저장됐습니다. 현재 작업을 덮어쓰지 않고 기기에 보존했습니다.")
            }
            .sheet(item: $openedPin) { pin in
                StopPinSheet(
                    place: pin.place,
                    stopNumber: pin.stopNumber,
                    canChoosePrimary: pin.canChoosePrimary,
                    isPrimary: pin.isPrimary,
                    savedGroup: savedGroup(containing: pin.place),
                    onMakePrimary: { makePrimary(pin.place) },
                    onSaveToLibrary: { group in
                        saveToLibrary(pin.place, group: group)
                    },
                    onRemove: { remove(pin.place) }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $openedMemo) { memo in
                MemoSheet(
                    label: memo,
                    onSave: { text in labels.updateLabel(id: memo.id, text: text) },
                    onMove: { movingMemoID = memo.id },
                    onRemove: { removeMemo(memo) }
                )
                .presentationDetents([.medium])
            }
            .sheet(item: $openedSavedPin) { pin in
                SavedPlacePinSheet(pin: pin, stops: stops) { stopID, place in
                    addCoursePlaces([place], toStopID: stopID)
                }
                .presentationDetents([.medium, .large])
            }
            .alert("새 지도를 만들까요?", isPresented: $confirmingNewMap) {
                Button("새 지도 만들기") { Task { await startNewMap() } }
                Button("취소", role: .cancel) {}
            } message: {
                Text("현재 지도는 먼저 저장한 뒤 새 지도를 엽니다.")
            }
            .task {
                restoreDraftIfNeeded()
                reloadSavedPins()
            }
            .onChange(of: title) { _ in documentDidChange() }
            .onChange(of: stops) { _ in documentDidChange() }
            .onChange(of: legs) { _ in documentDidChange() }
            .onChange(of: strokes) { _ in documentDidChange() }
            .onChange(of: labels) { _ in documentDidChange() }
            .onChange(of: showCandidateLinks) { _ in documentDidChange() }
            .onChange(of: showStopArrows) { _ in documentDidChange() }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    // 공유 익스텐션은 별도 프로세스다. 앱으로 돌아오는 순간 파일을 다시
                    // 읽어야 방금 다른 앱에서 담은 장소가 지도에 나타난다.
                    reloadSavedPins()
                } else {
                    persistDraft()
                }
            }
            .onDisappear {
                autoSaveTask?.cancel()
                undoTask?.cancel()
                persistDraft()
            }
    }

    // MARK: - 저장과 공유

    /// 지금 화면에 있는 것을 한 문서로 모은다.
    private func currentDocument() -> MapDocument {
        let camera = mapController?.cameraSnapshot()
        return MapDocument(
            title: title,
            center: camera?.center ?? pendingCamera?.center ?? MapPalette.defaultCenter,
            zoomLevel: camera?.zoomLevel ?? pendingCamera?.zoomLevel ?? 3,
            stops: stops,
            legs: LegRules.persistable(stops: stops, legs: legs),
            strokes: strokes,
            labels: labels,
            showCandidateLinks: showCandidateLinks,
            showStopArrows: showStopArrows
        )
    }

    /// 처음이면 만들고, 그다음부터는 덮어쓴다. 자동 저장 실패는 작업을 막지 않고
    /// 기기 초안에 남기며, 공유·지도 전환처럼 사람이 요청한 저장만 경고를 띄운다.
    @discardableResult
    private func save(reportError: Bool) async -> Bool {
        if saveConflict != nil {
            if reportError { showingSaveConflict = true }
            return false
        }
        guard !saving else {
            pendingServerSave = true
            return false
        }
        saving = true
        persistenceStatus = .saving
        saveError = nil

        let document = currentDocument()
        var succeeded = false
        do {
            let target: String
            if let slug {
                target = slug
            } else {
                target = try await MapStore.create(
                    title: document.title,
                    center: document.center,
                    zoomLevel: document.zoomLevel
                )
                slug = target
            }
            updatedAt = try await MapStore.save(
                slug: target,
                document: document,
                expectedUpdatedAt: updatedAt
            )
            persistenceStatus = .saved
            consecutiveSaveFailures = 0
            succeeded = true
            _ = persistDraft(reportError: reportError)
        } catch is MapStore.Conflict {
            // 서버 버전을 조용히 덮거나 로컬 작업을 버리지 않는다. 사용자가 해결 방법을
            // 고를 때까지 자동 저장을 멈추고 현재 내용은 초안에 계속 남긴다.
            if let slug {
                saveConflict = SaveConflict(slug: slug)
                showingSaveConflict = reportError
            }
            persistenceStatus = .conflict
            _ = persistDraft(reportError: false)
        } catch {
            persistenceStatus = .serverFailed
            consecutiveSaveFailures = min(consecutiveSaveFailures + 1, 6)
            _ = persistDraft(reportError: false)
            if reportError { saveError = error.localizedDescription }
        }

        saving = false
        if pendingServerSave {
            pendingServerSave = false
            if saveConflict == nil {
                let delay = succeeded ? UInt64(0) : autoSaveDelayNanoseconds
                Task {
                    if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                    guard !Task.isCancelled else { return }
                    _ = await save(reportError: false)
                }
            }
        }
        return succeeded
    }

    /// 충돌 당시의 로컬 내용을 새 지도에 저장한다. 원본 서버 지도는 건드리지 않는다.
    private func saveConflictAsCopy() async {
        guard saveConflict != nil else { return }
        showingSaveConflict = false
        saving = true
        persistenceStatus = .saving

        let copy = duplicatedMapDocument(currentDocument())
        do {
            let newSlug = try await MapStore.create(
                title: copy.title,
                center: copy.center,
                zoomLevel: copy.zoomLevel
            )
            let newUpdatedAt = try await MapStore.save(
                slug: newSlug,
                document: copy,
                expectedUpdatedAt: nil
            )
            slug = newSlug
            updatedAt = newUpdatedAt
            title = copy.title
            saveConflict = nil
            consecutiveSaveFailures = 0
            persistenceStatus = .saved
            lastDraftFingerprint = editFingerprint
            _ = persistDraft(reportError: true)
        } catch {
            persistenceStatus = .conflict
            saveError = "복사본을 저장하지 못했습니다. 현재 작업은 기기에 남아 있습니다.\n\(error.localizedDescription)"
        }
        saving = false
    }

    /// 사용자가 명시적으로 고른 경우에만 서버 버전으로 바꾼다. 그 전까지 로컬 초안은
    /// 그대로 두므로 충돌 알림 하나 때문에 작업이 사라지지 않는다.
    private func loadServerAfterConflict() async {
        guard let conflict = saveConflict else { return }
        showingSaveConflict = false
        do {
            let loaded = try await MapStore.load(slug: conflict.slug)
            saveConflict = nil
            consecutiveSaveFailures = 0
            apply(document: loaded.document, slug: conflict.slug, updatedAt: loaded.updatedAt)
            persistenceStatus = persistDraft(
                document: loaded.document,
                reportError: false
            ) ? .saved : .localFailed
        } catch {
            persistenceStatus = .conflict
            saveError = error.localizedDescription
        }
    }

    /// 저장해 둔 지도를 화면에 올린다.
    private func open(slug picked: String) async {
        if picked != slug, hasMeaningfulContent {
            autoSaveTask?.cancel()
            await waitForCurrentSave()
            guard await save(reportError: true) else { return }
        }
        do {
            let loaded = try await MapStore.load(slug: picked)
            apply(
                document: loaded.document,
                slug: picked,
                updatedAt: loaded.updatedAt,
                focusOnContent: true
            )
            persistenceStatus = persistDraft(
                document: loaded.document,
                reportError: false
            ) ? .saved : .localFailed
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// 저장한 뒤 링크를 내놓는다. 저장 안 된 지도의 링크는 빈 지도를 가리킨다.
    private func share() async {
        autoSaveTask?.cancel()
        await waitForCurrentSave()
        guard await save(reportError: true), let slug else { return }
        shareLink = ShareLink(url: MapStore.shareURL(slug: slug))
    }

    private var hasMeaningfulContent: Bool {
        !stops.isEmpty || !strokes.isEmpty || !labels.isEmpty || title != "새 지도"
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    #if DEBUG
    private var appStorePreviewDocument: MapDocument? {
        if ProcessInfo.processInfo.arguments.contains("-uiTestingDateCourse") {
            return AppStorePreview.seongsuDate
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTestingGangwonTrip") {
            return AppStorePreview.gangwonTrip
        }
        return nil
    }
    #endif

    /// 모든 편집은 먼저 로컬 초안에 원자적으로 쓰고, 잠시 입력이 멈추면 서버에도 저장한다.
    private func documentDidChange() {
        guard restoredDraft else { return }
        let current = editFingerprint
        guard current != lastDraftFingerprint else { return }
        lastDraftFingerprint = current
        let savedLocally = persistDraft(reportError: false)
        persistenceStatus = savedLocally ? .local : .localFailed
        guard hasMeaningfulContent, !isUITesting, saveConflict == nil else { return }

        autoSaveTask?.cancel()
        let delay = autoSaveDelayNanoseconds
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            autoSaveTask = nil
            _ = await save(reportError: false)
        }
    }

    @discardableResult
    private func persistDraft(
        document: MapDocument? = nil,
        reportError: Bool = false
    ) -> Bool {
        guard restoredDraft else { return true }
        do {
            try draftStore.save(
                MapDraft(
                    document: document ?? currentDocument(),
                    slug: slug,
                    updatedAt: updatedAt
                )
            )
            return true
        } catch {
            persistenceStatus = .localFailed
            if reportError { saveError = error.localizedDescription }
            return false
        }
    }

    private func restoreDraftIfNeeded() {
        guard !restoredDraft else { return }
        restoredDraft = true
        if isUITesting {
            try? draftStore.clear()
            #if DEBUG
            if let preview = appStorePreviewDocument {
                apply(document: preview, slug: nil, updatedAt: nil)
                mapController?.fit(points: preview.stops.flatMap { $0.candidates.map(\.location) })
            }
            #endif
            return
        }
        do {
            guard let draft = try draftStore.load() else { return }
            apply(document: draft.document, slug: draft.slug, updatedAt: draft.updatedAt)
            persistenceStatus = draft.slug == nil ? .local : .saved
        } catch {
            persistenceStatus = .localFailed
            do {
                try draftStore.quarantineCorruptFiles()
                saveError = "편집 중이던 지도 파일을 읽지 못해 별도로 보관했습니다. 새 작업은 정상적으로 저장됩니다."
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    private func apply(
        document: MapDocument,
        slug: String?,
        updatedAt: String?,
        focusOnContent: Bool = false
    ) {
        self.slug = slug
        self.updatedAt = updatedAt
        title = document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "새 지도"
            : document.title
        stops = document.stops
        legs = LegRules.synced(stops: document.stops, legs: document.legs)
        strokes = document.strokes
        labels = document.labels
        showCandidateLinks = document.showCandidateLinks
        showStopArrows = document.showStopArrows
        lastDraftFingerprint = editFingerprint
        plot = nil
        mapController?.show(midpoint: nil)

        // 목록에서 지도를 명시적으로 고른 경우에는 그 지도에서 마지막으로 보던 카메라보다
        // 실제 핀·경로·메모가 우선이다. 강원도 지도를 보고 있다가 서울 지도를 열어도
        // 서울 동선 전체가 즉시 화면 안에 들어와야 한다.
        let viewportPoints = focusOnContent ? document.contentViewportPoints : []
        if !viewportPoints.isEmpty {
            pendingCamera = nil
            if let mapController {
                pendingViewportPoints = []
                mapController.fit(points: viewportPoints)
            } else {
                pendingViewportPoints = viewportPoints
            }
            return
        }

        pendingViewportPoints = []
        if let mapController {
            mapController.move(
                to: document.center.lat,
                lng: document.center.lng,
                level: document.zoomLevel
            )
        } else {
            pendingCamera = PendingCamera(center: document.center, zoomLevel: document.zoomLevel)
        }
    }

    private var editFingerprint: EditFingerprint {
        EditFingerprint(
            title: title,
            stops: stops,
            legs: legs,
            strokes: strokes,
            labels: labels,
            showCandidateLinks: showCandidateLinks,
            showStopArrows: showStopArrows
        )
    }

    private var autoSaveDelayNanoseconds: UInt64 {
        let multiplier = 1 << min(consecutiveSaveFailures, 5)
        let seconds = min(60.0, 1.5 * Double(multiplier))
        return UInt64(seconds * 1_000_000_000)
    }

    private func waitForCurrentSave() async {
        while saving {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func startNewMap() async {
        autoSaveTask?.cancel()
        if hasMeaningfulContent {
            await waitForCurrentSave()
            guard await save(reportError: true) else { return }
        }

        title = "새 지도"
        stops = []
        legs = []
        strokes = []
        labels = []
        showCandidateLinks = true
        showStopArrows = true
        plot = nil
        slug = nil
        updatedAt = nil
        saveConflict = nil
        showingSaveConflict = false
        consecutiveSaveFailures = 0
        persistenceStatus = .local
        lastDraftFingerprint = editFingerprint
        mapController?.show(midpoint: nil)
        do {
            try draftStore.clear()
        } catch {
            persistenceStatus = .localFailed
            saveError = error.localizedDescription
        }
        _ = persistDraft(reportError: true)
    }

    /// 내 동선 화면에서 지금 열려 있던 서버 지도를 완전 삭제한 경우, 사라진 편집 토큰으로
    /// 자동 저장을 반복하지 않도록 편집 화면도 새 로컬 지도로 전환한다.
    private func resetAfterDeletedMap(slug deletedSlug: String) {
        guard slug == deletedSlug else { return }
        autoSaveTask?.cancel()
        pendingServerSave = false
        title = "새 지도"
        stops = []
        legs = []
        strokes = []
        labels = []
        showCandidateLinks = true
        showStopArrows = true
        plot = nil
        slug = nil
        updatedAt = nil
        saveConflict = nil
        showingSaveConflict = false
        consecutiveSaveFailures = 0
        persistenceStatus = .local
        lastDraftFingerprint = editFingerprint
        mapController?.show(midpoint: nil)
        do {
            try draftStore.clear()
            _ = persistDraft(reportError: true)
        } catch {
            persistenceStatus = .localFailed
            saveError = error.localizedDescription
        }
    }

    // MARK: - 단계 고치기

    /// 중간 크기 동선 시트 뒤의 지도 핀을 눌러도 목록과 같은 단계 선택으로 처리한다.
    private func toggleCourseStopSelection(candidateID: String) {
        guard let stopID = stops.first(where: {
            $0.candidates.contains { $0.id == candidateID }
        })?.id else { return }

        if selectedCourseStopIDs.contains(stopID) {
            selectedCourseStopIDs.remove(stopID)
        } else {
            selectedCourseStopIDs.insert(stopID)
        }
    }

    /// 현재 문서에서 고른 단계만 새 서버 동선으로 복제한다. 원본은 바꾸지 않으며,
    /// 성공한 뒤 시트가 내려가면 새 동선을 열어 사람이 바로 결과를 확인하게 한다.
    private func createRouteFromSelectedStops(
        _ selectedStopIDs: Set<String>,
        title: String
    ) async throws {
        guard let document = extractedRouteDocument(
            from: currentDocument(),
            selectedStopIDs: selectedStopIDs,
            title: title
        ) else {
            throw AppError.message("새 동선으로 만들 단계를 선택해 주세요.")
        }

        let newSlug = try await MapStore.create(
            title: document.title,
            center: document.center,
            zoomLevel: document.zoomLevel
        )
        _ = try await MapStore.save(
            slug: newSlug,
            document: document,
            expectedUpdatedAt: nil
        )
        pendingMapSlug = newSlug
    }

    private var placeSearchCenter: PlaceCandidate.Coordinate? {
        guard let center = mapController?.cameraSnapshot()?.center else { return nil }
        return PlaceCandidate.Coordinate(lat: center.lat, lng: center.lng)
    }

    /// 웹의 장소 검색 패널과 같이 여러 결과를 새 단계 하나로 묶거나 기존 단계에 더한다.
    private func addCoursePlaces(_ candidates: [PlaceCandidate], toStopID stopID: String?) {
        addCoursePlaces(candidates.map(\.mapPlace), toStopID: stopID)
    }

    /// 꾹 눌러 한 곳을 고른 흐름과 검색에서 여러 곳을 고른 흐름이 같은 규칙으로
    /// 새 단계 또는 기존 단계의 후보를 만든다.
    private func addCoursePlaces(_ places: [MapPlace], toStopID stopID: String?) {
        guard !places.isEmpty else { return }

        if let stopID {
            guard stops.addCandidates(places, toStopID: stopID) else { return }
        } else {
            stops.append(Stop(candidates: places))
        }
        legs = LegRules.synced(stops: stops, legs: legs)

        // 새로 담은 곳들이 있는 동네로 이동한다. 한 곳만 보여 주면 같은 단계의 다른 후보가
        // 빠진 것처럼 보이므로 평균 위치를 쓴다.
        let count = Double(places.count)
        let center = GeoPoint(
            lat: places.reduce(0) { $0 + $1.location.lat } / count,
            lng: places.reduce(0) { $0 + $1.location.lng } / count
        )
        mapController?.move(to: center.lat, lng: center.lng)
    }

    private func resolvePin(_ candidateId: String) -> OpenedPin? {
        guard
            let index = stops.firstIndex(where: { $0.candidates.contains { $0.id == candidateId } }),
            let place = stops[index].candidates.first(where: { $0.id == candidateId })
        else { return nil }

        return OpenedPin(
            place: place,
            stopNumber: index + 1,
            canChoosePrimary: stops[index].candidates.count > 1,
            isPrimary: stops[index].primaryId == candidateId
        )
    }

    private func makePrimary(_ place: MapPlace) {
        guard let index = stops.firstIndex(where: { $0.candidates.contains { $0.id == place.id } })
        else { return }
        stops[index].primaryId = place.id
        legs = LegRules.synced(stops: stops, legs: legs)
        refreshRoutes(touchingStopAt: index)
    }

    /// 지도 핀 상세에서 대표를 정한 경우에도 동선 화면과 똑같이 실제 경로를 갱신한다.
    private func refreshRoutes(touchingStopAt stopIndex: Int) {
        let targets = LegRules.needingRoute(
            touchingStopAt: stopIndex,
            stops: stops,
            legs: legs
        )

        for index in targets {
            guard let ends = LegRules.endpoints(stops: stops, index: index),
                  legs.indices.contains(index)
            else { continue }
            let mode = legs[index].mode
            let fromID = ends.from.id
            let toID = ends.to.id

            Task {
                guard let route = try? await RouteLookup.find(mode: mode, from: ends.from, to: ends.to),
                      legs.indices.contains(index),
                      legs[index].mode == mode,
                      let current = LegRules.endpoints(stops: stops, index: index),
                      current.from.id == fromID,
                      current.to.id == toID
                else { return }
                legs[index].route = route
            }
        }
    }

    private func remove(_ place: MapPlace) {
        let snapshot = UndoState(
            message: "\(place.name)을(를) 동선에서 뺐습니다.",
            stops: stops,
            legs: legs,
            strokes: nil,
            labels: nil
        )
        for index in stops.indices {
            stops[index].candidates.removeAll { $0.id == place.id }
            // 대표를 지웠으면 대표도 함께 없앤다. 남겨 두면 없는 후보를 가리킨다.
            if stops[index].primaryId == place.id { stops[index].primaryId = nil }
        }
        // 후보가 하나도 없는 단계는 번호만 차지한다.
        stops.removeAll { $0.candidates.isEmpty }
        legs = LegRules.synced(stops: stops, legs: legs)
        showUndo(snapshot)
    }

    private func removeMemo(_ memo: MapLabel) {
        let snapshot = UndoState(
            message: "메모를 삭제했습니다.",
            stops: nil,
            legs: nil,
            strokes: nil,
            labels: labels
        )
        labels.removeAll { $0.id == memo.id }
        showUndo(snapshot)
    }

    private func showUndo(_ snapshot: UndoState) {
        undoTask?.cancel()
        withAnimation { undoState = snapshot }
        undoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { undoState = nil }
        }
    }

    private func restoreUndo() {
        guard let snapshot = undoState else { return }
        undoTask?.cancel()
        if let restoredStops = snapshot.stops { stops = restoredStops }
        if let restoredLegs = snapshot.legs { legs = restoredLegs }
        if let restoredStrokes = snapshot.strokes { strokes = restoredStrokes }
        if let restoredLabels = snapshot.labels { labels = restoredLabels }
        withAnimation { undoState = nil }
    }

    // MARK: - 지도 위 조작

    private var controls: some View {
        VStack {
            HStack(alignment: .top) {
                roundButton("line.3.horizontal", label: "메뉴") {
                    withAnimation(.easeOut(duration: 0.22)) { menuOpen = true }
                }
                .accessibilityIdentifier("map.menu")

                Spacer()

                Button { showTitleEditor = true } label: {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(title).lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.caption2)
                        }
                        .font(.footnote.weight(.semibold))
                        Text(persistenceStatus.text)
                            .font(.caption2)
                            .foregroundStyle(persistenceStatus.needsAttention ? Color.orange : Color.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.title")
                .accessibilityLabel("지도 이름 \(title), \(persistenceStatus.text)")
            }

            Button { showPlacePicker = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                    Text("장소나 주소 검색")
                        .font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("map.searchBar")
            .accessibilityLabel("장소나 주소 검색")
            .padding(.top, 8)

            if persistenceStatus.needsAttention {
                HStack {
                    Spacer()
                    Button {
                        switch persistenceStatus {
                        case .conflict:
                            showingSaveConflict = true
                        case .localFailed:
                            retryLocalSave()
                        case .serverFailed:
                            Task { _ = await save(reportError: true) }
                        default:
                            break
                        }
                    } label: {
                        Label(
                            persistenceStatus == .conflict ? "저장 충돌 해결" : "저장 다시 시도",
                            systemImage: "arrow.clockwise"
                        )
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.persistence.retry")
                }
                .padding(.top, 6)
            }

            if let plot {
                // 무엇을 보고 있는지 밝힌다. 지도 위 핀만으로는 이게 몇 번째 후보인지,
                // 애초에 중간지점 결과인지 알 수 없다. 누르면 지운다.
                HStack {
                    Spacer()
                    Button { self.plot = nil } label: {
                        HStack(spacing: 6) {
                            Text(plotChipTitle(plot)).font(.footnote.weight(.medium))
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.plotChip")
                    .accessibilityLabel("중간지점 후보 \(plot.meetings.count)곳 결과 지우기")
                }
                .padding(.top, 6)
            }

            if !stops.isEmpty {
                // 몇 단계까지 담았는지. 핀이 화면 밖으로 나가면 지도만 봐서는
                // 담은 것이 있는지조차 알 수 없다.
                HStack {
                    Button { showCourse = true } label: {
                        HStack(spacing: 5) {
                            Text("단계 \(stops.count)")
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.stopCount")
                    .accessibilityLabel("동선 열기")
                    Spacer()
                }
                .padding(.top, 8)
            }

            Spacer()

            HStack(alignment: .bottom) {
                roundButton(
                    currentLocation.isRequesting ? "location.circle" : "location.fill",
                    label: currentLocation.isRequesting ? "현재 위치 확인 중" : "현재 위치로 이동",
                    active: currentLocation.isRequesting
                ) { moveToCurrentLocation() }
                    .accessibilityIdentifier("map.currentLocation")
                    .accessibilityValue(currentLocationPoint == nil ? "" : "현재 위치 표시됨")
                    .accessibilityHint(
                        currentLocationPoint == nil
                            ? "현재 위치를 확인합니다"
                            : "다시 누르면 현재 위치로 지도를 이동합니다"
                    )

                Spacer()
                VStack(spacing: 10) {
                    mapPrimaryIconButton(
                        "scribble.variable",
                        label: "손그림",
                        background: .indigo,
                        active: isDrawing
                    ) { startDrawing() }
                        .accessibilityIdentifier("map.draw")
                        .accessibilityValue(isDrawing ? "\(strokes.count)획" : "")

                    if isDrawing {
                        HStack(spacing: 10) {
                            mapIconButton(
                                "arrow.uturn.backward",
                                label: "한 획 되돌리기",
                                tint: .accentColor
                            ) { undoLastStroke() }
                                .disabled(strokes.isEmpty)
                                .accessibilityIdentifier("map.draw.undo")

                            mapIconButton(
                                "trash",
                                label: "전체 지우기",
                                tint: .red
                            ) { clearStrokes() }
                                .disabled(strokes.isEmpty)
                                .accessibilityIdentifier("map.draw.clear")
                        }
                    }

                    // 담은 것이 없으면 나눠 볼 것도 없다.
                    if !stops.isEmpty || !strokes.isEmpty || !labels.isEmpty {
                        mapPrimaryIconButton(
                            saving ? "arrow.triangle.2.circlepath" : "square.and.arrow.up",
                            label: "공유하기",
                            background: .teal,
                            active: saving
                        ) { Task { await share() } }
                            .accessibilityIdentifier("map.share")
                            .disabled(saving)
                    }
                }
                // 지도 오른쪽 아래 구석에는 카카오 로고가 박혀 있다. 그 위에 버튼을
                // 얹으면 로고가 가려지는데, SDK 이용약관이 로고 노출을 요구한다.
                .padding(.bottom, 24)
            }

            if movingMemoID != nil {
                HStack(spacing: 8) {
                    hint("메모를 옮길 자리를 꾹 누르세요.")
                    Button("취소") { movingMemoID = nil }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier("memo.move.cancel")
                }
            } else if isDrawing {
                hint("지도가 잠깁니다. 손가락으로 선을 그리세요.")
            } else if stops.isEmpty {
                // 꾹 누르기는 화면에 아무 표시가 없다. 알려 주지 않으면 아무도 안 한다.
                // 한 곳이라도 담고 나면 사라진다 — 이미 아는 사람에게는 잔소리다.
                hint("지도를 꾹 누르면 그 자리를 담습니다.")
            }

            if let undoState {
                UndoBanner(message: undoState.message) { restoreUndo() }
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func plotChipTitle(_ plot: MidpointPlot) -> String {
        guard let first = plot.meetings.first else { return "중간지점" }
        return plot.meetings.count == 1
            ? "\(first.rank)순위 · \(first.pin.title)"
            : "중간지점 후보 \(plot.meetings.count)곳"
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 10)
    }

    private func roundButton(
        _ symbol: String,
        label: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 46, height: 46)
                .background(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial))
                .foregroundStyle(active ? Color.white : Color.primary)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityLabel(label)
    }

    /// 지도 편집의 핵심 세 동작. 화면에는 큰 아이콘만 두고 기능 이름은 VoiceOver로
    /// 제공한다. 서로 다른 단색 배경을 써 지도 타일 색과 무관하게 바로 구별된다.
    private func mapPrimaryIconButton(
        _ symbol: String,
        label: String,
        background: Color,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 50, height: 50)
                .background(background.opacity(active ? 1 : 0.92), in: Circle())
                .foregroundStyle(Color.white)
                .overlay {
                    Circle().stroke(Color.white.opacity(active ? 0.9 : 0.35), lineWidth: active ? 3 : 1)
                }
                .shadow(color: .black.opacity(0.2), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 화면에는 아이콘만 남기되 VoiceOver에는 기능 이름을 그대로 제공한다.
    private func mapIconButton(
        _ symbol: String,
        label: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(Color.white.opacity(0.96), in: Circle())
                .foregroundStyle(tint)
                .overlay(Circle().stroke(tint.opacity(0.32), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func undoLastStroke() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
    }

    private func clearStrokes() {
        guard !strokes.isEmpty else { return }
        let snapshot = UndoState(
            message: "손그림을 모두 지웠습니다.",
            stops: nil,
            legs: nil,
            strokes: strokes,
            labels: nil
        )
        strokes.removeAll()
        showUndo(snapshot)
    }

    private func startDrawing() {
        isDrawing.toggle()
    }

    private func moveToCurrentLocation() {
        // 첫 요청 뒤 지도를 움직였거나 지도 엔진보다 위치 응답이 먼저 왔더라도, 두 번째
        // 탭은 GPS를 다시 기다리지 않고 마지막 위치로 즉시 포커스를 되돌린다.
        if let point = currentLocationPoint {
            if let mapController {
                mapController.focusOnCurrentLocation(point)
            } else {
                pendingCamera = PendingCamera(center: point, zoomLevel: 5)
            }
            return
        }

        // 첫 요청이 아직 진행 중일 때 반복 탭해도 CLLocationManager 요청을 중첩하지 않는다.
        guard !currentLocation.isRequesting else { return }
        currentLocation.request { result in
            switch result {
            case .success(let point):
                currentLocationPoint = point
                if let mapController {
                    mapController.focusOnCurrentLocation(point)
                } else {
                    pendingCamera = PendingCamera(
                        center: point,
                        zoomLevel: min(pendingCamera?.zoomLevel ?? 5, 5)
                    )
                }
            case .failure(let error):
                saveError = error.localizedDescription
            }
        }
    }

    private func retryLocalSave() {
        if persistDraft(reportError: true) {
            persistenceStatus = slug == nil ? .local : .saved
        }
    }

    private func reloadSavedPins() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingSeedSavedPins") {
            savedPins = makeSavedPlacePins(
                places: AppStorePreview.savedPlaces,
                groups: AppStorePreview.savedPlaceGroups
            )
            return
        }
        #endif

        do {
            savedPins = makeSavedPlacePins(
                places: try SavedPlaceStore(storage: AppGroupPlaceStorage()).all(),
                groups: try SavedPlaceGroupStore(storage: AppGroupSavedPlaceGroupStorage()).all()
            )
        } catch {
            // 서명 없는 CI에서는 App Group 컨테이너가 없을 수 있다. 실제 앱에서는
            // 보관함 장애를 빈 목록으로 가장하지 않고 사용자에게 알린다.
            if !isUITesting { saveError = error.localizedDescription }
        }
    }

    private func savedGroup(containing place: MapPlace) -> SavedPlaceGroup? {
        let saved = place.savedPlace()
        return savedPins.first { isSamePlace($0.place, saved) }?.group
    }

    private func saveToLibrary(_ place: MapPlace, group: SavedPlaceGroup) -> String? {
        do {
            let store = SavedPlaceStore(storage: AppGroupPlaceStorage())
            _ = try store.addOrMove(place.savedPlace(groupID: group.id), to: group.id)
            reloadSavedPins()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

/// iOS 16.4 이상에서는 중간 크기 동선 시트를 유지한 채 뒤의 지도 핀도 선택할 수 있다.
/// 더 낮은 버전은 목록 선택만 제공한다.
private struct CourseMapSelectionBackgroundInteraction: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *), enabled {
            content.presentationBackgroundInteraction(.enabled(upThrough: .medium))
        } else {
            content
        }
    }
}

/// 옆에서 나오는 메뉴.
///
/// 예전 첫 화면이 그대로 여기로 들어왔다. 자주 쓰는 것은 지도 위 버튼으로 꺼내 두고,
/// 여기는 전체 목록을 보는 자리로 둔다.
struct SideMenu: View {
    @Binding var isOpen: Bool
    let onDrawCourse: () -> Void
    let onNewMap: () -> Void
    let onRenameMap: () -> Void
    let onFindMidpoint: () -> Void
    let onOpenSaved: () -> Void

    private let width: CGFloat = 280

    /// 홈 화면에 실제로 표시되는 앱 아이콘을 그대로 메뉴 헤더에도 사용한다.
    /// AppIcon은 일반 이미지 세트와 달리 빌드 과정에서 이름이 바뀔 수 있어
    /// 번들의 아이콘 메타데이터와 생성된 PNG까지 차례로 확인한다.
    private static let appIconImage: UIImage? = {
        if let image = UIImage(named: "AppIcon") {
            return image
        }

        for dictionaryKey in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            guard
                let icons = Bundle.main.infoDictionary?[dictionaryKey] as? [String: Any],
                let primary = icons["CFBundlePrimaryIcon"] as? [String: Any]
            else { continue }

            let names = (primary["CFBundleIconFiles"] as? [String] ?? [])
                + [primary["CFBundleIconName"] as? String].compactMap { $0 }
            for name in names.reversed() {
                if let image = UIImage(named: name) {
                    return image
                }
            }
        }

        return Bundle.main.paths(forResourcesOfType: "png", inDirectory: nil)
            .filter { URL(fileURLWithPath: $0).lastPathComponent.localizedCaseInsensitiveContains("AppIcon") }
            .compactMap(UIImage.init(contentsOfFile:))
            .max {
                ($0.size.width * $0.scale) * ($0.size.height * $0.scale)
                    < ($1.size.width * $1.scale) * ($1.size.height * $1.scale)
            }
    }()

    var body: some View {
        ZStack(alignment: .leading) {
            // 바깥을 누르면 닫힌다. 뒤 지도가 움직이지 않도록 덮어 둔다.
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { close() }

            // 패널의 검은 배경만 상태바 뒤까지 채운다. 내용까지 안전영역을 무시하면
            // 다이내믹 아일랜드/시계와 앱 이름이 겹친다.
            Color(.systemBackground)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(edges: .vertical)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Group {
                        if let appIcon = Self.appIconImage {
                            Image(uiImage: appIcon)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "app.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.accentColor)
                                .padding(4)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text("도화지")
                        .font(.title2.weight(.bold))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("도화지")
                .accessibilityIdentifier("menu.brand")
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)

                item("plus.square.on.square", "새 지도", "현재 지도를 저장하고 새로 시작합니다") {
                    close()
                    onNewMap()
                }
                .accessibilityIdentifier("menu.newMap")

                item("pencil", "지도 이름 변경", "내 동선에서 알아보기 쉽게 이름을 붙입니다") {
                    close()
                    onRenameMap()
                }
                .accessibilityIdentifier("menu.renameMap")

                item("scribble.variable", "손그림", "지도에 직접 선을 그립니다") {
                    close()
                    onDrawCourse()
                }
                .accessibilityIdentifier("menu.draw")

                item(
                    "point.topleft.down.curvedto.point.bottomright.up",
                    "중간지점 찾기",
                    "여러 곳에서 오는 사람들이 모일 자리"
                ) {
                    close()
                    onFindMidpoint()
                }
                .accessibilityIdentifier("menu.midpoint")

                item("bookmark", "보관함", "장소를 폴더와 마크로 모아 두는 곳") {
                    close()
                    onOpenSaved()
                }
                .accessibilityIdentifier("menu.saved")

                Spacer()
            }
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .transition(.move(edge: .leading))
        }
    }

    private func item(
        _ symbol: String,
        _ title: String,
        _ subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .frame(width: 26)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        // List 밖의 Button도 강조색을 물려주므로 꺼 둔다. 안에서 지정한 색이 살아야 한다.
        .buttonStyle(.plain)
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.18)) { isOpen = false }
    }
}
