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
        } else {
            shot(app, "7-찾기버튼-비활성")
            XCTFail("사람을 둘 넣었는데도 찾기 버튼이 눌리지 않는다")
        }
    }

    // MARK: - 도구

    /// 장소를 검색해 한 명 추가한다.
    private func addPerson(_ app: XCUIApplication, query: String, step: String) {
        app.buttons["midpoint.addPerson"].tap()

        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 10) else {
            shot(app, "\(step)-검색창없음")
            XCTFail("검색창을 찾지 못했다")
            return
        }
        field.tap()
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
