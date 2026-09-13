import XCTest
@testable import KeyboardProject

@MainActor
final class FeedbackServiceTests: XCTestCase {
    func testRapidTypingSoftensFeedbackAndPauseRestoresIt() {
        let letter = KeyAction.character("a")
        let normal = FeedbackService.intensity(for: letter, interval: nil)
        XCTAssertLessThan(FeedbackService.intensity(for: letter, interval: 0.06), normal)
        XCTAssertEqual(FeedbackService.intensity(for: letter, interval: 0.5), normal)
    }

    func testStructuralKeysAreDistinctFromLettersAtTheSameCadence() {
        let intervals: [TimeInterval?] = [nil, 0.06, 0.5]
        for interval in intervals {
            let letter = FeedbackService.intensity(for: .character("a"), interval: interval)
            let actions: [KeyAction] = [.space, .newline, .backspace, .shift]
            for action in actions {
                let intensity = FeedbackService.intensity(for: action, interval: interval)
                XCTAssertGreaterThan(intensity, letter)
                XCTAssertLessThanOrEqual(intensity, 1)
            }
        }
    }
}
