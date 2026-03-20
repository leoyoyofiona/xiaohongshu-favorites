import Foundation

public struct BrowserSyncNotePayload: Codable, Hashable, Sendable {
    public var url: String
    public var title: String
    public var text: String
    public var coverImageURL: String?
    public var author: String?
    public var isVideo: Bool
    public var videoURL: String?

    public init(
        url: String,
        title: String,
        text: String = "",
        coverImageURL: String? = nil,
        author: String? = nil,
        isVideo: Bool = false,
        videoURL: String? = nil
    ) {
        self.url = url
        self.title = title
        self.text = text
        self.coverImageURL = coverImageURL
        self.author = author
        self.isVideo = isVideo
        self.videoURL = videoURL
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case title
        case text
        case coverImageURL
        case author
        case isVideo
        case videoURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        coverImageURL = try container.decodeIfPresent(String.self, forKey: .coverImageURL)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        isVideo = try container.decodeIfPresent(Bool.self, forKey: .isVideo) ?? false
        videoURL = try container.decodeIfPresent(String.self, forKey: .videoURL)
    }
}

public struct BrowserSyncImportRequest: Codable, Sendable {
    public var source: String
    public var pageURL: String?
    public var pageTitle: String?
    public var notes: [BrowserSyncNotePayload]

    public init(
        source: String = "browser-script",
        pageURL: String? = nil,
        pageTitle: String? = nil,
        notes: [BrowserSyncNotePayload]
    ) {
        self.source = source
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.notes = notes
    }
}

public struct BrowserSyncImportResult: Codable, Sendable {
    public var importedCount: Int
    public var duplicateCount: Int
    public var failedCount: Int
    public var pageURL: String?
    public var message: String

    public init(importedCount: Int, duplicateCount: Int, failedCount: Int, pageURL: String?, message: String) {
        self.importedCount = importedCount
        self.duplicateCount = duplicateCount
        self.failedCount = failedCount
        self.pageURL = pageURL
        self.message = message
    }
}

public struct BrowserSyncImportProgress: Sendable {
    public var phase: String
    public var processedCount: Int
    public var totalCount: Int
    public var importedCount: Int
    public var duplicateCount: Int
    public var failedCount: Int
    public var remainingCount: Int

    public init(
        phase: String,
        processedCount: Int,
        totalCount: Int,
        importedCount: Int,
        duplicateCount: Int,
        failedCount: Int,
        remainingCount: Int
    ) {
        self.phase = phase
        self.processedCount = processedCount
        self.totalCount = totalCount
        self.importedCount = importedCount
        self.duplicateCount = duplicateCount
        self.failedCount = failedCount
        self.remainingCount = remainingCount
    }
}

public struct BrowserSyncImportService: Sendable {
    private let classifier = LibraryClassificationService()

    public init() {}

    @MainActor
    public func importNotes(_ request: BrowserSyncImportRequest, into store: LibraryStore) -> BrowserSyncImportResult {
        var importedCount = 0
        var duplicateCount = 0
        var failedCount = 0
        var syncedCanonicalKeys: [String] = []
        var syncedCanonicalKeySet: Set<String> = []

        for note in request.notes {
            let normalizedURL = note.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedURL.isEmpty, !normalizedTitle.isEmpty else {
                failedCount += 1
                continue
            }

            let body = [note.text, note.author].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                .joined(separator: "\n")
            let classification = classifier.classify(
                title: normalizedTitle,
                body: body,
                sourceType: .link,
                existingItems: store.savedItems
            )

            let item = SavedItem(
                canonicalKey: TextProcessing.canonicalKey(from: normalizedURL),
                title: normalizedTitle,
                sourceApp: "小红书",
                sourceURL: normalizedURL,
                summary: TextProcessing.firstSentences(from: body.isEmpty ? normalizedTitle : body, maxLength: 220),
                fullText: body,
                imageAssets: note.coverImageURL?.nilIfEmpty.map { [$0] } ?? [],
                tags: classification.tags,
                primaryCategorySlug: classification.primaryCategorySlug,
                secondaryTopics: classification.secondaryTopics,
                importedAt: .now,
                reviewState: classification.reviewState,
                isCategoryManual: false,
                sourceType: .link,
                hasVideo: note.isVideo || note.videoURL?.isEmpty == false,
                videoAssets: note.videoURL?.nilIfEmpty.map { [$0] } ?? []
            )
            if syncedCanonicalKeySet.insert(item.canonicalKey).inserted {
                syncedCanonicalKeys.append(item.canonicalKey)
            }

            if store.upsertSavedItem(item, autosave: false) {
                importedCount += 1
            } else {
                duplicateCount += 1
            }
        }

        let message = "浏览器同步完成：新增 \(importedCount) 条，合并 \(duplicateCount) 条，失败 \(failedCount) 条。"
        store.saveNow()
        if importedCount > 0 {
            store.reclassifyAllSavedItems()
        }
        let recentSyncedItemIDs = resolveSyncedItemIDs(from: syncedCanonicalKeys, store: store)
        store.updateXHSSyncSettings { settings in
            settings.lastFavoritesURL = request.pageURL ?? settings.lastFavoritesURL
            settings.lastSyncAt = .now
            settings.lastSyncSummary = message
            settings.lastCheckedAt = .now
            settings.lastKnownRemoteCount = request.notes.count
            settings.pendingUnsyncedCount = 0
            settings.recentSyncedItemIDs = recentSyncedItemIDs
        }

        return BrowserSyncImportResult(
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            failedCount: failedCount,
            pageURL: request.pageURL,
            message: message
        )
    }

