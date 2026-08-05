import XCTest

/// 화면을 눈으로 보기 위한 테스트.
///
/// 맥이 없어 시뮬레이터를 직접 띄울 수 없다. 그래서 흐름을 한 번 걸어가며 각 단계를
/// 찍어 아티팩트로 남긴다. 이게 유일한 "화면 보기" 수단이다.
///
/// 실패해도 지금까지 찍은 것은 남겨야 한다. 어디서 어긋났는지는 그 그림에 있다.
/// 그래서 단언으로 세우는 대신 각 단계마다 찍고, 못 찾은 것은 기록만 남기고 넘어간다.
final class ScreenshotUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func test_화면들을_찍는다() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. 첫 화면은 지도다.
        //
        // 요소 종류를 찍어 고르지 않는다. SwiftUI가 무엇으로 낼지는 버전과 스타일에
        // 따라 다르고, 틀리면 "없다"고만 나와 원인을 알기 어렵다.
        let midpointButton = app.descendants(matching: .any).matching(identifier: "map.midpoint").firstMatch
        XCTAssertTrue(midpointButton.waitForExistence(timeout: 30), "지도 화면이 뜨지 않았다")
        // 타일이 그려질 틈을 준다.
        Thread.sleep(forTimeInterval: 3)
        shot(app, "1-지도")

        // 2. 옆 메뉴
        let menu = app.descendants(matching: .any).matching(identifier: "map.menu").firstMatch
        if menu.exists {
            menu.tap()
            Thread.sleep(forTimeInterval: 1)
            shot(app, "2-메뉴")
            // 메뉴에서 중간지점으로 들어간다. 지도 위 버튼과 같은 곳으로 가야 한다.
            let fromMenu = app.descendants(matching: .any).matching(identifier: "menu.midpoint").firstMatch
            if fromMenu.exists { fromMenu.tap() } else { midpointButton.tap() }
        } else {
            midpointButton.tap()
        }
        XCTAssertTrue(app.buttons["midpoint.addPerson"].waitForExistence(timeout: 10))
        shot(app, "3-중간지점-빈화면")

        // 3. 사람 둘 추가
        addPerson(app, query: "강남역", step: "4")
        addPerson(app, query: "홍대입구역", step: "5")
        shot(app, "6-사람둘")

        // 4. 찾기. 참가자 수만큼 길찾기가 나가므로 넉넉히 기다린다.
        let find = app.buttons["midpoint.find"]
        if find.isEnabled {
            find.tap()
            // 결과가 붙으면 "모이기 좋은 곳" 머리글이 생긴다.
            let header = app.staticTexts["모이기 좋은 곳"]
            let appeared = header.waitForExistence(timeout: 60)
            shot(app, appeared ? "7-결과" : "7-결과없음")
            XCTAssertTrue(appeared, "60초 안에 결과가 오지 않았다")

            // 5. 지도로 옮겨 그린다.
            //
            // 이 기능의 답은 목록이 아니라 이 화면이다. 누가 어디서 오는지, 모이는 곳이
            // 그 사이 어디쯤인지는 지도에서만 읽힌다. 핀이 제자리에 붙었는지도 여기서만
            // 확인할 수 있어서 마지막 한 장이 제일 중요하다.
            if appeared { showOnMap(app) }
        } else {
            shot(app, "7-찾기버튼-비활성")
            XCTFail("사람을 둘 넣었는데도 찾기 버튼이 눌리지 않는다")
        }
    }

    // MARK: - 도구

    /// 1·2순위 후보를 함께 골라 지도에 얹고 찍는다.
    private func showOnMap(_ app: XCUIApplication) {
        // 1순위는 기본 선택되어 있다. 2순위도 더해 여러 후보와 경로가 함께 보이는지 본다.
        let second = app.descendants(matching: .any)
            .matching(identifier: "midpoint.candidate.1").firstMatch
        if second.waitForExistence(timeout: 10) {
            scrollUntilHittable(second, in: app)
            second.tap()
            shot(app, "8-후보둘선택")
        } else {
            XCTFail("2순위 후보 선택 항목이 없다")
        }

        let button = app.descendants(matching: .any)
            .matching(identifier: "midpoint.showOnMap").firstMatch
        guard button.waitForExistence(timeout: 10) else {
            shot(app, "8-지도에서보기-없음")
            XCTFail("결과에 '지도에서 보기'가 없다")
            return
        }
        scrollUntilHittable(button, in: app)
        button.tap()

        // 시트가 닫히고 지도가 나오면 무엇을 보고 있는지 알리는 칩이 붙는다.
        let chip = app.descendants(matching: .any)
            .matching(identifier: "map.plotChip").firstMatch
        let onMap = chip.waitForExistence(timeout: 15)
        // 카메라가 미끄러져 자리를 잡고 타일과 핀이 그려질 틈을 준다.
        Thread.sleep(forTimeInterval: 4)
        shot(app, onMap ? "9-후보둘-지도에표시" : "9-지도로안넘어감")
        XCTAssertTrue(onMap, "후보를 골랐는데 지도로 넘어가지 않았다")
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable, attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "선택 항목을 화면 안으로 가져오지 못했다")
    }

    /// 장소를 검색해 한 명 추가한다.
    private func addPerson(_ app: XCUIApplication, query: String, step: String) {
        app.buttons["midpoint.addPerson"].tap()

        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 10) else {
            shot(app, "\(step)-검색창없음")
            XCTFail("검색창을 찾지 못했다")
            return
        }
        // 시트가 아직 미끄러지는 중에 두드리면 그 탭이 삼켜진다. 자리를 잡을 틈을 준다.
        Thread.sleep(forTimeInterval: 1)

        // 그래도 한 번에 포커스가 안 올 때가 있다. 그대로 typeText를 부르면
        // "Neither element nor any descendant has keyboard focus"로 흐름 전체가
        // 멈춰 버려서, 정작 보려던 뒷 화면을 한 장도 못 건진다.
        var attempts = 0
        field.tap()
        while !app.keyboards.element.waitForExistence(timeout: 3), attempts < 3 {
            field.tap()
            attempts += 1
        }
        guard app.keyboards.element.exists else {
            shot(app, "\(step)-키보드안뜸")
            XCTFail("검색창에 포커스가 오지 않았다")
            return
        }
        field.typeText(query)

        // 치는 도중에는 부르지 않고 잠깐 기다렸다 부른다. 그만큼 기다려 준다.
        let first = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", query)).firstMatch
        if first.waitForExistence(timeout: 20) {
            shot(app, "\(step)-검색결과")
            first.tap()
        } else {
            // 결과가 없는 것도 봐야 할 화면이다. 네트워크나 쿼터 문제일 수 있다.
            shot(app, "\(step)-검색결과없음")
            XCTFail("'\(query)' 검색 결과가 뜨지 않았다")
            app.buttons["취소"].firstMatch.tap()
        }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
