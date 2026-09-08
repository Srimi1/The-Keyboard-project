import CryptoKit
import Foundation

/// One text item retained in the on-device clipboard history.
nonisolated struct ClipboardItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var createdAt: Date
    var pinned: Bool
    var contentHash: String
    var sourceHint: String?
    /// True when the source exceeded the per-item byte budget.
    var wasTruncated: Bool

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date,
        pinned: Bool = false,
        sourceHint: String? = nil,
        sourceWasTruncated: Bool = false
    ) {
        let stored = ClipboardLimits.truncate(text)
        self.id = id
        self.text = stored.text
        self.createdAt = createdAt
        self.pinned = pinned
        self.contentHash = ClipboardLimits.hash(stored.text)
        self.sourceHint = sourceHint
        self.wasTruncated = sourceWasTruncated || stored.wasTruncated
    }

    func hasExpired(at now: Date, retention: TimeInterval = ClipboardLimits.retention) -> Bool {
        !pinned && now.timeIntervalSince(createdAt) >= retention
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, createdAt, pinned, contentHash, sourceHint, wasTruncated
    }

    /// `wasTruncated` did not exist in the pre-launch prototype. Defaulting it preserves
    /// valid local history during the schema migration.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        pinned = try values.decode(Bool.self, forKey: .pinned)
        contentHash = try values.decode(String.self, forKey: .contentHash)
        sourceHint = try values.decodeIfPresent(String.self, forKey: .sourceHint)
        wasTruncated = try values.decodeIfPresent(Bool.self, forKey: .wasTruncated) ?? false
    }
}

nonisolated struct ClipboardTruncation: Equatable, Sendable {
    let text: String
    let wasTruncated: Bool
}

/// Hard memory and retention boundaries for the extension process.
nonisolated enum ClipboardLimits {
    static let retention: TimeInterval = 60 * 60
    static let maxTextBytes = 16 * 1024
    static let maxEncodedFileBytes = 2 * 1024 * 1024
    static let maxUnpinned = 50
    static let maxPinned = 25

    /// Truncates at an extended-grapheme boundary while enforcing a UTF-8 byte budget.
    /// Character-count limits are insufficient: one Swift `Character` may occupy many bytes.
    static func truncate(_ text: String) -> ClipboardTruncation {
        guard text.utf8.count > maxTextBytes else {
            return ClipboardTruncation(text: text, wasTruncated: false)
        }

        var stored = String()
        stored.reserveCapacity(maxTextBytes)
        var byteCount = 0
        for character in text {
            let characterBytes = String(character).utf8.count
            guard byteCount + characterBytes <= maxTextBytes else { break }
            stored.append(character)
            byteCount += characterBytes
        }
        return ClipboardTruncation(text: stored, wasTruncated: true)
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func isWorthStoring(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
