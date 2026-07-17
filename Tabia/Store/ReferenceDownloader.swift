import Foundation
import CryptoKit

/// The manifest published alongside the hosted reference database (produced by chess-db-builder's
/// `--export-pgn`). Read from `<baseURL>/manifest.json`.
struct ReferenceManifest: Codable {
    struct Base: Codable {
        let file: String
        let url: String
        let format: String     // "pgn.gz" (app) or "pgn.zst"
        let sha256: String
        let bytes: Int64
        let games: Int
    }
    let schema_version: Int
    let base: Base
    let attribution: String?
    let license: String?
}

/// Downloads the hosted reference database (manifest → compressed PGN) with progress, integrity
/// verification, and native gzip decompression. The decompressed PGN is handed to the existing
/// streaming `Ingestor` (which dedups via `game_hash`). Kernel-managed download → efficient + supports
/// in-session resume on transient failure.
final class ReferenceDownloader: NSObject, URLSessionDownloadDelegate {

    enum DownloadError: Error { case badManifest, unsupportedFormat, checksumMismatch, httpError(Int), noURL }

    private var progressHandler: ((Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var currentTask: URLSessionDownloadTask?
    private var isCancelled = false

    /// Cancel an in-flight download. The pending `runDownload` continuation resumes with a
    /// cancellation error, which `download(...)` rethrows immediately (no resume retry).
    func cancel() {
        isCancelled = true
        currentTask?.cancel()
    }

    // MARK: - Manifest

    func fetchManifest(_ manifestURL: URL) async throws -> ReferenceManifest {
        var req = URLRequest(url: manifestURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.httpError(http.statusCode)
        }
        do { return try JSONDecoder().decode(ReferenceManifest.self, from: data) }
        catch { throw DownloadError.badManifest }
    }

    // MARK: - Download (kernel-managed, with progress)

    /// Download `base` to `dst`. `retriesOnFailure` uses URLSession resume data to continue an
    /// interrupted transfer without restarting from zero.
    func download(base: ReferenceManifest.Base, to dst: URL,
                  retriesOnFailure: Int = 3,
                  progress: @escaping (Double) -> Void) async throws {
        guard let url = URL(string: base.url) else { throw DownloadError.noURL }
        self.destination = dst
        self.progressHandler = progress

        var resumeData: Data?
        var attempt = 0
        while true {
            do {
                let temp = try await runDownload(url: url, resumeData: resumeData)
                if FileManager.default.fileExists(atPath: dst.path) { try? FileManager.default.removeItem(at: dst) }
                try FileManager.default.moveItem(at: temp, to: dst)
                return
            } catch {
                if isCancelled { throw error }               // deliberate cancel — don't retry
                attempt += 1
                if attempt > retriesOnFailure { throw error }
                // Capture resume data if the failure provided it.
                resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            }
        }
    }

    private func runDownload(url: URL, resumeData: Data?) async throws -> URL {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let task = resumeData.map { session.downloadTask(withResumeData: $0) }
                ?? session.downloadTask(with: url)
            self.currentTask = task
            if isCancelled { task.cancel() }                 // cancel arrived before the task existed
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Move out of the temp location synchronously (it's deleted when this returns).
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("tabia-refdb-\(UUID().uuidString).part")
        do {
            try FileManager.default.moveItem(at: location, to: staged)
            continuation?.resume(returning: staged)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.resume(throwing: error); continuation = nil }
    }

    // MARK: - Verify + decompress

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while case let chunk = handle.readData(ofLength: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Decompress the downloaded artifact to a plain `.pgn`. Only gzip is supported natively (zstd
    /// would need an external dependency — the app artifact must be `pgn.gz`).
    static func decompressToPGN(_ src: URL, format: String) throws -> URL {
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("tabia-refdb-\(UUID().uuidString).pgn")
        switch format {
        case "pgn.gz":
            try GzipDecompressor.decompress(src: src, to: dst)
        default:
            throw DownloadError.unsupportedFormat
        }
        return dst
    }
}
