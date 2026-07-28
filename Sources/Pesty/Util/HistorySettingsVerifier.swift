import Foundation

enum HistorySettingsVerifier {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws {
        guard HistoryRetentionPolicy.defaultLimit == 5_000 else {
            throw Failure(description: "the default history limit is not 5,000")
        }
        guard HistoryRetentionPolicy.trimDelay >= 10 else {
            throw Failure(description: "destructive history trimming waits less than 10 seconds")
        }
        guard BarLayoutPolicy.defaultHeight == 350 else {
            throw Failure(description: "the default panel height is not 350 pixels")
        }

        let finiteNodes = [
            (0.0, 100),
            (8.0, 900),
            (9.0, 1_000),
            (10.0, 2_000),
            (13.0, 5_000),
            (18.0, 10_000),
        ]
        for (position, expected) in finiteNodes {
            let actual = HistoryRetentionPolicy.selection(at: position)
            guard actual == expected else {
                throw Failure(
                    description: "slider position \(position) expected \(expected), got \(String(describing: actual))"
                )
            }
        }

        guard HistoryRetentionPolicy.selection(at: 19) == nil else {
            throw Failure(description: "the node after 10,000 is not unlimited")
        }
        guard HistoryRetentionPolicy.sliderPosition(limit: 5_000, unlimited: false) == 13,
              HistoryRetentionPolicy.sliderPosition(limit: 10_000, unlimited: false) == 18,
              HistoryRetentionPolicy.sliderPosition(limit: 5_000, unlimited: true) == 19 else {
            throw Failure(description: "saved history settings do not map back to slider nodes")
        }

        let sampleHistory = Array(0..<12_000)
        guard HistoryRetentionPolicy.retainedPrefix(
            of: sampleHistory,
            limit: 10_000
        ).count == 10_000 else {
            throw Failure(description: "the 10,000-item limit did not trim merged history")
        }
        guard HistoryRetentionPolicy.retainedPrefix(
            of: sampleHistory,
            limit: nil
        ).count == 12_000 else {
            throw Failure(description: "unlimited retention trimmed merged history")
        }

        let legacySnapshot = try JSONDecoder().decode(
            ClipboardStoreSnapshot.self,
            from: Data(#"{"history":[],"pinboards":[]}"#.utf8)
        )
        guard legacySnapshot.configuration == nil,
              legacySnapshot.deletions == nil else {
            throw Failure(description: "legacy store unexpectedly decoded newer snapshot fields")
        }

        let earlier = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)
        let effectiveAt = Date(timeIntervalSince1970: 2_010)
        let olderConfiguration = SyncedHistoryRetentionConfiguration(
            limit: 5_000,
            unlimited: false,
            updatedAt: earlier,
            effectiveAt: nil,
            revisionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let newerConfiguration = SyncedHistoryRetentionConfiguration(
            limit: 9_000,
            unlimited: false,
            updatedAt: later,
            effectiveAt: effectiveAt,
            revisionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
        guard newerConfiguration.supersedes(olderConfiguration),
              !olderConfiguration.supersedes(newerConfiguration) else {
            throw Failure(description: "history-setting conflict resolution is not last-writer-wins")
        }

        let lowerTieBreaker = SyncedHistoryRetentionConfiguration(
            limit: 100,
            unlimited: false,
            updatedAt: later,
            effectiveAt: effectiveAt,
            revisionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        guard newerConfiguration.supersedes(lowerTieBreaker) else {
            throw Failure(description: "equal-time history-setting conflicts are not deterministic")
        }

        let malformedUnlimited = SyncedHistoryRetentionConfiguration(
            limit: 50_000,
            unlimited: true,
            updatedAt: later,
            effectiveAt: effectiveAt,
            revisionID: UUID()
        ).normalized()
        guard malformedUnlimited.limit == HistoryRetentionPolicy.maximumFiniteLimit,
              malformedUnlimited.effectiveAt == nil else {
            throw Failure(description: "synchronized history settings were not normalized safely")
        }

        let synchronizedSnapshot = ClipboardStoreSnapshot(
            history: [],
            pinboards: [],
            configuration: SyncedConfiguration(historyRetention: newerConfiguration),
            deletions: [
                ClipDeletionTombstone(
                    contentDigest: String(repeating: "a", count: 64),
                    historyDeletedAt: later,
                    pinboardDeletedAt: earlier
                ),
            ]
        )
        let roundTripData = try JSONEncoder().encode(synchronizedSnapshot)
        let roundTrip = try JSONDecoder().decode(
            ClipboardStoreSnapshot.self,
            from: roundTripData
        )
        guard roundTrip.configuration?.historyRetention == newerConfiguration else {
            throw Failure(description: "synchronized history settings did not survive JSON round-trip")
        }
        guard roundTrip.deletions == synchronizedSnapshot.deletions else {
            throw Failure(description: "deletion tombstones did not survive JSON round-trip")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesty-history-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(repeating: 0xA5, count: 1_024)
            .write(to: directory.appendingPathComponent("store.json"))
        let images = directory.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: 512)
            .write(to: images.appendingPathComponent("sample.png"))

        let bytes = HistoryStorageUsage.bytes(in: directory)
        guard bytes == 1_536 else {
            throw Failure(description: "storage usage expected 1536 bytes, got \(bytes)")
        }
    }
}
