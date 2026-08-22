import AppKit

struct ClipItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var type: ClipType
    var text: String?
    var rtfData: Data?
    var imageFileName: String?
    var imageHash: String?
    var fileURLs: [String]
    var colorHex: String?

    var sourceBundleID: String?
    var sourceAppName: String?

    var customTitle: String?
    var createdAt: Date

    init(id: UUID = UUID(),
         type: ClipType,
         text: String? = nil,
         rtfData: Data? = nil,
         imageFileName: String? = nil,
         imageHash: String? = nil,
         fileURLs: [String] = [],
         colorHex: String? = nil,
         sourceBundleID: String? = nil,
         sourceAppName: String? = nil,
         customTitle: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.type = type
        self.text = text
        self.rtfData = rtfData
        self.imageFileName = imageFileName
        self.imageHash = imageHash
        self.fileURLs = fileURLs
        self.colorHex = colorHex
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.customTitle = customTitle
        self.createdAt = createdAt
    }

    var charCount: Int { text?.count ?? 0 }

    var hasTextContent: Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var hasTranslatableContent: Bool {
        hasTextContent || (type == .image && imageFileName != nil)
    }

    var displayTitle: String {
        if let t = customTitle, !t.isEmpty { return t }
        switch type {
        case .link:
            if let text {
                let bounded = String(text.prefix(2_048))
                let candidate = bounded.trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: candidate) {
                    return url.host ?? String(candidate.prefix(60))
                }
                return String(candidate.prefix(60))
            }
            return L10n.text("Link", "链接")
        case .image:
            return L10n.image
        case .file:
            return fileURLs.first.flatMap { URL(string: $0)?.lastPathComponent } ?? L10n.file
        case .color:
            return colorHex ?? L10n.color
        default:
            let bounded = String((text ?? "").prefix(256))
            let firstLine = bounded.firstIndex(where: \.isNewline).map {
                String(bounded[..<$0])
            } ?? bounded
            return firstLine.isEmpty ? type.label : String(firstLine.prefix(60))
        }
    }

    var searchableText: String {
        [customTitle, text, sourceAppName, fileURLs.joined(separator: " "), colorHex]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    var maximumSearchableUTF8Count: Int {
        let components = [customTitle, text, sourceAppName, colorHex]
            .compactMap { $0 }
        let rawBytes = components.reduce(into: 0) { total, value in
            total += value.utf8.count
        } + fileURLs.reduce(into: 0) { total, value in
            total += value.utf8.count
        }
        let (bytesWithSeparators, additionOverflow) = rawBytes
            .addingReportingOverflow(max(0, fileURLs.count - 1))
        let (sourceBytes, componentOverflow) = bytesWithSeparators
            .addingReportingOverflow(components.count)
        // Unicode lowercasing can expand a scalar. Reserving four times the
        // source byte count keeps the mmap builder bounded without committing
        // those untouched virtual pages to physical memory.
        let (maximum, multiplicationOverflow) = sourceBytes
            .multipliedReportingOverflow(by: 4)
        return additionOverflow || componentOverflow || multiplicationOverflow
            ? Int.max
            : maximum
    }

    func sameContent(as other: ClipItem) -> Bool {
        guard type == other.type else { return false }
        switch type {
        case .image:
            if let h = imageHash, let oh = other.imageHash { return h == oh }
            return imageFileName == other.imageFileName
        case .color:
            return colorHex == other.colorHex
        case .file:
            return fileURLs == other.fileURLs
        default:
            return text == other.text
        }
    }
}
