import Foundation

/// Pure clipboard history rules; persistence and clocks stay outside this value type.
nonisolated struct ClipboardHistory: Codable, Equatable, Sendable {
    private(set) var items: [ClipboardItem] = []

    init(items: [ClipboardItem] = []) {
        self.items = items
    }

    func visible(at now: Date) -> (pinned: [ClipboardItem], recent: [ClipboardItem]) {
        let live = items.filter { !$0.hasExpired(at: now) }
        return (
            pinned: live.filter(\.pinned).sorted { $0.createdAt > $1.createdAt },
            recent: live.filter { !$0.pinned }.sorted { $0.createdAt > $1.createdAt }
        )
    }

    func mostRecent(at now: Date) -> ClipboardItem? {
        items.filter { !$0.hasExpired(at: now) }.max { $0.createdAt < $1.createdAt }
    }

    var nextExpirationDate: Date? {
        items.lazy
            .filter { !$0.pinned }
            .map { $0.createdAt.addingTimeInterval(ClipboardLimits.retention) }
            .min()
    }

    enum InsertOutcome: Equatable, Sendable {
        case stored(ClipboardItem)
        case refreshed(ClipboardItem)
        case rejectedEmpty
    }

    @discardableResult
    mutating func insert(
        _ rawText: String,
        at now: Date,
        sourceWasTruncated: Bool = false
    ) -> InsertOutcome {
        let truncated = ClipboardLimits.truncate(rawText)
        let text = truncated.text
        guard ClipboardLimits.isWorthStoring(text) else { return .rejectedEmpty }

        let hash = ClipboardLimits.hash(text)
        if let index = items.firstIndex(where: { $0.contentHash == hash && $0.text == text }) {
            items[index].createdAt = now
            items[index].wasTruncated = items[index].wasTruncated
                || truncated.wasTruncated
                || sourceWasTruncated
            let refreshed = items[index]
            enforceCaps()
            return .refreshed(refreshed)
        }

        let item = ClipboardItem(
            text: rawText,
            createdAt: now,
            sourceWasTruncated: sourceWasTruncated
        )
        items.append(item)
        enforceCaps()
        return .stored(item)
    }

    enum PinOutcome: Equatable, Sendable {
        case changed
        case unchanged
        case notFound
        case pinnedSectionFull
    }

    @discardableResult
    mutating func setPinned(_ pinned: Bool, id: UUID) -> PinOutcome {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return .notFound }
        guard items[index].pinned != pinned else { return .unchanged }
        if pinned, items.lazy.filter(\.pinned).count >= ClipboardLimits.maxPinned {
            return .pinnedSectionFull
        }
        items[index].pinned = pinned
        enforceCaps()
        return .changed
    }

    @discardableResult
    mutating func delete(id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items.remove(at: index)
        return true
    }

    mutating func removeAll() {
        items.removeAll()
    }

    @discardableResult
    mutating func sweep(at now: Date) -> Int {
        let oldCount = items.count
        items.removeAll { $0.hasExpired(at: now) }
        return oldCount - items.count
    }

    func validate() throws {
        guard items.filter(\.pinned).count <= ClipboardLimits.maxPinned,
              items.filter({ !$0.pinned }).count <= ClipboardLimits.maxUnpinned else {
            throw ClipboardStoreError.invalidData("item count exceeds the configured cap")
        }
        guard Set(items.map(\.id)).count == items.count else {
            throw ClipboardStoreError.invalidData("duplicate item identifiers")
        }

        for item in items {
            guard ClipboardLimits.isWorthStoring(item.text) else {
                throw ClipboardStoreError.invalidData("empty clipboard item")
            }
            guard item.text.utf8.count <= ClipboardLimits.maxTextBytes else {
                throw ClipboardStoreError.invalidData("clipboard item exceeds the byte cap")
            }
            guard item.contentHash == ClipboardLimits.hash(item.text) else {
                throw ClipboardStoreError.invalidData("clipboard item hash mismatch")
            }
        }
    }

    private mutating func enforceCaps() {
        let pinned = items.filter(\.pinned).sorted { $0.createdAt > $1.createdAt }
        let recent = items.filter { !$0.pinned }.sorted { $0.createdAt > $1.createdAt }
        items = Array(pinned.prefix(ClipboardLimits.maxPinned))
            + Array(recent.prefix(ClipboardLimits.maxUnpinned))
    }
}
