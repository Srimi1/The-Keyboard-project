import CoreGraphics

/// A key with its absolute rect inside the key area.
struct PositionedKey: Identifiable, Equatable {
    var id: String { key.id }
    let key: Key
    let rect: CGRect
}

/// Turns the percentage-based layout ([UI-SPEC.md](../../docs/UI-SPEC.md) §1) into absolute
/// rects.
///
/// Rendering and hit-testing both read from this one computation, so the drawn key and the
/// touchable key can never drift apart — which is the usual source of "I pressed A and got S"
/// bugs in hand-rolled keyboards.
enum KeyboardMetrics {

    static func positionedKeys(rows: [KeyRow], in size: CGSize) -> [PositionedKey] {
        guard size.width > 0, !rows.isEmpty else { return [] }

        let rowHeight = self.rowHeight(rowCount: rows.count, in: size)
        var positioned: [PositionedKey] = []
        positioned.reserveCapacity(rows.reduce(0) { $0 + $1.keys.count })

        for (rowIndex, row) in rows.enumerated() {
            let y = KeyboardTheme.keyboardVerticalPadding
                + CGFloat(rowIndex) * (rowHeight + KeyboardTheme.rowSpacing)

            let inset = size.width * row.leadingInset
            let gapTotal = CGFloat(row.keys.count - 1) * KeyboardTheme.keySpacing
            let usableWidth = size.width - gapTotal - inset * 2
            let fractionSum = row.keys.reduce(0) { $0 + $1.widthFraction }
            guard fractionSum > 0, usableWidth > 0 else { continue }

            var x = inset
            for key in row.keys {
                let width = usableWidth * (key.widthFraction / fractionSum)
                positioned.append(
                    PositionedKey(key: key, rect: CGRect(x: x, y: y, width: width, height: rowHeight))
                )
                x += width + KeyboardTheme.keySpacing
            }
        }

        return positioned
    }

    static func rowHeight(rowCount: Int, in size: CGSize) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let spacing = CGFloat(rowCount - 1) * KeyboardTheme.rowSpacing
        let available = size.height - spacing - KeyboardTheme.keyboardVerticalPadding * 2
        guard available > 0 else { return preferredRowHeight(forWidth: size.width) }
        return available / CGFloat(rowCount)
    }

    /// Row height derived from key width rather than hardcoded per device.
    ///
    /// A letter key is 10% of the keyboard's width, so tying height to that keeps keys the
    /// same shape on every iPhone — which is what actually transfers muscle memory, and it
    /// adapts to device classes without a table of magic numbers. The ratio itself is a
    /// 📐 MEASURE item (UI-SPEC.md V-02/V-11): measure a real Gboard key's width-to-height
    /// ratio and replace it. Clamped so unusual widths cannot produce a comical keyboard.
    static func preferredRowHeight(forWidth width: CGFloat) -> CGFloat {
        let letterKeyWidth = width * 0.10
        let ratio: CGFloat = 1.35
        return min(max(letterKeyWidth * ratio, 44), 62)
    }

    /// Total height to request from the system, including the status/suggestion strip.
    static func preferredKeyboardHeight(rowCount: Int, width: CGFloat, stripHeight: CGFloat) -> CGFloat {
        let rowHeight = preferredRowHeight(forWidth: width)
        return CGFloat(rowCount) * rowHeight
            + CGFloat(max(rowCount - 1, 0)) * KeyboardTheme.rowSpacing
            + KeyboardTheme.keyboardVerticalPadding * 2
            + stripHeight
    }

    /// The key under a touch point.
    ///
    /// Hit rects are expanded by a hysteresis margin, so a finger that drifts slightly off a
    /// key keeps it rather than cancelling — real keyboards all do this, and without it fast
    /// typing drops characters. Overlap is resolved by distance to centre.
    static func key(at point: CGPoint, in keys: [PositionedKey], hysteresis: CGFloat = 0) -> PositionedKey? {
        var best: (key: PositionedKey, distance: CGFloat)?

        for positioned in keys {
            let hitRect = positioned.rect.insetBy(dx: -hysteresis, dy: -hysteresis)
            guard hitRect.contains(point) else { continue }

            let centre = CGPoint(x: positioned.rect.midX, y: positioned.rect.midY)
            let distance = hypot(point.x - centre.x, point.y - centre.y)
            if best == nil || distance < best!.distance {
                best = (positioned, distance)
            }
        }

        return best?.key
    }
}
