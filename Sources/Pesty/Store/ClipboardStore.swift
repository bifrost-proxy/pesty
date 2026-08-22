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

enum BarSource: Equatable, Sendable {
    case history
    case pinboard(UUID)
}

enum ICloudStoreLoadState: Equatable, Sendable {
    case ready
    case downloading
    case failed
}

struct ClipDeletionTombstone: Codable, Equatable, Sendable {
    let contentDigest: String
    let historyDeletedAt: Date
    let pinboardDeletedAt: Date?
}

struct ClipboardStoreSnapshot: Codable, Sendable {
    var history: [ClipItem]
    var pinboards: [Pinboard]
    var configuration: SyncedConfiguration?
    var deletions: [ClipDeletionTombstone]? = nil
}

private struct ClipboardMergeContext: Sendable {
    var history: [ClipItem]
    var pinboards: [Pinboard]
    var deletionTombstones: [String: ClipDeletionTombstone]
    var configuration: SyncedHistoryRetentionConfiguration?
    var historyLimitTrimAfter: Date?
    var retainedHistoryLimit: Int?
    let usesSharedConfiguration: Bool
}

private struct ClipboardMergeResult: Sendable {
    let history: [ClipItem]
    let pinboards: [Pinboard]
    let deletionTombstones: [String: ClipDeletionTombstone]
    let adoptedConfiguration: SyncedHistoryRetentionConfiguration?
    let configurationChanged: Bool
    let configurationNeedsWrite: Bool
}

private struct ClipboardDiskReconciliationResult: Sendable {
    let mergeResult: ClipboardMergeResult
    let conflictCount: Int
    let readErrors: [String]
}

private enum ClipboardStoreReconciler {
    static func mergeForSnapshot(
        context: ClipboardMergeContext,
        snapshot: ClipboardStoreSnapshot
    ) -> ClipboardMergeResult {
        merge(context: context, snapshots: [snapshot])
    }

    static func reconcile(
        context: ClipboardMergeContext,
        storeURL: URL,
        automatedDelayMilliseconds: UInt64 = 0
    ) -> ClipboardDiskReconciliationResult {
        var snapshots: [ClipboardStoreSnapshot] = []
        var readErrors: [String] = []
        if let snapshot = readSnapshot(at: storeURL, errors: &readErrors) {
            snapshots.append(snapshot)
        }

        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(
            at: storeURL
        ) ?? []
        for version in conflicts {
            if let snapshot = readSnapshot(
                at: version.url,
                errors: &readErrors
            ) {
                snapshots.append(snapshot)
            }
        }

        if automatedDelayMilliseconds > 0 {
            Thread.sleep(
                forTimeInterval: Double(automatedDelayMilliseconds) / 1_000
            )
        }

        return ClipboardDiskReconciliationResult(
            mergeResult: merge(context: context, snapshots: snapshots),
            conflictCount: conflicts.count,
            readErrors: readErrors
        )
    }

