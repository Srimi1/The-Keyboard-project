import SwiftUI
import UIKit

/// One touch's progress, identified so several fingers can be tracked at once.
struct KeyboardTouch: Equatable {
    enum Phase { case began, moved, ended, cancelled }

    /// Stable for the lifetime of one touch sequence. UIKit recycles `UITouch` objects
    /// between sequences, which is exactly the lifetime we need.
    let id: ObjectIdentifier
    let phase: Phase
    let location: CGPoint
}

/// Raw multi-touch capture for the key area.
///
/// SwiftUI cannot express keyboard touch handling: a `DragGesture` tracks one logical drag,
/// so pressing a second key before releasing the first — which is how anyone types quickly —
/// either drops a character or cancels the first key. UIKit's `touchesBegan/Moved/Ended`
/// reports every finger independently, which is what rollover needs.
///
/// SwiftUI still renders the keys; this view only reports where fingers are.
struct TouchTracker: UIViewRepresentable {
    let onTouches: ([KeyboardTouch]) -> Void
    /// Areas this layer must not consume, so the UIKit views beneath it stay reachable —
    /// currently the globe key, which has to be a real UIButton (C-47).
    var passthroughRects: [CGRect] = []

    func makeUIView(context: Context) -> MultiTouchView {
        let view = MultiTouchView()
        view.onTouches = onTouches
        view.passthroughRects = passthroughRects
        return view
    }

    func updateUIView(_ view: MultiTouchView, context: Context) {
        view.onTouches = onTouches
        view.passthroughRects = passthroughRects
    }
}

final class MultiTouchView: UIView {

    var onTouches: (([KeyboardTouch]) -> Void)?
    var passthroughRects: [CGRect] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Off by default. The symptom of forgetting it is not "no rollover" but "the second
        // key is silently dropped", which is indistinguishable from a bad hit test.
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isExclusiveTouch = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// This view sits above the drawn keys and consumes everything, which would leave any
    /// real UIKit control underneath unreachable. Returning nil lets those points fall
    /// through to the view below.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if passthroughRects.contains(where: { $0.contains(point) }) { return nil }
        return super.hitTest(point, with: event)
    }

    // Deliberately no `super` calls: the default implementations forward up the responder
    // chain, letting an ancestor re-handle a touch this view already consumed.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: .began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: .moved)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: .ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: .cancelled)
    }

    private func report(_ touches: Set<UITouch>, phase: KeyboardTouch.Phase) {
        guard let onTouches else { return }

        // `touches` is a Set: two fingers landing in one event arrive in arbitrary order,
        // which silently corrupts rollover ordering. Sort by when they actually happened.
        let ordered = touches.sorted { $0.timestamp < $1.timestamp }

        onTouches(ordered.map {
            KeyboardTouch(id: ObjectIdentifier($0), phase: phase, location: $0.location(in: self))
        })
    }
}
