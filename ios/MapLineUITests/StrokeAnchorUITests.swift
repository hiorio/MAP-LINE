import XCTest

/// 이 프로젝트에서 네이티브로 갈지 말지를 가르는 단 하나의 질문을 확인한다.
///
/// > 손가락으로 그은 선이 위경도에 고정되어, 지도를 옮겨도 제자리에 남는가
///
/// 컴파일이 된다고 답이 나오지 않는다. `PolylineShape`(모델 좌표)과
/// `MapPolylineShape`(위경도)은 둘 다 컴파일되지만, 앞의 것을 쓰면 선이 화면에
/// 붙어 버려 지도를 옮겨도 따라오지 않는다. 그림을 봐야 안다.
///
/// 맥이 없어 사람이 눈으로 볼 수 없으므로 스크린샷을 남긴다. CI가 아티팩트로 올리면
/// 그때 픽셀을 분석해 판정한다. 여기서는 상황만 정확히 만들고 증거를 남긴다.
final class StrokeAnchorUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_지도를_옮겨도_획이_따라오는가() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTesting")
        app.launch()

        // 첫 화면이 곧 지도다. 그리기 버튼은 그 위에 얹혀 있다.
        let toggle = app.descendants(matching: .any).matching(identifier: "map.draw").firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), "지도 화면이 뜨지 않았다")

        try waitForMap(app)

        // 1. 그리기를 켜고 화면 가운데를 가로지르는 선을 긋는다.
        toggle.tap()

        let undo = app.descendants(matching: .any).matching(identifier: "map.draw.undo").firstMatch
        let clear = app.descendants(matching: .any).matching(identifier: "map.draw.clear").firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "그리기 모드에 한 획 되돌리기가 없다")
        XCTAssertTrue(clear.exists, "그리기 모드에 전체 지우기가 없다")
        XCTAssertEqual(toggle.label, "손그림")
        XCTAssertTrue(waitForValue("0획", of: toggle))

        drag(app, from: CGVector(dx: 0.25, dy: 0.40), to: CGVector(dx: 0.75, dy: 0.40))
        XCTAssertTrue(waitForValue("1획", of: toggle))
        attach(app, name: "1-그린직후")

        // 두 번째 획만 되돌린 뒤, 전체 지우기와 실행 취소도 같은 화면에서 확인한다.
        drag(app, from: CGVector(dx: 0.35, dy: 0.32), to: CGVector(dx: 0.35, dy: 0.58))
        XCTAssertTrue(waitForValue("2획", of: toggle))
        undo.tap()
        XCTAssertTrue(waitForValue("1획", of: toggle), "마지막 획 하나만 되돌리지 못했다")
        clear.tap()
        XCTAssertTrue(waitForValue("0획", of: toggle), "전체 지우기가 획을 남겼다")

        let undoBanner = app.descendants(matching: .any).matching(identifier: "undo.banner").firstMatch
        XCTAssertTrue(undoBanner.waitForExistence(timeout: 5), "전체 지우기 뒤 실행 취소가 없다")
        app.buttons["실행 취소"].tap()
        XCTAssertTrue(waitForValue("1획", of: toggle), "전체 지우기를 실행 취소해도 획이 돌아오지 않았다")
        attach(app, name: "1a-손그림편집도구")

        // 2. 그리기를 끄고 지도를 위로 끌어올린다. 획이 지도에 붙어 있다면 같이 올라간다.
        toggle.tap()
        drag(app, from: CGVector(dx: 0.50, dy: 0.65), to: CGVector(dx: 0.50, dy: 0.35))

        // 타일과 도형이 다시 그려질 틈을 준다.
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "2-위로팬")

        // 3. 반대로 내린다. 원래 자리 근처로 돌아와야 한다.
        drag(app, from: CGVector(dx: 0.50, dy: 0.35), to: CGVector(dx: 0.50, dy: 0.65))
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "3-되돌린뒤")
    }

    // MARK: - 도구

    /// 지도가 준비될 때까지 기다린다.
    ///
    /// 고정 시간 대기는 러너가 느린 날 깨진다. 앱이 성공·실패를 접근성 식별자로
    /// 내걸어 두므로 그것을 본다. 실패면 앱 키나 번들 ID 등록 문제이고, 그건
    /// 코드 문제와 구별해서 알려 줘야 한다.
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

    private func drag(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        let start = app.coordinate(withNormalizedOffset: from)
        let end = app.coordinate(withNormalizedOffset: to)
        // 누르고 있는 시간을 줘야 팬과 그리기 모두 제스처로 인식된다.
        start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    private func waitForValue(_ expected: String, of element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if element.value as? String == expected { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return element.value as? String == expected
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        // 통과해도 남겨야 한다. 판정은 사람이 그림을 보고 한다.
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
