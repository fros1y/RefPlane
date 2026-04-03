import XCTest

final class RefPlaneStudioUITests: XCTestCase {
    private var app: XCUIApplication!
    private var screenshotRecorder: StudioScreenshotRecorder!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()
        screenshotRecorder = StudioScreenshotRecorder(testName: name)
    }

    override func tearDown() {
        screenshotRecorder = nil
        app = nil
        super.tearDown()
    }

    func testStudioChromeStartsWithCanvasActions() {
        XCTAssertTrue(app.buttons["Library"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Samples"].exists)
        XCTAssertTrue(app.buttons["chrome.studio"].exists)
        XCTAssertTrue(app.staticTexts["Build a study from any reference"].exists)
    }

    func testOpeningStudioRevealsStudyControls() {
        openStudioIfNeeded()

        XCTAssertTrue(app.otherElements["studio.inspector"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["studio.section.study"].exists)
        XCTAssertTrue(app.buttons["studio.section.structure"].exists)
        XCTAssertTrue(app.buttons["studio.section.depth"].exists)
        XCTAssertTrue(app.buttons["studio.section.mixing"].exists)
        XCTAssertTrue(app.buttons["studio.section.export"].exists)
    }

    func testModeDockContainsAllStudyModesWhenAvailable() {
        openSculptureSampleAndWaitForCanvas()

        XCTAssertTrue(app.buttons["mode-dock.original"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["mode-dock.tonal"].exists)
        XCTAssertTrue(app.buttons["mode-dock.value"].exists)
        XCTAssertTrue(app.buttons["mode-dock.color"].exists)
    }

    func testCaptureUXScenarioScreenshots() throws {
        try captureScreenshot("01-empty-state")

        app.buttons["Browse Samples"].tap()
        XCTAssertTrue(app.buttons["sample-picker.statue"].waitForExistence(timeout: 3))
        try captureScreenshot("02-sample-picker")

        app.buttons["sample-picker.statue"].tap()
        XCTAssertTrue(app.otherElements["canvas.image"].waitForExistence(timeout: 8))
        waitForProcessingToSettle()
        try captureScreenshot("03-original-sculpture")

        selectStudyMode(identifier: "value", title: "Value")
        waitForProcessingToSettle()
        try captureScreenshot("04-value-study")

        openStudioIfNeeded()

        XCTAssertTrue(app.buttons["studio.section.structure"].waitForExistence(timeout: 3))
        app.buttons["studio.section.structure"].tap()
        XCTAssertTrue(app.switches["Show Grid"].waitForExistence(timeout: 3))
        app.switches["Show Grid"].tap()
        try captureScreenshot("05-grid-overlay")

        app.buttons["chrome.compare"].tap()
        XCTAssertTrue(app.otherElements["compare.canvas"].waitForExistence(timeout: 3))
        try captureScreenshot("06-compare-value")

        selectStudyMode(identifier: "color", title: "Color")
        waitForProcessingToSettle(timeout: 14)
        app.buttons["chrome.compare"].tap()
        XCTAssertTrue(app.buttons["studio.section.mixing"].waitForExistence(timeout: 3))
        app.buttons["studio.section.mixing"].tap()
        let firstMixCard = app.buttons.matching(identifier: "mix-card.0").firstMatch
        if firstMixCard.waitForExistence(timeout: 8) {
            firstMixCard.tap()
        }
        try captureScreenshot("07-color-mixing")

        app.buttons["studio.section.depth"].tap()
        XCTAssertTrue(app.switches["Depth Effects"].waitForExistence(timeout: 3))
        app.switches["Depth Effects"].tap()
        waitForProcessingToSettle(timeout: 14)
        try captureScreenshot("08-depth-effects")
    }

    private func waitForProcessingToSettle(timeout: TimeInterval = 10) {
        let canvasOverlay = app.otherElements["canvas.processing-overlay"]
        let compareOverlay = app.otherElements["compare.processing-overlay"]

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if canvasOverlay.exists == false && compareOverlay.exists == false {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }

        XCTAssertFalse(canvasOverlay.exists, "Canvas processing overlay did not disappear before timeout.")
        XCTAssertFalse(compareOverlay.exists, "Compare processing overlay did not disappear before timeout.")
    }

    private func captureScreenshot(_ stepName: String) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = stepName
        attachment.lifetime = .keepAlways
        add(attachment)
        try screenshotRecorder.save(screenshot: screenshot, stepName: stepName)
    }

    private func openStudioIfNeeded() {
        if app.otherElements["studio.inspector"].exists {
            return
        }

        if app.buttons["studio.sidebar-reveal"].exists {
            app.buttons["studio.sidebar-reveal"].tap()
        } else {
            app.buttons["chrome.studio"].tap()
        }
    }

    private func openSculptureSampleAndWaitForCanvas() {
        app.buttons["canvas.empty.samples"].tap()
        XCTAssertTrue(app.buttons["sample-picker.statue"].waitForExistence(timeout: 3))
        app.buttons["sample-picker.statue"].tap()
        XCTAssertTrue(app.otherElements["canvas.image"].waitForExistence(timeout: 8))
        waitForProcessingToSettle()
    }

    private func selectStudyMode(identifier: String, title: String) {
        let dockButton = app.buttons["mode-dock.\(identifier)"]
        if dockButton.waitForExistence(timeout: 2) {
            dockButton.tap()
            return
        }

        let inspectorSegment = app.buttons["inspector-mode.\(identifier)"]
        if inspectorSegment.waitForExistence(timeout: 2) {
            inspectorSegment.tap()
            return
        }

        let labeledButton = app.buttons[title]
        if labeledButton.waitForExistence(timeout: 2) {
            labeledButton.tap()
            return
        }

        XCTFail("No visible mode control for \(title).")
    }
}

private final class StudioScreenshotRecorder {
    private let runDirectory: URL

    init(testName: String) {
        let deviceName = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
            ?? "simulator"
        let projectRoot = Self.resolveProjectRoot(sourcePath: #filePath)

        var resolvedRunDirectory = projectRoot
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("ux-screenshots", isDirectory: true)
            .appendingPathComponent(Self.slug(deviceName), isDirectory: true)
            .appendingPathComponent(Self.slug(testName), isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: resolvedRunDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            resolvedRunDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("refplane-ux-screenshots", isDirectory: true)
                .appendingPathComponent(Self.slug(deviceName), isDirectory: true)
                .appendingPathComponent(Self.slug(testName), isDirectory: true)
            try? FileManager.default.createDirectory(
                at: resolvedRunDirectory,
                withIntermediateDirectories: true
            )
        }

        Self.removeExistingPNGs(from: resolvedRunDirectory)
        runDirectory = resolvedRunDirectory
    }

    func save(screenshot: XCUIScreenshot, stepName: String) throws {
        let targetURL = runDirectory
            .appendingPathComponent("\(Self.slug(stepName)).png")
        try screenshot.pngRepresentation.write(to: targetURL, options: .atomic)
    }

    private static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func resolveProjectRoot(sourcePath: String) -> URL {
        let fileManager = FileManager.default
        let candidates = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            URL(fileURLWithPath: sourcePath, isDirectory: false).deletingLastPathComponent(),
        ]

        for candidate in candidates {
            var directory = candidate.standardizedFileURL
            while directory.path != "/" {
                let projectFile = directory
                    .appendingPathComponent("ios", isDirectory: true)
                    .appendingPathComponent("RefPlane.xcodeproj", isDirectory: true)
                    .appendingPathComponent("project.pbxproj", isDirectory: false)
                if fileManager.fileExists(atPath: projectFile.path) {
                    return directory
                }
                directory.deleteLastPathComponent()
            }
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    }

    private static func removeExistingPNGs(from directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for file in files where file.pathExtension.lowercased() == "png" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
