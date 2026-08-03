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
        app.launch()

        // 앱이 홈에서 시작하도록 바뀌었다. 지도로 들어가야 엔진이 뜬다.
        // 예전에는 지도가 첫 화면이라 바로 기다리면 됐다.
        let toMap = app.descendants(matching: .any).matching(identifier: "home.blankMap").firstMatch
        XCTAssertTrue(toMap.waitForExistence(timeout: 20), "홈이 뜨지 않았다")
        toMap.tap()

        try waitForMap(app)

        // 1. 그리기를 켜고 화면 가운데를 가로지르는 선을 긋는다.
        let toggle = app.buttons["drawToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "그리기 버튼을 찾지 못했다")
        toggle.tap()

        drag(app, from: CGVector(dx: 0.25, dy: 0.40), to: CGVector(dx: 0.75, dy: 0.40))
        attach(app, name: "1-그린직후")

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

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        // 통과해도 남겨야 한다. 판정은 사람이 그림을 보고 한다.
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
