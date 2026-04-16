import Foundation

/// Derives human-readable transcript text from stored API response bodies (e.g. strips JSON wrappers).
enum TranscriptionDisplayText {

    /// Plain transcript for UI, clipboard, and web clients.
    static func plain(from stored: String) -> String {
        let t = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }

        if t.contains("\n") {
            let lines = t.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if lines.count > 1, lines.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") }) {
                let pieces = lines.compactMap { extractFromSingleJSONObject($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                if !pieces.isEmpty {
                    return pieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        if t.hasPrefix("{"), let extracted = extractFromSingleJSONObject(t) {
            return extracted
        }

        return t
    }

    private static func extractFromSingleJSONObject(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let text = root["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return text
            }
        }

        if let segments = root["segments"] as? [[String: Any]], !segments.isEmpty {
            let parts = segments
                .compactMap { $0["text"] as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty {
                return parts.joined(separator: " ")
            }
        }

        if let text = root["text"] as? String {
            return text
        }

        return nil
    }
}
