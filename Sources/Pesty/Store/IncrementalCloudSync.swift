import CryptoKit
import Foundation
import OSLog

/// The v2 iCloud format uses small rolling, device-owned segments. A device may
/// append to its current segment until it reaches the size limit, but never
/// rewrites another device's files. The UI always reads the local materialized
/// snapshot instead of waiting for File Provider.
actor IncrementalCloudSync {
    struct SyncResult: Sendable {
        let snapshot: ClipboardStoreSnapshot
        let requestedCompactionCompleted: Bool
    }

    struct MigrationReceipt: Codable, Sendable {
        let formatVersion: Int
        let legacySHA256: String
        let migratedAt: Date
        let historyCount: Int
        let pinboardCount: Int
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
        var activeBatch: Batch?
        var appliedCheckpointIDs: Set<UUID>?
        var retiredImageVersions: [String: Date]?
        var verifiedRetiredImageVersions: [String: Date]?
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
    private let migrationDirectory: URL
    private let imageRetirementGrace: TimeInterval
    private let logger = Logger(
        subsystem: "com.bifrostproxy.pesty",
        category: "incremental-cloud-sync"
    )
    private var state: State?

    init(
        localDirectory: URL,
        cloudDirectory: URL,
        imageRetirementGrace: TimeInterval = 600
    ) {
        self.localDirectory = localDirectory
        self.cloudDirectory = cloudDirectory
        self.imageRetirementGrace = imageRetirementGrace
        stateURL = localDirectory.appendingPathComponent("state.json")
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
        migrationDirectory = cloudDirectory.appendingPathComponent(
            "migration",
            isDirectory: true
        )
    }

    nonisolated static func localSnapshot(in localDirectory: URL)
        -> ClipboardStoreSnapshot? {
        let url = localDirectory.appendingPathComponent("state.json")
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(State.self, from: data),
              state.formatVersion == 2 else { return nil }
        return state.snapshot
    }

    func synchronize(
        _ snapshot: ClipboardStoreSnapshot,
        requestsCompaction: Bool = false
    ) async
        -> SyncResult? {
        prepareDirectories()
        loadStateIfNeeded()
        await record(snapshot)
        await flushOutbox()
        await pullRemoteCheckpoints()
        await pullRemoteBatches()
        let compacted = await compactIfNeeded(force: requestsCompaction)
        if let current = state {
            garbageCollectImages(
                referencedBy: current.snapshot,
                retiredImageVersions: current.verifiedRetiredImageVersions
                    ?? [:],
                olderThan: Date().addingTimeInterval(-imageRetirementGrace)
            )
        }
        guard let snapshot = state?.snapshot else { return nil }
        return SyncResult(
            snapshot: snapshot,
            requestedCompactionCompleted: !requestsCompaction || compacted
        )
    }

    /// Persists all migration records, verifies that no local batch remains in
    /// the outbox, then writes a small receipt that can be inspected on future
    /// launches. The caller still verifies the legacy file before deleting it.
    func commitLegacyMigration(
        snapshot: ClipboardStoreSnapshot,
        legacySHA256: String
    ) async -> Bool {
        _ = await synchronize(snapshot)
        guard outboxFiles().isEmpty,
              let migrated = state?.snapshot,
              contains(migrated, allRecordsFrom: snapshot) else {
            return false
        }

        let receipt = MigrationReceipt(
            formatVersion: 2,
            legacySHA256: legacySHA256,
            migratedAt: Date(),
            historyCount: snapshot.history.count,
            pinboardCount: snapshot.pinboards.count
        )
        let receiptURL = migrationDirectory.appendingPathComponent(
            "legacy-store-\(legacySHA256).json"
        )
        guard coordinatedWrite(receipt, to: receiptURL),
              coordinatedRead(MigrationReceipt.self, from: receiptURL)
                == receipt else {
            return false
        }
        return true
    }

    private func contains(
        _ migrated: ClipboardStoreSnapshot,
        allRecordsFrom expected: ClipboardStoreSnapshot
    ) -> Bool {
        let migratedHistory = Dictionary(
            uniqueKeysWithValues: migrated.history.map { (contentKey($0), $0) }
        )
        guard expected.history.allSatisfy({ item in
            guard let actual = migratedHistory[contentKey(item)] else {
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
                actual.items.contains { contentKey($0) == contentKey(expectedItem) }
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
            migrationDirectory,
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

    private func loadStateIfNeeded() {
        guard state == nil else { return }
        if let decoded = try? Data(contentsOf: stateURL),
           let saved = try? JSONDecoder().decode(State.self, from: decoded),
           saved.formatVersion == 2 {
            state = saved
            return
        }
        state = State(
            deviceID: UUID(),
            nextSequence: 1,
            snapshot: emptySnapshot,
            historyVersions: [:],
            boardVersions: [:],
            deletedBoardVersions: [:],
            appliedBatchVersions: [:],
            activeBatch: nil,
            appliedCheckpointIDs: [],
            retiredImageVersions: [:],
            verifiedRetiredImageVersions: [:]
        )
        persistState()
    }

    private func record(_ snapshot: ClipboardStoreSnapshot) async {
        guard var current = state else { return }
        let records = difference(from: current.snapshot, to: snapshot)
        guard !records.isEmpty else {
            current.snapshot = snapshot
            state = current
            persistState()
            return
        }

        for chunk in chunked(records) {
            let existingRecords = current.activeBatch?.records ?? []
            let canAppend = !existingRecords.isEmpty
                && existingRecords.count + chunk.count <= 100
                && encodedBytes(existingRecords) + encodedBytes(chunk)
                    <= 256_000
            let sequence: UInt64
            let combinedRecords: [Record]
            if canAppend, let active = current.activeBatch {
                sequence = active.sequence
                combinedRecords = existingRecords + chunk
            } else {
                sequence = current.nextSequence
                current.nextSequence &+= 1
                combinedRecords = chunk
            }
            let batch = Batch(
                formatVersion: 2,
                id: UUID(),
                deviceID: current.deviceID,
                sequence: sequence,
                createdAt: Date(),
                records: combinedRecords
            )
            current.activeBatch = combinedRecords.count < 100
                    && encodedBytes(combinedRecords) < 256_000
                ? batch
                : nil
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
                return
            }
        }
        // Preserve the exact local ordering after the semantic operations have
        // been recorded. Remote devices reconstruct the same ordering from the
        // item timestamps.
        current.snapshot = snapshot
        state = current
        persistState()
    }

    private func difference(
        from previous: ClipboardStoreSnapshot,
        to next: ClipboardStoreSnapshot
    ) -> [Record] {
        var result: [Record] = []
        let now = Date()
        let oldHistory = Dictionary(
            uniqueKeysWithValues: previous.history.map { (contentKey($0), $0) }
        )
        for item in next.history
            where oldHistory[contentKey(item)] != item {
            result.append(Record(
                recordedAt: oldHistory[contentKey(item)] == nil
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

    private func pullRemoteBatches() async {
        guard var current = state else { return }
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: batchesDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        let urls = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "json" }
        var candidates: [(URL, Batch)] = []
        for url in urls {
            if ClipImageMaterializer.isDataLess(at: url) {
                _ = await ClipImageMaterializer.prepare(
                    at: url,
                    kind: .history,
                    timeout: .seconds(30)
                ) { _ in }
            }
            guard let batch = coordinatedRead(Batch.self, from: url),
                  batch.formatVersion == 2,
                  current.appliedBatchVersions[batchVersionKey(batch)]
                    != batch.id else { continue }
            candidates.append((url, batch))
        }
        candidates.sort {
            if $0.1.createdAt != $1.1.createdAt {
                return $0.1.createdAt < $1.1.createdAt
            }
            if $0.1.deviceID != $1.1.deviceID {
                return $0.1.deviceID.uuidString < $1.1.deviceID.uuidString
            }
            return $0.1.sequence < $1.1.sequence
        }
        for (_, batch) in candidates {
            apply(batch, to: &current)
            current.appliedBatchVersions[batchVersionKey(batch)] = batch.id
        }
        state = current
        persistState()
    }

    private func pullRemoteCheckpoints() async {
        guard var current = state else { return }
        var candidates: [(CheckpointManifest, CheckpointPayload)] = []
        for manifestURL in checkpointManifestURLs() {
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
            ), manifest.formatVersion == 2,
                  !(current.appliedCheckpointIDs ?? []).contains(manifest.id),
                  let payload = await readCheckpoint(
                    manifest,
                    manifestURL: manifestURL
                  ) else { continue }
            candidates.append((manifest, payload))
        }
        candidates.sort {
            if $0.0.createdAt != $1.0.createdAt {
                return $0.0.createdAt < $1.0.createdAt
            }
            return $0.0.id.uuidString < $1.0.id.uuidString
        }
        for (manifest, payload) in candidates {
            applyCheckpoint(payload, manifest: manifest, to: &current)
        }
        state = current
        persistState()
    }

    private func applyCheckpoint(
        _ payload: CheckpointPayload,
        manifest: CheckpointManifest,
        to state: inout State
    ) {
        var records: [Record] = []
        records += payload.snapshot.history.map { item in
            Record(
                recordedAt: payload.historyVersions[contentKey(item)]
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

    private func compactIfNeeded(force: Bool) async -> Bool {
        guard var current = state, outboxFiles().isEmpty else { return false }
        let compactionStartedAt = Date()
        let inventory = batchInventory()
        let sealedCount = inventory.count - Set(
            inventory.map { $0.batch.deviceID }
        ).count
        let totalBytes = inventory.reduce(0) { $0 + $1.byteCount }
        guard force || sealedCount >= 8 || totalBytes >= 2_000_000 else {
            return true
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
        guard let payloadData = try? JSONEncoder().encode(payload) else {
            return false
        }
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
            return false
        }

        var chunks: [CheckpointChunk] = []
        for (index, data) in splitCheckpointPayload(payloadData).enumerated() {
            let name = String(format: "chunk-%05d.part", index)
            let url = checkpointDirectory.appendingPathComponent(name)
            guard coordinatedWrite(data, to: url) else { return false }
            chunks.append(CheckpointChunk(
                name: name,
                byteCount: data.count,
                sha256: sha256(data)
            ))
        }
        let manifest = CheckpointManifest(
            formatVersion: 2,
            id: checkpointID,
            deviceID: current.deviceID,
            createdAt: Date(),
            payloadSHA256: sha256(payloadData),
            chunks: chunks,
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
              let verifiedPayload = await readCheckpoint(
                verifiedManifest,
                manifestURL: manifestURL
              ),
              contains(
                verifiedPayload.snapshot,
                allRecordsFrom: current.snapshot
              ) else { return false }

        var applied = current.appliedCheckpointIDs ?? []
        applied.insert(checkpointID)
        current.appliedCheckpointIDs = applied
        var verifiedRetirements = current.verifiedRetiredImageVersions ?? [:]
        mergeVersions(
            verifiedPayload.retiredImageVersions,
            into: &verifiedRetirements
        )
        current.verifiedRetiredImageVersions = verifiedRetirements
        state = current
        persistState()
        garbageCollectBatches(coveredBy: manifest, inventory: inventory)
        garbageCollectCheckpoints(includedBy: manifest)
        garbageCollectImages(
            referencedBy: current.snapshot,
            retiredImageVersions: current.verifiedRetiredImageVersions ?? [:],
            olderThan: compactionStartedAt.addingTimeInterval(
                -imageRetirementGrace
            )
        )
        return true
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
                let key = contentKey(item)
                guard record.recordedAt >= (state.historyVersions[key]
                    ?? .distantPast) else { continue }
                if let deletion = deletionMap(state.snapshot)[
                    contentDigest(item)
                ], deletion.historyDeletedAt >= item.createdAt {
                    continue
                }
                state.historyVersions[key] = record.recordedAt
                state.snapshot.history.removeAll {
                    contentKey($0) == key
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

    private func contentKey(_ item: ClipItem) -> String {
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

    private func contentDigest(_ item: ClipItem) -> String {
        SHA256.hash(data: Data(contentKey(item).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func batchFileName(_ batch: Batch) -> String {
        String(format: "%020llu.json", batch.sequence)
    }

    private func batchVersionKey(_ batch: Batch) -> String {
        "\(batch.deviceID.uuidString.lowercased()):\(batch.sequence)"
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

    private func splitCheckpointPayload(_ data: Data) -> [Data] {
        let chunkSize = 256_000
        guard !data.isEmpty else { return [Data()] }
        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(data.count, offset + chunkSize)
            chunks.append(data.subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }

    private func garbageCollectBatches(
        coveredBy manifest: CheckpointManifest,
        inventory: [BatchInventoryItem]
    ) {
        let highestSequence = Dictionary(
            grouping: inventory,
            by: { $0.batch.deviceID }
        ).mapValues { items in
            items.map(\.batch.sequence).max() ?? 0
        }
        for item in inventory {
            // The highest sequence may still be receiving appends. Retain one
            // such segment for every device even though the checkpoint covers
            // its current contents.
            guard item.batch.sequence
                    < (highestSequence[item.batch.deviceID] ?? 0),
                  manifest.coveredBatchVersions[
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
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: stateURL.path
            )
        } catch {
            logger.error(
                "Failed to persist incremental sync state domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)"
            )
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

extension IncrementalCloudSync.MigrationReceipt: Equatable {}

enum LegacyStoreMigrationIO {
    struct ReadResult: Sendable {
        let snapshots: [ClipboardStoreSnapshot]
        let versionDigests: [String]
    }

    static func readAllSnapshots(at url: URL) -> ReadResult? {
        let urls = [url] + (NSFileVersion.unresolvedConflictVersionsOfItem(
            at: url
        ) ?? []).map(\.url)
        var snapshots: [ClipboardStoreSnapshot] = []
        var digests: [String] = []
        for candidate in urls {
            guard let data = readData(at: candidate),
                  let snapshot = try? JSONDecoder().decode(
                    ClipboardStoreSnapshot.self,
                    from: data
                  ) else {
                return nil
            }
            snapshots.append(snapshot)
            digests.append(SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined())
        }
        return ReadResult(
            snapshots: snapshots,
            versionDigests: digests.sorted()
        )
    }

    private static func readData(at url: URL) -> Data? {
        var coordinatorError: NSError?
        var data: Data?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinatorError
        ) { coordinatedURL in
            data = try? Data(contentsOf: coordinatedURL)
        }
        return coordinatorError == nil ? data : nil
    }

    static func resolveConflictVersionsAfterMigration(
        at url: URL,
        expectedVersionDigests: [String]
    ) -> Bool {
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(
            at: url
        ) ?? []
        let urls = [url] + conflicts.map(\.url)
        let currentDigests = urls.compactMap { candidate in
            readData(at: candidate).map { data in
                SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }
                    .joined()
            }
        }.sorted()
        guard currentDigests == expectedVersionDigests else { return false }
        guard !conflicts.isEmpty else { return true }
        for version in conflicts { version.isResolved = true }
        do {
            try NSFileVersion.removeOtherVersionsOfItem(at: url)
            return (NSFileVersion.unresolvedConflictVersionsOfItem(at: url)
                ?? []).isEmpty
        } catch {
            return false
        }
    }

    static func sha256(at url: URL) -> String? {
        var coordinatorError: NSError?
        var digest: String?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinatorError
        ) { coordinatedURL in
            guard let data = try? Data(contentsOf: coordinatedURL) else {
                return
            }
            digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }
        return coordinatorError == nil ? digest : nil
    }

    /// Deletes only the exact legacy monolith, and only if it is unchanged
    /// since the verified v2 migration. Conflict versions cause a safe retry
    /// instead of being discarded here.
    static func deleteIfUnchanged(at url: URL, sha256 expected: String) -> Bool {
        guard (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [])
            .isEmpty,
              sha256(at: url) == expected else { return false }
        var coordinatorError: NSError?
        var removalError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinatorError
        ) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                removalError = error
            }
        }
        return coordinatorError == nil
            && removalError == nil
            && !FileManager.default.fileExists(atPath: url.path)
    }
}
