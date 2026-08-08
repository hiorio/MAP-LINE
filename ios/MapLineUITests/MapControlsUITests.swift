import XCTest

/// 지도 홈의 핵심 조작부와 보관 장소·현재 위치 표식을 한 흐름에서 확인한다.
final class MapControlsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_아이콘보관장소새지도현재위치를확인한다() {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "-uiTesting",
            "-uiTestingDateCourse",
            "-uiTestingSeedSavedPins",
            "-uiTestingCurrentLocation",
        ])
        app.launch()

        let map = app.descendants(matching: .any).matching(identifier: "mapReady").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 30), "지도가 준비되지 않았다")

        let search = element("map.searchBar", in: app)
        let draw = element("map.draw", in: app)
        let share = element("map.share", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 10), "지도 상단 검색바가 없다")
        XCTAssertTrue(draw.exists, "손그림 아이콘이 없다")
        XCTAssertTrue(share.exists, "공유 아이콘이 없다")
        XCTAssertGreaterThan(search.frame.width, search.frame.height * 3, "검색 진입점이 검색바 모양이 아니다")
        assertCircularIcon(draw)
        assertCircularIcon(share)

        search.tap()
        XCTAssertTrue(
            app.searchFields["장소나 주소"].waitForExistence(timeout: 5),
            "상단 검색바가 장소 검색 화면을 열지 못했다"
        )
        app.buttons["취소"].firstMatch.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5), "장소 검색을 닫은 뒤 지도로 돌아오지 못했다")

        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "지도-아이콘-보관장소마커")

        element("map.title", in: app).tap()
        let newMap = element("mapTitle.newMap", in: app)
        XCTAssertTrue(newMap.waitForExistence(timeout: 5), "지도 이름 모달에 새 지도 버튼이 없다")
        attach(app, name: "지도이름-새지도버튼")
        newMap.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "새 지도 확인창이 뜨지 않았다")
        app.alerts.firstMatch.buttons["취소"].tap()

        let location = element("map.currentLocation", in: app)
        XCTAssertTrue(location.waitForExistence(timeout: 5), "현재 위치 버튼이 없다")
        location.tap()
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "현재 위치 표시됨"),
            object: location
        )
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        // 한 번 찾은 뒤에는 다시 위치를 요청하지 않고 저장된 좌표로 즉시 재포커스한다.
        location.tap()
        XCTAssertEqual(location.value as? String, "현재 위치 표시됨")
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "현재위치-이동-파란점")
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertCircularIcon(_ element: XCUIElement) {
        XCTAssertEqual(element.frame.width, element.frame.height, accuracy: 1)
        XCTAssertLessThanOrEqual(element.frame.width, 52)
        XCTAssertGreaterThanOrEqual(element.frame.width, 48)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
