import AppKit
import CryptoKit
import Observation
import OSLog

enum HistoryStorageUsage {
    static func bytes(in directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

enum BarSource: Equatable {
    case history
    case pinboard(UUID)
}

struct ClipDeletionTombstone: Codable, Equatable {
    let contentDigest: String
    let historyDeletedAt: Date
    let pinboardDeletedAt: Date?
}

struct ClipboardStoreSnapshot: Codable {
    var history: [ClipItem]
    var pinboards: [Pinboard]
    var configuration: SyncedConfiguration?
    var deletions: [ClipDeletionTombstone]? = nil
}

@Observable
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()

    private(set) var stripContentRevision: UInt64 = 0
    private(set) var history: [ClipItem] = [] {
        didSet { stripContentRevision &+= 1 }
    }
    private(set) var pinboards: [Pinboard] = [] {
        didSet { stripContentRevision &+= 1 }
    }
    private(set) var storageUsageBytes: Int64 = 0

    var source: BarSource = .history {
        didSet {
            if source != oldValue { stripContentRevision &+= 1 }
        }
    }
    var searchText: String = "" {
        didSet {
            if searchText != oldValue { stripContentRevision &+= 1 }
        }
    }
    var isSearchFieldActive = false
    var selectedID: UUID?

    private var storeURL: URL
    private var imagesDir: URL
    private var baseDir: URL
    private var saveWorkItem: DispatchWorkItem?
    private var historyLimitWorkItem: DispatchWorkItem?
    private var deletionTombstones: [String: ClipDeletionTombstone] = [:]
    @ObservationIgnored private var storageUsageTask: Task<Void, Never>?

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

    private var usesSharedConfiguration: Bool {
        Settings.shared.iCloudSync || ClipboardStore.automatedTestBase != nil
    }

    private init() {
        let base = ClipboardStore.automatedTestBase
            ?? (Settings.shared.iCloudSync ? ClipboardStore.iCloudBase : nil)
            ?? ClipboardStore.localBase
        baseDir = base
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        storeURL = base.appendingPathComponent("store.json")
        prepareDirectories()
        load()
        resumeDeferredHistoryLimitTrim()
        refreshStorageUsage()
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

    func addCaptured(_ capturedItem: ClipItem) {
        var item = capturedItem
        if let deletedAt = deletionTombstones[
            contentDigest(item)
        ]?.historyDeletedAt,
           deletedAt >= item.createdAt {
            item.createdAt = deletedAt.addingTimeInterval(0.001)
        }
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

    func promoteToFront(_ item: ClipItem) {
        switch source {
        case .history:
            guard let index = history.firstIndex(where: { $0.id == item.id }) else { return }
            var promoted = history.remove(at: index)
            promoted.createdAt = Date()
            history.insert(promoted, at: 0)
        case .pinboard(let boardID):
            guard let boardIndex = pinboards.firstIndex(where: { $0.id == boardID }),
                  let itemIndex = pinboards[boardIndex].items.firstIndex(where: { $0.id == item.id })
            else { return }
            var promoted = pinboards[boardIndex].items.remove(at: itemIndex)
            promoted.createdAt = Date()
            pinboards[boardIndex].items.insert(promoted, at: 0)
        }
        selectedID = item.id
        scheduleSave()
    }

    func historyRetentionDidChange(
        effectiveAt: Date?,
        configurationChanged: Bool
    ) {
        historyLimitWorkItem?.cancel()
        historyLimitWorkItem = nil

        guard Settings.shared.retainedHistoryLimit != nil else {
            Settings.shared.clearDeferredHistoryLimitTrim()
            if configurationChanged { scheduleSave() }
            return
        }

        if let effectiveAt, effectiveAt > Date() {
            Settings.shared.deferHistoryLimitTrim(until: effectiveAt)
            scheduleHistoryLimitTrim(at: effectiveAt)
        } else {
            Settings.shared.clearDeferredHistoryLimitTrim()
            trimHistory()
        }
        if configurationChanged { scheduleSave() }
    }

    private func trimHistory() {
        guard Settings.shared.historyLimitTrimAfter == nil,
              let limit = Settings.shared.retainedHistoryLimit,
              history.count > limit else { return }
        let removed = Array(history[limit...])
        history.removeLast(history.count - limit)
        for item in removed { deleteImageFile(item) }
    }

    private func resumeDeferredHistoryLimitTrim() {
        guard let deadline = Settings.shared.historyLimitTrimAfter,
              Settings.shared.retainedHistoryLimit != nil else {
            Settings.shared.clearDeferredHistoryLimitTrim()
            return
        }
        if deadline > Date() {
            scheduleHistoryLimitTrim(at: deadline)
        } else {
            Settings.shared.clearDeferredHistoryLimitTrim()
            trimHistory()
            scheduleSave()
        }
    }

    private func scheduleHistoryLimitTrim(at deadline: Date) {
        historyLimitWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.historyLimitWorkItem = nil
            Settings.shared.clearDeferredHistoryLimitTrim()
            self.trimHistory()
            self.scheduleSave()
        }
        historyLimitWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, deadline.timeIntervalSinceNow),
            execute: work
        )
    }

