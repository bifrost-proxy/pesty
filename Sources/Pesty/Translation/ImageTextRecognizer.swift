import CoreGraphics
import Foundation
import ImageIO
@_weakLinked import Vision

enum ImageTextRecognitionError: Error {
    case imageUnavailable
    case noTextRecognized
}

enum ImageTextRecognizer {
    static let maximumPixelDimension = 2_048
    static let recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    static let automaticallyDetectsLanguage = true
    static let usesLanguageCorrection = true

    static func recognizeText(at url: URL) async throws -> String {
        let operation = RecognitionOperation(url: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try operation.run()
                    })
                }
            }
        } onCancel: {
            operation.cancel()
        }
    }

    static func recognizeTextSynchronously(at url: URL) throws -> String {
        try RecognitionOperation(url: url).run()
    }

    private final class RecognitionOperation: @unchecked Sendable {
        private let url: URL
        private let request = VNRecognizeTextRequest()

        init(url: URL) {
            self.url = url
            request.recognitionLevel = recognitionLevel
            request.revision = VNRecognizeTextRequestRevision3
            request.automaticallyDetectsLanguage = automaticallyDetectsLanguage
            request.usesLanguageCorrection = usesLanguageCorrection
        }

        func cancel() {
            request.cancel()
        }

        func run() throws -> String {
            try Task.checkCancellation()
            guard let image = downsampledImage(at: url) else {
                throw ImageTextRecognitionError.imageUnavailable
            }

            try VNImageRequestHandler(
                cgImage: image,
                orientation: .up,
                options: [:]
            ).perform([request])
            try Task.checkCancellation()

            let lines = (request.results ?? []).compactMap {
                observation -> Line? in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= 0.2 else {
                    return nil
                }
                let text = candidate.string.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !text.isEmpty else { return nil }
                return Line(text: text, boundingBox: observation.boundingBox)
            }.sorted(by: readingOrder)

            let text = lines.map(\.text).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw ImageTextRecognitionError.noTextRecognized
            }
            return text
        }
    }

    private struct Line {
        let text: String
        let boundingBox: CGRect
    }

    private static func readingOrder(_ lhs: Line, _ rhs: Line) -> Bool {
        let verticalDifference = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
        if verticalDifference > 0.012 {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    private static func downsampledImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        )
    }
}
