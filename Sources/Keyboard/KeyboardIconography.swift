import Foundation

/// Semantic icon names keep toolbar and function-key imagery consistent across themes.
/// SF Symbols are vector, localized where appropriate, and do not increase extension size.
enum KeyboardIconography {
    static let clipboard = "doc.on.clipboard"
    static let clipboardFilled = "doc.on.clipboard.fill"
    static let settings = "gearshape"
    static let keyboard = "keyboard"
    static let shift = "shift"
    static let shiftActive = "shift.fill"
    static let backspace = "delete.left"
    static let globe = "globe"
    static let returnArrow = "return"

    static func symbolName(for key: Key, isActive: Bool) -> String? {
        switch key.action {
        case .shift:
            isActive ? shiftActive : shift
        case .backspace:
            backspace
        case .newline where key.label.lowercased() == "return":
            returnArrow
        default:
            nil
        }
    }
}
