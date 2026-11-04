import XCTest

@MainActor
final class ProbeUITests: XCTestCase {
    private func wait(_ element: XCUIElement, for predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    func testSingleFingerDoubleTapAndHorizontalSeek() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "hevc8"]
        app.launch()
        let ready = app.staticTexts["playbackReady"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15))
        XCTAssertTrue(wait(ready, for: NSPredicate(format: "label == %@", "画面已输出"), timeout: 30))
        let surface = app.otherElements["gestureSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        let state = app.staticTexts["playbackState"]
        surface.doubleTap()
        XCTAssertTrue(wait(state, for: NSPredicate(format: "label == %@", "已暂停"), timeout: 5))
        let progress = app.staticTexts["playbackPosition"]
        let previousLabel = progress.label
        let before = Double(previousLabel.components(separatedBy: " ").first ?? "") ?? -1
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        )
        XCTAssertTrue(wait(progress, for: NSPredicate(format: "label != %@", previousLabel), timeout: 10))
        let after = Double(progress.label.components(separatedBy: " ").first ?? "") ?? -1
        XCTAssertGreaterThan(after, before + 2)
        XCTAssertEqual(state.label, "已暂停")
        surface.doubleTap()
        XCTAssertTrue(wait(state, for: NSPredicate(format: "label == %@", "播放中"), timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native sample-buffer 4K playback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