    public func importNotes(
        _ request: BrowserSyncImportRequest,
        into store: LibraryStore,
        progress: (@Sendable (BrowserSyncImportProgress) async -> Void)? = nil
    ) async -> BrowserSyncImportResult {
        let totalCount = request.notes.count
        let existingItems = await MainActor.run { store.savedItems }

        if let progress {
            await progress(
                BrowserSyncImportProgress(
                    phase: "准备处理",
                    processedCount: 0,
                    totalCount: totalCount,
                    importedCount: 0,
                    duplicateCount: 0,
                    failedCount: 0,
                    remainingCount: totalCount
                )
            )
        }

        var preparedItems: [SavedItem] = []
        preparedItems.reserveCapacity(totalCount)
        var syncedCanonicalKeys: [String] = []
        var syncedCanonicalKeySet: Set<String> = []
        var failedCount = 0

        for (index, note) in request.notes.enumerated() {
            let normalizedURL = note.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedURL.isEmpty, !normalizedTitle.isEmpty else {
                failedCount += 1
                if let progress, (index + 1).isMultiple(of: 50) || index + 1 == totalCount {
                    await progress(
                        BrowserSyncImportProgress(
                            phase: "整理抓取结果",
                            processedCount: index + 1,
                            totalCount: totalCount,
                            importedCount: 0,
                            duplicateCount: 0,
                            failedCount: failedCount,
                            remainingCount: max(0, totalCount - (index + 1))
                        )
                    )
                }
                continue
            }

            let body = [note.text, note.author].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                .joined(separator: "\n")
            let classification = classifier.classify(
                title: normalizedTitle,
                body: body,
                sourceType: .link,
                existingItems: existingItems
            )

            preparedItems.append(
                SavedItem(
                canonicalKey: TextProcessing.canonicalKey(from: normalizedURL),
                title: normalizedTitle,
                sourceApp: "小红书",
                sourceURL: normalizedURL,
                summary: TextProcessing.firstSentences(from: body.isEmpty ? normalizedTitle : body, maxLength: 220),
                fullText: body,
                imageAssets: note.coverImageURL?.nilIfEmpty.map { [$0] } ?? [],
                tags: classification.tags,
                primaryCategorySlug: classification.primaryCategorySlug,
                secondaryTopics: classification.secondaryTopics,
                importedAt: .now,
                reviewState: classification.reviewState,
                isCategoryManual: false,
                sourceType: .link,
                hasVideo: note.isVideo || note.videoURL?.isEmpty == false,
                videoAssets: note.videoURL?.nilIfEmpty.map { [$0] } ?? []
                )
            )
            if let canonicalKey = preparedItems.last?.canonicalKey,
               syncedCanonicalKeySet.insert(canonicalKey).inserted {
                syncedCanonicalKeys.append(canonicalKey)
            }

            if let progress, (index + 1).isMultiple(of: 50) || index + 1 == totalCount {
                await progress(
                    BrowserSyncImportProgress(
                        phase: "整理抓取结果",
                        processedCount: index + 1,
                        totalCount: totalCount,
                        importedCount: 0,
                        duplicateCount: 0,
                        failedCount: failedCount,
                        remainingCount: max(0, totalCount - (index + 1))
                    )
                )
            }

            if (index + 1).isMultiple(of: 100) {
                await Task.yield()
            }
        }

        if let progress {
            await progress(
                BrowserSyncImportProgress(
                    phase: "批量入库",
                    processedCount: 0,
                    totalCount: preparedItems.count,
                    importedCount: 0,
                    duplicateCount: 0,
                    failedCount: failedCount,
                    remainingCount: preparedItems.count
                )
            )
        }

        let batchResult = await MainActor.run { () -> (Int, Int) in
            let result = store.upsertSavedItemsBatch(preparedItems)
            store.saveNow()
            return result
        }
        let importedCount = batchResult.0
        let duplicateCount = batchResult.1

        var rescuedCount = 0
        if importedCount > 0 {
            let uncategorizedTotal = await MainActor.run {
                store.savedItems.reduce(into: 0) { partialResult, item in
                    if !item.isCategoryManual && item.primaryCategorySlug == Category.uncategorizedSlug {
                        partialResult += 1
                    }
                }
            }

            if uncategorizedTotal > 0 {
                if let progress {
                    await progress(
                        BrowserSyncImportProgress(
                            phase: "整理未分类",
                            processedCount: 0,
                            totalCount: uncategorizedTotal,
                            importedCount: importedCount,
                            duplicateCount: duplicateCount,
                            failedCount: failedCount,
                            remainingCount: uncategorizedTotal
                        )
                    )
                }

                rescuedCount = (try? await store.reclassifyUncategorizedSavedItemsProgressively { processedCount, totalCount in
                    if let progress {
                        await progress(
                            BrowserSyncImportProgress(
                                phase: "整理未分类",
                                processedCount: processedCount,
                                totalCount: totalCount,
                                importedCount: importedCount,
                                duplicateCount: duplicateCount,
                                failedCount: failedCount,
                                remainingCount: max(0, totalCount - processedCount)
                            )
                        )
                    }
                }) ?? 0
            }
        }

        let rescueSuffix = rescuedCount > 0 ? "，补分 \(rescuedCount) 条未分类" : ""
        let message = "浏览器同步完成：新增 \(importedCount) 条，合并 \(duplicateCount) 条，失败 \(failedCount) 条\(rescueSuffix)。"
        let recentSyncedItemIDs = await MainActor.run { resolveSyncedItemIDs(from: syncedCanonicalKeys, store: store) }
        await MainActor.run {
            store.updateXHSSyncSettings { settings in
                settings.lastFavoritesURL = request.pageURL ?? settings.lastFavoritesURL
                settings.lastSyncAt = .now
                settings.lastSyncSummary = message
                settings.lastCheckedAt = .now
                settings.lastKnownRemoteCount = request.notes.count
                settings.pendingUnsyncedCount = 0
                settings.recentSyncedItemIDs = recentSyncedItemIDs
            }
        }

        if let progress {
            await progress(
                BrowserSyncImportProgress(
                    phase: "完成",
                    processedCount: importedCount + duplicateCount + failedCount,
                    totalCount: max(totalCount, importedCount + duplicateCount + failedCount),
                    importedCount: importedCount,
                    duplicateCount: duplicateCount,
                    failedCount: failedCount,
                    remainingCount: 0
                )
            )
        }

        return BrowserSyncImportResult(
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            failedCount: failedCount,
            pageURL: request.pageURL,
            message: message
        )
    }

    @MainActor
    private func resolveSyncedItemIDs(from canonicalKeys: [String], store: LibraryStore) -> [UUID] {
        var ids: [UUID] = []
        var idSet: Set<UUID> = []
        ids.reserveCapacity(canonicalKeys.count)
        for key in canonicalKeys {
            guard let item = store.existingSavedItem(for: key) else { continue }
            if idSet.insert(item.id).inserted {
                ids.append(item.id)
            }
        }
        return ids
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
