import CryptoKit
import Foundation

enum IncrementalSyncCompactionVerifier {
    struct Result: Codable, Sendable {
        let success: Bool
        let historyAfterLimit: Int
        let historyAfterClear: Int
        let batchFilesAfterLimit: Int
        let checkpointFilesAfterLimit: Int
        let checkpointFilesAfterClear: Int
        let unreferencedImageDeleted: Bool
        let untrackedImagePreserved: Bool
        let clearedHistoryImageDeleted: Bool
        let retainedImagePreserved: Bool
        let pinnedImagePreserved: Bool
        let freshDeviceRebuiltLimit: Bool
        let freshDeviceRebuiltClear: Bool
        let idleSyncSkippedPersistence: Bool
        let idleSyncDecodedBatchCount: Int
        let publishedBatchesAreImmutable: Bool
    }

    static func run() async throws -> Result {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pesty-compaction-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = root.appendingPathComponent("cloud", isDirectory: true)
        let syncCloud = cloud.appendingPathComponent("sync-v2", isDirectory: true)
        let images = cloud.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(
            at: images,
            withIntermediateDirectories: true
        )

        let imageIndexes = Set([0, 200, 201])
        let allItems = (0..<250).map { index -> ClipItem in
            if imageIndexes.contains(index) {
                return ClipItem(
                    type: .image,
                    imageFileName: "image-\(index).png",
                    imageHash: "hash-\(index)",
                    createdAt: Date(timeIntervalSinceNow: -Double(index + 1))
                )
            }
            return ClipItem(
                type: .text,
                text: "pesty-compaction-\(index)",
                createdAt: Date(timeIntervalSinceNow: -Double(index + 1))
            )
        }
        for index in imageIndexes {
            let url = images.appendingPathComponent("image-\(index).png")
            try Data("synthetic-image-\(index)".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -3_600)],
                ofItemAtPath: url.path
            )
        }
        let untrackedImage = images.appendingPathComponent(
            "untracked-image.png"
        )
        try Data("synthetic-untracked-image".utf8).write(to: untrackedImage)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3_600)],
            ofItemAtPath: untrackedImage.path
        )

        let deviceA = IncrementalCloudSync(
            localDirectory: root.appendingPathComponent("device-a"),
            cloudDirectory: syncCloud,
            imageRetirementGrace: 0
        )
        let initial = ClipboardStoreSnapshot(
            history: allItems,
            pinboards: [],
            configuration: nil,
            deletions: nil
        )
        _ = await deviceA.synchronize(initial)
        let idleResult = await deviceA.synchronize(
            initial,
            recordLocalChanges: false
        )
        let idleSyncSkippedPersistence = idleResult?.persistedState == false
            && idleResult?.hasRemoteChanges == false
            && idleResult?.decodedBatchCount == 0
        let publishedBatchesAreImmutable = await verifyImmutableBatches(
            below: root.appendingPathComponent("immutable-batches")
        )

        let retained = Array(allItems.prefix(100))
        let removed = Array(allItems.dropFirst(100))
        let limitTombstones = removed.map { item in
            ClipDeletionTombstone(
                contentDigest: contentDigest(item),
                historyDeletedAt: Date(),
                pinboardDeletedAt: nil
            )
        }
        let pinned = Pinboard(
            name: "Pinned during compaction",
            items: [allItems[200]]
        )
        let limited = ClipboardStoreSnapshot(
            history: retained,
            pinboards: [pinned],
            configuration: nil,
            deletions: limitTombstones
        )
        let limitedResult = await deviceA.synchronize(
            limited,
            requestsCompaction: true
        )
        let batchFilesAfterLimit = fileCount(
            below: syncCloud.appendingPathComponent("batches"),
            named: nil,
            extension: "json"
        )
        let checkpointFilesAfterLimit = fileCount(
            below: syncCloud.appendingPathComponent("checkpoints"),
            named: "manifest.json",
            extension: nil
        )

        let retainedImage = images.appendingPathComponent("image-0.png")
        let pinnedImage = images.appendingPathComponent("image-200.png")
        let unreferencedImage = images.appendingPathComponent("image-201.png")
        let retainedImagePreserved = FileManager.default.fileExists(
            atPath: retainedImage.path
        )
        let pinnedImagePreserved = FileManager.default.fileExists(
            atPath: pinnedImage.path
        )
        let unreferencedImageDeleted = !FileManager.default.fileExists(
            atPath: unreferencedImage.path
        )
        let untrackedImagePreserved = FileManager.default.fileExists(
            atPath: untrackedImage.path
        )

        let deviceB = IncrementalCloudSync(
            localDirectory: root.appendingPathComponent("device-b"),
            cloudDirectory: syncCloud
        )
        let rebuiltLimit = await deviceB.synchronize(emptySnapshot)
        let freshDeviceRebuiltLimit = rebuiltLimit?.snapshot.history.count == 100
            && rebuiltLimit?.snapshot.pinboards.first?.items.count == 1

        let clearDate = Date().addingTimeInterval(1)
        let clearTombstones = limitTombstones + retained.map { item in
            ClipDeletionTombstone(
                contentDigest: contentDigest(item),
                historyDeletedAt: clearDate,
                pinboardDeletedAt: nil
            )
        }
        let cleared = ClipboardStoreSnapshot(
            history: [],
            pinboards: [pinned],
            configuration: nil,
            deletions: clearTombstones
        )
        let clearedResult = await deviceA.synchronize(
            cleared,
            requestsCompaction: true
        )
        let clearedHistoryImageDeleted = !FileManager.default.fileExists(
            atPath: retainedImage.path
        )
        let checkpointFilesAfterClear = fileCount(
            below: syncCloud.appendingPathComponent("checkpoints"),
            named: "manifest.json",
            extension: nil
        )
        let deviceC = IncrementalCloudSync(
            localDirectory: root.appendingPathComponent("device-c"),
            cloudDirectory: syncCloud
        )
        let rebuiltClear = await deviceC.synchronize(emptySnapshot)
        let freshDeviceRebuiltClear = rebuiltClear?.snapshot.history.isEmpty == true
            && rebuiltClear?.snapshot.pinboards.first?.items.count == 1

        let result = Result(
            success: limitedResult?.requestedCompactionCompleted == true
                && limitedResult?.snapshot.history.count == 100
                && clearedResult?.requestedCompactionCompleted == true
                && clearedResult?.snapshot.history.isEmpty == true
                && batchFilesAfterLimit == 1
                && checkpointFilesAfterLimit == 1
                && checkpointFilesAfterClear == 1
                && unreferencedImageDeleted
                && untrackedImagePreserved
                && clearedHistoryImageDeleted
                && retainedImagePreserved
                && pinnedImagePreserved
                && freshDeviceRebuiltLimit
                && freshDeviceRebuiltClear
                && idleSyncSkippedPersistence
                && publishedBatchesAreImmutable,
            historyAfterLimit: limitedResult?.snapshot.history.count ?? -1,
            historyAfterClear: clearedResult?.snapshot.history.count ?? -1,
            batchFilesAfterLimit: batchFilesAfterLimit,
            checkpointFilesAfterLimit: checkpointFilesAfterLimit,
            checkpointFilesAfterClear: checkpointFilesAfterClear,
            unreferencedImageDeleted: unreferencedImageDeleted,
            untrackedImagePreserved: untrackedImagePreserved,
            clearedHistoryImageDeleted: clearedHistoryImageDeleted,
            retainedImagePreserved: retainedImagePreserved,
            pinnedImagePreserved: pinnedImagePreserved,
            freshDeviceRebuiltLimit: freshDeviceRebuiltLimit,
            freshDeviceRebuiltClear: freshDeviceRebuiltClear,
            idleSyncSkippedPersistence: idleSyncSkippedPersistence,
            idleSyncDecodedBatchCount: idleResult?.decodedBatchCount ?? -1,
            publishedBatchesAreImmutable: publishedBatchesAreImmutable
        )
        return result
    }

    private static var emptySnapshot: ClipboardStoreSnapshot {
        ClipboardStoreSnapshot(
            history: [],
            pinboards: [],
            configuration: nil,
            deletions: nil
        )
    }

    private static func verifyImmutableBatches(below root: URL) async -> Bool {
        let cloud = root.appendingPathComponent("cloud/sync-v2")
        let sync = IncrementalCloudSync(
            localDirectory: root.appendingPathComponent("local"),
            cloudDirectory: cloud
        )
        let first = ClipItem(type: .text, text: "immutable-first")
        _ = await sync.synchronize(ClipboardStoreSnapshot(
            history: [first],
            pinboards: [],
            configuration: nil,
            deletions: nil
        ))
        let before = batchContents(below: cloud)
        let second = ClipItem(type: .text, text: "immutable-second")
        _ = await sync.synchronize(ClipboardStoreSnapshot(
            history: [second, first],
            pinboards: [],
            configuration: nil,
            deletions: nil
        ))
        let after = batchContents(below: cloud)
        return !before.isEmpty
            && after.count > before.count
            && before.allSatisfy { after[$0.key] == $0.value }
    }

    private static func batchContents(below root: URL) -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [:] }
        return enumerator.compactMap { value -> (String, Data)? in
            guard let url = value as? URL,
                  url.pathExtension == "json",
                  url.path.contains("/batches/"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return (url.path, data)
        }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }

    private static func contentDigest(_ item: ClipItem) -> String {
        let key: String
        switch item.type {
        case .image:
            key = "img:" + (item.imageHash ?? item.imageFileName
                ?? item.id.uuidString)
        case .color:
            key = "col:" + (item.colorHex ?? "")
        case .file:
            key = "file:" + item.fileURLs.joined(separator: "|")
        default:
            key = "txt:" + (item.text ?? "")
        }
        return SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func fileCount(
        below directory: URL,
        named name: String?,
        extension pathExtension: String?
    ) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return enumerator.compactMap { $0 as? URL }.filter { url in
            (name == nil || url.lastPathComponent == name)
                && (pathExtension == nil || url.pathExtension == pathExtension)
        }.count
    }
}
