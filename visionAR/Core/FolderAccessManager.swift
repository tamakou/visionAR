import Foundation

actor FolderAccessManager {
    enum FolderAccessError: Error {
        case bookmarkUnavailable
        case bookmarkResolutionFailed
    }

    private let bookmarkDefaultsKey = "linkedFolderBookmark"
    private let fileManager = FileManager.default
    private var scopedURL: URL?

    func persistSecurityScopedBookmark(for url: URL) throws {
        #if os(visionOS)
        let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        #else
        let options: URL.BookmarkCreationOptions = [.withSecurityScope, .minimalBookmark]
        #endif
        let data = try url.bookmarkData(options: options,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkDefaultsKey)
        UserDefaults.standard.synchronize()
        scopedURL = url
    }

    func storedFolderURL() throws -> URL? {
        if let scopedURL {
            return scopedURL
        }
        guard let data = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) else {
            return nil
        }
        var isStale = false
        #if os(visionOS)
        let resolveOptions: URL.BookmarkResolutionOptions = [.withoutUI]
        #else
        let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #endif
        let restoredURL = try URL(resolvingBookmarkData: data,
                                  options: resolveOptions,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale)
        if isStale {
            throw FolderAccessError.bookmarkResolutionFailed
        }
        scopedURL = restoredURL
        return restoredURL
    }

    func startAccessingIfNeeded() throws -> URL? {
        guard let url = try storedFolderURL() else { return nil }
        guard url.startAccessingSecurityScopedResource() else {
            throw FolderAccessError.bookmarkResolutionFailed
        }
        return url
    }

    func stopAccessingIfNeeded() {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    func applicationSupportModelsDirectory() throws -> URL {
        let supportURL = try fileManager.url(for: .applicationSupportDirectory,
                                             in: .userDomainMask,
                                             appropriateFor: nil,
                                             create: true)
        let modelsURL = supportURL.appendingPathComponent("Models", isDirectory: true)
        if !fileManager.fileExists(atPath: modelsURL.path) {
            try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        }
        return modelsURL
    }
}
