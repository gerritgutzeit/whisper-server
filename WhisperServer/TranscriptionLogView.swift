import AppKit
import SwiftUI

/// Full transcription history browser (list + detail + search).
struct TranscriptionLogView: View {
    @StateObject private var model = TranscriptionLogViewModel()

    private static let listDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationSplitView {
            listColumn
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
        } detail: {
            detailColumn
        }
        .searchable(text: $model.searchText, prompt: "Search text or filename")
        .onAppear {
            model.refreshFromStore()
        }
        .onChange(of: model.searchText) { _, _ in
            model.ensureSelectionVisibleInFilter()
        }
        .onChange(of: model.filteredEntries.count) { _, _ in
            model.ensureSelectionVisibleInFilter()
        }
    }

    private var listColumn: some View {
        Group {
            if model.filteredEntries.isEmpty {
                ContentUnavailableView(
                    model.entries.isEmpty ? "No transcriptions" : "No matches",
                    systemImage: "text.bubble",
                    description: Text(
                        model.entries.isEmpty
                            ? "Successful API transcriptions will appear here."
                            : "Try a different search term."
                    )
                )
            } else {
                List(selection: $model.selectionId) {
                    ForEach(model.filteredEntries) { entry in
                        row(for: entry)
                            .tag(entry.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear all", role: .destructive) {
                    clearWithConfirmation()
                }
                .disabled(model.entries.isEmpty)
            }
        }
        .navigationTitle("Transcription log")
    }

    private func row(for entry: TranscriptionHistoryStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.listDateFormatter.string(from: entry.date))
                .font(.subheadline.weight(.semibold))
            if let name = entry.sourceFilename, !name.isEmpty {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(previewLine(TranscriptionDisplayText.plain(from: entry.fullText)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func previewLine(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 120 else { return collapsed.isEmpty ? "—" : collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 120)
        return String(collapsed[..<end]) + "…"
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let entry = model.selectedEntry {
            let displayed = TranscriptionDisplayText.plain(from: entry.fullText)
            ScrollView {
                Text(displayed)
                    .font(detailFont(for: displayed))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        copyToPasteboard(displayed)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle(entry.sourceFilename ?? "Transcript")
            .navigationSubtitle(Self.listDateFormatter.string(from: entry.date))
        } else {
            ContentUnavailableView(
                "Select an entry",
                systemImage: "arrow.left",
                description: Text("Choose a row in the list or run a transcription.")
            )
        }
    }

    private func detailFont(for text: String) -> Font {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("{") || t.hasPrefix("[") {
            return .system(.body, design: .monospaced)
        }
        if t.contains("-->") {
            return .system(.body, design: .monospaced)
        }
        return .body
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func clearWithConfirmation() {
        guard !model.entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Clear all transcriptions?"
        alert.informativeText = "This removes every item from the log. The action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.clearAll()
        }
    }
}

#if DEBUG
#Preview {
    TranscriptionLogView()
        .frame(width: 800, height: 560)
}
#endif
