import Combine
import Foundation

@MainActor
final class TranscriptionLogViewModel: ObservableObject {
    @Published private(set) var entries: [TranscriptionHistoryStore.Entry] = []
    @Published var selectionId: UUID?
    @Published var searchText: String = ""

    private var cancellables = Set<AnyCancellable>()

    var filteredEntries: [TranscriptionHistoryStore.Entry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { entry in
            let plain = TranscriptionDisplayText.plain(from: entry.fullText).lowercased()
            if plain.contains(q) { return true }
            if entry.fullText.lowercased().contains(q) { return true }
            if let name = entry.sourceFilename?.lowercased(), name.contains(q) { return true }
            return false
        }
    }

    var selectedEntry: TranscriptionHistoryStore.Entry? {
        guard let selectionId else { return nil }
        return entries.first { $0.id == selectionId }
    }

    init() {
        refreshFromStore()
        NotificationCenter.default.publisher(for: .transcriptionHistoryDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshFromStore()
            }
            .store(in: &cancellables)
    }

    func refreshFromStore() {
        entries = TranscriptionHistoryStore.shared.recentEntries()
        if let sid = selectionId, entries.contains(where: { $0.id == sid }) {
            ensureSelectionVisibleInFilter()
            return
        }
        selectionId = entries.first?.id
        ensureSelectionVisibleInFilter()
    }

    func clearAll() {
        TranscriptionHistoryStore.shared.clear()
        selectionId = nil
    }

    /// Keeps selection consistent when search filters the list.
    func ensureSelectionVisibleInFilter() {
        let visible = filteredEntries
        guard let sid = selectionId else {
            selectionId = visible.first?.id
            return
        }
        if !visible.contains(where: { $0.id == sid }) {
            selectionId = visible.first?.id
        }
    }
}
