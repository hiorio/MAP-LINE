import XCTest

/// 네트워크 검색 결과와 무관하게 같은 여행 동선을 심사용으로 찍는다.
final class AppStoreScreenshotUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_성수_데이트_코스와_구간별_메모() {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-uiTesting", "-uiTestingDateCourse"])
        app.launch()

        let ready = app.descendants(matching: .any).matching(identifier: "mapReady").firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 60), "성수 데이트 코스 지도가 준비되지 않았다")
        let stopCount = app.descendants(matching: .any).matching(identifier: "map.stopCount").firstMatch
        XCTAssertTrue(stopCount.waitForExistence(timeout: 10), "데이트 코스 다섯 단계가 지도에 표시되지 않았다")

        // 카메라가 전체 동선에 맞춰지고 지도 타일·경로·메모가 그려질 시간을 준다.
        Thread.sleep(forTimeInterval: 5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "심사-01-성수-데이트-코스와-메모"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_강원도_일곱곳_여행동선() {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-uiTesting", "-uiTestingGangwonTrip"])
        app.launch()

        let ready = app.descendants(matching: .any).matching(identifier: "mapReady").firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 60), "강원도 여행 지도가 준비되지 않았다")
        let stopCount = app.descendants(matching: .any).matching(identifier: "map.stopCount").firstMatch
        XCTAssertTrue(stopCount.waitForExistence(timeout: 10), "일곱 단계가 지도에 표시되지 않았다")

        // 카메라가 전체 동선에 맞춰지고 지도 타일·경로·메모가 그려질 시간을 준다.
        Thread.sleep(forTimeInterval: 5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "심사-04-강원도-7곳-여행동선"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
