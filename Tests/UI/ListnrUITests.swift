import XCTest

/// Golden-path UI tests. Every launch is deterministic: `-uitest` forces the
/// in-memory store and the fixed sample library, `-mockengine` the
/// deterministic playback engine.
final class ListnrUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest", "-mockengine"]
        app.launch()
        return app
    }

    /// Buttons whose label starts with `prefix` (row labels carry metadata).
    private func button(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Polls until the element is gone; XCUITest has no negative wait.
    @discardableResult
    private func waitAbsent(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            usleep(200_000)
        }
        return !element.exists
    }

    /// Opens the header filter menu, picks a choice, and gives the diff
    /// animation a moment to settle.
    private func filter(_ app: XCUIApplication, name: String) {
        let menu = app.buttons["Filter"]
        XCTAssertTrue(menu.waitForExistence(timeout: 8), "filter menu missing")
        menu.tap()
        let item = app.buttons[name]
        XCTAssertTrue(item.waitForExistence(timeout: 6), "filter item \(name) missing")
        item.tap()
        usleep(400_000)
    }

    private func openPlayer(_ app: XCUIApplication) {
        let row = button(app, startingWith: "Project Hail Mary by Andy Weir")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "sample row missing")
        row.tap()
        XCTAssertTrue(app.staticTexts["Project Hail Mary"].waitForExistence(timeout: 6))
    }

    private func noteField(_ app: XCUIApplication) -> XCUIElement {
        let tf = app.textFields["Note text"]
        return tf.exists ? tf : app.textViews["Note text"]
    }

    // MARK: shell

    func testTabsExistAndConstructionScreensShow() {
        let app = launch()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        for name in ["Library", "Audiobook", "Reader", "Scan"] {
            XCTAssertTrue(tabBar.buttons[name].exists, "tab \(name) missing")
        }
        tabBar.buttons["Reader"].tap()
        XCTAssertTrue(app.staticTexts["The reader is not built yet — it arrives with the paired EPUB."]
            .waitForExistence(timeout: 5))
        tabBar.buttons["Scan"].tap()
        XCTAssertTrue(app.staticTexts["Scan-to-sync is not built yet — it arrives after notes."]
            .waitForExistence(timeout: 5))
        tabBar.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 5))
    }

    // MARK: library

    func testLibraryFiltersAndSearch() {
        let app = launch()
        XCTAssertTrue(button(app, startingWith: "Project Hail Mary by").waitForExistence(timeout: 8))

        filter(app, name: "Audiobooks")
        XCTAssertTrue(waitAbsent(button(app, startingWith: "Sea of Tranquility by")),
                      "ebook-only title must vanish under Audiobooks")

        filter(app, name: "Paired")
        XCTAssertTrue(button(app, startingWith: "Piranesi by").waitForExistence(timeout: 3))

        filter(app, name: "In progress")
        XCTAssertTrue(waitAbsent(button(app, startingWith: "The Dawn of Everything by")),
                      "untouched title must vanish under In progress")

        filter(app, name: "All")
        let search = app.textFields["Search your books"]
        search.tap()
        search.typeText("tranquility")
        XCTAssertTrue(button(app, startingWith: "Sea of Tranquility by").waitForExistence(timeout: 4))
        XCTAssertTrue(waitAbsent(button(app, startingWith: "Piranesi by")))
    }

    // MARK: player

    func testOpenBookShowsPlayerAndPlayToggles() {
        let app = launch()
        openPlayer(app)
        let play = app.buttons["Play"]
        XCTAssertTrue(play.exists, "play button missing")
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 4), "state did not flip to pause")
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 4), "did not flip back to play")
    }

    func testChapterWheelSeeks() {
        let app = launch()
        openPlayer(app)

        // the chapter line under the identity block is the only control that
        // opens the wheel now — the separate chapter button is gone
        let chapterLine = button(app, startingWith: "Chapters:")
        XCTAssertTrue(chapterLine.waitForExistence(timeout: 6), "chapter line missing")
        chapterLine.tap()

        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 6), "chapter wheel missing")
        wheel.adjust(toPickerWheelValue: "Chapter 5")
        app.buttons["Done picking chapters"].tap()

        XCTAssertTrue(
            button(app, startingWith: "Chapters: Chapter 5").waitForExistence(timeout: 6),
            "selection did not reach the player state")
    }

    func testSpeedCyclesAndSleepArms() {
        let app = launch()
        openPlayer(app)
        let speed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Playback speed")).firstMatch
        XCTAssertTrue(speed.waitForExistence(timeout: 6))
        speed.tap()
        XCTAssertTrue(
            app.buttons["Playback speed 1.2"].exists,
            "speed should cycle 1.0 -> 1.2")

        app.buttons["Sleep timer"].tap()
        XCTAssertTrue(app.buttons["Sleep in 15 minutes"].waitForExistence(timeout: 4))
        app.buttons["Sleep in 30 minutes"].tap()
        XCTAssertFalse(app.buttons["Sleep in 15 minutes"].waitForExistence(timeout: 2),
                       "picker should close after choosing")
    }

    // MARK: mini-player

    func testMiniPlayerOnLibrary() {
        let app = launch()
        openPlayer(app)

        // back to Library — the accessory only exists off the Audiobook tab
        app.tabBars.firstMatch.buttons["Library"].tap()

        let accessory = app.buttons["Now playing: Project Hail Mary"]
        XCTAssertTrue(accessory.waitForExistence(timeout: 6), "mini-player missing on Library")

        // its play key toggles playback and must not switch tabs
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 4), "mini-player play key missing")
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 4),
                      "mini-player play key did not flip the label")
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Library"].isSelected,
                      "the play key must not change tabs")
        app.buttons["Pause"].tap()

        // the body opens the player
        accessory.tap()
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Audiobook"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Audiobook"].isSelected,
                      "tapping the accessory body must select the Audiobook tab")
    }

    // MARK: notes

    func testNoteCaptureRoundTrip() {
        let app = launch()
        openPlayer(app)

        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 4))

        app.buttons["New note"].tap()
        let field = noteField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("Rocky speaks in exclamation marks")

        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 4), "save must resume playback")

        app.buttons["New note"].tap()
        XCTAssertTrue(app.staticTexts["Rocky speaks in exclamation marks"].waitForExistence(timeout: 6))
        app.buttons["Cancel"].tap()
    }
}
