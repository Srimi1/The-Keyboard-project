import XCTest

/// Trial C — the three layers and the keys that move between them.
///
/// `perform(.switchLayer:)` calls `releaseAllTouches()`, so these also exercise the path
/// where the grid is rebuilt underneath a finger that has just lifted.
final class LayerTrials: KeyboardUITestCase {

    // MARK: - C1

    func testC1_symbolsLayerTypesDigits() {
        launchPreview()

        tapKey("layer")                                   // ?123
        assertLayerShows("1", "The ?123 key did not switch to the symbols layer")

        tapKey(row: 0, index: 0, layer: .symbols)         // 1
        tapKey(row: 0, index: 4, layer: .symbols)         // 5
        tapKey(row: 0, index: 9, layer: .symbols)         // 0
        tapKey(row: 1, index: 0, layer: .symbols)         // @

        print("=== C1 typed: '\(typedText)'")
        XCTAssertEqual(typedText, "150@")
    }

    // MARK: - C2

    func testC2_extendedSymbolsLayer() {
        launchPreview()

        tapKey("layer")                                   // ?123
        tapKey("extended", layer: .symbols)               // =\<
        assertLayerShows("√", "The =\\< key did not switch to the extended-symbols layer")

        tapKey(row: 0, index: 0, layer: .extendedSymbols) // ~
        tapKey(row: 1, index: 2, layer: .extendedSymbols) // €
        tapKey(row: 2, index: 1, layer: .extendedSymbols) // %

        print("=== C2 typed: '\(typedText)'")
        XCTAssertEqual(typedText, "~€%")
    }

    // MARK: - C3

    func testC3_abcKeyReturnsToLetters() {
        launchPreview()

        tapKey("layer")                                   // ?123
        tapKey(row: 0, index: 2, layer: .symbols)         // 3
        XCTAssertEqual(typedText, "3")

        tapKey("layer", layer: .symbols)                  // ABC
        assertLayerShows("q", "The ABC key did not return to the letter layer")

        type("ab")
        print("=== C3 typed: '\(typedText)'")
        XCTAssertEqual(typedText, "3ab")
    }

    /// The round trip the other three tests only cover in pieces: base -> ?123 -> =\< ->
    /// ABC -> base, typing one character from each layer on the way through.
    func testC_roundTripThroughEveryLayer() {
        launchPreview()

        tapKey("x")                                       // base
        tapKey("layer")                                   // ?123
        tapKey(row: 0, index: 6, layer: .symbols)         // 7
        tapKey("extended", layer: .symbols)               // =\<
        tapKey(row: 0, index: 5, layer: .extendedSymbols) // π
        tapKey("symbols", layer: .extendedSymbols)        // ?123
        tapKey(row: 1, index: 1, layer: .symbols)         // #
        tapKey("layer", layer: .symbols)                  // ABC
        tapKey("y")

        print("=== C round trip typed: '\(typedText)'")
        XCTAssertEqual(typedText, "X7π#y")
    }

    // MARK: - Helpers

    /// The layer's own identity check: a glyph that exists only on that layer must be drawn.
    private func assertLayerShows(_ glyph: String, _ message: String) {
        let element = labelElement(glyph)
        XCTAssertTrue(element.waitForExistence(timeout: 3), "\(message) (no '\(glyph)' key on screen)")
    }
}
