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
