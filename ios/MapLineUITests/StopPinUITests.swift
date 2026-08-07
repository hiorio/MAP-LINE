import XCTest

/// 꾹 눌러 장소를 담는 흐름이 실제로 되는가.
///
/// 이건 컴파일로 답이 안 나온다. SDK의 꾹 누르기 이벤트가 팬 제스처에 먹히는지,
/// 핀이 정말 찍히는지는 그림을 봐야 안다. 맥이 없으므로 여기서 상황을 만들고
/// 스크린샷을 남긴다.
final class StopPinUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func test_꾹눌러_단계를_담는다() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTesting")
        app.launch()

        let draw = app.descendants(matching: .any).matching(identifier: "map.draw").firstMatch
        XCTAssertTrue(draw.waitForExistence(timeout: 30), "지도 화면이 뜨지 않았다")
        try waitForMap(app)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "map.addPlace").firstMatch.exists,
            "지도 첫 화면에 장소 추가 진입점이 없다"
        )
        // 타일이 올라올 틈을 준다. 빈 지도를 찍으면 핀이 붙었는지 알아볼 수 없다.
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "1-담기전")

        // 주변 검색이 끝나야 목록이 뜬다. 검색이 실패해도 "여기에 그대로"는 있어야 한다.
        // iOS 26 CI 시뮬레이터가 첫 press 이벤트를 간헐적으로 삼키므로 메뉴가 실제로
        // 뜰 때까지 같은 좌표를 제한적으로 다시 누른다.
        let dropHere = openDropPinMenu(app, x: 0.5, y: 0.42)
        let opened = dropHere != nil
        attach(app, name: opened ? "2-꾹누른뒤" : "2-메뉴안뜸")
        guard let dropHere else {
            XCTFail("지도를 꾹 눌렀는데 메뉴가 뜨지 않았다")
            return
        }

        // 자동 후보에 없는 예식장 같은 장소도 같은 자리에서 이름으로 찾을 수 있어야 한다.
        let nearbySearch = app.descendants(matching: .any)
            .matching(identifier: "droppin.search").firstMatch
        XCTAssertTrue(nearbySearch.exists, "꾹 누르기 메뉴에 주변 장소 검색이 없다")
        nearbySearch.tap()
        let searchField = app.searchFields["장소나 주소"]
        let searchOpened = searchField.waitForExistence(timeout: 5)
        attach(app, name: searchOpened ? "2-주변장소검색" : "2-주변장소검색안뜸")
        XCTAssertTrue(searchOpened, "주변 장소 검색 화면이 뜨지 않았다")
        app.buttons["취소"].firstMatch.tap()
        XCTAssertTrue(dropHere.waitForExistence(timeout: 5), "검색을 닫은 뒤 꾹 누르기 메뉴로 돌아오지 않았다")

        dropHere.tap()

        // 담기면 단계 수가 화면에 뜬다. 핀이 지도에 그려질 틈도 준다.
        let counter = app.descendants(matching: .any)
            .matching(identifier: "map.stopCount").firstMatch
        let added = counter.waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: added ? "3-단계담김" : "3-안담김")
        XCTAssertTrue(added, "장소를 골랐는데 단계가 늘지 않았다")

        // 찍어 둔 핀은 한 번 눌러 열려야 한다. 꾹 누르기와 구별되는 동작이다.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
        let remove = app.descendants(matching: .any)
            .matching(identifier: "stop.remove").firstMatch
        let detailOpened = remove.waitForExistence(timeout: 10)
        attach(app, name: detailOpened ? "4-핀상세" : "4-핀상세안뜸")
        XCTAssertTrue(detailOpened, "찍어 둔 핀을 눌렀는데 상세가 열리지 않았다")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "stop.save").firstMatch.exists,
            "동선 장소 상세에서 보관함 폴더에 저장할 수 없다"
        )
        app.buttons["닫기"].firstMatch.tap()

        try drawWalkingLeg(app, counter: counter)
        addCandidateToFirstStop(app, counter: counter)
        addLongPressedPlaceToFirstStop(app, counter: counter)
    }

    func test_지도기본POI를한번눌러_핀메뉴를연다() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTesting")
        app.launch()
        try waitForMap(app)

        // 초기 강남역 화면에서 기본 POI가 그려질 때까지 기다린다. 기기 화면비에 따라
        // 마커의 세로 위치가 조금 달라져, 실제로 메뉴가 열린 순간까지만 후보를 순회한다.
        Thread.sleep(forTimeInterval: 3)
        let likelyPoiPositions = [
            CGVector(dx: 0.48, dy: 0.26), // 의원 POI
            CGVector(dx: 0.69, dy: 0.27), // 스타벅스 케이스퀘어점
            CGVector(dx: 0.28, dy: 0.42), // 스타벅스 몬테소리점
            CGVector(dx: 0.51, dy: 0.63), // 스타벅스 강남역7번출구점
            CGVector(dx: 0.65, dy: 0.66), // 스타벅스 강남역신분당역사점
            CGVector(dx: 0.91, dy: 0.17), // 음식점 POI
        ]
        let title = app.navigationBars["여기에 무엇을 담을까요"]

        for position in likelyPoiPositions where !title.exists {
            app.coordinate(withNormalizedOffset: position).tap()
            _ = title.waitForExistence(timeout: 2)
        }

        guard title.exists else {
            attach(app, name: "2-기본POI탭메뉴안뜸")
            XCTFail("지도에 표시된 기본 장소 마커를 한 번 눌렀는데 핀 메뉴가 뜨지 않았다")
            return
        }

        let tappedPlace = app.descendants(matching: .any)
            .matching(identifier: "droppin.tappedPlace").firstMatch
        let prioritized = tappedPlace.waitForExistence(timeout: 15)
        attach(app, name: prioritized ? "2-기본POI탭-선택장소상단" : "2-선택장소상단없음")
        XCTAssertTrue(prioritized, "누른 기본 마커의 장소가 컨텍스트 상단에 표시되지 않았다")

        // 장소명 글자가 아니라 행 오른쪽의 빈 여백을 눌러도 같은 선택으로 처리돼야 한다.
        guard prioritized else { return }
        tappedPlace.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let targetPicker = app.descendants(matching: .any)
            .matching(identifier: "droppin.targetPicker").firstMatch
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, title.exists, !targetPicker.exists {
            Thread.sleep(forTimeInterval: 0.25)
        }
        let progressedFromRowEdge = !title.exists || targetPicker.exists
        attach(app, name: progressedFromRowEdge ? "3-장소행전체탭" : "3-장소행여백탭실패")
        XCTAssertTrue(progressedFromRowEdge, "장소 행의 글자 밖 여백을 눌렀는데 다음 단계로 진행되지 않았다")
    }

    func test_메모를_다른위치로_옮긴다() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTesting")
        app.launch()
        try waitForMap(app)

        let oldPosition = app.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.40))
        oldPosition.press(forDuration: 0.55)

        let memoButton = app.descendants(matching: .any)
            .matching(identifier: "droppin.memo").firstMatch
        XCTAssertTrue(memoButton.waitForExistence(timeout: 10), "꾹 누르기 메뉴에 메모가 없다")
        memoButton.tap()

        let field = app.textFields["여기에 대해 할 말"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "메모 입력창이 뜨지 않았다")
        field.typeText("입구에서 만나요")
        app.buttons["남기기"].tap()
        Thread.sleep(forTimeInterval: 2)

        // 메모를 다시 열고 이동 버튼을 고르는 단계 없이, 메모 자체를 길게 눌러 끈다.
        let newPosition = app.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.52))
        oldPosition.press(
            forDuration: 0.55,
            thenDragTo: newPosition,
            withVelocity: .slow,
            thenHoldForDuration: 0.2
        )
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "11-메모직접드래그후")
        XCTAssertFalse(
            app.navigationBars["여기에 무엇을 담을까요"].exists,
            "메모 드래그를 빈 지도 롱프레스로 잘못 처리했다"
        )

        // 새 자리에서 다시 편집 화면이 열리면 화면에만 움직인 것이 아니라 모델도 옮겨졌다.
        newPosition.tap()
        let memoText = app.textFields.matching(identifier: "memo.text").firstMatch
        XCTAssertTrue(memoText.waitForExistence(timeout: 10), "옮긴 자리에서 메모가 눌리지 않았다")
        XCTAssertEqual(memoText.value as? String, "입구에서 만나요", "드래그 뒤 메모 내용이 바뀌었다")
        attach(app, name: "12-옮긴메모다시열림")
    }

    /// 두 번째 단계를 담고 그 사이를 도보로 잇는다.
    ///
    /// 이게 이 커밋의 핵심이다. 실제 경로가 지도에 파란 점선으로 그려지는지는
    /// 컴파일로도 유닛 테스트로도 알 수 없다 — SDK가 그린 그림을 봐야 안다.
    private func drawWalkingLeg(_ app: XCUIApplication, counter: XCUIElement) throws {
        // 첫 핀과 떨어진 자리를 꾹 눌러 두 번째 단계를 담는다.
        guard let dropHere = openDropPinMenu(app, x: 0.32, y: 0.62) else {
            attach(app, name: "5-두번째메뉴안뜸")
            XCTFail("두 번째 꾹 누르기에서 메뉴가 뜨지 않았다")
            return
        }
        dropHere.tap()

        // 이미 1단계가 있으므로 이제는 곧바로 새 단계가 되지 않는다. 새 단계와
        // 기존 단계의 후보 중 어디에 담을지 먼저 고른다.
        let newStop = app.descendants(matching: .any)
            .matching(identifier: "droppin.target.new").firstMatch
        guard newStop.waitForExistence(timeout: 5) else {
            attach(app, name: "5-단계선택안뜸")
            XCTFail("두 번째 장소를 찍었는데 담을 단계를 고르는 화면이 뜨지 않았다")
            return
        }
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "droppin.target.0").firstMatch.exists,
            "기존 1단계에 후보로 추가하는 선택지가 없다"
        )
        attach(app, name: "5-새단계또는후보선택")
        // 단계명 글자 밖의 행 오른쪽 여백도 선택 영역이어야 한다.
        newStop.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "5-단계둘")

        // 단계 칩을 눌러 동선 화면으로. 여기서 이동수단을 고른다.
        counter.tap()
        let walk = app.buttons["도보"].firstMatch
        guard walk.waitForExistence(timeout: 10) else {
            attach(app, name: "6-동선화면안뜸")
            XCTFail("동선 화면에 이동수단 선택이 없다")
            return
        }
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "course.reorder").firstMatch.exists,
            "동선 화면에서 단계 순서를 바꿀 수 없다"
        )
        walk.tap()

        // 길찾기가 서버를 거쳐 온다. 넉넉히 기다린 뒤 결과를 찍는다.
        Thread.sleep(forTimeInterval: 12)
        attach(app, name: "6-동선화면")

        app.buttons["닫기"].firstMatch.tap()
        // 시트가 내려가고 선이 그려질 틈을 준다.
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "7-도보경로")

        // 지도가 무엇을 그렸는지 숫자로 남긴다. 그림만으로는 연결선을 안 만든 것인지
        // 만들었는데 안 그려진 것인지 구별할 수 없다.
        let mapView = app.descendants(matching: .any).matching(identifier: "mapReady").firstMatch
        let report = XCTAttachment(string: (mapView.value as? String) ?? "(값 없음)")
        report.name = "8-그린것"
        report.lifetime = .keepAlways
        add(report)
        XCTAssertTrue(
            ((mapView.value as? String) ?? "").contains("labels:1"),
            "실제 경로는 그려졌지만 선 중간의 이동수단·거리·시간 표시가 없다"
        )
    }

    /// 웹의 `+ 이 단계에 후보 추가`와 같은 흐름이 앱에도 실제로 보이고 동작하는가.
    private func addCandidateToFirstStop(_ app: XCUIApplication, counter: XCUIElement) {
        counter.tap()

        let add = app.descendants(matching: .any)
            .matching(identifier: "course.addCandidate.0").firstMatch
        guard add.waitForExistence(timeout: 10) else {
            attach(app, name: "9-후보추가버튼없음")
            XCTFail("동선 화면에 '이 단계에 후보 추가'가 없다")
            return
        }
        add.tap()

        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 10) else {
            attach(app, name: "9-후보검색창없음")
            XCTFail("후보 추가 검색창이 뜨지 않았다")
            return
        }
        XCTAssertTrue(
            app.staticTexts["1단계의 후보로 담습니다"].waitForExistence(timeout: 5),
            "검색 화면에서 어느 단계에 담는지 보이지 않는다"
        )
        Thread.sleep(forTimeInterval: 1)
        field.tap()
        guard app.keyboards.element.waitForExistence(timeout: 5) else {
            attach(app, name: "9-후보검색키보드없음")
            XCTFail("후보 검색창에 포커스가 오지 않았다")
            return
        }
        field.typeText("강남역")

        let result = app.descendants(matching: .any)
            .matching(identifier: "coursePicker.result").firstMatch
        guard result.waitForExistence(timeout: 20) else {
            attach(app, name: "9-후보검색결과없음")
            XCTFail("후보 검색 결과가 뜨지 않았다")
            return
        }

        // iOS 26 시뮬레이터는 검색 직후 첫 탭을 간헐적으로 키보드 정리에만 쓴다.
        // 실제 선택 상태가 바뀐 것을 확인하고, 반영되지 않았을 때만 제한적으로 다시 누른다.
        for _ in 0..<3 where (result.value as? String) != "선택됨" {
            result.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard (result.value as? String) == "선택됨" else {
            attach(app, name: "9-후보선택안됨")
            XCTFail("검색 결과를 눌렀지만 선택 상태로 바뀌지 않았다")
            return
        }

        // 웹처럼 결과를 누르는 것만으로 닫히지 않고, 여러 곳을 체크한 뒤 한 번에 담는다.
        let commit = app.descendants(matching: .any)
            .matching(identifier: "coursePicker.commit").firstMatch
        guard commit.waitForExistence(timeout: 5), commit.isEnabled else {
            attach(app, name: "9-복수선택확정버튼없음")
            XCTFail("후보를 골랐지만 여러 장소를 한 번에 추가하는 버튼이 활성화되지 않았다")
            return
        }
        attach(app, name: "9-후보복수선택")
        commit.tap()

        let summary = app.staticTexts["후보 2곳 · 대표를 정해야 경로를 그립니다"]
        let added = summary.waitForExistence(timeout: 10)
        attach(app, name: added ? "9-한단계후보둘" : "9-후보안담김")
        XCTAssertTrue(added, "장소를 골랐지만 첫 단계의 후보 수가 늘지 않았다")

        app.buttons["닫기"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "10-같은번호핀둘-회색보조선")

        let mapView = app.descendants(matching: .any).matching(identifier: "mapReady").firstMatch
        XCTAssertTrue(
            ((mapView.value as? String) ?? "").contains("candidateSpokes:2"),
            "같은 1단계의 후보 두 곳 사이에 회색 보조선이 그려지지 않았다"
        )
    }

    /// 지도에서 새 장소를 꾹 누른 직후 기존 단계의 후보로 담을 수 있는가.
    private func addLongPressedPlaceToFirstStop(_ app: XCUIApplication, counter: XCUIElement) {
        guard let dropHere = openDropPinMenu(app, x: 0.70, y: 0.43) else {
            attach(app, name: "11-후보핀메뉴안뜸")
            XCTFail("후보로 담을 새 장소의 꾹 누르기 메뉴가 뜨지 않았다")
            return
        }
        dropHere.tap()

        let firstStop = app.descendants(matching: .any)
            .matching(identifier: "droppin.target.0").firstMatch
        guard firstStop.waitForExistence(timeout: 5) else {
            attach(app, name: "11-후보단계선택안뜸")
            XCTFail("기존 단계에 후보로 추가하는 선택지가 뜨지 않았다")
            return
        }
        attach(app, name: "11-후보단계선택")
        firstStop.tap()

        XCTAssertTrue(counter.waitForExistence(timeout: 10), "후보 추가 뒤 지도 화면으로 돌아오지 않았다")
        counter.tap()
        let summary = app.staticTexts["후보 3곳 · 대표를 정해야 경로를 그립니다"]
        let added = summary.waitForExistence(timeout: 10)
        attach(app, name: added ? "11-꾹눌러첫단계후보셋" : "11-꾹눌러후보안담김")
        XCTAssertTrue(added, "꾹 눌러 고른 장소가 첫 단계 후보로 추가되지 않았다")
        app.buttons["닫기"].firstMatch.tap()
    }

    // MARK: - 도구

    private func openDropPinMenu(
        _ app: XCUIApplication,
        x: CGFloat,
        y: CGFloat
    ) -> XCUIElement? {
        let dropHere = app.descendants(matching: .any)
            .matching(identifier: "droppin.here").firstMatch
        let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))

        for _ in 0..<3 {
            coordinate.press(forDuration: 0.65)
            if dropHere.waitForExistence(timeout: 10) { return dropHere }
        }
        return nil
    }

    private func waitForMap(_ app: XCUIApplication) throws {
        let ready = app.descendants(matching: .any).matching(identifier: "mapReady").firstMatch
        let failed = app.descendants(matching: .any).matching(identifier: "mapFailed").firstMatch

        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if failed.exists {
                attach(app, name: "0-지도실패")
                XCTFail("지도 엔진이 뷰 추가에 실패했다. 앱 키와 번들 ID 등록을 확인하라.")
                return
            }
            if ready.exists { return }
            Thread.sleep(forTimeInterval: 0.5)
        }

        attach(app, name: "0-지도대기초과")
        XCTFail("60초 안에 지도가 준비되지 않았다.")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
