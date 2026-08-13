import CryptoKit
import Foundation
import OSLog

/// The v2 iCloud format uses small rolling, device-owned segments. A device may
/// append to its current segment until it reaches the size limit, but never
/// rewrites another device's files. The UI always reads the local materialized
/// snapshot instead of waiting for File Provider.
actor IncrementalCloudSync {
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
    }

    private let localDirectory: URL
    private let cloudDirectory: URL
    private let stateURL: URL
    private let outboxDirectory: URL
    private let batchesDirectory: URL
    private let migrationDirectory: URL
    private let logger = Logger(
        subsystem: "com.bifrostproxy.pesty",
        category: "incremental-cloud-sync"
    )
    private var state: State?

    init(localDirectory: URL, cloudDirectory: URL) {
        self.localDirectory = localDirectory
        self.cloudDirectory = cloudDirectory
        stateURL = localDirectory.appendingPathComponent("state.json")
        outboxDirectory = localDirectory.appendingPathComponent(
            "outbox",
            isDirectory: true
        )
        batchesDirectory = cloudDirectory.appendingPathComponent(
            "batches",
            isDirectory: true
        )
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

    func synchronize(_ snapshot: ClipboardStoreSnapshot) async
        -> ClipboardStoreSnapshot? {
        prepareDirectories()
        loadStateIfNeeded()
        await record(snapshot)
        await flushOutbox()
        await pullRemoteBatches()
        return state?.snapshot
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
            activeBatch: nil
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
