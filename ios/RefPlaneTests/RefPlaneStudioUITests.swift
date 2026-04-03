import XCTest

final class RefPlaneStudioUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testStudioChromeStartsWithCanvasActions() {
        XCTAssertTrue(app.buttons["Library"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Samples"].exists)
        XCTAssertTrue(app.buttons["Show studio"].exists)
        XCTAssertTrue(app.staticTexts["Build a study from any reference"].exists)
    }

    func testOpeningStudioRevealsStudyControls() {
        let studioButton = app.buttons["Show studio"]
        if studioButton.exists {
            studioButton.tap()
        }

        XCTAssertTrue(app.staticTexts["Studio Controls"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Study"].exists)
        XCTAssertTrue(app.buttons["Structure"].exists)
        XCTAssertTrue(app.buttons["Depth"].exists)
        XCTAssertTrue(app.buttons["Mixing"].exists)
        XCTAssertTrue(app.buttons["Export"].exists)
    }

    func testModeDockContainsAllStudyModesWhenAvailable() {
        XCTAssertTrue(app.buttons["Choose Photo"].exists)

        let showStudioButton = app.buttons["Show studio"]
        if showStudioButton.exists {
            showStudioButton.tap()
        }

        XCTAssertTrue(app.buttons["Original study"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Tonal study"].exists)
        XCTAssertTrue(app.buttons["Value study"].exists)
        XCTAssertTrue(app.buttons["Color study"].exists)
    }
}
