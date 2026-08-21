import CoreGraphics

/// A key with both the rect it is drawn in and the rect it responds to.
///
/// These differ deliberately: hit rects **tile the whole key area with no holes**, so the gaps
/// between keys and the margins at the edges belong to their nearest key rather than being
/// dead zones that swallow keystrokes.
struct PositionedKey: Identifiable, Equatable {
    var id: String { key.id }
    let key: Key
    /// What is drawn.
    let rect: CGRect
    /// What is touchable — larger, and tiled edge to edge.
    let hitRect: CGRect
}

/// Turns the percentage-based layout ([UI-SPEC.md](../../docs/UI-SPEC.md) §1) into absolute
/// rects.
///
/// Rendering and hit-testing both read from this one computation, so the drawn key and the
/// touchable key can never drift apart — the usual source of "I pressed A and got S".
enum KeyboardMetrics {

    /// Below this the geometry is one of the garbage sizes iOS hands a keyboard extension
    /// while it settles (0×0, then full-screen, then a wrong height) — solving against those
    /// produces a layout that is thrown away and, worse, hit rects that are briefly wrong.
    private static let minimumPlausibleSize = CGSize(width: 120, height: 60)

    static func isPlausible(_ size: CGSize) -> Bool {
        size.width >= minimumPlausibleSize.width && size.height >= minimumPlausibleSize.height
    }

    static func positionedKeys(rows: [KeyRow], in size: CGSize) -> [PositionedKey] {
        guard isPlausible(size), !rows.isEmpty else { return [] }

        let rowHeight = self.rowHeight(rowCount: rows.count, in: size)
        var positioned: [PositionedKey] = []
        positioned.reserveCapacity(rows.reduce(0) { $0 + $1.keys.count })

        for (rowIndex, row) in rows.enumerated() where !row.keys.isEmpty {
            let y = KeyboardTheme.keyboardVerticalPadding
                + CGFloat(rowIndex) * (rowHeight + KeyboardTheme.rowSpacing)

            // --- what gets drawn ---
            let inset = size.width * row.leadingInset
            let gapTotal = CGFloat(row.keys.count - 1) * KeyboardTheme.keySpacing
            let usableWidth = size.width - gapTotal - inset * 2
            let fractionSum = row.keys.reduce(0) { $0 + $1.widthFraction }
            guard fractionSum > 0, usableWidth > 0 else { continue }

            var visualRects: [CGRect] = []
            visualRects.reserveCapacity(row.keys.count)
            var x = inset
            for key in row.keys {
                let width = usableWidth * (key.widthFraction / fractionSum)
                visualRects.append(CGRect(x: x, y: y, width: width, height: rowHeight))
                x += width + KeyboardTheme.keySpacing
            }

            // --- what responds to touch ---
            // Vertical: split the row gap with the neighbouring row; the first and last rows
            // claim all the way to the keyboard's edges.
            let hitTop = rowIndex == 0 ? 0 : y - KeyboardTheme.rowSpacing / 2
            let hitBottom = rowIndex == rows.count - 1
                ? size.height
                : y + rowHeight + KeyboardTheme.rowSpacing / 2

            for (index, visual) in visualRects.enumerated() {
                // Horizontal: split the gap with each neighbour; the first and last keys claim
                // the row's inset and the screen edge — which is what makes the home row's
                // half-key inset touchable rather than dead.
                let hitLeft = index == 0
                    ? 0
                    : (visualRects[index - 1].maxX + visual.minX) / 2
                let hitRight = index == visualRects.count - 1
                    ? size.width
                    : (visual.maxX + visualRects[index + 1].minX) / 2

                positioned.append(
                    PositionedKey(
                        key: row.keys[index],
                        rect: visual,
                        hitRect: CGRect(x: hitLeft, y: hitTop, width: hitRight - hitLeft, height: hitBottom - hitTop)
                    )
                )
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
    /// 📐 MEASURE item (UI-SPEC.md V-02/V-11). Clamped so an unusual width cannot produce a
    /// comical keyboard.
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

    /// The key under a touch point. Hit rects tile the area, so any point inside the keyboard
    /// resolves to exactly one key.
    static func key(at point: CGPoint, in keys: [PositionedKey]) -> PositionedKey? {
        keys.first { $0.hitRect.contains(point) }
    }

    /// Whether a moving finger is still on the key it started on.
    ///
    /// Measured from the **visual** rect, not the hit rect: the hit rect already extends half a
    /// gap past the key, so measuring from it would make the effective slack larger than
    /// intended and slide-to-correct feel sticky.
    static func isStillOnKey(_ point: CGPoint, key: PositionedKey, hysteresis: CGFloat) -> Bool {
        key.rect.insetBy(dx: -hysteresis, dy: -hysteresis).contains(point)
    }
}
