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
        guard available > 0 else { return KeyboardTheme.keyRowHeight }
        return available / CGFloat(rowCount)
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
