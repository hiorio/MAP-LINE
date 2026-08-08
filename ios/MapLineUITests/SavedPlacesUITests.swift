import XCTest

/// 보관함이 단순 공유 수신 목록이 아니라 폴더·마크를 만드는 화면으로 보이는지 확인한다.
final class SavedPlacesUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_보관함에서폴더와마크를만든다() {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTesting")
        app.launch()

        let menu = app.descendants(matching: .any).matching(identifier: "map.menu").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "지도 화면이 뜨지 않았다")
        menu.tap()

        let saved = app.descendants(matching: .any).matching(identifier: "menu.saved").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "메뉴에 보관함이 없다")
        saved.tap()

        let addGroup = app.descendants(matching: .any)
            .matching(identifier: "saved.addGroup").firstMatch
        XCTAssertTrue(addGroup.waitForExistence(timeout: 10), "보관함에 새 폴더 버튼이 없다")
        XCTAssertTrue(app.searchFields.firstMatch.exists, "보관함 전체 검색창이 없다")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "saved.sortGroups").firstMatch.exists,
            "보관함에 폴더 정렬 버튼이 없다"
        )
        attach(app, name: "보관함-폴더목록")
        addGroup.tap()

        let name = app.textFields["saved.groupEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "폴더 이름 입력창이 없다")
        name.tap()
        name.typeText("가고 싶은 카페")

        let coffee = app.descendants(matching: .any)
            .matching(identifier: "saved.marker.coffee").firstMatch
        XCTAssertTrue(coffee.exists, "카페 마크 선택지가 없다")
        coffee.tap()
        app.swipeUp()
        let nature = app.descendants(matching: .any)
            .matching(identifier: "saved.marker.nature").firstMatch
        XCTAssertTrue(nature.waitForExistence(timeout: 5), "확장된 자연 마크 선택지가 없다")
        attach(app, name: "보관함-폴더마크편집")
    }

    func test_보관함안의내동선에썸네일이름과단계수가보인다() {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-uiTesting", "-uiTestingSeedMaps"])
        app.launch()

        let menu = app.descendants(matching: .any).matching(identifier: "map.menu").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "지도 화면이 뜨지 않았다")
        menu.tap()

        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "menu.myMaps").firstMatch.exists,
            "내 동선은 보관함 밖의 메뉴에 중복 노출되면 안 된다"
        )
        let saved = app.descendants(matching: .any).matching(identifier: "menu.saved").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "메뉴에 보관함이 없다")
        saved.tap()

        let myRoutes = app.descendants(matching: .any).matching(identifier: "saved.myRoutes").firstMatch
        XCTAssertTrue(myRoutes.waitForExistence(timeout: 10), "보관함 안에 내 동선이 없다")
        myRoutes.tap()

        let row = app.descendants(matching: .any).matching(identifier: "mymaps.row.ui-map").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "내 동선 항목이 보이지 않는다")
        XCTAssertTrue(app.staticTexts["주말 나들이"].exists, "지도 이름이 보이지 않는다")
        XCTAssertTrue(app.staticTexts["3단계"].exists, "단계 수가 보이지 않는다")
        attach(app, name: "내동선-썸네일-이름-단계수")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
