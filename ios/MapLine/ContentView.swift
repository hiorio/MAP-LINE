import SwiftUI

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
    @State private var showCourse = false
    @State private var showPlacePicker = false
    @State private var showSaved = false
    @State private var showMyMaps = false
    @State private var showTitleEditor = false
    @State private var confirmingNewMap = false

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
    @State private var restoredDraft = false
    @State private var lastDraftFingerprint: EditFingerprint?
    @State private var shareLink: ShareLink?
    /// 지금 보고 있는 자리를 물어보기 위해 들고 있는다.
    @State private var mapController: KakaoMapViewController?
    @State private var pendingCameraCenter: GeoPoint?
    @StateObject private var currentLocation = CurrentLocationProvider()

    private struct ShareLink: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
    /// 꾹 눌러 정한 자리. 여기에 무엇을 담을지 고르는 중이다.
    @State private var pendingPin: PendingPin?
    /// 눌러서 열어 둔 핀.
    @State private var openedPin: OpenedPin?
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
        case local, saving, saved, failed

        var text: String {
            switch self {
            case .local: return "기기에 저장됨"
            case .saving: return "저장 중…"
            case .saved: return "저장됨"
            case .failed: return "기기에만 저장됨"
            }
        }
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
                    strokes: strokes,
                    labels: labels,
                    onLongPress: { coordinate in
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
                    onTapStopPin: { id in openedPin = resolvePin(id) },
                    onTapMapPoi: { coordinate, poiID in
                        guard movingMemoID == nil else { return }
                        pendingPin = PendingPin(
                            coordinate: coordinate,
                            preferredKakaoPlaceId: poiID
                        )
                    },
                    onTapMemo: { id in
                        guard movingMemoID == nil else { return }
                        openedMemo = labels.first { $0.id == id }
                    },
                    onMoveMemo: { id, location in
                        labels.updateLabel(id: id, location: location)
                    },
                    onStrokesChanged: { strokes = $0 },
                    onReady: { controller in
                        mapController = controller
                        if let center = pendingCameraCenter {
                            controller.move(to: center.lat, lng: center.lng)
                            pendingCameraCenter = nil
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
                        onOpenSaved: { showSaved = true },
                        onOpenMyMaps: { showMyMaps = true }
                    )
                    .ignoresSafeArea()
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
                    onWriteMemo: { text in
                        labels.append(MapLabel(location: pin.coordinate, text: text))
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showCourse) {
                CourseSheet(stops: $stops, legs: $legs, searchCenter: placeSearchCenter)
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
            .sheet(isPresented: $showSaved) {
                SavedPlacesView(stops: stops) { stopID, places in
                    addCoursePlaces(places, toStopID: stopID)
                }
            }
            .sheet(isPresented: $showMyMaps) {
                MyMapsView { picked in Task { await open(slug: picked) } }
            }
            .sheet(isPresented: $showTitleEditor) {
                MapTitleSheet(currentTitle: title) { title = $0 }
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
            .sheet(item: $openedPin) { pin in
                StopPinSheet(
                    place: pin.place,
                    stopNumber: pin.stopNumber,
                    canChoosePrimary: pin.canChoosePrimary,
                    isPrimary: pin.isPrimary,
                    onMakePrimary: { makePrimary(pin.place) },
                    onRemove: { remove(pin.place) }
                )
                .presentationDetents([.medium])
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
            .alert("새 지도를 만들까요?", isPresented: $confirmingNewMap) {
                Button("새 지도 만들기") { Task { await startNewMap() } }
                Button("취소", role: .cancel) {}
            } message: {
                Text("현재 지도는 먼저 저장한 뒤 새 지도를 엽니다.")
            }
            .task { restoreDraftIfNeeded() }
            .onChange(of: title) { _ in documentDidChange() }
            .onChange(of: stops) { _ in documentDidChange() }
            .onChange(of: legs) { _ in documentDidChange() }
            .onChange(of: strokes) { _ in documentDidChange() }
            .onChange(of: labels) { _ in documentDidChange() }
            .onChange(of: scenePhase) { phase in
                if phase != .active { persistDraft() }
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
            center: camera?.center ?? MapPalette.defaultCenter,
            zoomLevel: camera?.zoomLevel ?? 3,
            stops: stops,
            legs: LegRules.synced(stops: stops, legs: legs),
            strokes: strokes,
            labels: labels
        )
    }

    /// 처음이면 만들고, 그다음부터는 덮어쓴다. 자동 저장 실패는 작업을 막지 않고
    /// 기기 초안에 남기며, 공유·지도 전환처럼 사람이 요청한 저장만 경고를 띄운다.
    @discardableResult
    private func save(reportError: Bool) async -> Bool {
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
            succeeded = true
            persistDraft()
        } catch {
            persistenceStatus = .failed
            if reportError { saveError = error.localizedDescription }
        }

        saving = false
        if pendingServerSave {
            pendingServerSave = false
            Task { await save(reportError: false) }
        }
        return succeeded
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
            apply(document: loaded.document, slug: picked, updatedAt: loaded.updatedAt)
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

    /// 모든 편집은 먼저 로컬 초안에 원자적으로 쓰고, 잠시 입력이 멈추면 서버에도 저장한다.
    private func documentDidChange() {
        guard restoredDraft else { return }
        let current = editFingerprint
        guard current != lastDraftFingerprint else { return }
        lastDraftFingerprint = current
        persistDraft()
        persistenceStatus = .local
        guard hasMeaningfulContent, !isUITesting else { return }

        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            autoSaveTask = nil
            _ = await save(reportError: false)
        }
    }

    private func persistDraft() {
        guard restoredDraft else { return }
        try? draftStore.save(
            MapDraft(document: currentDocument(), slug: slug, updatedAt: updatedAt)
        )
    }

    private func restoreDraftIfNeeded() {
        guard !restoredDraft else { return }
        restoredDraft = true
        if isUITesting {
            try? draftStore.clear()
            return
        }
        guard let draft = draftStore.load() else { return }
        apply(document: draft.document, slug: draft.slug, updatedAt: draft.updatedAt)
        persistenceStatus = draft.slug == nil ? .local : .saved
    }

    private func apply(document: MapDocument, slug: String?, updatedAt: String?) {
        self.slug = slug
        self.updatedAt = updatedAt
        title = document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "새 지도"
            : document.title
        stops = document.stops
        legs = LegRules.synced(stops: document.stops, legs: document.legs)
        strokes = document.strokes
        labels = document.labels
        lastDraftFingerprint = editFingerprint
        plot = nil
        mapController?.show(midpoint: nil)
        if let mapController {
            mapController.move(to: document.center.lat, lng: document.center.lng)
        } else {
            pendingCameraCenter = document.center
        }
        persistDraft()
    }

    private var editFingerprint: EditFingerprint {
        EditFingerprint(title: title, stops: stops, legs: legs, strokes: strokes, labels: labels)
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
        plot = nil
        slug = nil
        updatedAt = nil
        persistenceStatus = .local
        lastDraftFingerprint = editFingerprint
        mapController?.show(midpoint: nil)
        try? draftStore.clear()
        persistDraft()
    }

    // MARK: - 단계 고치기

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
                            .foregroundStyle(persistenceStatus == .failed ? Color.orange : Color.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.title")
                .accessibilityLabel("지도 이름 \(title), \(persistenceStatus.text)")
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
                    .disabled(currentLocation.isRequesting)
                    .accessibilityIdentifier("map.currentLocation")

                Spacer()
                VStack(spacing: 10) {
                    mapActionButton(
                        "magnifyingglass",
                        label: "장소 추가"
                    ) { showPlacePicker = true }
                        .accessibilityIdentifier("map.addPlace")

                    mapActionButton(
                        "scribble.variable",
                        label: isDrawing ? "손그림 · \(strokes.count)획" : "손그림",
                        active: isDrawing
                    ) { startDrawing() }
                        .accessibilityIdentifier("map.draw")

                    if isDrawing {
                        drawingEditButton(
                            "arrow.uturn.backward",
                            label: "한 획 되돌리기",
                            tint: .accentColor
                        ) { undoLastStroke() }
                            .disabled(strokes.isEmpty)
                            .accessibilityIdentifier("map.draw.undo")

                        drawingEditButton(
                            "trash",
                            label: "전체 지우기",
                            tint: .red
                        ) { clearStrokes() }
                            .disabled(strokes.isEmpty)
                            .accessibilityIdentifier("map.draw.clear")
                    }

                    // 담은 것이 없으면 나눠 볼 것도 없다.
                    if !stops.isEmpty || !strokes.isEmpty || !labels.isEmpty {
                        mapActionButton(
                            saving ? "arrow.triangle.2.circlepath" : "square.and.arrow.up",
                            label: "공유하기"
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

    private func mapActionButton(
        _ symbol: String,
        label: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial))
                .foregroundStyle(active ? Color.white : Color.primary)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 손그림 버튼 바로 아래에 붙는 편집 도구. 지도 하단에서 따로 찾지 않아도 된다.
    private func drawingEditButton(
        _ symbol: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(Color.white.opacity(0.96), in: Capsule())
                .foregroundStyle(tint)
                .overlay(Capsule().stroke(tint.opacity(0.38), lineWidth: 1.5))
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
        currentLocation.request { result in
            switch result {
            case .success(let point):
                mapController?.move(to: point.lat, lng: point.lng, level: 3)
            case .failure(let error):
                saveError = error.localizedDescription
            }
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
    let onOpenMyMaps: () -> Void

    private let width: CGFloat = 280

    var body: some View {
        ZStack(alignment: .leading) {
            // 바깥을 누르면 닫힌다. 뒤 지도가 움직이지 않도록 덮어 둔다.
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(alignment: .leading, spacing: 0) {
                Text("도화지")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                item("plus.square.on.square", "새 지도", "현재 지도를 저장하고 새로 시작합니다") {
                    close()
                    onNewMap()
                }
                .accessibilityIdentifier("menu.newMap")

                item("pencil", "지도 이름 변경", "내 지도에서 알아보기 쉽게 이름을 붙입니다") {
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

                item("map", "내 지도", "이 기기에서 만든 지도") {
                    close()
                    onOpenMyMaps()
                }
                .accessibilityIdentifier("menu.myMaps")

                Spacer()
            }
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(Color(.systemBackground))
            .ignoresSafeArea(edges: .vertical)
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
