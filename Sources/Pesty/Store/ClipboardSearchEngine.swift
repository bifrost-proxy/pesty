import Foundation
import Darwin

struct ClipboardSearchIndex: Sendable {
    let source: BarSource
    let contentRevision: UInt64
    // The array remains a copy-on-write view of the store. Normalized bytes
    // live in an mmap-backed Data so clearing search can return all index pages
    // to the OS instead of leaving them in malloc's resident-page cache.
    let items: [ClipItem]
    let searchableBytes: Data
    let searchableRanges: [Range<Int>]
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
        var mappedCapacity = 0
        for item in items {
            let (nextCapacity, overflow) = mappedCapacity.addingReportingOverflow(
                item.maximumSearchableUTF8Count
            )
            guard !overflow else { return nil }
            mappedCapacity = nextCapacity
        }
        guard !Task.isCancelled else { return nil }

        if mappedCapacity == 0 {
            return ClipboardSearchIndex(
                source: source,
                contentRevision: contentRevision,
                items: items,
                searchableBytes: Data(),
                searchableRanges: Array(repeating: 0..<0, count: items.count)
            )
        }

        guard let mappedBytes = mmap(
            nil,
            mappedCapacity,
            PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANON,
            -1,
            0
        ), mappedBytes != MAP_FAILED else {
            return nil
        }

        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(items.count)
        var offset = 0
        for (itemOffset, item) in items.enumerated() {
            if itemOffset.isMultiple(of: 8), Task.isCancelled {
                munmap(mappedBytes, mappedCapacity)
                return nil
            }
            let searchableText = item.searchableText
            let byteCount = searchableText.utf8.count
            guard byteCount <= mappedCapacity - offset else {
                munmap(mappedBytes, mappedCapacity)
                return nil
            }
            let destination = mappedBytes.advanced(by: offset)
            let copiedContiguously = searchableText.utf8
                .withContiguousStorageIfAvailable { bytes -> Bool in
                    if let baseAddress = bytes.baseAddress, !bytes.isEmpty {
                        memcpy(destination, baseAddress, bytes.count)
                    }
                    return true
                } ?? false
            if !copiedContiguously {
                var byteOffset = 0
                for byte in searchableText.utf8 {
                    destination.storeBytes(of: byte, toByteOffset: byteOffset,
                                           as: UInt8.self)
                    byteOffset += 1
                }
            }
            ranges.append(offset..<(offset + byteCount))
            offset += byteCount
        }
        guard !Task.isCancelled else {
            munmap(mappedBytes, mappedCapacity)
            return nil
        }

        let searchableBytes = Data(
            bytesNoCopy: mappedBytes,
            count: offset,
            deallocator: .custom { pointer, _ in
                munmap(pointer, mappedCapacity)
            }
        )
        return ClipboardSearchIndex(
            source: source,
            contentRevision: contentRevision,
            items: items,
            searchableBytes: searchableBytes,
            searchableRanges: ranges
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
                  index.searchableRanges.indices.contains(candidate) else { continue }
            if contains(
                needle,
                in: index.searchableBytes,
                range: index.searchableRanges[candidate]
            ) {
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

    private static func contains(
        _ needle: Data,
        in haystack: Data,
        range: Range<Int>
    ) -> Bool {
        guard !needle.isEmpty else { return true }
        guard range.count >= needle.count else { return false }
        guard range.count > cancellableChunkSize else {
            return haystack.range(of: needle, in: range) != nil
        }

        let overlap = max(0, needle.count - 1)
        var start = range.lowerBound
        while start < range.upperBound {
            if Task.isCancelled { return false }
            let upperBound = min(range.upperBound, start + cancellableChunkSize)
            let lowerBound = max(range.lowerBound, start - overlap)
            if haystack.range(of: needle, in: lowerBound..<upperBound) != nil {
                return true
            }
            start = upperBound
        }
        return false
    }
}
