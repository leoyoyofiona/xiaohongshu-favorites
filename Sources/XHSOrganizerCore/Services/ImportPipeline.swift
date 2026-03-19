import Foundation

public struct ImportBatchResult: Sendable {
    public var importedCount: Int
    public var duplicateCount: Int
    public var failedCount: Int

    public init(importedCount: Int = 0, duplicateCount: Int = 0, failedCount: Int = 0) {
        self.importedCount = importedCount
        self.duplicateCount = duplicateCount
        self.failedCount = failedCount
    }

    public var summary: String {
        "新增 \(importedCount) 条，合并 \(duplicateCount) 条，失败 \(failedCount) 条"
    }
}

@MainActor
public final class ImportPipeline {
    private let store: LibraryStore
    private let extractor: ContentExtractor
    private let ocrService: OCRService
    private let classifier: LibraryClassificationService
    private let imageStore: ImageAssetStore

    public init(
        store: LibraryStore,
        extractor: ContentExtractor = ContentExtractor(),
        ocrService: OCRService = OCRService(),
        classifier: LibraryClassificationService = LibraryClassificationService(),
        imageStore: ImageAssetStore = ImageAssetStore()
    ) {
        self.store = store
        self.extractor = extractor
        self.ocrService = ocrService
        self.classifier = classifier
        self.imageStore = imageStore
    }

    public func importLinks(from rawInput: String) async -> ImportBatchResult {
        let rawLinks = rawInput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result = ImportBatchResult()
        for rawLink in rawLinks {
            var importItem = ImportItem(sourceType: .link, sourceURL: rawLink, rawText: rawLink, parseStatus: .processing)
            store.addImportItem(importItem)

            guard let url = URL(string: rawLink) else {
                importItem.parseStatus = .failed
                importItem.errorReason = "无效链接"
                store.updateImportItem(importItem)
                result.failedCount += 1
                continue
            }

            do {
                let extracted = try await extractor.extract(from: url)
                let imageAssets = await persistRemoteImages(urlStrings: extracted.imageURLs)
                let classification = classifier.classify(
                    title: extracted.title,
                    body: extracted.fullText,
                    sourceType: .link,
                    existingItems: store.savedItems
                )
                let item = buildSavedItem(
                    canonicalKey: extracted.canonicalKey,
                    title: extracted.title,
                    sourceApp: extracted.sourceApp,
                    sourceURL: extracted.sourceURL,
                    body: extracted.fullText,
                    summary: classification.summary,
                    imageAssets: imageAssets,
                    tags: classification.tags,
                    categorySlug: classification.primaryCategorySlug,
                    topics: classification.secondaryTopics,
                    reviewState: classification.reviewState,
                    sourceType: .link
                )
                let wasInserted = store.upsertSavedItem(item)
                importItem.parseStatus = wasInserted ? .succeeded : .duplicate
                importItem.errorReason = wasInserted ? nil : "已合并到现有收藏"
                store.updateImportItem(importItem)
                if wasInserted {
                    result.importedCount += 1
                } else {
                    result.duplicateCount += 1
                }
            } catch {
                importItem.parseStatus = .failed
                importItem.errorReason = error.localizedDescription
                store.updateImportItem(importItem)
                result.failedCount += 1
            }
        }
        if result.importedCount > 0 {
            store.reclassifyAllSavedItems()
        }
        return result
    }

