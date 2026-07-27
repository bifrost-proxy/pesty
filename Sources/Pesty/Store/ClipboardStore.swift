import AppKit
import Observation
import OSLog

enum BarSource: Equatable {
    case history
    case pinboard(UUID)
}

@Observable
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()

    private(set) var history: [ClipItem] = []
    private(set) var pinboards: [Pinboard] = []

    var source: BarSource = .history
    var searchText: String = ""
    var selectedID: UUID?

    var historyLimit: Int {
        get { Settings.shared.historyLimit }
        set { Settings.shared.historyLimit = newValue; trimHistory() }
    }

    private var storeURL: URL
    private var imagesDir: URL
    private var baseDir: URL
    private var saveWorkItem: DispatchWorkItem?

    private var fileWatch: DispatchSourceFileSystemObject?
    private var ignoreWatchUntil: Date = .distantPast
    private let logger = Logger(subsystem: "com.bifrostproxy.pesty", category: "clipboard-store")

    static var localBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pesty", isDirectory: true)
    }

    static var automatedTestBase: URL? {
        guard let path = ProcessInfo.processInfo.environment["PESTY_AUTOMATED_TEST_DATA_DIR"],
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static var iCloudBase: URL? {
        guard !isSandboxed else { return nil }
        let p = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: p.path) else { return nil }
        return p.appendingPathComponent("Pesty", isDirectory: true)
    }

    var iCloudAvailable: Bool { ClipboardStore.iCloudBase != nil }

    private init() {
        let base = ClipboardStore.automatedTestBase
            ?? (Settings.shared.iCloudSync ? ClipboardStore.iCloudBase : nil)
            ?? ClipboardStore.localBase
        baseDir = base
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        storeURL = base.appendingPathComponent("store.json")
        prepareDirectories()
        load()
        if Settings.shared.iCloudSync && ClipboardStore.automatedTestBase == nil {
            startWatching()
        }
    }

    private func prepareDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDir.path)
    }

    var visibleItems: [ClipItem] {
        let base: [ClipItem]
        switch source {
        case .history:
            base = history
        case .pinboard(let id):
            base = pinboards.first(where: { $0.id == id })?.items ?? []
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { $0.searchableText.contains(q) }
    }

    var selectedItem: ClipItem? {
        guard let id = selectedID else { return nil }
        return visibleItems.first(where: { $0.id == id })
    }

    func addCaptured(_ item: ClipItem) {
        if let idx = history.firstIndex(where: { $0.sameContent(as: item) }) {
            if item.imageFileName != history[idx].imageFileName { deleteImageFile(item) }
            var existing = history.remove(at: idx)
            existing.createdAt = item.createdAt
            history.insert(existing, at: 0)
            if source == .history && searchText.isEmpty { selectedID = existing.id }
            scheduleSave()
            return
        }
        history.insert(item, at: 0)
        trimHistory()
        if source == .history && searchText.isEmpty {
            selectedID = item.id
        }
        scheduleSave()
    }

    func applyHistoryLimit() { trimHistory(); scheduleSave() }

    private func trimHistory() {
        guard history.count > historyLimit else { return }
        let removed = Array(history[historyLimit...])
        history.removeLast(history.count - historyLimit)
        for item in removed { deleteImageFile(item) }
    }

    func delete(_ item: ClipItem) {
        let visibleBeforeDeletion = visibleItems
        let deletedSelectionIndex = selectedID == item.id
            ? visibleBeforeDeletion.firstIndex(where: { $0.id == item.id })
            : nil
        let preferredSelectionID = deletedSelectionIndex.flatMap { index -> UUID? in
            if index + 1 < visibleBeforeDeletion.count {
                return visibleBeforeDeletion[index + 1].id
            }
            if index > 0 {
                return visibleBeforeDeletion[index - 1].id
            }
            return nil
        }

        history.removeAll { $0.id == item.id }
        for i in pinboards.indices { pinboards[i].items.removeAll { $0.id == item.id } }
        deleteImageFile(item)
        if selectedID == item.id {
            let remainingIDs = Set(visibleItems.map(\.id))
            selectedID = preferredSelectionID.flatMap {
                remainingIDs.contains($0) ? $0 : nil
            } ?? visibleItems.first?.id
        }
        scheduleSave()
    }

    @discardableResult
    func deleteSelectedItem() -> Bool {
        guard let selectedItem else { return false }
        delete(selectedItem)
        return true
    }

    func clearHistory() {
        let old = history
        history.removeAll()
        selectedID = nil
        for item in old { deleteImageFile(item) }
        scheduleSave()
    }

    func removeAutomatedTestItems(withTexts texts: Set<String>) {
        let removedIDs = Set<UUID>(history.compactMap { item in
            guard let text = item.text, texts.contains(text) else { return nil }
            return item.id
        })
        guard !removedIDs.isEmpty else { return }
        history.removeAll { removedIDs.contains($0.id) }
        if let selectedID, removedIDs.contains(selectedID) {
            selectFirst()
        }
        saveNow()
    }

    func replaceHistoryForAutomatedPerformanceTest(_ items: [ClipItem]) {
        let environment = ProcessInfo.processInfo.environment
        guard ClipboardStore.automatedTestBase != nil,
              environment["PESTY_AUTOMATED_UI_TEST"] == "performance" else { return }
        history = items
        pinboards = []
        source = .history
        searchText = ""
        selectedID = items.first?.id
        saveNow()
    }

    func replaceHistoryForAutomatedKeyboardTest(_ items: [ClipItem]) {
        let environment = ProcessInfo.processInfo.environment
        guard ClipboardStore.automatedTestBase != nil,
              environment["PESTY_AUTOMATED_UI_TEST"] == "keyboard-delete" else { return }
        history = items
        pinboards = []
        source = .history
        searchText = ""
        selectedID = items.first?.id
        saveNow()
    }

    @discardableResult
    func addPinboard(name: String, colorHex: String = "#5B8DEF") -> Pinboard {
        let b = Pinboard(name: name, colorHex: colorHex)
        pinboards.append(b)
        scheduleSave()
        return b
    }

    func renamePinboard(_ id: UUID, to name: String) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }) else { return }
        pinboards[i].name = name
        scheduleSave()
    }

    func deletePinboard(_ id: UUID) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }) else { return }
        if case .pinboard(let cur) = source, cur == id { source = .history }
        let removedItems = pinboards[i].items
        pinboards.remove(at: i)
        for item in removedItems { deleteImageFile(item) }
        scheduleSave()
    }

    func saveToPinboard(_ item: ClipItem, boardID: UUID) {
        guard let i = pinboards.firstIndex(where: { $0.id == boardID }) else { return }
        if pinboards[i].items.contains(where: { $0.sameContent(as: item) }) { return }
        var copy = item
        if let dup = duplicateImageFile(item) { copy.imageFileName = dup }
        pinboards[i].items.insert(copy, at: 0)
        scheduleSave()
    }

    func setTitle(_ title: String, for item: ClipItem) {
        if let i = history.firstIndex(where: { $0.id == item.id }) { history[i].customTitle = title }
        for b in pinboards.indices {
            if let i = pinboards[b].items.firstIndex(where: { $0.id == item.id }) {
                pinboards[b].items[i].customTitle = title
            }
        }
        scheduleSave()
    }

    func selectFirst() { selectedID = visibleItems.first?.id }

    func moveSelection(by delta: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else {
            selectedID = items.first?.id; return
        }
        let next = max(0, min(items.count - 1, idx + delta))
        selectedID = items[next].id
    }

    func imageURL(for item: ClipItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return imagesDir.appendingPathComponent(name)
    }

    func loadImage(for item: ClipItem) -> NSImage? {
        guard let url = imageURL(for: item) else { return nil }
        return NSImage(contentsOf: url)
    }

    func storeImageData(_ data: Data) -> String? {
        let name = "\(UUID().uuidString).png"
        let url = imagesDir.appendingPathComponent(name)
        do {
            try data.write(to: url)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return name
        } catch { return nil }
    }

    private func duplicateImageFile(_ item: ClipItem) -> String? {
        guard let src = imageURL(for: item), FileManager.default.fileExists(atPath: src.path) else { return nil }
        let name = "\(UUID().uuidString).png"
        let dst = imagesDir.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: src, to: dst)
            return name
        } catch {
            return nil
        }
    }

    private func deleteImageFile(_ item: ClipItem) {
        guard let name = item.imageFileName else { return }
        let stillUsed = history.contains { $0.imageFileName == name }
            || pinboards.contains { $0.items.contains { $0.imageFileName == name } }
        if stillUsed { return }
        if let url = imageURL(for: item) { try? FileManager.default.removeItem(at: url) }
    }

    private struct Snapshot: Codable {
        var history: [ClipItem]
        var pinboards: [Pinboard]
    }

    private func load() {
        if let snap = readSnapshot(at: storeURL) {
            history = snap.history
            pinboards = snap.pinboards
        }
        reconcileFromDisk()
        selectFirst()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        _ = writeSnapshot()
    }

    @discardableResult
    private func writeSnapshot() -> Bool {
        let snap = Snapshot(history: history, pinboards: pinboards)
        let data: Data
        do {
            data = try JSONEncoder().encode(snap)
        } catch {
            logger.error("Failed to encode clipboard history: \(error.localizedDescription, privacy: .public)")
            return false
        }

        ignoreWatchUntil = Date().addingTimeInterval(1.5)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: storeURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: coordinatedURL.path
                )
            } catch {
                writeError = error
            }
        }

        if let error = coordinationError ?? writeError as NSError? {
            logger.error("Failed to save clipboard history: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return true
    }

    func setICloudSync(_ enabled: Bool) {
        stopWatching()
        let target = (enabled ? ClipboardStore.iCloudBase : ClipboardStore.localBase) ?? ClipboardStore.localBase
        let newImages = target.appendingPathComponent("images", isDirectory: true)
        let newStore = target.appendingPathComponent("store.json")
        let fm = FileManager.default
        try? fm.createDirectory(at: newImages, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])

        if fm.fileExists(atPath: newStore.path),
           let snap = readSnapshot(at: newStore) {
            copyImages(from: imagesDir, to: newImages)
            baseDir = target; imagesDir = newImages; storeURL = newStore
            _ = mergeExternal(snap)
            saveNow()
        } else {
            copyImages(from: imagesDir, to: newImages)
            baseDir = target; imagesDir = newImages; storeURL = newStore
            saveNow()
        }
        prepareDirectories()
        if enabled { startWatching() }
    }

    private func copyImages(from src: URL, to dst: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "png" {
            let target = dst.appendingPathComponent(f.lastPathComponent)
            if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: f, to: target) }
        }
    }

    private func contentKey(_ item: ClipItem) -> String {
        switch item.type {
        case .image: return "img:" + (item.imageHash ?? item.imageFileName ?? item.id.uuidString)
        case .color: return "col:" + (item.colorHex ?? "")
        case .file:  return "file:" + item.fileURLs.joined(separator: "|")
        default:     return "txt:" + (item.text ?? "")
        }
    }

    @discardableResult
    private func mergeExternal(_ snap: Snapshot) -> Bool {
        let previousHistory = history
        let previousPinboards = pinboards
        var combined = (history + snap.history).sorted { $0.createdAt > $1.createdAt }
        var seen = Set<String>()
        var merged: [ClipItem] = []
        for it in combined where seen.insert(contentKey(it)).inserted { merged.append(it) }
        history = Array(merged.prefix(historyLimit))

        var byID: [UUID: Pinboard] = Dictionary(uniqueKeysWithValues: pinboards.map { ($0.id, $0) })
        for b in snap.pinboards {
            if var existing = byID[b.id] {
                for it in b.items where !existing.items.contains(where: { $0.sameContent(as: it) }) {
                    existing.items.append(it)
                }
                byID[b.id] = existing
            } else {
                byID[b.id] = b
            }
        }
        pinboards = pinboards.map { byID[$0.id] ?? $0 }
            + byID.values.filter { b in !pinboards.contains(where: { $0.id == b.id }) }

        combined.removeAll()
        selectFirst()
        return history != previousHistory || pinboards != previousPinboards
    }

    private func readSnapshot(at url: URL) -> Snapshot? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                logger.error("Failed to read clipboard history: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    /// Reconciles the in-memory store with both the current iCloud file and any
    /// conflict versions. The merged snapshot is written before conflicts are
    /// marked resolved, so no clipboard entries are discarded.
    func reconcileFromDisk() {
        var changed = false
        if let snap = readSnapshot(at: storeURL) {
            changed = mergeExternal(snap)
        }

        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: storeURL) ?? []
        for version in conflicts {
            guard let snap = readSnapshot(at: version.url) else { continue }
            changed = mergeExternal(snap) || changed
        }

        guard changed || !conflicts.isEmpty else { return }
        guard writeSnapshot() else { return }

        for version in conflicts {
            version.isResolved = true
        }
        if !conflicts.isEmpty {
            do {
                try NSFileVersion.removeOtherVersionsOfItem(at: storeURL)
                logger.info("Merged and resolved \(conflicts.count, privacy: .public) clipboard history conflict version(s)")
            } catch {
                logger.error("Failed to remove resolved history versions: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func startWatching() {
        stopWatching()
        let fd = open(storeURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let event = src.data
            let needsReattach = event.contains(.rename) || event.contains(.delete)

            if Date() >= self.ignoreWatchUntil,
               let snap = self.readSnapshot(at: self.storeURL),
               self.mergeExternal(snap) {
                self.saveNow()
            }

            if needsReattach {
                DispatchQueue.main.async { [weak self] in
                    self?.startWatching()
                }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileWatch = src
    }

    private func stopWatching() {
        fileWatch?.cancel()
        fileWatch = nil
    }
}
