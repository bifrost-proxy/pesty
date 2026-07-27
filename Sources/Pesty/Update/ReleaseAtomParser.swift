import Foundation

struct ReleaseAtomEntry: Equatable {
    let tag: String
    let releaseURL: URL
    let content: String
}

final class ReleaseAtomParser: NSObject, XMLParserDelegate {
    private var entries: [ReleaseAtomEntry] = []
    private var currentTag: String?
    private var currentReleaseURL: URL?
    private var currentContent = ""
    private var text = ""
    private var insideEntry = false
    private var parseFailure: Error?

    static func parse(_ data: Data) throws -> [ReleaseAtomEntry] {
        let delegate = ReleaseAtomParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.parseFailure == nil else {
            throw delegate.parseFailure ?? parser.parserError ?? UpdateService.Failure.invalidRelease
        }
        return delegate.entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        text = ""
        if elementName == "entry" {
            insideEntry = true
            currentTag = nil
            currentReleaseURL = nil
            currentContent = ""
        } else if insideEntry,
                  elementName == "link",
                  attributeDict["rel"] == "alternate",
                  let value = attributeDict["href"],
                  let url = URL(string: value) {
            currentReleaseURL = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideEntry else { return }
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard insideEntry else { return }
        switch elementName {
        case "id":
            if let component = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "/")
                .last {
                currentTag = String(component)
            }
        case "content":
            currentContent = text
        case "entry":
            if let currentTag, let currentReleaseURL {
                entries.append(
                    ReleaseAtomEntry(
                        tag: currentTag,
                        releaseURL: currentReleaseURL,
                        content: currentContent
                    )
                )
            }
            insideEntry = false
        default:
            break
        }
        text = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parseFailure = parseError
    }
}
