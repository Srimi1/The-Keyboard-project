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

    func makeUIView(context: Context) -> MultiTouchView {
        let view = MultiTouchView()
        view.onTouches = onTouches
        return view
    }

    func updateUIView(_ view: MultiTouchView, context: Context) {
        view.onTouches = onTouches
    }
}

final class MultiTouchView: UIView {

    var onTouches: (([KeyboardTouch]) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isExclusiveTouch = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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
        onTouches(touches.map {
            KeyboardTouch(id: ObjectIdentifier($0), phase: phase, location: $0.location(in: self))
        })
    }
}
