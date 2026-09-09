import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    var maxItems: Int {
        didSet { trim(); scheduleSave() }
    }

    private var saveWorkItem: DispatchWorkItem?

    init(maxItems: Int = 50) {
        self.maxItems = maxItems
        load()
    }

    // MARK: - Mutations

    func add(text: String, concealed: Bool) {
        // An identical entry moves back to the top instead of doubling up.
        if let index = items.firstIndex(where: { $0.text == text }) {
            var existing = items.remove(at: index)
            existing.createdAt = Date()
            existing.concealed = existing.concealed || concealed
            insert(existing)
        } else {
            insert(ClipItem(text: text, concealed: concealed))
        }
        trim()
        scheduleSave()
    }

    func togglePin(_ id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.pinned.toggle()
        insert(item)
        scheduleSave()
    }

    func remove(_ id: ClipItem.ID) {
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Forgets unpinned entries older than `hours`. Pinning means "keep this", so it
    /// survives expiry just as it survives the clear button.
    /// - Returns: how many were removed, for logging.
    @discardableResult
    func expire(olderThanHours hours: Int) -> Int {
        guard hours > 0 else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let before = items.count
        items.removeAll { !$0.pinned && $0.createdAt < cutoff }
        let removed = before - items.count
        if removed > 0 { scheduleSave() }
        return removed
    }

    /// Pinning is a deliberate "keep this", so the panel's clear button uses this and
    /// leaves pinned entries alone. Removing those stays a per-item action.
    func clearUnpinned() {
        items.removeAll { !$0.pinned }
        scheduleSave()
    }

    func clearAll() {
        items.removeAll()
        scheduleSave()
    }

    // MARK: - Ordering

    /// Pinned items sit above unpinned ones; within each group, newest first.
    private func insert(_ item: ClipItem) {
        let position = items.firstIndex { candidate in
            if item.pinned != candidate.pinned { return item.pinned }
            return item.createdAt > candidate.createdAt
        }
        items.insert(item, at: position ?? items.count)
    }

    private func trim() {
        guard items.count > maxItems else { return }
        // Pinned items are never dropped by the cap — they are at the front, and
        // trimming from the back only ever reaches unpinned entries unless the
        // user has pinned more than the cap allows.
        items.removeLast(items.count - maxItems)
    }

    // MARK: - Persistence

    private var storageURL: URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.michaelsmith.toothpaste", isDirectory: true)
        return directory.appendingPathComponent("history.json")
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.save() }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func save() {
        // Only pinned entries are persisted. The history is a session thing: whatever
        // you copied today is gone when the app restarts, and pinning is how you say
        // "this one should outlive the session".
        //
        // Concealed items are excluded even when pinned. A password manager marked
        // them secret, and writing a secret to a plain-text file because someone
        // pinned it would quietly undo that.
        let persistable = items.filter { $0.pinned && !$0.concealed }

        let url = storageURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(persistable).write(to: url, options: .atomic)
        } catch {
            NSLog("Toothpaste: could not save history: \(error.localizedDescription)")
        }
    }

    private func load() {
        let url = storageURL

        // No file at all is the normal first run.
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([ClipItem].self, from: try Data(contentsOf: url))
            trim()
        } catch {
            // The file exists but could not be read. Starting empty here would be
            // fine on its own — the damage is that the next save then writes over it,
            // turning a transient read failure into permanent loss. Move it aside so
            // there is always something left to recover from.
            let stamp = Int(Date().timeIntervalSince1970)
            let rescued = url.deletingLastPathComponent()
                .appendingPathComponent("history.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: rescued)
            NSLog("Toothpaste: history unreadable (\(error.localizedDescription)); kept it as \(rescued.lastPathComponent)")
        }
    }
}
