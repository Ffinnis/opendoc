import XCTest

#if !os(macOS)
final class opendocUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testCreateDockAddWidgetAndPersistNote() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", UUID().uuidString]
        app.launch()
        app.buttons["new-dock"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Writing")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["profile-Writing"].waitForExistence(timeout: 3))
        app.buttons["nav-Widget library"].tap()
        app.buttons["add-widget-note"].tap()
        app.buttons["nav-My docks"].tap()
        let openNote = app.buttons["Open Sticky note"].firstMatch
        XCTAssertTrue(openNote.waitForExistence(timeout: 3))
        openNote.tap()
        let note = app.textViews["Note text"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        note.typeText(" Saved from UI test")
        app.buttons["Save note"].tap()
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["profile-Writing"].waitForExistence(timeout: 5))
        app.buttons["Open Sticky note"].firstMatch.tap()
        XCTAssertTrue((app.textViews["Note text"].value as? String ?? "").contains("Saved from UI test"))
    }

    @MainActor
    func testAppearanceAndProfileSwitching() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", UUID().uuidString]
        app.launch()
        app.buttons["nav-Appearance"].tap()
        app.segmentedControls["Wallpaper"].buttons["Ocean"].tap()
        app.segmentedControls["Position"].buttons["Left"].tap()
        XCTAssertTrue(app.segmentedControls["Position"].buttons["Left"].isSelected)
        app.buttons["profile-Personal"].tap()
        app.buttons["nav-Appearance"].tap()
        XCTAssertTrue(app.segmentedControls["Position"].buttons["Bottom"].isSelected)
        app.buttons["profile-Everyday"].tap()
        app.buttons["nav-Appearance"].tap()
        XCTAssertTrue(app.segmentedControls["Position"].buttons["Left"].isSelected)
    }
}

#endif