    private static func readSnapshot(
        at url: URL,
        errors: inout [String]
    ) -> ClipboardStoreSnapshot? {
        guard !ClipImageMaterializer.isDataLess(at: url) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(
                ClipboardStoreSnapshot.self,
                from: data
            )
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                errors.append(error.localizedDescription)
            }
            return nil
        }
    }

    private static func merge(
        context: ClipboardMergeContext,
        snapshots: [ClipboardStoreSnapshot]
    ) -> ClipboardMergeResult {
        var history = context.history
        var pinboards = context.pinboards
        var tombstones = context.deletionTombstones
        var configuration = context.configuration
        var trimAfter = context.historyLimitTrimAfter
        var retainedHistoryLimit = context.retainedHistoryLimit
        var adoptedConfiguration: SyncedHistoryRetentionConfiguration?
        var configurationChanged = false
        var configurationNeedsWrite = false
        let now = Date()

        for snapshot in snapshots {
            mergeDeletionTombstones(
                snapshot.deletions ?? [],
                into: &tombstones
            )

            if let incoming = snapshot.configuration?.historyRetention
                .normalized(),
               configuration.map({ incoming.supersedes($0) }) ?? true {
                configuration = incoming
                adoptedConfiguration = incoming
                configurationChanged = true
                retainedHistoryLimit = incoming.unlimited
                    ? nil
                    : incoming.limit
                trimAfter = incoming.unlimited
                    ? nil
                    : incoming.effectiveAt.flatMap {
                        $0 > now ? $0 : nil
                    }
            }
            configurationNeedsWrite = configurationNeedsWrite
                || configuration
                    != snapshot.configuration?.historyRetention.normalized()

            var combined = (history + snapshot.history)
                .filter {
                    !isDeletedFromHistory(
                        $0,
                        tombstones: tombstones
                    )
                }
                .sorted { $0.createdAt > $1.createdAt }
            var seen = Set<String>()
            var merged: [ClipItem] = []
            for item in combined
                where seen.insert(contentDigest(item)).inserted {
                merged.append(item)
            }

            let mergeLimit: Int?
            if context.usesSharedConfiguration && configuration == nil {
                mergeLimit = nil
            } else {
                mergeLimit = trimAfter == nil ? retainedHistoryLimit : nil
            }
            history = HistoryRetentionPolicy.retainedPrefix(
                of: merged,
                limit: mergeLimit
            )

            pinboards = filteringDeletedPinboardItems(
                from: pinboards,
                tombstones: tombstones
            )
            var byID = Dictionary(
                uniqueKeysWithValues: pinboards.map { ($0.id, $0) }
            )
            for board in filteringDeletedPinboardItems(
                from: snapshot.pinboards,
                tombstones: tombstones
            ) {
                if var existing = byID[board.id] {
                    for item in board.items
                        where !existing.items.contains(where: {
                            $0.sameContent(as: item)
                        }) {
                        existing.items.append(item)
                    }
                    byID[board.id] = existing
                } else {
                    byID[board.id] = board
                }
            }
            pinboards = pinboards.map { byID[$0.id] ?? $0 }
                + byID.values.filter { board in
                    !pinboards.contains(where: { $0.id == board.id })
                }
            combined.removeAll()
        }

        return ClipboardMergeResult(
            history: history,
            pinboards: pinboards,
            deletionTombstones: tombstones,
            adoptedConfiguration: adoptedConfiguration,
            configurationChanged: configurationChanged,
            configurationNeedsWrite: configurationNeedsWrite
        )
    }

    private static func mergeDeletionTombstones(
        _ incoming: [ClipDeletionTombstone],
        into tombstones: inout [String: ClipDeletionTombstone]
    ) {
        for tombstone in incoming {
            let existing = tombstones[tombstone.contentDigest]
            tombstones[tombstone.contentDigest] = ClipDeletionTombstone(
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
        }
    }

    private static func filteringDeletedPinboardItems(
        from boards: [Pinboard],
        tombstones: [String: ClipDeletionTombstone]
    ) -> [Pinboard] {
        boards.map { board in
            var filtered = board
            filtered.items.removeAll {
                guard let deletedAt = tombstones[
                    contentDigest($0)
                ]?.pinboardDeletedAt else {
                    return false
                }
                return deletedAt >= $0.createdAt
            }
            return filtered
        }
    }

    private static func isDeletedFromHistory(
        _ item: ClipItem,
        tombstones: [String: ClipDeletionTombstone]
    ) -> Bool {
        guard let tombstone = tombstones[contentDigest(item)] else {
            return false
        }
        return tombstone.historyDeletedAt >= item.createdAt
    }

    private static func contentDigest(_ item: ClipItem) -> String {
        SHA256.hash(data: Data(contentKey(item).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func contentKey(_ item: ClipItem) -> String {
        switch item.type {
        case .image:
            return "img:"
                + (item.imageHash ?? item.imageFileName ?? item.id.uuidString)
        case .color:
            return "col:" + (item.colorHex ?? "")
        case .file:
            return "file:" + item.fileURLs.joined(separator: "|")
        default:
            return "txt:" + (item.text ?? "")
        }
    }

    private static func maxDeletionDate(
        _ lhs: Date?,
        _ rhs: Date?
    ) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (date?, nil), let (nil, date?):
            return date
        case (nil, nil):
            return nil
        }
    }
}

@Observable
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()

    private(set) var stripContentRevision: UInt64 = 0
    private(set) var history: [ClipItem] = [] {
        didSet {
            stripContentRevision &+= 1
            dataRevision &+= 1
            historySearchRevision &+= 1
            if source == .history {
                invalidateSearchIndexAndRefreshResults()
            }
        }
    }
    private(set) var pinboards: [Pinboard] = [] {
        didSet {
            stripContentRevision &+= 1
            dataRevision &+= 1
            pinboardSearchRevision &+= 1
            if case .pinboard = source {
                invalidateSearchIndexAndRefreshResults()
            }
        }
    }
    private(set) var storageUsageBytes: Int64 = 0
    private(set) var iCloudStoreLoadState: ICloudStoreLoadState = .ready

    var source: BarSource = .history {
        didSet {
            if source != oldValue {
                stripContentRevision &+= 1
                invalidateSearchIndexAndRefreshResults()
            }
        }
    }
    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            let oldQuery = normalizedSearchQuery(oldValue)
            let newQuery = normalizedSearchQuery(searchText)
            guard oldQuery != newQuery else { return }
            if newQuery.isEmpty {
                searchTask?.cancel()
                searchTask = nil
                searchGeneration &+= 1
                stripContentRevision &+= 1
                scheduleSearchIndexEviction()
            } else {
                searchIndexEvictionTask?.cancel()
                searchIndexEvictionTask = nil
                scheduleSearchResultsUpdate(debounce: true)
            }
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
    @ObservationIgnored private var dataRevision: UInt64 = 0
    @ObservationIgnored private var historySearchRevision: UInt64 = 0
    @ObservationIgnored private var pinboardSearchRevision: UInt64 = 0
    @ObservationIgnored private var filteredSearchItems: [ClipItem] = []
    @ObservationIgnored private var filteredSearchIndices: [Int] = []
    @ObservationIgnored private var appliedSearchSource: BarSource?
    @ObservationIgnored private var appliedSearchContentRevision: UInt64 = 0
    @ObservationIgnored private var searchIndex: ClipboardSearchIndex?
    @ObservationIgnored private var searchIndexTask: Task<ClipboardSearchIndex?, Never>?
    @ObservationIgnored private var searchIndexGeneration: UInt64 = 0
    @ObservationIgnored private var searchIndexBuildIsDeferred = false
    @ObservationIgnored private var searchIndexEvictionTask: Task<Void, Never>?
    @ObservationIgnored private var searchCandidateCache: [String: [Int]] = [:]
    @ObservationIgnored private var searchCandidateCacheOrder: [String] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration: UInt64 = 0
    @ObservationIgnored private var completedSearchIndexBuildCount = 0
    @ObservationIgnored private var lastSearchScannedItemCount = 0
    @ObservationIgnored private var storageUsageTask: Task<Void, Never>?
    @ObservationIgnored private var diskReconciliationTask: Task<Void, Never>?
    @ObservationIgnored private var storeMaterializationTask: Task<Void, Never>?
    @ObservationIgnored private var incrementalSyncTask: Task<Void, Never>?
    @ObservationIgnored private var incrementalSyncPollTask: Task<Void, Never>?
    @ObservationIgnored private var incrementalSyncRequested = false
    @ObservationIgnored private var incrementalLocalChangesRequested = false
    @ObservationIgnored private var incrementalRemoteScanRequested = false
    @ObservationIgnored private var incrementalCompactionRequested = false
    @ObservationIgnored private var diskReconciliationRequested = false
    @ObservationIgnored private var isApplyingMaterializedStore = false
    @ObservationIgnored private var storeMaterializationCompletedForCurrentURL = false
    @ObservationIgnored private var pendingConflictResolution = false
    @ObservationIgnored private var incrementalCloudSync: IncrementalCloudSync?

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
        configureIncrementalCloudSync()
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
        if usesICloudMetadataCache {
            try? fm.createDirectory(
                at: metadataCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        if usesIncrementalCloudSync {
            try? fm.createDirectory(
                at: incrementalCloudDirectory.appendingPathComponent(
                    "batches",
                    isDirectory: true
                ),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            beginIncrementalSyncPolling()
        }
    }

    private var usesIncrementalCloudSync: Bool {
        guard Settings.shared.iCloudSync else { return false }
        if ClipboardStore.automatedTestBase != nil {
            return ProcessInfo.processInfo.environment[
                "PESTY_AUTOMATED_INCREMENTAL_SYNC"
            ] == "1"
        }
        return ClipboardStore.iCloudBase != nil
    }

    private var incrementalCloudDirectory: URL {
        baseDir.appendingPathComponent("sync-v2", isDirectory: true)
    }

    private var incrementalLocalDirectory: URL {
        let root: URL
        if let explicit = ProcessInfo.processInfo.environment[
            "PESTY_AUTOMATED_INCREMENTAL_LOCAL_DIR"
        ], !explicit.isEmpty {
            root = URL(fileURLWithPath: explicit, isDirectory: true)
        } else {
            root = ClipboardStore.automatedTestBase ?? ClipboardStore.localBase
        }
        return root.appendingPathComponent("sync-v2-local", isDirectory: true)
    }

    private func configureIncrementalCloudSync() {
        incrementalCloudSync = usesIncrementalCloudSync
            ? IncrementalCloudSync(
                localDirectory: incrementalLocalDirectory,
                cloudDirectory: incrementalCloudDirectory
            )
            : nil
    }

    private func beginIncrementalSyncPolling() {
        guard usesIncrementalCloudSync,
              incrementalSyncPollTask == nil else { return }
        incrementalSyncPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self,
                      self.usesIncrementalCloudSync else { break }
                self.scheduleIncrementalSync()
            }
            self?.incrementalSyncPollTask = nil
        }
    }

    var visibleItems: [ClipItem] {
        let base = items(for: source)
        guard !normalizedSearchQuery(searchText).isEmpty else { return base }
        guard appliedSearchSource == source,
              appliedSearchContentRevision == searchContentRevision(for: source) else {
            return base
        }
        return filteredSearchItems
    }

    private func items(for source: BarSource) -> [ClipItem] {
        switch source {
        case .history:
            history
        case .pinboard(let id):
            pinboards.first(where: { $0.id == id })?.items ?? []
        }
    }

    private func normalizedSearchQuery(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func searchContentRevision(for source: BarSource) -> UInt64 {
        switch source {
        case .history:
            historySearchRevision
        case .pinboard:
            pinboardSearchRevision
        }
    }

    private func invalidateSearchIndexAndRefreshResults() {
        searchIndexTask?.cancel()
        searchIndexTask = nil
        searchIndexEvictionTask?.cancel()
        searchIndexEvictionTask = nil
        searchIndexGeneration &+= 1
        searchIndexBuildIsDeferred = false
        discardSearchIndexOffMainActor()
        searchCandidateCache.removeAll(keepingCapacity: true)
        searchCandidateCacheOrder.removeAll(keepingCapacity: true)
        filteredSearchIndices.removeAll(keepingCapacity: true)

        if normalizedSearchQuery(searchText).isEmpty {
            // A capture invalidates the complete normalized byte index. Do not
            // immediately rebuild it while persistence is encoding the same
            // history. The next real query builds a fresh index on demand.
        } else {
            scheduleSearchResultsUpdate(debounce: false)
        }
    }

    private func discardSearchIndexOffMainActor() {
        searchIndex = nil
    }

    private func scheduleSearchIndexEviction() {
        searchIndexEvictionTask?.cancel()
        guard searchIndex != nil || searchIndexTask != nil else {
            searchIndexEvictionTask = nil
            return
        }
        searchIndexEvictionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard let self,
                  self.normalizedSearchQuery(self.searchText).isEmpty else {
                return
            }
            self.searchIndexTask?.cancel()
            self.searchIndexTask = nil
            self.searchIndexGeneration &+= 1
            self.discardSearchIndexOffMainActor()
            self.searchCandidateCache.removeAll(keepingCapacity: false)
            self.searchCandidateCacheOrder.removeAll(keepingCapacity: false)
            self.filteredSearchItems.removeAll(keepingCapacity: false)
            self.filteredSearchIndices.removeAll(keepingCapacity: false)
            self.searchIndexEvictionTask = nil
        }
    }

    private func scheduleSearchResultsUpdate(debounce: Bool) {
        searchTask?.cancel()
        searchGeneration &+= 1

        let query = normalizedSearchQuery(searchText)
        guard !query.isEmpty else {
            searchTask = nil
            return
        }

        let generation = searchGeneration
        let expectedSource = source
        let expectedContentRevision = searchContentRevision(for: expectedSource)
        let shouldDebounce = debounce && !hasSmallCachedCandidate(for: query)

        searchTask = Task { [weak self] in
            // Keep native text editing responsive while a user is still
            // composing a query. Until the newest result is ready, the strip
            // continues to display its last coherent snapshot.
            if shouldDebounce {
                do {
                    try await Task.sleep(for: .milliseconds(60))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }

            guard let self,
                  let index = await self.ensureSearchIndex(),
                  !Task.isCancelled,
                  index.source == expectedSource,
                  index.contentRevision == expectedContentRevision else { return }

            let exactCandidates = self.searchCandidateCache[query]
            let candidates = exactCandidates
                ?? self.searchCandidates(for: query, in: index)
            let worker = Task.detached(priority: .userInitiated) { () -> ClipboardSearchResult? in
                if exactCandidates != nil {
                    guard !Task.isCancelled else { return nil }
                    return ClipboardSearchResult(
                        indices: candidates,
                        items: candidates.map { index.items[$0] },
                        scannedCount: 0
                    )
                }
                return ClipboardSearchEngine.filter(
                    index,
                    query: query,
                    candidates: candidates
                )
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled,
                  let result,
                  self.searchGeneration == generation,
                  self.source == expectedSource,
                  self.searchContentRevision(for: self.source)
                    == expectedContentRevision,
                  self.normalizedSearchQuery(self.searchText) == query else { return }

            self.cacheSearchCandidates(result.indices, for: query)
            self.lastSearchScannedItemCount = result.scannedCount
            let contentChanged = self.appliedSearchSource != expectedSource
                || self.appliedSearchContentRevision != expectedContentRevision
                || self.filteredSearchIndices != result.indices
            if contentChanged {
                self.filteredSearchItems = result.items
                self.filteredSearchIndices = result.indices
            }
            self.appliedSearchSource = expectedSource
            self.appliedSearchContentRevision = expectedContentRevision
            self.selectedID = result.items.first?.id
            if contentChanged {
                self.stripContentRevision &+= 1
            }
            self.searchTask = nil
        }
    }

    private func scheduleSearchIndexBuild(deferred: Bool) {
        searchIndexTask?.cancel()
        searchIndexGeneration &+= 1

        let generation = searchIndexGeneration
        let expectedSource = source
        let expectedContentRevision = searchContentRevision(for: expectedSource)
        let base = items(for: expectedSource)
        searchIndexBuildIsDeferred = deferred

        let task = Task<ClipboardSearchIndex?, Never> { [weak self] in
            if deferred {
                do {
                    // Do not compete with application launch or panel
                    // presentation. A real query promotes this build below.
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return nil
                }
            }
            guard !Task.isCancelled else { return nil }

            let priority: TaskPriority = deferred ? .utility : .userInitiated
            let worker = Task.detached(priority: priority) {
                ClipboardSearchEngine.build(
                    items: base,
                    source: expectedSource,
                    contentRevision: expectedContentRevision
                )
            }
            let builtIndex = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled,
                  let builtIndex,
                  let self,
                  self.searchIndexGeneration == generation,
                  self.source == expectedSource,
                  self.searchContentRevision(for: self.source)
                    == expectedContentRevision else { return nil }

            self.searchIndex = builtIndex
            self.searchCandidateCache.removeAll(keepingCapacity: true)
            self.searchCandidateCacheOrder.removeAll(keepingCapacity: true)
            self.completedSearchIndexBuildCount += 1
            self.searchIndexTask = nil
            self.searchIndexBuildIsDeferred = false
            return builtIndex
        }
        searchIndexTask = task
    }

    private func ensureSearchIndex() async -> ClipboardSearchIndex? {
        let expectedSource = source
        let expectedContentRevision = searchContentRevision(for: expectedSource)
        if let searchIndex,
           searchIndex.source == expectedSource,
           searchIndex.contentRevision == expectedContentRevision {
            return searchIndex
        }

        if searchIndexTask == nil || searchIndexBuildIsDeferred {
            searchIndexTask?.cancel()
            scheduleSearchIndexBuild(deferred: false)
        }
        guard let task = searchIndexTask,
              let index = await task.value,
              index.source == expectedSource,
              index.contentRevision == expectedContentRevision else { return nil }
        return index
    }

    private func searchCandidates(
        for query: String,
        in index: ClipboardSearchIndex
    ) -> [Int] {
        if let exact = searchCandidateCache[query] { return exact }
        let prefix = searchCandidateCacheOrder
            .filter { query.hasPrefix($0) }
            .max { $0.count < $1.count }
        if let prefix, let cached = searchCandidateCache[prefix] {
            return cached
        }
        return Array(index.items.indices)
    }

    private func hasSmallCachedCandidate(for query: String) -> Bool {
        searchCandidateCacheOrder.contains { cachedQuery in
            query.hasPrefix(cachedQuery)
                && (searchCandidateCache[cachedQuery]?.count ?? .max) <= 256
        }
    }

    private func cacheSearchCandidates(_ indices: [Int], for query: String) {
        if searchCandidateCache[query] == nil {
            searchCandidateCacheOrder.append(query)
        }
        searchCandidateCache[query] = indices
        while searchCandidateCacheOrder.count > 8 {
            let evicted = searchCandidateCacheOrder.removeFirst()
            searchCandidateCache.removeValue(forKey: evicted)
        }
    }

    func waitForSearchForAutomatedTest() async {
        guard ClipboardStore.automatedTestBase != nil else { return }
        while let task = searchTask {
            await task.value
        }
    }

    func waitForSearchIndexForAutomatedTest() async {
        guard ClipboardStore.automatedTestBase != nil else { return }
        while let task = searchIndexTask {
            _ = await task.value
        }
    }

    func searchDiagnosticsForAutomatedTest() -> (
        indexCount: Int,
        buildCount: Int,
        lastScannedCount: Int
    ) {
        guard ClipboardStore.automatedTestBase != nil else { return (0, 0, 0) }
        return (
            searchIndex?.items.count ?? 0,
            completedSearchIndexBuildCount,
            lastSearchScannedItemCount
        )
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
        let deletedAt = Date()
        for item in removed {
            registerDeletion(
                of: item,
                at: deletedAt,
                removesPinboardCopies: false
            )
        }
        history.removeLast(history.count - limit)
        for item in removed {
            deleteImageFile(item, deferForIncrementalSync: true)
        }
        incrementalCompactionRequested = true
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
        deleteImageFile(item, deferForIncrementalSync: true)
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
        for item in old {
            deleteImageFile(item, deferForIncrementalSync: true)
        }
        incrementalCompactionRequested = true
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

    func replaceHistoryForAutomatedMemoryTest(_ items: [ClipItem]) {
        guard ClipboardStore.automatedTestBase != nil,
              ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"]
                == "memory-seed" else {
            return
        }
        history = items
        pinboards = []
        deletionTombstones = [:]
        source = .history
        searchText = ""
        selectedID = items.first?.id
        saveNow()
    }

    func replaceHistoryForAutomatedSettingsCountTest(_ items: [ClipItem]) {
        guard ClipboardStore.automatedTestBase != nil,
              ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"]
                == "settings-record-count" else {
            return
        }
        history = items
        source = .history
        searchText = ""
        selectedID = items.first?.id
    }

    func replaceHistoryForAutomatedSearchTest(_ items: [ClipItem]) {
        guard ClipboardStore.automatedTestBase != nil,
              ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"]
                == "search-input" else {
            return
        }
        history = items
        pinboards = []
        source = .history
        searchText = ""
        selectedID = items.first?.id
    }

    func replaceHistoryForAutomatedPanelReconciliationTest(
        _ items: [ClipItem]
    ) {
        guard ClipboardStore.automatedTestBase != nil,
              ProcessInfo.processInfo.environment[
                "PESTY_AUTOMATED_UI_TEST"
              ] == "panel-reconciliation" else {
            return
        }
        history = items
        pinboards = []
        deletionTombstones = [:]
        source = .history
        searchText = ""
        selectedID = items.first?.id
        saveNow()
    }

    func addConcurrentItemForAutomatedPanelReconciliationTest(
        _ item: ClipItem
    ) {
        guard ClipboardStore.automatedTestBase != nil,
              ProcessInfo.processInfo.environment[
                "PESTY_AUTOMATED_UI_TEST"
              ] == "panel-reconciliation" else {
            return
        }
        history.insert(item, at: 0)
        selectedID = item.id
    }

    func addConcurrentItemForAutomatedICloudStoreTest(_ item: ClipItem) {
        guard ClipboardStore.automatedTestBase != nil,
              ProcessInfo.processInfo.environment[
                "PESTY_AUTOMATED_UI_TEST"
              ] == "icloud-store-loading" else {
            return
        }
        history.insert(item, at: 0)
        selectedID = item.id
        saveNow()
    }

    func reverseHistoryForAutomatedSettingsCountTest() {
        guard ClipboardStore.automatedTestBase != nil,
              ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"]
                == "settings-record-count" else {
            return
        }
        history.reverse()
    }

    func replaceHistoryForAutomatedKeyboardTest(_ items: [ClipItem]) {
        let environment = ProcessInfo.processInfo.environment
        guard ClipboardStore.automatedTestBase != nil,
              [
                  "keyboard-delete",
                  "translation-board",
                  "image-translation",
                  "explanation-board",
              ].contains(
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
        for item in removedItems {
            deleteImageFile(item, deferForIncrementalSync: true)
        }
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
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let error = writeError ?? coordinationError {
            logger.error(
                "Failed to save clipboard image id=\(name, privacy: .public) domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)"
            )
            return nil
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return name
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

    private func deleteImageFile(
        _ item: ClipItem,
        deferForIncrementalSync: Bool = false
    ) {
        guard let name = item.imageFileName else { return }
        let stillUsed = history.contains { $0.imageFileName == name }
            || pinboards.contains { $0.items.contains { $0.imageFileName == name } }
        if stillUsed { return }
        if deferForIncrementalSync && usesIncrementalCloudSync {
            incrementalCompactionRequested = true
            return
        }
        guard let url = imageURL(for: item),
              FileManager.default.fileExists(atPath: url.path) else { return }
        var coordinationError: NSError?
        var removalError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                removalError = error
            }
        }
        if let error = coordinationError ?? removalError as NSError? {
            logger.error(
                "Failed to remove unreferenced clipboard image id=\(name, privacy: .public) domain=\(error.domain, privacy: .public) code=\(error.code)"
            )
        }
    }

    private func load() {
        let loadsFromMetadataCache = usesICloudMetadataCache
        let needsMaterialization = loadsFromMetadataCache
            && storeNeedsMaterializationBeforeReading
        let initialSnapshot = usesIncrementalCloudSync
            ? incrementalCloudSync?.initialSnapshot
            : readSnapshot(
                at: loadsFromMetadataCache ? metadataCacheURL : storeURL
            )
        if let snap = initialSnapshot {
            _ = mergeDeletionTombstones(snap.deletions ?? [])
            history = snap.history.filter { !isDeletedFromHistory($0) }
            pinboards = filteringDeletedPinboardItems(from: snap.pinboards)
            if usesSharedConfiguration,
               let configuration = snap.configuration?.historyRetention
                .normalized() {
                if Settings.shared.adoptSyncedHistoryRetention(configuration) {
                    historyRetentionDidChange(
                        effectiveAt: configuration.effectiveAt,
                        configurationChanged: false
                    )
                }
            }
        }
        if usesIncrementalCloudSync {
            // The local snapshot is the launch source of truth. Cloud event
            // batches and checkpoints are consumed only in background tasks.
            scheduleIncrementalSync(
                localDataChanged: true,
                forceRemoteScan: true
            )
        } else if loadsFromMetadataCache {
            if FileManager.default.fileExists(atPath: storeURL.path) {
                beginICloudStoreBackgroundLoad(
                    requiresMaterialization: needsMaterialization
                )
            }
        } else {
            reconcileFromDisk()
        }
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
        } else if usesICloudMetadataCache {
            saveMetadataCacheNow()
        }
        selectFirst()
    }

    private var usesICloudMetadataCache: Bool {
        Settings.shared.iCloudSync || ClipboardStore.automatedTestBase != nil
    }

    private var metadataCacheURL: URL {
        if usesIncrementalCloudSync {
            return incrementalLocalDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("icloud-metadata-cache.json")
        }
        let cacheBase = ClipboardStore.automatedTestBase
            ?? ClipboardStore.localBase
        return cacheBase.appendingPathComponent("icloud-metadata-cache.json")
    }

    private var storeNeedsMaterializationBeforeReading: Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return false
        }
        if ClipboardStore.automatedTestBase != nil,
           ProcessInfo.processInfo.environment[
               "PESTY_AUTOMATED_STORE_DOWNLOAD_DELAY_MS"
           ]?.isEmpty == false {
            return !storeMaterializationCompletedForCurrentURL
        }
        return ClipImageMaterializer.isDataLess(at: storeURL)
    }

    private func beginICloudStoreBackgroundLoad(
        requiresMaterialization: Bool
    ) {
        guard storeMaterializationTask == nil else { return }
        let requestedStoreURL = storeURL
        iCloudStoreLoadState = .downloading
        storeMaterializationTask = Task { [weak self] in
            let prepared: Bool
            if requiresMaterialization {
                prepared = await ClipImageMaterializer.prepare(
                    at: requestedStoreURL,
                    kind: .history,
                    timeout: .seconds(60)
                ) { _ in }
            } else {
                prepared = true
            }
            guard let self, self.storeURL == requestedStoreURL else { return }
            guard prepared else {
                self.iCloudStoreLoadState = .failed
                self.storeMaterializationTask = nil
                return
            }

            self.storeMaterializationCompletedForCurrentURL = true
            self.isApplyingMaterializedStore = true
            self.reconcileFromDiskInBackground()
            while let task = self.diskReconciliationTask {
                await task.value
            }
            self.isApplyingMaterializedStore = false
            guard self.storeURL == requestedStoreURL else { return }
            self.iCloudStoreLoadState = .ready
            self.storeMaterializationTask = nil
            self.saveNow()
        }
    }

    private func beginICloudStoreMaterialization() {
        beginICloudStoreBackgroundLoad(requiresMaterialization: true)
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
        if usesIncrementalCloudSync {
            // IncrementalCloudSync owns the local materialized state. Encoding
            // the complete history here made every new clipboard item rewrite
            // the legacy metadata cache on the main actor, delaying pasteboard
            // polling long enough to miss subsequent copies.
            scheduleIncrementalSync(localDataChanged: true)
            refreshStorageUsage()
            return true
        }
        guard let data = encodedCurrentSnapshot() else { return false }
        let metadataCacheSaved = writeMetadataCache(data)
        guard iCloudStoreLoadState == .ready else {
            logger.info(
                "Saved clipboard changes locally while iCloud history sync is unavailable"
            )
            return metadataCacheSaved
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
        resolvePendingConflictVersionsIfNeeded()
        refreshStorageUsage()
        return true
    }

    private func encodedCurrentSnapshot() -> Data? {
        do {
            return try JSONEncoder().encode(currentSnapshot)
        } catch {
            logger.error(
                "Failed to encode clipboard history: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private var currentSnapshot: ClipboardStoreSnapshot {
        let configuration = Settings.shared.syncedHistoryRetention.map {
            SyncedConfiguration(historyRetention: $0)
        }
        return ClipboardStoreSnapshot(
            history: history,
            pinboards: pinboards,
            configuration: configuration,
            deletions: serializedDeletionTombstones
        )
    }

    private func scheduleIncrementalSync(
        localDataChanged: Bool = false,
        forceRemoteScan: Bool = false
    ) {
        guard incrementalCloudSync != nil else { return }
        incrementalSyncRequested = true
        if localDataChanged {
            incrementalLocalChangesRequested = true
        }
        if forceRemoteScan {
            incrementalRemoteScanRequested = true
        }
        guard incrementalSyncTask == nil else { return }
        incrementalSyncTask = Task { [weak self] in
            guard let self else { return }
            while self.incrementalSyncRequested {
                self.incrementalSyncRequested = false
                guard let sync = self.incrementalCloudSync else { break }
                let local = self.currentSnapshot
                let recordLocalChanges = self.incrementalLocalChangesRequested
                self.incrementalLocalChangesRequested = false
                let forceRemoteScan = self.incrementalRemoteScanRequested
                self.incrementalRemoteScanRequested = false
                let requestsCompaction = self.incrementalCompactionRequested
                let result = await sync.synchronize(
                    local,
                    requestsCompaction: requestsCompaction,
                    recordLocalChanges: recordLocalChanges,
                    forceRemoteScan: forceRemoteScan
                )
                guard !Task.isCancelled else { break }
                if let result {
                    if result.requestedCompactionCompleted {
                        self.incrementalCompactionRequested = false
                    }
                    guard result.hasRemoteChanges else { continue }
                    let merged = result.snapshot
                    let pinboardsWereUnchanged = self.pinboards
                        == local.pinboards
                    var changed = self.mergeExternal(merged)
                    if pinboardsWereUnchanged,
                       self.pinboards != merged.pinboards {
                        self.pinboards = merged.pinboards
                        changed = true
                    }
                    if changed {
                        self.saveMetadataCacheNow()
                        self.incrementalSyncRequested = true
                        self.incrementalLocalChangesRequested = true
                    }
                }
            }
            self.incrementalSyncTask = nil
            if self.incrementalSyncRequested {
                self.scheduleIncrementalSync()
            }
        }
    }

    private func saveMetadataCacheNow() {
        // The incremental state is already persisted by IncrementalCloudSync.
        // Keeping a second full-history cache would reintroduce monolithic
        // serialization and can also become stale relative to the delta log.
        guard !usesIncrementalCloudSync else { return }
        guard let data = encodedCurrentSnapshot() else { return }
        _ = writeMetadataCache(data)
    }

    @discardableResult
    private func writeMetadataCache(_ data: Data) -> Bool {
        guard usesICloudMetadataCache else { return true }
        do {
            try FileManager.default.createDirectory(
                at: metadataCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: metadataCacheURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: metadataCacheURL.path
            )
            return true
        } catch {
            logger.error(
                "Failed to save local clipboard metadata cache: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func resolvePendingConflictVersionsIfNeeded() {
        guard pendingConflictResolution else { return }
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(
            at: storeURL
        ) ?? []
        for version in conflicts {
            version.isResolved = true
        }
        do {
            if !conflicts.isEmpty {
                try NSFileVersion.removeOtherVersionsOfItem(at: storeURL)
            }
            pendingConflictResolution = false
            if !conflicts.isEmpty {
                logger.info(
                    "Merged and resolved \(conflicts.count, privacy: .public) clipboard history conflict version(s)"
                )
            }
        } catch {
            logger.error(
                "Failed to remove resolved history versions: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func setICloudSync(_ enabled: Bool) {
        stopWatching()
        storeMaterializationTask?.cancel()
        storeMaterializationTask = nil
        incrementalSyncTask?.cancel()
        incrementalSyncTask = nil
        incrementalSyncPollTask?.cancel()
        incrementalSyncPollTask = nil
        incrementalSyncRequested = false
        incrementalLocalChangesRequested = false
        incrementalRemoteScanRequested = false
        incrementalCompactionRequested = false
        incrementalCloudSync = nil
        storeMaterializationCompletedForCurrentURL = false
        iCloudStoreLoadState = .ready
        let target = (enabled ? ClipboardStore.iCloudBase : ClipboardStore.localBase) ?? ClipboardStore.localBase
        let newImages = target.appendingPathComponent("images", isDirectory: true)
        let newStore = target.appendingPathComponent("store.json")
        let fm = FileManager.default
        try? fm.createDirectory(at: newImages, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])

        let targetNeedsMaterialization = fm.fileExists(atPath: newStore.path)
            && ClipImageMaterializer.isDataLess(at: newStore)
        let targetSnapshot = !enabled
            && fm.fileExists(atPath: newStore.path)
            ? readSnapshot(at: newStore)
            : nil

        copyImages(from: imagesDir, to: newImages)
        baseDir = target; imagesDir = newImages; storeURL = newStore
        configureIncrementalCloudSync()
        prepareDirectories()
        if enabled && usesIncrementalCloudSync {
            saveNow()
        } else if enabled {
            beginICloudStoreBackgroundLoad(
                requiresMaterialization: targetNeedsMaterialization
            )
            saveNow()
        } else if let snap = targetSnapshot {
            _ = mergeExternal(snap)
            saveNow()
        } else {
            saveNow()
        }
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
        let suppliedResult = ClipboardStoreReconciler.mergeForSnapshot(
            context: mergeContext,
            snapshot: snap
        )
        let changed = applyMergeResult(suppliedResult)
        selectFirst()
        return changed
    }

    private func readSnapshot(at url: URL) -> ClipboardStoreSnapshot? {
        guard !ClipImageMaterializer.isDataLess(at: url) else { return nil }
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
        if storeNeedsMaterializationBeforeReading {
            beginICloudStoreMaterialization()
            return
        }
        if iCloudStoreLoadState == .failed {
            iCloudStoreLoadState = .ready
        }
        let result = ClipboardStoreReconciler.reconcile(
            context: mergeContext,
            storeURL: storeURL
        )
        logReadErrors(result.readErrors)
        let changed = applyMergeResult(result.mergeResult)
        pendingConflictResolution = result.conflictCount > 0
        guard changed || result.conflictCount > 0 else { return }
        saveNow()
    }

    /// Reconciles iCloud and local snapshots without delaying panel
    /// presentation or blocking interactions with disk decoding and merging.
    /// A revision guard discards stale results if clipboard data or retention
    /// settings change while the worker is running, then immediately retries
    /// against the newest in-memory state.
    func reconcileFromDiskInBackground() {
        if storeNeedsMaterializationBeforeReading {
            beginICloudStoreMaterialization()
            return
        }
        if iCloudStoreLoadState == .failed {
            iCloudStoreLoadState = .ready
        }
        guard iCloudStoreLoadState == .ready
                || isApplyingMaterializedStore else {
            return
        }
        guard diskReconciliationTask == nil else {
            diskReconciliationRequested = true
            return
        }

        let context = mergeContext
        let requestedStoreURL = storeURL
        let requestedDataRevision = dataRevision
        let requestedConfiguration = Settings.shared.syncedHistoryRetention
        let requestedTrimAfter = Settings.shared.historyLimitTrimAfter
        let requestedRetainedLimit = Settings.shared.retainedHistoryLimit
        let automatedDelayMilliseconds: UInt64
        if ClipboardStore.automatedTestBase != nil {
            automatedDelayMilliseconds = UInt64(
                ProcessInfo.processInfo.environment[
                    "PESTY_AUTOMATED_RECONCILIATION_DELAY_MS"
                ] ?? ""
            ) ?? 0
        } else {
            automatedDelayMilliseconds = 0
        }

        diskReconciliationTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                ClipboardStoreReconciler.reconcile(
                    context: context,
                    storeURL: requestedStoreURL,
                    automatedDelayMilliseconds: automatedDelayMilliseconds
                )
            }.value
            guard let self else { return }

            self.diskReconciliationTask = nil
            self.logReadErrors(result.readErrors)
            let stateIsCurrent = self.storeURL == requestedStoreURL
                && self.dataRevision == requestedDataRevision
                && Settings.shared.syncedHistoryRetention
                    == requestedConfiguration
                && Settings.shared.historyLimitTrimAfter == requestedTrimAfter
                && Settings.shared.retainedHistoryLimit
                    == requestedRetainedLimit

            if stateIsCurrent {
                let changed = self.applyMergeResult(result.mergeResult)
                if result.conflictCount > 0 {
                    self.pendingConflictResolution = true
                }
                if changed || result.conflictCount > 0 {
                    self.scheduleSave()
                }
            } else {
                self.diskReconciliationRequested = true
            }

            if self.diskReconciliationRequested {
                self.diskReconciliationRequested = false
                self.reconcileFromDiskInBackground()
            }
        }
    }

    func waitForDiskReconciliationForAutomatedTest() async {
        guard ClipboardStore.automatedTestBase != nil else { return }
        while let task = diskReconciliationTask {
            await task.value
        }
    }

    func waitForICloudStoreLoadForAutomatedTest() async {
        await storeMaterializationTask?.value
    }

    func flushPendingWrites() async {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        if let incrementalCloudSync {
            await incrementalCloudSync.persistLocalSnapshot(currentSnapshot)
        } else {
            _ = writeSnapshot()
        }
    }

    func flushPendingWrites(
        completion: @escaping @Sendable () -> Void
    ) {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        if let incrementalCloudSync {
            let snapshot = currentSnapshot
            Task.detached {
                await incrementalCloudSync.persistLocalSnapshot(snapshot)
                completion()
            }
        } else {
            _ = writeSnapshot()
            completion()
        }
    }

    func waitForIncrementalSyncForAutomatedTest() async {
        guard ClipboardStore.automatedTestBase != nil else { return }
        while let task = incrementalSyncTask {
            await task.value
        }
    }

    func requestIncrementalCompactionForAutomatedMemoryTest() {
        guard ClipboardStore.automatedTestBase != nil,
              ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"]
                == "memory-measure" else { return }
        incrementalCompactionRequested = true
        scheduleIncrementalSync()
    }

    private var mergeContext: ClipboardMergeContext {
        ClipboardMergeContext(
            history: history,
            pinboards: pinboards,
            deletionTombstones: deletionTombstones,
            configuration: Settings.shared.syncedHistoryRetention,
            historyLimitTrimAfter: Settings.shared.historyLimitTrimAfter,
            retainedHistoryLimit: Settings.shared.retainedHistoryLimit,
            usesSharedConfiguration: usesSharedConfiguration
        )
    }

    @discardableResult
    private func applyMergeResult(_ result: ClipboardMergeResult) -> Bool {
        var changed = false
        if let configuration = result.adoptedConfiguration,
           Settings.shared.adoptSyncedHistoryRetention(configuration) {
            changed = true
            historyRetentionDidChange(
                effectiveAt: configuration.effectiveAt,
                configurationChanged: false
            )
        }
        if deletionTombstones != result.deletionTombstones {
            deletionTombstones = result.deletionTombstones
            dataRevision &+= 1
            changed = true
        }
        if history != result.history {
            history = result.history
            changed = true
        }
        if pinboards != result.pinboards {
            pinboards = result.pinboards
            changed = true
        }
        if changed {
            selectFirst()
        }
        return changed
            || result.configurationChanged
            || result.configurationNeedsWrite
    }

    private func logReadErrors(_ errors: [String]) {
        for error in errors {
            logger.error(
                "Failed to read clipboard history: \(error, privacy: .public)"
            )
        }
    }

    private func startWatching() {
        stopWatching()
        let watchedURL = usesIncrementalCloudSync
            ? incrementalCloudDirectory.appendingPathComponent(
                "batches",
                isDirectory: true
            )
            : storeURL
        let fd = open(watchedURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let event = src.data
            let needsReattach = event.contains(.rename) || event.contains(.delete)

            if self.usesIncrementalCloudSync {
                self.scheduleIncrementalSync(forceRemoteScan: true)
                self.refreshStorageUsage()
            } else if Date() >= self.ignoreWatchUntil {
                self.reconcileFromDiskInBackground()
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
