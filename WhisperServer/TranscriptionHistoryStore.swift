import Foundation

/// Thread-safe ring buffer of completed transcriptions for the menu bar log.
final class TranscriptionHistoryStore {
    static let shared = TranscriptionHistoryStore()

    struct Entry: Sendable, Identifiable, Hashable {
        let id: UUID
        let date: Date
        /// Original upload filename when available.
        let sourceFilename: String?
        /// Plain text for clipboard (may be long subtitle/JSON body).
        let fullText: String

        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let maxEntries = 20
    private let maxStoredCharacters = 150_000

    private init() {}

    /// Appends a new entry (newest first). Posts `transcriptionHistoryDidUpdate` on success.
    func record(completedText: String, sourceFilename: String?) {
        let trimmed = completedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let capped: String
        if trimmed.count > maxStoredCharacters {
            capped = String(trimmed.prefix(maxStoredCharacters))
        } else {
            capped = trimmed
        }

        let entry = Entry(
            id: UUID(),
            date: Date(),
            sourceFilename: sourceFilename.flatMap { $0.isEmpty ? nil : $0 },
            fullText: capped
        )

        lock.lock()
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        lock.unlock()

        NotificationCenter.default.post(name: .transcriptionHistoryDidUpdate, object: self)
    }

    func recentEntries() -> [Entry] {
        lock.lock()
        let copy = entries
        lock.unlock()
        return copy
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        NotificationCenter.default.post(name: .transcriptionHistoryDidUpdate, object: self)
    }
}

/// Accumulates transcript text from streaming callbacks (escaping closures cannot mutate outer `var` reliably).
final class TranscriptAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var parts: [String] = []

    func append(_ fragment: String) {
        let t = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lock.lock()
        parts.append(t)
        lock.unlock()
    }

    func combined(separator: String = " ") -> String {
        lock.lock()
        let joined = parts.joined(separator: separator)
        lock.unlock()
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