    func refreshStorageUsage() {
        storageUsageTask?.cancel()
        let directory = baseDir
        storageUsageTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let bytes = await Task.detached(priority: .utility) {
                HistoryStorageUsage.bytes(in: directory)
            }.value
            guard !Task.isCancelled, let self, self.baseDir == directory else { return }
            self.storageUsageBytes = bytes
        }
    }

    func delete(_ item: ClipItem) {
        registerDeletion(of: item, at: Date(), removesPinboardCopies: true)
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
        saveNow()
    }

    @discardableResult
    func deleteSelectedItem() -> Bool {
        guard let selectedItem else { return false }
        delete(selectedItem)
        return true
    }

    func clearHistory() {
        let old = history
        let deletedAt = Date()
        for item in old {
            registerDeletion(
                of: item,
                at: deletedAt,
                removesPinboardCopies: false
            )
        }
        history.removeAll()
        selectedID = nil
        for item in old { deleteImageFile(item) }
        saveNow()
    }

    func removeAutomatedTestItems(withTexts texts: Set<String>) {
        let removedItems = history.filter { item in
            guard let text = item.text else { return false }
            return texts.contains(text)
        }
        let removedIDs = Set(removedItems.map(\.id))
        guard !removedIDs.isEmpty else { return }
        let deletedAt = Date()
        for item in removedItems {
            registerDeletion(
                of: item,
                at: deletedAt,
                removesPinboardCopies: false
            )
        }
        history.removeAll { removedIDs.contains($0.id) }
        if let selectedID, removedIDs.contains(selectedID) {
            selectFirst()
        }
        saveNow()
    }

    func replaceHistoryForAutomatedStripTest(_ items: [ClipItem]) {
        let environment = ProcessInfo.processInfo.environment
        let phase = environment["PESTY_AUTOMATED_UI_TEST"]
        guard ClipboardStore.automatedTestBase != nil,
              phase == "performance"
                || phase == "mouse-selection"
                || phase == "preview"
        else {
            return
        }
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
              ["keyboard-delete", "translation-board", "explanation-board"].contains(
                environment["PESTY_AUTOMATED_UI_TEST"]
              ) else { return }
        history = items
        pinboards = []
        source = .history
        searchText = ""
        selectedID = items.first?.id
        saveNow()
    }

    func replaceHistoryForAutomatedRetentionTest(_ items: [ClipItem]) {
        let environment = ProcessInfo.processInfo.environment
        guard ClipboardStore.automatedTestBase != nil,
              environment["PESTY_AUTOMATED_UI_TEST"]?.hasPrefix("retention-") == true,
              environment["PESTY_AUTOMATED_TEST_DEFAULTS_SUITE"] != nil else { return }
        history = items
        pinboards = []
        source = .history
        searchText = ""
        selectedID = items.first?.id
        saveNow()
    }

    func replaceHistoryForAutomatedClearConfirmationTest(_ items: [ClipItem]) {
        let environment = ProcessInfo.processInfo.environment
        guard ClipboardStore.automatedTestBase != nil,
              environment["PESTY_AUTOMATED_UI_TEST"] == "clear-confirmation" else { return }
        history = items
        pinboards = []
        source = .history
        searchText = ""
        selectedID = items.first?.id
        saveNow()
    }

    func replaceHistoryForAutomatedDeletionSyncTest(_ items: [ClipItem]) {
        let environment = ProcessInfo.processInfo.environment
        guard ClipboardStore.automatedTestBase != nil,
              environment["PESTY_AUTOMATED_UI_TEST"]?
                .hasPrefix("deletion-sync-") == true,
              environment["PESTY_AUTOMATED_TEST_DEFAULTS_SUITE"] != nil else {
            return
        }
        history = items
        pinboards = []
        source = .history
        searchText = ""
        selectedID = items.first?.id
        saveNow()
    }

    func mergeSnapshotForAutomatedDeletionSyncTest(
        _ snapshot: ClipboardStoreSnapshot
    ) {
        let environment = ProcessInfo.processInfo.environment
        guard ClipboardStore.automatedTestBase != nil,
              environment["PESTY_AUTOMATED_UI_TEST"]?
                .hasPrefix("deletion-sync-") == true,
              environment["PESTY_AUTOMATED_TEST_DEFAULTS_SUITE"] != nil else {
            return
        }
        if mergeExternal(snapshot) {
            saveNow()
        }
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

    private func load() {
        let initialSnapshot = readSnapshot(at: storeURL)
        if let snap = initialSnapshot {
            _ = mergeDeletionTombstones(snap.deletions ?? [])
            history = snap.history.filter { !isDeletedFromHistory($0) }
            pinboards = filteringDeletedPinboardItems(from: snap.pinboards)
        }
        reconcileFromDisk()
        let initializedConfiguration = usesSharedConfiguration
            ? Settings.shared.ensureSyncedHistoryRetention(
                effectiveAt: Date().addingTimeInterval(HistoryRetentionPolicy.trimDelay)
            )
            : false
        if initializedConfiguration {
            historyRetentionDidChange(
                effectiveAt: Settings.shared.syncedHistoryRetention?.effectiveAt,
                configurationChanged: false
            )
        }
        let currentConfiguration = Settings.shared.syncedHistoryRetention
        if initializedConfiguration
            || initialSnapshot?.configuration?.historyRetention != currentConfiguration {
            saveNow()
        }
        selectFirst()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        _ = writeSnapshot()
    }

    @discardableResult
    private func writeSnapshot() -> Bool {
        if usesSharedConfiguration {
            _ = Settings.shared.ensureSyncedHistoryRetention(
                effectiveAt: Date().addingTimeInterval(HistoryRetentionPolicy.trimDelay)
            )
        }
        let configuration = Settings.shared.syncedHistoryRetention.map {
            SyncedConfiguration(historyRetention: $0)
        }
        let snap = ClipboardStoreSnapshot(
            history: history,
            pinboards: pinboards,
            configuration: configuration,
            deletions: serializedDeletionTombstones
        )
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
        refreshStorageUsage()
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

        let targetSnapshot = fm.fileExists(atPath: newStore.path)
            ? readSnapshot(at: newStore)
            : nil
        if enabled, targetSnapshot?.configuration == nil {
            let configuration = Settings.shared.publishCurrentHistoryRetention(
                effectiveAt: Date().addingTimeInterval(HistoryRetentionPolicy.trimDelay)
            )
            historyRetentionDidChange(
                effectiveAt: configuration.effectiveAt,
                configurationChanged: false
            )
        }

        if let snap = targetSnapshot {
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

    private func contentDigest(_ item: ClipItem) -> String {
        SHA256.hash(data: Data(contentKey(item).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func registerDeletion(
        of item: ClipItem,
        at deletedAt: Date,
        removesPinboardCopies: Bool
    ) {
        let digest = contentDigest(item)
        let existing = deletionTombstones[digest]
        let effectiveDeletedAt = max(deletedAt, item.createdAt)
        deletionTombstones[digest] = ClipDeletionTombstone(
            contentDigest: digest,
            historyDeletedAt: max(
                existing?.historyDeletedAt ?? .distantPast,
                effectiveDeletedAt
            ),
            pinboardDeletedAt: removesPinboardCopies
                ? max(
                    existing?.pinboardDeletedAt ?? .distantPast,
                    effectiveDeletedAt
                )
                : existing?.pinboardDeletedAt
        )
    }

    private func isDeletedFromHistory(_ item: ClipItem) -> Bool {
        guard let tombstone = deletionTombstones[contentDigest(item)] else {
            return false
        }
        return tombstone.historyDeletedAt >= item.createdAt
    }

    private func isDeletedFromPinboard(_ item: ClipItem) -> Bool {
        guard let deletedAt = deletionTombstones[
            contentDigest(item)
        ]?.pinboardDeletedAt else {
            return false
        }
        return deletedAt >= item.createdAt
    }

    @discardableResult
    private func mergeDeletionTombstones(
        _ tombstones: [ClipDeletionTombstone]
    ) -> Bool {
        var changed = false
        for tombstone in tombstones {
            let existing = deletionTombstones[tombstone.contentDigest]
            let merged = ClipDeletionTombstone(
                contentDigest: tombstone.contentDigest,
                historyDeletedAt: max(
                    existing?.historyDeletedAt ?? .distantPast,
                    tombstone.historyDeletedAt
                ),
                pinboardDeletedAt: maxDeletionDate(
                    existing?.pinboardDeletedAt,
                    tombstone.pinboardDeletedAt
                )
            )
            if merged != existing {
                deletionTombstones[tombstone.contentDigest] = merged
                changed = true
            }
        }
        return changed
    }

    private func maxDeletionDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (date?, nil), let (nil, date?):
            return date
        case (nil, nil):
            return nil
        }
    }

    private var serializedDeletionTombstones: [ClipDeletionTombstone]? {
        guard !deletionTombstones.isEmpty else { return nil }
        return deletionTombstones
            .map(\.value)
            .sorted { $0.contentDigest < $1.contentDigest }
    }

    private func filteringDeletedPinboardItems(
        from boards: [Pinboard]
    ) -> [Pinboard] {
        boards.map { board in
            var filtered = board
            filtered.items.removeAll(where: isDeletedFromPinboard)
            return filtered
        }
    }

    @discardableResult
    private func mergeExternal(_ snap: ClipboardStoreSnapshot) -> Bool {
        let previousHistory = history
        let previousPinboards = pinboards
        let deletionsChanged = mergeDeletionTombstones(snap.deletions ?? [])
        var configurationChanged = false
        if let incoming = snap.configuration?.historyRetention,
           Settings.shared.adoptSyncedHistoryRetention(incoming) {
            configurationChanged = true
            historyRetentionDidChange(
                effectiveAt: Settings.shared.syncedHistoryRetention?.effectiveAt,
                configurationChanged: false
            )
        }
        let configurationNeedsWrite =
            Settings.shared.syncedHistoryRetention
                != snap.configuration?.historyRetention.normalized()

        var combined = (history + snap.history)
            .filter { !isDeletedFromHistory($0) }
            .sorted { $0.createdAt > $1.createdAt }
        var seen = Set<String>()
        var merged: [ClipItem] = []
        for it in combined where seen.insert(contentKey(it)).inserted { merged.append(it) }
        let mergeLimit: Int?
        if usesSharedConfiguration && Settings.shared.syncedHistoryRetention == nil {
            mergeLimit = nil
        } else {
            mergeLimit = Settings.shared.historyLimitTrimAfter == nil
                ? Settings.shared.retainedHistoryLimit
                : nil
        }
        history = HistoryRetentionPolicy.retainedPrefix(of: merged, limit: mergeLimit)

        pinboards = filteringDeletedPinboardItems(from: pinboards)
        var byID: [UUID: Pinboard] = Dictionary(
            uniqueKeysWithValues: pinboards.map { ($0.id, $0) }
        )
        for b in filteringDeletedPinboardItems(from: snap.pinboards) {
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
        return history != previousHistory
            || pinboards != previousPinboards
            || deletionsChanged
            || configurationChanged
            || configurationNeedsWrite
    }

    private func readSnapshot(at url: URL) -> ClipboardStoreSnapshot? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ClipboardStoreSnapshot.self, from: data)
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
            } else {
                self.refreshStorageUsage()
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
