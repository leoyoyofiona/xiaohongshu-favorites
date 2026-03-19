import Foundation

public struct ImageAssetStore: Sendable {
    public let baseDirectory: URL

    public init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = appSupport.appendingPathComponent("XHSOrganizer", isDirectory: true)
        let images = directory.appendingPathComponent("Images", isDirectory: true)
        try? fileManager.createDirectory(at: images, withIntermediateDirectories: true)
        self.baseDirectory = images
    }

    public func storeImportedImage(at sourceURL: URL) throws -> String {
        let destination = uniqueDestinationURL(extension: sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination.path
    }

    public func storeRemoteImage(data: Data, preferredExtension: String?) throws -> String {
        let destination = uniqueDestinationURL(extension: preferredExtension ?? "jpg")
        try data.write(to: destination, options: .atomic)
        return destination.path
    }

    private func uniqueDestinationURL(extension pathExtension: String) -> URL {
        baseDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(pathExtension)
    }
}
