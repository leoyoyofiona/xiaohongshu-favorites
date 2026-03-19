import AppKit
import Foundation
import XHSOrganizerCore

@MainActor
enum SavedItemExportService {
    static func export(
        item: SavedItem,
        displayText: String,
        displayImages: [String],
        fileManager: FileManager = .default
    ) async throws -> URL {
        let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Downloads", isDirectory: true)
        let exportRoot = downloadsURL.appendingPathComponent("小红书收藏导出", isDirectory: true)
        try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        let folderName = uniqueFolderName(for: item, at: exportRoot)
        let exportDirectory = exportRoot.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let exportText = buildText(item: item, displayText: displayText)
        try exportText.write(to: exportDirectory.appendingPathComponent("原文.txt"), atomically: true, encoding: .utf8)

        if let sourceURL = item.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceURL.isEmpty {
            try sourceURL.write(to: exportDirectory.appendingPathComponent("原文链接.txt"), atomically: true, encoding: .utf8)
        }

        for (index, asset) in displayImages.enumerated() {
            try await exportImage(
                asset: asset,
                index: index + 1,
                to: exportDirectory,
                fileManager: fileManager
            )
        }

        NSWorkspace.shared.open(exportDirectory)
        return exportDirectory
    }

    private static func buildText(item: SavedItem, displayText: String) -> String {
        let sourceURL = item.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = [
            "标题：\(item.title)",
            sourceURL?.isEmpty == false ? "原文链接：\(sourceURL!)" : nil,
            "分类：\(item.primaryCategorySlug)",
            "",
            "正文：",
            displayText.nilIfEmpty ?? item.summary.nilIfEmpty ?? item.title
        ]
        return lines.compactMap { $0 }.joined(separator: "\n")
    }

    private static func exportImage(
        asset: String,
        index: Int,
        to directory: URL,
        fileManager: FileManager
    ) async throws {
        let ext = preferredExtension(for: asset)
        let destination = directory.appendingPathComponent(String(format: "图片-%02d.%@", index, ext))

        if asset.hasPrefix("http"), let url = URL(string: asset) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 16
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<400 ~= httpResponse.statusCode else {
                throw ExportError.downloadFailed(asset)
            }
            try data.write(to: destination, options: .atomic)
            return
        }

        let sourceURL = URL(fileURLWithPath: asset)
        if fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false)) {
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
        }
    }

    private static func preferredExtension(for asset: String) -> String {
        if let url = URL(string: asset), let ext = url.pathExtension.nilIfEmpty {
            return ext
        }
        let fileURL = URL(fileURLWithPath: asset)
        return fileURL.pathExtension.nilIfEmpty ?? "jpg"
    }

    private static func uniqueFolderName(for item: SavedItem, at root: URL) -> String {
        let base = sanitizedFileName(item.title).nilIfEmpty ?? "小红书收藏"
        let stamp = item.importedAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let preferred = "\(base)-\(stamp)"

        var candidate = preferred
        var index = 2
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(candidate, isDirectory: true).path(percentEncoded: false)) {
            candidate = "\(preferred)-\(index)"
            index += 1
        }
        return candidate
    }

    private static func sanitizedFileName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return raw.components(separatedBy: invalid).joined(separator: "-")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(48)
            .description
    }
}

private enum ExportError: LocalizedError {
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let asset):
            return "图片下载失败：\(asset)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
