#if os(macOS)
import XCTest

final class NativeDockUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNativeProfileAndAppearancePersistence() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", UUID().uuidString]
        app.launch()
        let settings = app.windows["Open Doc"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        XCTAssertTrue(settings.tables["dock-profiles"].exists)
        XCTAssertTrue(settings.tables["dock-items"].exists)
        let name = settings.textFields["dock-name"]
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Renamed Dock")
        name.typeKey(.return, modifierFlags: [])
        settings.radioButtons["Appearance"].click()
        settings.radioButtons["Right"].click()
        app.terminate()
        app.launch()
        XCTAssertEqual(app.windows["Open Doc"].textFields["dock-name"].value as? String, "Renamed Dock")
        app.windows["Open Doc"].radioButtons["Appearance"].click()
        XCTAssertEqual(app.windows["Open Doc"].radioButtons["Right"].value as? String, "1")
    }

    @MainActor
    func testAddAndRemoveWidget() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", UUID().uuidString]
        app.launch()
        let settings = app.windows["Open Doc"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        let before = settings.tables["dock-items"].tableRows.count
        settings.buttons["Widget Library"].click()
        let search = app.searchFields["Search widgets"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("Hydration")
        app.buttons["Add Widget"].click()
        XCTAssertEqual(settings.tables["dock-items"].tableRows.count, before + 1)
        settings.tables["dock-items"].tableRows.element(boundBy: before).click()
        settings.buttons["Remove Item"].click()
        XCTAssertEqual(settings.tables["dock-items"].tableRows.count, before)
    }
}
#endif