    public func importText(title: String?, body: String, sourceURL: String? = nil) async -> ImportBatchResult {
        let cleanedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedBody.isEmpty else {
            return ImportBatchResult(failedCount: 1)
        }

        var importItem = ImportItem(sourceType: .text, sourceURL: sourceURL, rawText: cleanedBody, parseStatus: .processing)
        store.addImportItem(importItem)

        let displayTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? TextProcessing.firstSentences(from: cleanedBody, maxLength: 32)
        let canonicalSeed = [sourceURL ?? "", displayTitle, cleanedBody].joined(separator: "\n")
        let classification = classifier.classify(
            title: displayTitle,
            body: cleanedBody,
            sourceType: .text,
            existingItems: store.savedItems
        )

        let item = buildSavedItem(
            canonicalKey: TextProcessing.canonicalKey(from: canonicalSeed),
            title: displayTitle,
            sourceApp: sourceURL == nil ? "手动导入" : "网页",
            sourceURL: sourceURL,
            body: cleanedBody,
            summary: classification.summary,
            imageAssets: [],
            tags: classification.tags,
            categorySlug: classification.primaryCategorySlug,
            topics: classification.secondaryTopics,
            reviewState: classification.reviewState,
            sourceType: .text
        )

        let wasInserted = store.upsertSavedItem(item)
        importItem.parseStatus = wasInserted ? .succeeded : .duplicate
        importItem.errorReason = wasInserted ? nil : "已合并到现有收藏"
        store.updateImportItem(importItem)
        if wasInserted {
            store.reclassifyAllSavedItems()
        }
        return wasInserted ? ImportBatchResult(importedCount: 1) : ImportBatchResult(duplicateCount: 1)
    }

    public func importImages(at urls: [URL]) async -> ImportBatchResult {
        guard !urls.isEmpty else { return ImportBatchResult() }

        let localPaths = urls.compactMap { try? imageStore.storeImportedImage(at: $0) }
        var importItem = ImportItem(
            sourceType: .image,
            rawText: urls.map(\.lastPathComponent).joined(separator: "\n"),
            imagePaths: localPaths,
            parseStatus: .processing
        )
        store.addImportItem(importItem)

        let localURLs = localPaths.map { URL(fileURLWithPath: $0) }
        let ocrText = await ocrService.recognizeText(from: localURLs)
        let title = TextProcessing.firstSentences(from: ocrText.isEmpty ? "图片收藏" : ocrText, maxLength: 36)
        let classification = classifier.classify(
            title: title,
            body: ocrText,
            sourceType: .image,
            existingItems: store.savedItems
        )
        let item = buildSavedItem(
            canonicalKey: TextProcessing.canonicalKey(from: localPaths.joined(separator: "|")),
            title: title,
            sourceApp: "截图导入",
            sourceURL: nil,
            body: ocrText,
            summary: classification.summary,
            imageAssets: localPaths,
            tags: classification.tags,
            categorySlug: classification.primaryCategorySlug,
            topics: classification.secondaryTopics,
            reviewState: classification.reviewState,
            sourceType: .image
        )

        let wasInserted = store.upsertSavedItem(item)
        importItem.parseStatus = wasInserted ? .succeeded : .duplicate
        importItem.errorReason = wasInserted ? nil : "图片内容已存在"
        store.updateImportItem(importItem)
        if wasInserted {
            store.reclassifyAllSavedItems()
        }
        return wasInserted ? ImportBatchResult(importedCount: 1) : ImportBatchResult(duplicateCount: 1)
    }

    private func buildSavedItem(
        canonicalKey: String,
        title: String,
        sourceApp: String,
        sourceURL: String?,
        body: String,
        summary: String,
        imageAssets: [String],
        tags: [String],
        categorySlug: String,
        topics: [String],
        reviewState: ReviewState,
        sourceType: SourceType
    ) -> SavedItem {
        SavedItem(
            canonicalKey: canonicalKey,
            title: title,
            sourceApp: sourceApp,
            sourceURL: sourceURL,
            summary: summary,
            fullText: body,
            imageAssets: imageAssets,
            tags: tags,
            primaryCategorySlug: categorySlug,
            secondaryTopics: topics,
            importedAt: .now,
            reviewState: reviewState,
            sourceType: sourceType
        )
    }

    private func persistRemoteImages(urlStrings: [String]) async -> [String] {
        var assets: [String] = []
        for urlString in urlStrings.prefix(5) {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let storedPath = try imageStore.storeRemoteImage(data: data, preferredExtension: url.pathExtension.nilIfEmpty)
                assets.append(storedPath)
            } catch {
                assets.append(urlString)
            }
        }
        return assets
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        switch self {
        case .some(let value) where !value.isEmpty: value
        default: nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
