import Foundation

struct ClipboardSearchIndex: Sendable {
    let source: BarSource
    let contentRevision: UInt64
    // Keep the original copy-on-write array instead of duplicating every
    // ClipItem struct into the index. Only normalized search bytes allocate.
    let items: [ClipItem]
    let searchableBytes: [Data]
}

struct ClipboardSearchResult: Sendable {
    let indices: [Int]
    let items: [ClipItem]
    let scannedCount: Int
}

enum ClipboardSearchEngine {
    private static let cancellableChunkSize = 128 * 1_024

    static func build(
        items: [ClipItem],
        source: BarSource,
        contentRevision: UInt64
    ) -> ClipboardSearchIndex? {
        var searchableBytes: [Data] = []
        searchableBytes.reserveCapacity(items.count)
        for (offset, item) in items.enumerated() {
            if offset.isMultiple(of: 8), Task.isCancelled { return nil }
            searchableBytes.append(Data(item.searchableText.utf8))
        }
        guard !Task.isCancelled else { return nil }
        return ClipboardSearchIndex(
            source: source,
            contentRevision: contentRevision,
            items: items,
            searchableBytes: searchableBytes
        )
    }

    static func filter(
        _ index: ClipboardSearchIndex,
        query: String,
        candidates: [Int]
    ) -> ClipboardSearchResult? {
        let needle = Data(query.utf8)
        var matchingIndices: [Int] = []
        var matchingItems: [ClipItem] = []
        matchingIndices.reserveCapacity(min(candidates.count, 256))
        matchingItems.reserveCapacity(min(candidates.count, 256))

        for (offset, candidate) in candidates.enumerated() {
            if offset.isMultiple(of: 8), Task.isCancelled { return nil }
            guard index.items.indices.contains(candidate),
                  index.searchableBytes.indices.contains(candidate) else { continue }
            if contains(needle, in: index.searchableBytes[candidate]) {
                matchingIndices.append(candidate)
                matchingItems.append(index.items[candidate])
            }
        }
        guard !Task.isCancelled else { return nil }
        return ClipboardSearchResult(
            indices: matchingIndices,
            items: matchingItems,
            scannedCount: candidates.count
        )
    }

    private static func contains(_ needle: Data, in haystack: Data) -> Bool {
        guard !needle.isEmpty else { return true }
        guard haystack.count >= needle.count else { return false }
        guard haystack.count > cancellableChunkSize else {
            return haystack.range(of: needle) != nil
        }

        let overlap = max(0, needle.count - 1)
        var start = 0
        while start < haystack.count {
            if Task.isCancelled { return false }
            let upperBound = min(haystack.count, start + cancellableChunkSize)
            let lowerBound = max(0, start - overlap)
            if haystack.range(of: needle, in: lowerBound..<upperBound) != nil {
                return true
            }
            start = upperBound
        }
        return false
    }
}
