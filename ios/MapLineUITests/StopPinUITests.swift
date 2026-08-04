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
        app.launch()

        let draw = app.descendants(matching: .any).matching(identifier: "map.draw").firstMatch
        XCTAssertTrue(draw.waitForExistence(timeout: 30), "지도 화면이 뜨지 않았다")
        try waitForMap(app)
        // 타일이 올라올 틈을 준다. 빈 지도를 찍으면 핀이 붙었는지 알아볼 수 없다.
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "1-담기전")

        // 화면 가운데를 꾹 누른다. 아래쪽 버튼들과 겹치지 않는 자리다.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
            .press(forDuration: 1.2)

        // 주변 검색이 끝나야 목록이 뜬다. 검색이 실패해도 "여기에 그대로"는 있어야 한다.
        let dropHere = app.descendants(matching: .any)
            .matching(identifier: "droppin.here").firstMatch
        let opened = dropHere.waitForExistence(timeout: 30)
        attach(app, name: opened ? "2-꾹누른뒤" : "2-메뉴안뜸")
        guard opened else {
            XCTFail("지도를 꾹 눌렀는데 메뉴가 뜨지 않았다")
            return
        }

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
        app.buttons["닫기"].firstMatch.tap()

        try drawWalkingLeg(app, counter: counter)
    }

    /// 두 번째 단계를 담고 그 사이를 도보로 잇는다.
    ///
    /// 이게 이 커밋의 핵심이다. 실제 경로가 지도에 파란 점선으로 그려지는지는
    /// 컴파일로도 유닛 테스트로도 알 수 없다 — SDK가 그린 그림을 봐야 안다.
    private func drawWalkingLeg(_ app: XCUIApplication, counter: XCUIElement) throws {
        // 첫 핀과 떨어진 자리를 꾹 눌러 두 번째 단계를 담는다.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.62))
            .press(forDuration: 1.2)

        let dropHere = app.descendants(matching: .any)
            .matching(identifier: "droppin.here").firstMatch
        guard dropHere.waitForExistence(timeout: 30) else {
            attach(app, name: "5-두번째메뉴안뜸")
            XCTFail("두 번째 꾹 누르기에서 메뉴가 뜨지 않았다")
            return
        }
        dropHere.tap()
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
    }

    // MARK: - 도구

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
