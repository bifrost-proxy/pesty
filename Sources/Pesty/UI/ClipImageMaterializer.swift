import Darwin
import Foundation
import OSLog

enum ClipImageLoadPhase: String, Sendable {
    case checkingICloud
    case downloadingICloud
    case reading
    case ready
    case failed
}

enum ClipImageMaterializer {
    typealias PhaseHandler = @MainActor @Sendable (ClipImageLoadPhase) -> Void

    private static let logger = Logger(
        subsystem: "com.bifrostproxy.pesty",
        category: "image-materializer"
    )
    private static let downloadTimeout: Duration = .seconds(30)
    private static let pollInterval: Duration = .milliseconds(200)

    static func prepare(
        at url: URL,
        phase: @escaping PhaseHandler
    ) async -> Bool {
        await phase(.checkingICloud)

        if let delay = automatedDownloadDelay {
            await phase(.downloadingICloud)
            do {
                try await Task.sleep(for: .milliseconds(delay))
            } catch {
                return false
            }
            guard !Task.isCancelled else { return false }
            await phase(.reading)
            return true
        }

        let initialState = await fileState(at: url)
        guard initialState.exists else {
            logger.error(
                "Image file is missing id=\(url.lastPathComponent, privacy: .public)"
            )
            await phase(.failed)
            return false
        }

        if initialState.needsDownload {
            await phase(.downloadingICloud)
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch {
                logger.error(
                    "Failed to request iCloud image download id=\(url.lastPathComponent, privacy: .public) domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)"
                )
                await phase(.failed)
                return false
            }

            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: downloadTimeout)
            while clock.now < deadline {
                guard !Task.isCancelled else { return false }
                do {
                    try await Task.sleep(for: pollInterval)
                } catch {
                    return false
                }
                let state = await fileState(at: url)
                if let error = state.downloadError {
                    logger.error(
                        "iCloud image download failed id=\(url.lastPathComponent, privacy: .public) domain=\(error.domain, privacy: .public) code=\(error.code)"
                    )
                    await phase(.failed)
                    return false
                }
                if state.exists && !state.needsDownload {
                    await phase(.reading)
                    return true
                }
            }

            logger.error(
                "Timed out downloading iCloud image id=\(url.lastPathComponent, privacy: .public)"
            )
            await phase(.failed)
            return false
        }

        await phase(.reading)
        return true
    }

    private struct FileState: @unchecked Sendable {
        let exists: Bool
        let needsDownload: Bool
        let downloadError: NSError?
    }

    private static func fileState(at url: URL) async -> FileState {
        await Task.detached(priority: .utility) {
            let exists = FileManager.default.fileExists(atPath: url.path)
            guard exists else {
                return FileState(
                    exists: false,
                    needsDownload: false,
                    downloadError: nil
                )
            }

            let values = try? url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemDownloadingErrorKey,
            ])
            let notDownloaded = values?.isUbiquitousItem == true
                && values?.ubiquitousItemDownloadingStatus
                    == .notDownloaded
            return FileState(
                exists: true,
                needsDownload: notDownloaded || isDataLess(at: url),
                downloadError: values?.ubiquitousItemDownloadingError
                    as NSError?
            )
        }.value
    }

    private static func isDataLess(at url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            var info = Darwin.stat()
            guard Darwin.lstat(path, &info) == 0 else { return false }
            // SF_DATALESS is present in sys/stat.h but is not imported by
            // Swift's Darwin overlay.
            let dataLessFlag: UInt32 = 0x4000_0000
            return info.st_flags & dataLessFlag != 0
        }
    }

    private static var automatedDownloadDelay: Int? {
        guard ProcessInfo.processInfo.environment[
                  "PESTY_AUTOMATED_TEST_DATA_DIR"
              ]?.isEmpty == false,
              let raw = ProcessInfo.processInfo.environment[
                  "PESTY_AUTOMATED_IMAGE_DOWNLOAD_DELAY_MS"
              ],
              let delay = Int(raw),
              delay > 0 else {
            return nil
        }
        return delay
    }
}
