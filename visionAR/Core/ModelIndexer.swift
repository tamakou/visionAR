import Foundation
import CryptoKit

struct ModelMetadata: Codable, Identifiable, Hashable {
    var id: String { relativePath }
    let fileName: String
    let relativePath: String
    let lastModified: Date
    let sha256: String
}

actor ModelIndexer {
    enum IndexerError: Error {
        case folderUnavailable
    }

    private let fileManager = FileManager.default
    private let folderAccessManager: FolderAccessManager
    private let catalogURL: URL

    private var cachedMetadata: [String: ModelMetadata] = [:]

    init(folderAccessManager: FolderAccessManager) async throws {
        self.folderAccessManager = folderAccessManager
        let modelsDirectory = try await folderAccessManager.applicationSupportModelsDirectory()
        catalogURL = modelsDirectory.appendingPathComponent("catalog.json")
        cachedMetadata = try loadCatalog()
    }

    func refreshModels(from folderURL: URL) async throws -> [ModelMetadata] {
        let baseDestination = try await folderAccessManager.applicationSupportModelsDirectory()
        guard let enumerator = fileManager.enumerator(at: folderURL,
                                                      includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                                                      options: [.skipsHiddenFiles]) else {
            throw IndexerError.folderUnavailable
        }

        var discovered: [String: ModelMetadata] = [:]
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true { continue }
            guard fileURL.pathExtension.lowercased() == "usdz" else { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
            let fileName = fileURL.lastPathComponent
            let destinationURL = baseDestination.appendingPathComponent(relativePath)
            try ensureParentDirectoryExists(for: destinationURL)

            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let modifiedDate = attributes[.modificationDate] as? Date ?? Date.distantPast
            let hashValue = try sha256(for: fileURL)

            if let existing = cachedMetadata[relativePath],
               existing.sha256 == hashValue,
               existing.lastModified == modifiedDate,
               fileManager.fileExists(atPath: destinationURL.path) {
                discovered[relativePath] = existing
                continue
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: fileURL, to: destinationURL)

            let metadata = ModelMetadata(fileName: fileName,
                                         relativePath: relativePath,
                                         lastModified: modifiedDate,
                                         sha256: hashValue)
            discovered[relativePath] = metadata
        }

        cachedMetadata = discovered
        try storeCatalog(discovered: Array(discovered.values))
        return Array(discovered.values).sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }

    func loadCatalog() throws -> [String: ModelMetadata] {
        guard fileManager.fileExists(atPath: catalogURL.path) else { return [:] }
        let data = try Data(contentsOf: catalogURL)
        let metadata = try JSONDecoder().decode([ModelMetadata].self, from: data)
        return Dictionary(uniqueKeysWithValues: metadata.map { ($0.relativePath, $0) })
    }

    private func storeCatalog(discovered: [ModelMetadata]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(discovered)
        try data.write(to: catalogURL, options: [.atomic])
    }

    private func ensureParentDirectoryExists(for destinationURL: URL) throws {
        let parentDirectory = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDirectory.path) {
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }
    }

    func localURL(for metadata: ModelMetadata) async throws -> URL {
        let base = try await folderAccessManager.applicationSupportModelsDirectory()
        return base.appendingPathComponent(metadata.relativePath)
    }

    private func sha256(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = try? handle.read(upToCount: 1_048_576)
            if let chunk, !chunk.isEmpty {
                hasher.update(data: chunk)
                return true
            }
            return false
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
