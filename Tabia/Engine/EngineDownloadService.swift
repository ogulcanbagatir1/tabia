import Foundation
import SwiftUI
import AppKit

// MARK: - Engine Registry

enum EngineDownloadType {
    case directDownload        // Stockfish, Lc0 — download from GitHub
    case externalLink(URL)     // Komodo — open browser
}

struct Lc0WeightsOption: Identifiable {
    let id: String
    let name: String
    let description: String
    let size: String
    let url: URL

    static let presets: [Lc0WeightsOption] = [
        Lc0WeightsOption(
            id: "bt4",
            name: "BT4 (Very Large)",
            description: "Best quality, needs 4 GB GPU memory",
            size: "~365 MB",
            url: URL(string: "https://storage.lczero.org/files/networks-contrib/BT4-1024x15x32h-swa-6147500-policytune-332.pb.gz")!
        ),
        Lc0WeightsOption(
            id: "bt3",
            name: "BT3 (Large)",
            description: "Great quality, needs 2.6 GB GPU memory",
            size: "~190 MB",
            url: URL(string: "https://storage.lczero.org/files/networks-contrib/BT3-768x15x24h-swa-2790000.pb.gz")!
        ),
        Lc0WeightsOption(
            id: "medium",
            name: "T3 (Medium)",
            description: "Good quality, needs 1.8 GB GPU memory",
            size: "~150 MB",
            url: URL(string: "https://storage.lczero.org/files/networks-contrib/t3-512x15x16h-distill-swa-2767500.pb.gz")!
        ),
        Lc0WeightsOption(
            id: "small",
            name: "T1 (Small)",
            description: "Fast, needs 1.6 GB GPU memory",
            size: "~35 MB",
            url: URL(string: "https://storage.lczero.org/files/networks-contrib/t1-256x10-distilled-swa-2432500.pb.gz")!
        ),
    ]
}

struct EngineRegistryEntry: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: Color
    let downloadType: EngineDownloadType
    let binaryName: String
    let githubRepo: String?         // e.g. "official-stockfish/Stockfish" — for API-based download
    let archiveType: ArchiveType
    let needsWeights: Bool

    enum ArchiveType {
        case tar
        case zip
        case none
    }

    static let available: [EngineRegistryEntry] = [
        EngineRegistryEntry(
            id: "stockfish",
            name: "Stockfish",
            description: "Strongest open-source chess engine (NNUE)",
            icon: "cpu",
            color: .green,
            downloadType: .directDownload,
            binaryName: "stockfish",
            githubRepo: "official-stockfish/Stockfish",
            archiveType: .tar,
            needsWeights: false
        ),
        EngineRegistryEntry(
            id: "lc0",
            name: "Leela Chess Zero",
            description: "Neural network engine with GPU acceleration",
            icon: "brain",
            color: .purple,
            downloadType: .directDownload,
            binaryName: "lc0",
            githubRepo: "LeelaChessZero/lc0",
            archiveType: .zip,
            needsWeights: true
        ),
        EngineRegistryEntry(
            id: "komodo",
            name: "Komodo Dragon",
            description: "Commercial engine — free version available",
            icon: "flame",
            color: .orange,
            downloadType: .externalLink(URL(string: "https://komodochess.com/downloads.htm")!),
            binaryName: "dragon",
            githubRepo: nil,
            archiveType: .none,
            needsWeights: false
        ),
    ]
}

// MARK: - GitHub Release Asset

private struct GitHubRelease: Decodable {
    let tag_name: String
    let assets: [GitHubAsset]
}

private struct GitHubAsset: Decodable {
    let name: String
    let browser_download_url: String
}

// MARK: - Download Service

