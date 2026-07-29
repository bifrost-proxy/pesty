import Foundation
import SwiftUI

enum ExplanationMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unordered(String)
    case ordered(number: Int, text: String)
    case quote(String)
    case code(String)
}

enum ExplanationMarkdownParser {
    static func blocks(from markdown: String) -> [ExplanationMarkdownBlock] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var blocks: [ExplanationMarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var isInsideCodeFence = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            guard !codeLines.isEmpty else { return }
            blocks.append(.code(codeLines.joined(separator: "\n")))
            codeLines.removeAll(keepingCapacity: true)
        }

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                flushParagraph()
                if isInsideCodeFence {
                    flushCode()
                }
                isInsideCodeFence.toggle()
                continue
            }

            if isInsideCodeFence {
                codeLines.append(rawLine)
                continue
            }

            guard !line.isEmpty else {
                flushParagraph()
                continue
            }

            if let heading = heading(from: line) {
                flushParagraph()
                blocks.append(heading)
            } else if let item = unorderedListItem(from: line) {
                flushParagraph()
                blocks.append(.unordered(item))
            } else if let item = orderedListItem(from: line) {
                flushParagraph()
                blocks.append(.ordered(number: item.number, text: item.text))
            } else if line.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst(2))))
            } else {
                paragraphLines.append(line)
            }
        }

        flushParagraph()
        flushCode()
        return blocks.isEmpty && !markdown.isEmpty ? [.paragraph(markdown)] : blocks
    }

    static func inlineAttributedString(from markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    private static func heading(from line: String) -> ExplanationMarkdownBlock? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(markerCount),
              line.hasPrefix(String(repeating: "#", count: markerCount) + " ") else {
            return nil
        }
        return .heading(
            level: markerCount,
            text: String(line.dropFirst(markerCount + 1))
        )
    }

    private static func unorderedListItem(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedListItem(from line: String) -> (number: Int, text: String)? {
        guard let markerRange = line.range(
            of: #"^\d+[.)]\s+"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let marker = String(line[markerRange])
        let numberText = marker.prefix(while: { $0.isNumber })
        guard let number = Int(numberText) else { return nil }
        return (number, String(line[markerRange.upperBound...]))
    }
}

struct ExplanationMarkdownView: View {
    let markdown: String
    let foregroundColor: Color

    private var blocks: [ExplanationMarkdownBlock] {
        ExplanationMarkdownParser.blocks(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: ExplanationMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(.system(size: headingFontSize(level), weight: .semibold))
                .padding(.top, level == 1 ? 2 : 0)
        case .paragraph(let text):
            inlineText(text)
                .font(.system(size: 13))
                .lineSpacing(1.5)
        case .unordered(let text):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("•")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 10)
                inlineText(text)
                    .font(.system(size: 13))
                    .lineSpacing(1.5)
            }
        case .ordered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(number).")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(minWidth: 16, alignment: .trailing)
                inlineText(text)
                    .font(.system(size: 13))
                    .lineSpacing(1.5)
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 7) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 2)
                inlineText(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(foregroundColor.opacity(0.82))
                    .lineSpacing(1.5)
            }
        case .code(let text):
            Text(text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(foregroundColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(
                    foregroundColor.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
    }

    private func inlineText(_ markdown: String) -> Text {
        Text(ExplanationMarkdownParser.inlineAttributedString(from: markdown))
            .foregroundStyle(foregroundColor)
    }

    private func headingFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 14.5
        case 2: 14
        default: 13.5
        }
    }
}
