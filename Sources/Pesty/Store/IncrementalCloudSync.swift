import CryptoKit
import Darwin
import Foundation
import OSLog

/// The v2 iCloud format uses small immutable, device-owned event batches. The
/// UI always reads the local materialized snapshot instead of waiting for File
/// Provider.
actor IncrementalCloudSync {
    struct SyncResult: Sendable {
        let snapshot: ClipboardStoreSnapshot
        let requestedCompactionCompleted: Bool
        let hasRemoteChanges: Bool
        let persistedState: Bool
        let decodedBatchCount: Int
    }

    private struct State: Codable, Sendable {
        var formatVersion = 2
        var deviceID: UUID
        var nextSequence: UInt64
        var snapshot: ClipboardStoreSnapshot
        var historyVersions: [String: Date]
        var boardVersions: [String: Date]
        var deletedBoardVersions: [String: Date]
        var appliedBatchVersions: [String: UUID]
        var appliedCheckpointIDs: Set<UUID>?
        var retiredImageVersions: [String: Date]?
        var verifiedRetiredImageVersions: [String: Date]?
        var batchDirectoryModificationDates: [String: Date]?
    }

    private struct Batch: Codable, Sendable {
        let formatVersion: Int
        let id: UUID
        let deviceID: UUID
        let sequence: UInt64
        let createdAt: Date
        let records: [Record]
    }

    private struct Record: Codable, Sendable {
        let recordedAt: Date
        let operation: Operation
    }

    private enum Operation: Codable, Sendable {
        case historyUpsert(ClipItem)
        case deletionUpsert(ClipDeletionTombstone)
        case pinboardUpsert(Pinboard)
        case pinboardDelete(UUID)
        case configurationUpsert(SyncedConfiguration)
        case imageRetire(String)
    }

    private struct CheckpointPayload: Codable, Sendable {
        let formatVersion: Int
        let snapshot: ClipboardStoreSnapshot
        let historyVersions: [String: Date]
        let boardVersions: [String: Date]
        let deletedBoardVersions: [String: Date]
        let coveredBatchVersions: [String: UUID]
        let includedCheckpointIDs: Set<UUID>
        let retiredImageVersions: [String: Date]
    }

    private struct CheckpointChunk: Codable, Equatable, Sendable {
        let name: String
        let byteCount: Int
        let sha256: String
    }

    private struct CheckpointManifest: Codable, Sendable {
        let formatVersion: Int
        let id: UUID
        let deviceID: UUID
        let createdAt: Date
        let payloadSHA256: String
        let chunks: [CheckpointChunk]
        let coveredBatchVersions: [String: UUID]
        let includedCheckpointIDs: Set<UUID>
    }

    private let localDirectory: URL
    private let cloudDirectory: URL
    private let stateURL: URL
    private let outboxDirectory: URL
    private let batchesDirectory: URL
    private let checkpointsDirectory: URL
    private let imagesDirectory: URL
    private let imageRetirementGrace: TimeInterval
    nonisolated let initialSnapshot: ClipboardStoreSnapshot?
    private let logger = Logger(
        subsystem: "com.bifrostproxy.pesty",
        category: "incremental-cloud-sync"
    )
    private var state: State?
    private var stateRequiresPersistence = false
    private var lastImageGarbageCollectionAt: Date?

    init(
        localDirectory: URL,
        cloudDirectory: URL,
        imageRetirementGrace: TimeInterval = 600
    ) {
        self.localDirectory = localDirectory
        self.cloudDirectory = cloudDirectory
        self.imageRetirementGrace = imageRetirementGrace
        let resolvedStateURL = localDirectory.appendingPathComponent("state.json")
        stateURL = resolvedStateURL
        outboxDirectory = localDirectory.appendingPathComponent(
            "outbox",
            isDirectory: true
        )
        batchesDirectory = cloudDirectory.appendingPathComponent(
            "batches",
            isDirectory: true
        )
        checkpointsDirectory = cloudDirectory.appendingPathComponent(
            "checkpoints",
            isDirectory: true
        )
        imagesDirectory = cloudDirectory.deletingLastPathComponent()
            .appendingPathComponent("images", isDirectory: true)
        let loaded = Self.loadPersistedState(at: resolvedStateURL)
        state = loaded.state
        stateRequiresPersistence = loaded.requiresPersistence
        initialSnapshot = loaded.state?.snapshot
    }

    nonisolated static func localSnapshot(in localDirectory: URL)
        -> ClipboardStoreSnapshot? {
        loadPersistedState(
            at: localDirectory.appendingPathComponent("state.json")
        ).state?.snapshot
    }

    func synchronize(
        _ snapshot: ClipboardStoreSnapshot,
        requestsCompaction: Bool = false,
        recordLocalChanges: Bool = true,
        forceRemoteScan: Bool = false
    ) async
        -> SyncResult? {
        prepareDirectories()
        var stateChanged = loadStateIfNeeded()
        if recordLocalChanges {
            stateChanged = await record(snapshot) || stateChanged
        }
        await flushOutbox()
        let checkpointChanges = await pullRemoteCheckpoints()
        stateChanged = checkpointChanges || stateChanged
        let batchChanges = await pullRemoteBatches(forceScan: forceRemoteScan)
        stateChanged = batchChanges.stateChanged || stateChanged
        let compaction: (completed: Bool, stateChanged: Bool)
        if stateChanged || requestsCompaction {
            compaction = await compactIfNeeded(force: requestsCompaction)
        } else {
            compaction = (true, false)
        }
        stateChanged = compaction.stateChanged || stateChanged
        if stateChanged {
            persistState()
        }
        let imageCleanupIsDue = lastImageGarbageCollectionAt.map {
            Date().timeIntervalSince($0) >= 600
        } ?? true
        if let current = state, stateChanged || imageCleanupIsDue {
            garbageCollectImages(
                referencedBy: current.snapshot,
                retiredImageVersions: current.verifiedRetiredImageVersions
                    ?? [:],
                olderThan: Date().addingTimeInterval(-imageRetirementGrace)
            )
            lastImageGarbageCollectionAt = Date()
        }
        guard let snapshot = state?.snapshot else { return nil }
        return SyncResult(
            snapshot: snapshot,
            requestedCompactionCompleted: !requestsCompaction
                || compaction.completed,
            hasRemoteChanges: checkpointChanges
                || batchChanges.hasRemoteChanges,
            persistedState: stateChanged,
            decodedBatchCount: batchChanges.decodedCount
        )
    }

    /// Makes local clipboard changes crash-safe without waiting for File
    /// Provider downloads or a complete remote reconciliation. The durable
    /// outbox is flushed by the normal background sync or the next launch.
    func persistLocalSnapshot(_ snapshot: ClipboardStoreSnapshot) async {
        prepareDirectories()
        var changed = loadStateIfNeeded()
        changed = await record(snapshot) || changed
        if changed { persistState() }
    }

    private func contains(
        _ migrated: ClipboardStoreSnapshot,
        allRecordsFrom expected: ClipboardStoreSnapshot
    ) -> Bool {
        let migratedHistory = Dictionary(
            uniqueKeysWithValues: migrated.history.map {
                (contentVersionKey($0), $0)
            }
        )
        guard expected.history.allSatisfy({ item in
            guard let actual = migratedHistory[contentVersionKey(item)] else {
                return false
            }
            return actual.createdAt >= item.createdAt
        }) else { return false }

        let migratedBoards = Dictionary(
            uniqueKeysWithValues: migrated.pinboards.map { ($0.id, $0) }
        )
        guard expected.pinboards.allSatisfy({ board in
            guard let actual = migratedBoards[board.id],
                  actual.name == board.name,
                  actual.colorHex == board.colorHex else { return false }
            return board.items.allSatisfy { expectedItem in
                actual.items.contains {
                    contentVersionKey($0) == contentVersionKey(expectedItem)
                }
            }
        }) else { return false }

        let migratedDeletions = deletionMap(migrated)
        return (expected.deletions ?? []).allSatisfy { deletion in
            guard let actual = migratedDeletions[deletion.contentDigest] else {
                return false
            }
            return actual.historyDeletedAt >= deletion.historyDeletedAt
                && (deletion.pinboardDeletedAt == nil
                    || (actual.pinboardDeletedAt ?? .distantPast)
                        >= deletion.pinboardDeletedAt!)
        }
    }

    private func prepareDirectories() {
        for directory in [
            localDirectory,
            outboxDirectory,
            cloudDirectory,
            batchesDirectory,
            checkpointsDirectory,
        ] {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                logger.error(
                    "Failed to create sync directory id=\(directory.lastPathComponent, privacy: .public) domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)"
                )
            }
        }
    }

    @discardableResult
    private func loadStateIfNeeded() -> Bool {
        guard state == nil else {
            let requiresPersistence = stateRequiresPersistence
            stateRequiresPersistence = false
            return requiresPersistence
        }
        if let decoded = try? Data(contentsOf: stateURL),
           var saved = try? JSONDecoder().decode(State.self, from: decoded),
           saved.formatVersion == 2 {
            let migrated = Self.normalizeHistoryVersionKeys(in: &saved)
            state = saved
            return migrated
        }
        state = State(
            deviceID: UUID(),
            nextSequence: 1,
            snapshot: emptySnapshot,
            historyVersions: [:],
            boardVersions: [:],
            deletedBoardVersions: [:],
            appliedBatchVersions: [:],
            appliedCheckpointIDs: [],
            retiredImageVersions: [:],
            verifiedRetiredImageVersions: [:],
            batchDirectoryModificationDates: [:]
        )
        return true
    }

    private func record(_ snapshot: ClipboardStoreSnapshot) async -> Bool {
        guard var current = state else { return false }
        let records = difference(from: current.snapshot, to: snapshot)
        guard !records.isEmpty else { return false }

        for chunk in chunked(records) {
            // Published batches are immutable. Every local delta gets a new
            // sequence instead of rewriting an existing cloud object.
            let sequence = current.nextSequence
            current.nextSequence &+= 1
            let batch = Batch(
                formatVersion: 2,
                id: UUID(),
                deviceID: current.deviceID,
                sequence: sequence,
                createdAt: Date(),
                records: chunk
            )
            current.appliedBatchVersions[batchVersionKey(batch)] = batch.id
            apply(batch, to: &current)
            let url = outboxDirectory.appendingPathComponent(
                batchFileName(batch)
            )
            do {
                let data = try JSONEncoder().encode(batch)
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: url.path
                )
            } catch {
                logger.error(
                    "Failed to queue incremental sync batch domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)"
                )
                return false
            }
        }
        // Preserve the exact local ordering after the semantic operations have
        // been recorded. Remote devices reconstruct the same ordering from the
        // item timestamps.
        current.snapshot = snapshot
        state = current
        return true
    }

    private func difference(
        from previous: ClipboardStoreSnapshot,
        to next: ClipboardStoreSnapshot
    ) -> [Record] {
        var result: [Record] = []
        let now = Date()
        let oldHistory = Dictionary(
            uniqueKeysWithValues: previous.history.map {
                (contentVersionKey($0), $0)
            }
        )
        for item in next.history
            where oldHistory[contentVersionKey(item)] != item {
            result.append(Record(
                recordedAt: oldHistory[contentVersionKey(item)] == nil
                    ? item.createdAt
                    : now,
                operation: .historyUpsert(item)
            ))
        }

        let oldDeletions = Dictionary(
            uniqueKeysWithValues: (previous.deletions ?? []).map {
                ($0.contentDigest, $0)
            }
        )
        for deletion in next.deletions ?? []
            where oldDeletions[deletion.contentDigest] != deletion {
            result.append(Record(
                recordedAt: max(
                    deletion.historyDeletedAt,
                    deletion.pinboardDeletedAt ?? .distantPast
                ),
                operation: .deletionUpsert(deletion)
            ))
        }

        let oldBoards = Dictionary(
            uniqueKeysWithValues: previous.pinboards.map { ($0.id, $0) }
        )
        let newBoards = Dictionary(
            uniqueKeysWithValues: next.pinboards.map { ($0.id, $0) }
        )
        for board in next.pinboards where oldBoards[board.id] != board {
            result.append(Record(
                recordedAt: now,
                operation: .pinboardUpsert(board)
            ))
        }
        for boardID in oldBoards.keys where newBoards[boardID] == nil {
            result.append(Record(
                recordedAt: now,
                operation: .pinboardDelete(boardID)
            ))
        }
        if previous.configuration != next.configuration,
           let configuration = next.configuration {
            result.append(Record(
                recordedAt: configuration.historyRetention.updatedAt,
                operation: .configurationUpsert(configuration)
            ))
        }
        let previousImages = referencedImageFileNames(in: previous)
        let nextImages = referencedImageFileNames(in: next)
        for fileName in previousImages.subtracting(nextImages) {
            result.append(Record(
                recordedAt: now,
                operation: .imageRetire(fileName)
            ))
        }
        return result
    }

    /// Keeps migration batches small enough for File Provider to fetch them
    /// independently. A single unusually large item remains a single record.
    private func chunked(_ records: [Record]) -> [[Record]] {
        var chunks: [[Record]] = []
        var current: [Record] = []
        var currentBytes = 0
        for record in records {
            let bytes = encodedBytes([record])
            if !current.isEmpty
                && (current.count >= 100 || currentBytes + bytes > 256_000) {
                chunks.append(current)
                current = []
                currentBytes = 0
            }
            current.append(record)
            currentBytes += bytes
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private func encodedBytes(_ records: [Record]) -> Int {
        (try? JSONEncoder().encode(records).count) ?? 0
    }

    private func flushOutbox() async {
        guard let deviceID = state?.deviceID else { return }
        let deviceDirectory = batchesDirectory.appendingPathComponent(
            deviceID.uuidString.lowercased(),
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: deviceDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        for source in outboxFiles() {
            guard let data = try? Data(contentsOf: source),
                  (try? JSONDecoder().decode(Batch.self, from: data)) != nil
            else { continue }
            let destination = deviceDirectory.appendingPathComponent(
                source.lastPathComponent
            )
            if coordinatedWrite(data, to: destination),
               coordinatedReadData(from: destination) == data {
                try? FileManager.default.removeItem(at: source)
            }
        }
    }

    private func pullRemoteBatches(forceScan: Bool) async -> (
        stateChanged: Bool,
        hasRemoteChanges: Bool,
        decodedCount: Int
    ) {
        guard let initialState = state else { return (false, false, 0) }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
        ]
        let directoryKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .contentModificationDateKey,
        ]
        guard let deviceDirectories = try? FileManager.default
            .contentsOfDirectory(
                at: batchesDirectory,
                includingPropertiesForKeys: Array(directoryKeys),
                options: [.skipsHiddenFiles]
            ) else { return (false, false, 0) }

        var directoryDates = initialState.batchDirectoryModificationDates
            ?? [:]
        let originalDirectoryDates = directoryDates
        let initiallyApplied = initialState.appliedBatchVersions
        var existingDeviceKeys = Set<String>()
        var candidates: [Batch] = []
        var decodedCount = 0

        for directory in deviceDirectories {
            let deviceKey = directory.lastPathComponent.lowercased()
            guard UUID(uuidString: deviceKey) != nil,
                  let directoryValues = try? directory.resourceValues(
                    forKeys: directoryKeys
                  ), directoryValues.isDirectory == true,
                  let directoryModifiedAt = directoryValues
                    .contentModificationDate else { continue }
            existingDeviceKeys.insert(deviceKey)
            guard forceScan
                    || directoryDates[deviceKey] != directoryModifiedAt else {
                continue
            }
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { continue }

            var directoryWasReadSuccessfully = true
            for url in urls where url.pathExtension == "json" {
                guard let pathKey = batchPathKey(url),
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true else {
                    directoryWasReadSuccessfully = false
                    continue
                }
                // A device/sequence path is immutable. Once its batch ID has
                // been applied, no later scan needs to open or decode it.
                guard initiallyApplied[pathKey] == nil else {
                    continue
                }
                if ClipImageMaterializer.isDataLess(at: url) {
                    _ = await ClipImageMaterializer.prepare(
                        at: url,
                        kind: .history,
                        timeout: .seconds(30)
                    ) { _ in }
                }
                guard let batch = coordinatedRead(Batch.self, from: url),
                      batch.formatVersion == 2,
                      batchVersionKey(batch) == pathKey else {
                    directoryWasReadSuccessfully = false
                    continue
                }
                decodedCount += 1
                candidates.append(batch)
            }
            guard directoryWasReadSuccessfully else { continue }
            directoryDates[deviceKey] = directoryModifiedAt
        }

        directoryDates = directoryDates.filter {
            existingDeviceKeys.contains($0.key)
        }
        let inventoryChanged = directoryDates != originalDirectoryDates
        guard var current = state else { return (false, false, decodedCount) }
        current.batchDirectoryModificationDates = directoryDates
        candidates.sort {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            if $0.deviceID != $1.deviceID {
                return $0.deviceID.uuidString < $1.deviceID.uuidString
            }
            return $0.sequence < $1.sequence
        }
        var appliedAny = false
        for batch in candidates {
            let key = batchVersionKey(batch)
            guard current.appliedBatchVersions[key] == nil else { continue }
            apply(batch, to: &current)
            current.appliedBatchVersions[key] = batch.id
            appliedAny = true
        }
        state = current
        return (
            inventoryChanged || appliedAny,
            appliedAny,
            decodedCount
        )
    }

    private func pullRemoteCheckpoints() async -> Bool {
        guard let initialState = state else { return false }
        var candidates: [(URL, CheckpointManifest)] = []
        let appliedIDs = initialState.appliedCheckpointIDs ?? []
        for manifestURL in checkpointManifestURLs() {
            if let checkpointID = UUID(
                uuidString: manifestURL.deletingLastPathComponent()
                    .lastPathComponent
            ), appliedIDs.contains(checkpointID) {
                continue
            }
            if ClipImageMaterializer.isDataLess(at: manifestURL) {
                _ = await ClipImageMaterializer.prepare(
                    at: manifestURL,
                    kind: .history,
                    timeout: .seconds(30)
                ) { _ in }
            }
            guard let manifest = coordinatedRead(
                CheckpointManifest.self,
                from: manifestURL
            ), manifest.formatVersion == 2 else { continue }
            candidates.append((manifestURL, manifest))
        }
        candidates.sort {
            if $0.1.createdAt != $1.1.createdAt {
                return $0.1.createdAt < $1.1.createdAt
            }
            return $0.1.id.uuidString < $1.1.id.uuidString
        }
        guard var current = state else { return false }
        var appliedAny = false
        for (manifestURL, manifest) in candidates {
            guard !(current.appliedCheckpointIDs ?? []).contains(
                manifest.id
            ) else { continue }
            guard let payload = await readCheckpoint(
                manifest,
                manifestURL: manifestURL
            ) else { continue }
            applyCheckpoint(payload, manifest: manifest, to: &current)
            appliedAny = true
        }
        guard appliedAny else { return false }
        state = current
        // JSONDecoder has released the assembled checkpoint bytes by this
        // point. Return their now-empty malloc pages so a one-time first sync
        // does not become the app's permanent idle footprint.
        _ = malloc_zone_pressure_relief(nil, 0)
        return true
    }

    private func applyCheckpoint(
        _ payload: CheckpointPayload,
        manifest: CheckpointManifest,
        to state: inout State
    ) {
        var records: [Record] = []
        records += payload.snapshot.history.map { item in
            Record(
                recordedAt: historyVersion(
                    for: item,
                    in: payload.historyVersions
                )
                    ?? item.createdAt,
                operation: .historyUpsert(item)
            )
        }
        records += (payload.snapshot.deletions ?? []).map { deletion in
            Record(
                recordedAt: max(
                    deletion.historyDeletedAt,
                    deletion.pinboardDeletedAt ?? .distantPast
                ),
                operation: .deletionUpsert(deletion)
            )
        }
        records += payload.snapshot.pinboards.map { board in
            Record(
                recordedAt: payload.boardVersions[
                    board.id.uuidString.lowercased()
                ] ?? manifest.createdAt,
                operation: .pinboardUpsert(board)
            )
        }
        records += payload.deletedBoardVersions.map { key, deletedAt in
            guard let id = UUID(uuidString: key) else { return nil }
            return Record(
                recordedAt: deletedAt,
                operation: .pinboardDelete(id)
            )
        }.compactMap { $0 }
        records += payload.retiredImageVersions.map { fileName, retiredAt in
            Record(
                recordedAt: retiredAt,
                operation: .imageRetire(fileName)
            )
        }
        if let configuration = payload.snapshot.configuration {
            records.append(Record(
                recordedAt: configuration.historyRetention.updatedAt,
                operation: .configurationUpsert(configuration)
            ))
        }
        let batch = Batch(
            formatVersion: 2,
            id: manifest.id,
            deviceID: manifest.deviceID,
            sequence: 0,
            createdAt: manifest.createdAt,
            records: records
        )
        apply(batch, to: &state)
        for (key, value) in payload.coveredBatchVersions {
            state.appliedBatchVersions[key] = value
        }
        var applied = state.appliedCheckpointIDs ?? []
        applied.formUnion(payload.includedCheckpointIDs)
        applied.insert(manifest.id)
        state.appliedCheckpointIDs = applied
        var verifiedRetirements = state.verifiedRetiredImageVersions ?? [:]
        mergeVersions(
            payload.retiredImageVersions,
            into: &verifiedRetirements
        )
        state.verifiedRetiredImageVersions = verifiedRetirements
    }

    private func compactIfNeeded(force: Bool) async -> (
        completed: Bool,
        stateChanged: Bool
    ) {
        guard let current = state, outboxFiles().isEmpty else {
            return (false, false)
        }
        let compactionStartedAt = Date()
        let inventory = batchInventory()
        let sealedCount = inventory.count
        let totalBytes = inventory.reduce(0) { $0 + $1.byteCount }
        guard force || sealedCount >= 8 || totalBytes >= 2_000_000 else {
            return (true, false)
        }

        let checkpointID = UUID()
        let included = current.appliedCheckpointIDs ?? []
        let payload = CheckpointPayload(
            formatVersion: 2,
            snapshot: current.snapshot,
            historyVersions: current.historyVersions,
            boardVersions: current.boardVersions,
            deletedBoardVersions: current.deletedBoardVersions,
            coveredBatchVersions: current.appliedBatchVersions,
            includedCheckpointIDs: included,
            retiredImageVersions: current.retiredImageVersions ?? [:]
        )
        let checkpointDirectory = checkpointsDirectory
            .appendingPathComponent(
                current.deviceID.uuidString.lowercased(),
                isDirectory: true
            )
            .appendingPathComponent(
                checkpointID.uuidString.lowercased(),
                isDirectory: true
            )
        do {
            try FileManager.default.createDirectory(
                at: checkpointDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            logCheckpointError("create", error: error)
            return (false, false)
        }

        guard let streamedPayload = writeCheckpointPayload(
            payload,
            to: checkpointDirectory
        ) else { return (false, false) }
        let manifest = CheckpointManifest(
            formatVersion: 2,
            id: checkpointID,
            deviceID: current.deviceID,
            createdAt: Date(),
            payloadSHA256: streamedPayload.sha256,
            chunks: streamedPayload.chunks,
            coveredBatchVersions: current.appliedBatchVersions,
            includedCheckpointIDs: included
        )
        let manifestURL = checkpointDirectory.appendingPathComponent(
            "manifest.json"
        )
        guard coordinatedWrite(manifest, to: manifestURL),
              let verifiedManifest = coordinatedRead(
                CheckpointManifest.self,
                from: manifestURL
              ),
              verifyCheckpointChunks(
                verifiedManifest,
                in: checkpointDirectory
              ),
              contains(payload.snapshot, allRecordsFrom: current.snapshot)
        else { return (false, false) }

        guard var latest = state else { return (false, false) }
        var applied = latest.appliedCheckpointIDs ?? []
        applied.insert(checkpointID)
        latest.appliedCheckpointIDs = applied
        var verifiedRetirements = latest.verifiedRetiredImageVersions ?? [:]
        mergeVersions(
            payload.retiredImageVersions,
            into: &verifiedRetirements
        )
        latest.verifiedRetiredImageVersions = verifiedRetirements
        state = latest
        garbageCollectBatches(coveredBy: manifest, inventory: inventory)
        garbageCollectCheckpoints(includedBy: manifest)
        garbageCollectImages(
            referencedBy: latest.snapshot,
            retiredImageVersions: latest.verifiedRetiredImageVersions ?? [:],
            olderThan: compactionStartedAt.addingTimeInterval(
                -imageRetirementGrace
            )
        )
        return (true, true)
    }

    private func readCheckpoint(
        _ manifest: CheckpointManifest,
        manifestURL: URL
    ) async -> CheckpointPayload? {
        let directory = manifestURL.deletingLastPathComponent()
        var data = Data()
        for chunk in manifest.chunks {
            let url = directory.appendingPathComponent(chunk.name)
            if ClipImageMaterializer.isDataLess(at: url) {
                _ = await ClipImageMaterializer.prepare(
                    at: url,
                    kind: .history,
                    timeout: .seconds(30)
                ) { _ in }
            }
            guard let chunkData = coordinatedReadData(from: url),
                  chunkData.count == chunk.byteCount,
                  sha256(chunkData) == chunk.sha256 else { return nil }
            data.append(chunkData)
        }
        guard sha256(data) == manifest.payloadSHA256,
              let payload = try? JSONDecoder().decode(
                CheckpointPayload.self,
                from: data
              ), payload.formatVersion == 2 else { return nil }
        return payload
    }

    private func apply(_ batch: Batch, to state: inout State) {
        for record in batch.records {
            switch record.operation {
            case .historyUpsert(let item):
                let key = contentVersionKey(item)
                guard record.recordedAt >= (state.historyVersions[key]
                    ?? .distantPast) else { continue }
                if let deletion = deletionMap(state.snapshot)[
                    contentDigest(item)
                ], deletion.historyDeletedAt >= item.createdAt {
                    continue
                }
                state.historyVersions[key] = record.recordedAt
                state.snapshot.history.removeAll {
                    contentVersionKey($0) == key
                }
                state.snapshot.history.append(item)
                state.snapshot.history.sort { $0.createdAt > $1.createdAt }

            case .deletionUpsert(let incoming):
                var deletions = deletionMap(state.snapshot)
                let old = deletions[incoming.contentDigest]
                deletions[incoming.contentDigest] = ClipDeletionTombstone(
                    contentDigest: incoming.contentDigest,
                    historyDeletedAt: max(
                        old?.historyDeletedAt ?? .distantPast,
                        incoming.historyDeletedAt
                    ),
                    pinboardDeletedAt: maxDate(
                        old?.pinboardDeletedAt,
                        incoming.pinboardDeletedAt
                    )
                )
                state.snapshot.deletions = Array(deletions.values)
                    .sorted { $0.contentDigest < $1.contentDigest }
                state.snapshot.history.removeAll { item in
                    guard let tombstone = deletions[contentDigest(item)] else {
                        return false
                    }
                    return tombstone.historyDeletedAt >= item.createdAt
                }
                state.snapshot.pinboards = state.snapshot.pinboards.map { board in
                    var filtered = board
                    filtered.items.removeAll { item in
                        guard let deletedAt = deletions[
                            contentDigest(item)
                        ]?.pinboardDeletedAt else { return false }
                        return deletedAt >= item.createdAt
                    }
                    return filtered
                }

            case .pinboardUpsert(let board):
                let key = board.id.uuidString.lowercased()
                guard record.recordedAt >= (state.deletedBoardVersions[key]
                    ?? .distantPast),
                      record.recordedAt >= (state.boardVersions[key]
                        ?? .distantPast) else { continue }
                state.deletedBoardVersions.removeValue(forKey: key)
                state.boardVersions[key] = record.recordedAt
                state.snapshot.pinboards.removeAll { $0.id == board.id }
                state.snapshot.pinboards.append(board)

            case .pinboardDelete(let boardID):
                let key = boardID.uuidString.lowercased()
                guard record.recordedAt >= (state.boardVersions[key]
                    ?? .distantPast),
                      record.recordedAt >= (state.deletedBoardVersions[key]
                        ?? .distantPast) else { continue }
                state.boardVersions.removeValue(forKey: key)
                state.deletedBoardVersions[key] = record.recordedAt
                state.snapshot.pinboards.removeAll { $0.id == boardID }

            case .configurationUpsert(let configuration):
                let incoming = configuration.historyRetention.normalized()
                if let existing = state.snapshot.configuration?
                    .historyRetention.normalized(),
                   !incoming.supersedes(existing) {
                    continue
                }
                state.snapshot.configuration = SyncedConfiguration(
                    historyRetention: incoming
                )

            case .imageRetire(let fileName):
                var retired = state.retiredImageVersions ?? [:]
                retired[fileName] = max(
                    retired[fileName] ?? .distantPast,
                    record.recordedAt
                )
                state.retiredImageVersions = retired
            }
        }
    }

    private var emptySnapshot: ClipboardStoreSnapshot {
        ClipboardStoreSnapshot(
            history: [],
            pinboards: [],
            configuration: nil,
            deletions: nil
        )
    }

    private nonisolated static func loadPersistedState(
        at url: URL
    ) -> (state: State?, requiresPersistence: Bool) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              var saved = try? JSONDecoder().decode(State.self, from: data),
              saved.formatVersion == 2 else {
            return (nil, false)
        }
        let migrated = normalizeHistoryVersionKeys(in: &saved)
        return (saved, migrated)
    }

    private nonisolated static func normalizeHistoryVersionKeys(
        in state: inout State
    ) -> Bool {
        var normalized: [String: Date] = [:]
        normalized.reserveCapacity(state.historyVersions.count)
        var changed = false
        for (key, date) in state.historyVersions {
            let normalizedKey: String
            if key.utf8.count == 64,
               key.utf8.allSatisfy({ byte in
                   (48...57).contains(byte) || (97...102).contains(byte)
               }) {
                normalizedKey = key
            } else {
                normalizedKey = digestContentKey(key)
            }
            normalized[normalizedKey] = max(
                normalized[normalizedKey] ?? .distantPast,
                date
            )
            changed = changed || normalizedKey != key
        }
        if changed {
            state.historyVersions = normalized
        }
        return changed
    }

    private nonisolated static func digestContentKey(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func deletionMap(_ snapshot: ClipboardStoreSnapshot)
        -> [String: ClipDeletionTombstone] {
        Dictionary(uniqueKeysWithValues: (snapshot.deletions ?? []).map {
            ($0.contentDigest, $0)
        })
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): max(lhs, rhs)
        case let (date?, nil), let (nil, date?): date
        case (nil, nil): nil
        }
    }

    private func mergeVersions(
        _ incoming: [String: Date],
        into versions: inout [String: Date]
    ) {
        for (key, date) in incoming {
            versions[key] = max(versions[key] ?? .distantPast, date)
        }
    }

    private func legacyContentKey(_ item: ClipItem) -> String {
        switch item.type {
        case .image:
            "img:" + (item.imageHash ?? item.imageFileName
                ?? item.id.uuidString)
        case .color:
            "col:" + (item.colorHex ?? "")
        case .file:
            "file:" + item.fileURLs.joined(separator: "|")
        default:
            "txt:" + (item.text ?? "")
        }
    }

    private func contentVersionKey(_ item: ClipItem) -> String {
        contentDigest(item)
    }

    private func historyVersion(
        for item: ClipItem,
        in versions: [String: Date]
    ) -> Date? {
        versions[contentVersionKey(item)]
            ?? versions[legacyContentKey(item)]
    }

    private func contentDigest(_ item: ClipItem) -> String {
        Self.digestContentKey(legacyContentKey(item))
    }

    private func batchFileName(_ batch: Batch) -> String {
        String(format: "%020llu.json", batch.sequence)
    }

    private func batchVersionKey(_ batch: Batch) -> String {
        "\(batch.deviceID.uuidString.lowercased()):\(batch.sequence)"
    }

    private func batchPathKey(_ url: URL) -> String? {
        let device = url.deletingLastPathComponent().lastPathComponent
        guard UUID(uuidString: device) != nil,
              let sequence = UInt64(url.deletingPathExtension()
                .lastPathComponent) else { return nil }
        return "\(device.lowercased()):\(sequence)"
    }

    private struct BatchInventoryItem {
        let url: URL
        let batch: Batch
        let byteCount: Int
    }

    private func batchInventory() -> [BatchInventoryItem] {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: batchesDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { value in
            guard let url = value as? URL,
                  url.pathExtension == "json",
                  !ClipImageMaterializer.isDataLess(at: url),
                  let batch = coordinatedRead(Batch.self, from: url)
            else { return nil }
            let size = (try? url.resourceValues(forKeys: keys).fileSize) ?? 0
            return BatchInventoryItem(
                url: url,
                batch: batch,
                byteCount: size
            )
        }
    }

    private func checkpointManifestURLs() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: checkpointsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == "manifest.json" }
    }

    private func writeCheckpointPayload(
        _ payload: CheckpointPayload,
        to directory: URL
    ) -> (chunks: [CheckpointChunk], sha256: String)? {
        let chunkSize = 256_000
        let encoder = JSONEncoder()
        var buffer = Data()
        buffer.reserveCapacity(chunkSize)
        var chunks: [CheckpointChunk] = []
        var payloadHasher = SHA256()

        func flushChunk() throws {
            guard !buffer.isEmpty else { return }
            let name = String(format: "chunk-%05d.part", chunks.count)
            let url = directory.appendingPathComponent(name)
            guard coordinatedWrite(buffer, to: url) else {
                throw CocoaError(.fileWriteUnknown)
            }
            chunks.append(CheckpointChunk(
                name: name,
                byteCount: buffer.count,
                sha256: sha256(buffer)
            ))
            buffer = Data()
            buffer.reserveCapacity(chunkSize)
        }

        func append(_ data: Data) throws {
            payloadHasher.update(data: data)
            var offset = data.startIndex
            while offset < data.endIndex {
                let available = chunkSize - buffer.count
                let end = min(data.endIndex, offset + available)
                buffer.append(contentsOf: data[offset..<end])
                offset = end
                if buffer.count == chunkSize {
                    try flushChunk()
                }
            }
        }

        func append(_ literal: String) throws {
            try append(Data(literal.utf8))
        }

        func appendEncoded<T: Encodable>(_ value: T) throws {
            try append(encoder.encode(value))
        }

        func appendArray<T: Encodable>(_ values: [T]) throws {
            try append("[")
            for (index, value) in values.enumerated() {
                if index > 0 { try append(",") }
                try appendEncoded(value)
            }
            try append("]")
        }

        do {
            try append("{\"formatVersion\":")
            try appendEncoded(payload.formatVersion)
            try append(",\"snapshot\":{\"history\":")
            try appendArray(payload.snapshot.history)
            try append(",\"pinboards\":")
            try appendArray(payload.snapshot.pinboards)
            try append(",\"configuration\":")
            if let configuration = payload.snapshot.configuration {
                try appendEncoded(configuration)
            } else {
                try append("null")
            }
            try append(",\"deletions\":")
            if let deletions = payload.snapshot.deletions {
                try appendArray(deletions)
            } else {
                try append("null")
            }
            try append("},\"historyVersions\":")
            try appendEncoded(payload.historyVersions)
            try append(",\"boardVersions\":")
            try appendEncoded(payload.boardVersions)
            try append(",\"deletedBoardVersions\":")
            try appendEncoded(payload.deletedBoardVersions)
            try append(",\"coveredBatchVersions\":")
            try appendEncoded(payload.coveredBatchVersions)
            try append(",\"includedCheckpointIDs\":")
            try appendEncoded(payload.includedCheckpointIDs)
            try append(",\"retiredImageVersions\":")
            try appendEncoded(payload.retiredImageVersions)
            try append("}")
            try flushChunk()
        } catch {
            logCheckpointError("stream", error: error)
            return nil
        }

        let digest = payloadHasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        return (chunks, digest)
    }

    private func verifyCheckpointChunks(
        _ manifest: CheckpointManifest,
        in directory: URL
    ) -> Bool {
        var payloadHasher = SHA256()
        for chunk in manifest.chunks {
            guard let data = coordinatedReadData(
                from: directory.appendingPathComponent(chunk.name)
            ), data.count == chunk.byteCount,
               sha256(data) == chunk.sha256 else { return false }
            payloadHasher.update(data: data)
        }
        let digest = payloadHasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        return digest == manifest.payloadSHA256
    }

    private func garbageCollectBatches(
        coveredBy manifest: CheckpointManifest,
        inventory: [BatchInventoryItem]
    ) {
        for item in inventory {
            guard manifest.coveredBatchVersions[
                    batchVersionKey(item.batch)
                  ] == item.batch.id else { continue }
            _ = coordinatedDeleteBatchIfMatches(
                at: item.url,
                expected: item.batch
            )
        }
    }

    private func garbageCollectCheckpoints(
        includedBy manifest: CheckpointManifest
    ) {
        for url in checkpointManifestURLs() {
            guard let old = coordinatedRead(
                CheckpointManifest.self,
                from: url
            ), manifest.includedCheckpointIDs.contains(old.id) else {
                continue
            }
            _ = coordinatedDeleteCheckpointIfMatches(
                at: url.deletingLastPathComponent(),
                expectedID: old.id
            )
        }
    }

    private func garbageCollectImages(
        referencedBy snapshot: ClipboardStoreSnapshot,
        retiredImageVersions: [String: Date],
        olderThan cutoff: Date
    ) {
        let referenced = referencedImageFileNames(in: snapshot)
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
        ]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in files where !referenced.contains(url.lastPathComponent) {
            guard let retiredAt = retiredImageVersions[
                url.lastPathComponent
            ], retiredAt < cutoff else { continue }
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt < cutoff else { continue }
            _ = coordinatedDeleteImageIfUnchanged(
                at: url,
                modifiedBefore: cutoff
            )
        }
    }

    private func coordinatedDeleteBatchIfMatches(
        at url: URL,
        expected: Batch
    ) -> Bool {
        var coordinatorError: NSError?
        var removalError: Error?
        var matched = false
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinatorError
        ) { coordinatedURL in
            guard let data = try? Data(contentsOf: coordinatedURL),
                  let current = try? JSONDecoder().decode(
                    Batch.self,
                    from: data
                  ), current.id == expected.id,
                  current.deviceID == expected.deviceID,
                  current.sequence == expected.sequence else { return }
            matched = true
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                removalError = error
            }
        }
        if let error = coordinatorError ?? removalError as NSError? {
            logger.error(
                "Failed to remove covered sync segment domain=\(error.domain, privacy: .public) code=\(error.code)"
            )
            return false
        }
        return matched && !FileManager.default.fileExists(atPath: url.path)
    }

    private func coordinatedDeleteCheckpointIfMatches(
        at directory: URL,
        expectedID: UUID
    ) -> Bool {
        var coordinatorError: NSError?
        var removalError: Error?
        var matched = false
        NSFileCoordinator().coordinate(
            writingItemAt: directory,
            options: .forDeleting,
            error: &coordinatorError
        ) { coordinatedURL in
            let manifestURL = coordinatedURL.appendingPathComponent(
                "manifest.json"
            )
            guard let data = try? Data(contentsOf: manifestURL),
                  let current = try? JSONDecoder().decode(
                    CheckpointManifest.self,
                    from: data
                  ), current.id == expectedID else { return }
            matched = true
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                removalError = error
            }
        }
        if let error = coordinatorError ?? removalError as NSError? {
            logger.error(
                "Failed to remove superseded checkpoint domain=\(error.domain, privacy: .public) code=\(error.code)"
            )
            return false
        }
        return matched
            && !FileManager.default.fileExists(atPath: directory.path)
    }

    private func coordinatedDeleteImageIfUnchanged(
        at url: URL,
        modifiedBefore cutoff: Date
    ) -> Bool {
        var coordinatorError: NSError?
        var removalError: Error?
        var matched = false
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinatorError
        ) { coordinatedURL in
            let values = try? coordinatedURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
            ])
            guard values?.isRegularFile == true,
                  let modifiedAt = values?.contentModificationDate,
                  modifiedAt < cutoff else { return }
            matched = true
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                removalError = error
            }
        }
        if let error = coordinatorError ?? removalError as NSError? {
            logger.error(
                "Failed to remove unreferenced image domain=\(error.domain, privacy: .public) code=\(error.code)"
            )
            return false
        }
        return matched && !FileManager.default.fileExists(atPath: url.path)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func referencedImageFileNames(
        in snapshot: ClipboardStoreSnapshot
    ) -> Set<String> {
        Set(
            (snapshot.history + snapshot.pinboards.flatMap(\.items))
                .compactMap(\.imageFileName)
        )
    }

    private func logCheckpointError(_ action: String, error: Error) {
        let nsError = error as NSError
        logger.error(
            "Failed to \(action, privacy: .public) sync checkpoint domain=\(nsError.domain, privacy: .public) code=\(nsError.code)"
        )
    }

    private func outboxFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: outboxDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func persistState() {
        guard let state else { return }
        let temporaryURL = stateURL.deletingLastPathComponent()
            .appendingPathComponent(".state-\(UUID().uuidString).tmp")
        do {
            try writeState(state, to: temporaryURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporaryURL.path
            )
            guard rename(temporaryURL.path, stateURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            logger.error(
                "Failed to persist incremental sync state domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)"
            )
        }
    }

    private func writeState(_ state: State, to url: URL) throws {
        let fm = FileManager.default
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: url)
        let encoder = JSONEncoder()

        func write(_ literal: String) throws {
            try handle.write(contentsOf: Data(literal.utf8))
        }
        func writeEncoded<T: Encodable>(_ value: T) throws {
            try handle.write(contentsOf: encoder.encode(value))
        }
        func writeArray<T: Encodable>(_ values: [T]) throws {
            try write("[")
            for (index, value) in values.enumerated() {
                if index > 0 { try write(",") }
                try writeEncoded(value)
            }
            try write("]")
        }

        do {
            try write("{\"formatVersion\":")
            try writeEncoded(state.formatVersion)
            try write(",\"deviceID\":")
            try writeEncoded(state.deviceID)
            try write(",\"nextSequence\":")
            try writeEncoded(state.nextSequence)
            try write(",\"snapshot\":{\"history\":")
            try writeArray(state.snapshot.history)
            try write(",\"pinboards\":")
            try writeArray(state.snapshot.pinboards)
            try write(",\"configuration\":")
            if let configuration = state.snapshot.configuration {
                try writeEncoded(configuration)
            } else {
                try write("null")
            }
            try write(",\"deletions\":")
            if let deletions = state.snapshot.deletions {
                try writeArray(deletions)
            } else {
                try write("null")
            }
            try write("},\"historyVersions\":")
            try writeEncoded(state.historyVersions)
            try write(",\"boardVersions\":")
            try writeEncoded(state.boardVersions)
            try write(",\"deletedBoardVersions\":")
            try writeEncoded(state.deletedBoardVersions)
            try write(",\"appliedBatchVersions\":")
            try writeEncoded(state.appliedBatchVersions)
            try write(",\"appliedCheckpointIDs\":")
            if let ids = state.appliedCheckpointIDs {
                try writeEncoded(ids)
            } else {
                try write("null")
            }
            try write(",\"retiredImageVersions\":")
            if let versions = state.retiredImageVersions {
                try writeEncoded(versions)
            } else {
                try write("null")
            }
            try write(",\"verifiedRetiredImageVersions\":")
            if let versions = state.verifiedRetiredImageVersions {
                try writeEncoded(versions)
            } else {
                try write("null")
            }
            try write(",\"batchDirectoryModificationDates\":")
            if let dates = state.batchDirectoryModificationDates {
                try writeEncoded(dates)
            } else {
                try write("null")
            }
            try write("}")
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private func coordinatedWrite<T: Encodable>(_ value: T, to url: URL)
        -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return coordinatedWrite(data, to: url)
    }

    private func coordinatedWrite(_ data: Data, to url: URL) -> Bool {
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinatorError
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
        if let error = coordinatorError ?? writeError as NSError? {
            logger.error(
                "Failed to write incremental cloud object domain=\(error.domain, privacy: .public) code=\(error.code)"
            )
            return false
        }
        return true
    }

    private func coordinatedRead<T: Decodable>(
        _ type: T.Type,
        from url: URL
    ) -> T? {
        guard let data = coordinatedReadData(from: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func coordinatedReadData(from url: URL) -> Data? {
        var coordinatorError: NSError?
        var readData: Data?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinatorError
        ) { coordinatedURL in
            readData = try? Data(contentsOf: coordinatedURL)
        }
        return coordinatorError == nil ? readData : nil
    }
}