class EngineDownloadService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var statusText: String = ""
    @Published var error: String?

    private var downloadTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?

    static let enginesDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Engines")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Public API

    /// Download and install an engine. Returns the path to the binary.
    func downloadEngine(entry: EngineRegistryEntry) async throws -> String {
        await MainActor.run {
            isDownloading = true
            progress = 0
            statusText = "Resolving latest version..."
            error = nil
        }

        do {
            // 1. Resolve download URL from GitHub API
            let (downloadURL, version) = try await resolveDownloadURL(for: entry)

            await MainActor.run { statusText = "Downloading \(entry.name)..." }

            // 2. Download the archive
            let archiveURL = try await downloadFile(from: downloadURL)

            // 3. Create destination directory
            let engineDir = Self.enginesDirectory.appendingPathComponent(entry.id)
            let fm = FileManager.default
            if fm.fileExists(atPath: engineDir.path) {
                try fm.removeItem(at: engineDir)
            }
            try fm.createDirectory(at: engineDir, withIntermediateDirectories: true)

            await MainActor.run { statusText = "Extracting..." }

            // 4. Extract archive
            try extractArchive(archiveURL, to: engineDir, type: entry.archiveType)
            try? fm.removeItem(at: archiveURL)

            // 5. Find the binary
            let binaryPath = try findBinary(named: entry.binaryName, in: engineDir)

            // 6. Set executable permissions and remove quarantine
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath)
            removeQuarantine(at: engineDir)

            // 7. Save version info
            let versionFile = engineDir.appendingPathComponent("version.txt")
            try version.write(to: versionFile, atomically: true, encoding: .utf8)

            await MainActor.run {
                isDownloading = false
                progress = 1.0
                statusText = ""
            }

            return binaryPath
        } catch {
            await MainActor.run {
                self.isDownloading = false
                self.statusText = ""
                self.error = error.localizedDescription
            }
            throw error
        }
    }

    /// Download Lc0 neural network weights. Returns the path to the weights file.
    func downloadWeights(option: Lc0WeightsOption) async throws -> String {
        await MainActor.run {
            isDownloading = true
            progress = 0
            statusText = "Downloading \(option.name) weights..."
            error = nil
        }

        do {
            let weightsURL = try await downloadFile(from: option.url)
            let fm = FileManager.default

            // Place weights in lc0 engine directory
            let lc0Dir = Self.enginesDirectory.appendingPathComponent("lc0")
            try fm.createDirectory(at: lc0Dir, withIntermediateDirectories: true)

            let destPath = lc0Dir.appendingPathComponent(option.url.lastPathComponent)
            if fm.fileExists(atPath: destPath.path) {
                try fm.removeItem(at: destPath)
            }
            try fm.moveItem(at: weightsURL, to: destPath)

            await MainActor.run {
                isDownloading = false
                progress = 1.0
                statusText = ""
            }

            return destPath.path
        } catch {
            await MainActor.run {
                self.isDownloading = false
                self.statusText = ""
                self.error = error.localizedDescription
            }
            throw error
        }
    }

    func openExternalDownload(url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - GitHub API Resolution

    private func resolveDownloadURL(for entry: EngineRegistryEntry) async throws -> (URL, String) {
        guard let repo = entry.githubRepo else {
            throw DownloadError.noGitHubRepo
        }

        let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        // Find the macOS asset for the current architecture
        #if arch(arm64)
        let archKeywords = ["macos", "apple-silicon", "m1", "arm64", "aarch64"]
        #else
        let archKeywords = ["macos", "x86-64", "x86_64", "intel", "amd64"]
        #endif

        // First try to find an asset matching both OS and architecture
        let nameLower = { (asset: GitHubAsset) in asset.name.lowercased() }

        // Filter assets that contain "macos" or "apple" or "darwin"
        let macAssets = release.assets.filter { asset in
            let n = asset.name.lowercased()
            return n.contains("macos") || n.contains("apple") || n.contains("darwin") || n.contains("mac")
        }

        // Among mac assets, prefer one matching our architecture
        var bestAsset: GitHubAsset?

        #if arch(arm64)
        bestAsset = macAssets.first { asset in
            let n = asset.name.lowercased()
            return n.contains("apple-silicon") || n.contains("m1") || n.contains("arm64") || n.contains("aarch64")
        }
        #else
        bestAsset = macAssets.first { asset in
            let n = asset.name.lowercased()
            return n.contains("x86-64") || n.contains("x86_64") || n.contains("intel") || n.contains("amd64") || n.contains("modern")
        }
        #endif

        // Fallback: any macOS asset
        if bestAsset == nil {
            bestAsset = macAssets.first
        }

        guard let asset = bestAsset,
              let url = URL(string: asset.browser_download_url) else {
            throw DownloadError.noMacOSBinary
        }

        return (url, release.tag_name)
    }

    // MARK: - Archive Extraction

    private func extractArchive(_ archiveURL: URL, to destination: URL, type: EngineRegistryEntry.ArchiveType) throws {
        let process = Process()

        switch type {
        case .tar:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", archiveURL.path, "-C", destination.path]
        case .zip:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", archiveURL.path, destination.path]
        case .none:
            return
        }

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DownloadError.extractionFailed
        }
    }

    private func removeQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - File Download

    private func downloadFile(from url: URL) async throws -> URL {
        // A delegate-based URLSession strongly retains its delegate (self) until it is invalidated.
        // Create it here and invalidate on exit so neither the session nor its retain on this service
        // leaks once the download finishes.
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            downloadTask = session.downloadTask(with: url)
            downloadTask?.resume()
        }
    }

    // MARK: - File System Helpers

    private func findBinary(named name: String, in directory: URL) throws -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw DownloadError.binaryNotFound
        }

        let skipExtensions: Set<String> = ["txt", "md", "cff", "json", "yml", "yaml", "png", "jpg",
                                            "html", "css", "js", "h", "c", "cpp", "rst", "py",
                                            "sh", "bat", "ps1", "cmake", "log", "cfg", "ini",
                                            "nnue", "nn", "gz", "tar", "zip", "7z"]

        // Exact name match first, then prefix match for platform-suffixed binaries
        // (e.g. "stockfish-macos-m1-apple-silicon" for binaryName "stockfish")
        var exactMatch: String?
        var prefixMatch: String?

        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            let ext = fileURL.pathExtension.lowercased()

            // Skip directories
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }

            // Skip known non-binary extensions
            if !ext.isEmpty && skipExtensions.contains(ext) { continue }

            let filenameLower = filename.lowercased()
            let nameLower = name.lowercased()

            // Exact name match (don't require executable bit — we set it after)
            if filenameLower == nameLower {
                exactMatch = fileURL.path
                break
            }

            // Prefix match for platform-suffixed binaries
            if prefixMatch == nil && filenameLower.hasPrefix(nameLower) {
                prefixMatch = fileURL.path
            }
        }

        if let match = exactMatch {
            return match
        }
        if let match = prefixMatch {
            return match
        }

        throw DownloadError.binaryNotFound
    }

    func isEngineDownloaded(entry: EngineRegistryEntry) -> Bool {
        let engineDir = Self.enginesDirectory.appendingPathComponent(entry.id)
        let fm = FileManager.default
        guard fm.fileExists(atPath: engineDir.path) else { return false }
        return (try? findBinary(named: entry.binaryName, in: engineDir)) != nil
    }

    func enginePath(for entry: EngineRegistryEntry) -> String? {
        let engineDir = Self.enginesDirectory.appendingPathComponent(entry.id)
        return try? findBinary(named: entry.binaryName, in: engineDir)
    }

    func installedVersion(for entry: EngineRegistryEntry) -> String? {
        let versionFile = Self.enginesDirectory
            .appendingPathComponent(entry.id)
            .appendingPathComponent("version.txt")
        return try? String(contentsOf: versionFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hasWeightsInstalled() -> Bool {
        let lc0Dir = Self.enginesDirectory.appendingPathComponent("lc0")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: lc0Dir, includingPropertiesForKeys: nil) else { return false }
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "gz" && fileURL.lastPathComponent.contains(".pb") {
                return true
            }
        }
        return false
    }

    func deleteEngine(entry: EngineRegistryEntry) {
        let engineDir = Self.enginesDirectory.appendingPathComponent(entry.id)
        try? FileManager.default.removeItem(at: engineDir)
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let ext = downloadTask.originalRequest?.url?.pathExtension ?? "download"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try FileManager.default.moveItem(at: location, to: tempURL)
            continuation?.resume(returning: tempURL)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let p = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        DispatchQueue.main.async {
            self.progress = p
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
            continuation = nil
            DispatchQueue.main.async {
                self.isDownloading = false
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Errors

    enum DownloadError: LocalizedError {
        case extractionFailed
        case binaryNotFound
        case noGitHubRepo
        case noMacOSBinary

        var errorDescription: String? {
            switch self {
            case .extractionFailed: return "Failed to extract engine archive"
            case .binaryNotFound: return "Engine binary not found in archive"
            case .noGitHubRepo: return "No GitHub repository configured for this engine"
            case .noMacOSBinary: return "No macOS binary found in the latest release"
            }
        }
    }
}
