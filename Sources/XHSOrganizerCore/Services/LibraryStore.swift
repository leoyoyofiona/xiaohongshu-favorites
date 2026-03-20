import Foundation
import Observation

@MainActor
@Observable
public final class LibraryStore {
    public private(set) var categories: [Category] = []
    public private(set) var savedItems: [SavedItem] = []
    public private(set) var importItems: [ImportItem] = []
    public private(set) var xhsSyncSettings: XHSSyncSettings = .init()

    private let persistenceURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let libraryClassifier = LibraryClassificationService()

    public init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = appSupport.appendingPathComponent("XHSOrganizer", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.persistenceURL = directory.appendingPathComponent("library.json")
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
        ensureDefaultCategories()
    }

    public func addImportItem(_ item: ImportItem) {
        importItems.insert(item, at: 0)
        save()
    }

    public func updateImportItem(_ item: ImportItem) {
        guard let index = importItems.firstIndex(where: { $0.id == item.id }) else { return }
        importItems[index] = item
        save()
    }

    public func upsertSavedItem(_ item: SavedItem, autosave: Bool = true) -> Bool {
        if let index = savedItems.firstIndex(where: { $0.canonicalKey == item.canonicalKey }) {
            savedItems[index] = merge(savedItems[index], with: item)
            if autosave {
                save()
            }
            return false
        }
        savedItems.insert(item, at: 0)
        if autosave {
            save()
        }
        return true
    }

    public func updateSavedItem(_ item: SavedItem) {
        guard let index = savedItems.firstIndex(where: { $0.id == item.id }) else { return }
        savedItems[index] = item
        save()
    }

    public func deleteSavedItem(id: UUID) {
        savedItems.removeAll { $0.id == id }
        save()
    }

    public func upsertSavedItemsBatch(_ items: [SavedItem]) -> (importedCount: Int, duplicateCount: Int) {
        var importedCount = 0
        var duplicateCount = 0

        for item in items {
            if upsertSavedItem(item, autosave: false) {
                importedCount += 1
            } else {
                duplicateCount += 1
            }
        }

        return (importedCount, duplicateCount)
    }

    public func saveNow() {
        save()
    }

    public func reclassifyAllSavedItems() {
        savedItems = libraryClassifier.reclassify(items: savedItems)
        save()
    }

    public func reclassifyUncategorizedSavedItems() -> Int {
        let snapshot = savedItems
        var updatedCount = 0

        for index in savedItems.indices {
            let item = savedItems[index]
            guard !item.isCategoryManual,
                  item.primaryCategorySlug == Category.uncategorizedSlug
            else {
                continue
            }

            let context = snapshot.enumerated()
                .filter { $0.offset != index }
                .map(\.element)

            let result = libraryClassifier.classify(
                title: item.title,
                body: [item.fullText, item.summary].joined(separator: "\n"),
                sourceType: item.sourceType,
                existingItems: context
            )

            guard result.primaryCategorySlug != Category.uncategorizedSlug else {
                continue
            }

            savedItems[index].primaryCategorySlug = result.primaryCategorySlug
            savedItems[index].tags = result.tags
            savedItems[index].secondaryTopics = result.secondaryTopics
            if savedItems[index].summary.isEmpty || savedItems[index].summary == item.title {
                savedItems[index].summary = result.summary
            }
            if savedItems[index].reviewState != .ready {
                savedItems[index].reviewState = result.reviewState
            }
            updatedCount += 1
        }

        if updatedCount > 0 {
            save()
        }
        return updatedCount
    }

    public func reclassifyUncategorizedSavedItemsProgressively(
        progress: ((Int, Int) async -> Void)? = nil,
        gate: (() async throws -> Void)? = nil
    ) async throws -> Int {
        let targetIndices = savedItems.indices.filter { index in
            let item = savedItems[index]
            return !item.isCategoryManual && item.primaryCategorySlug == Category.uncategorizedSlug
        }

        guard !targetIndices.isEmpty else {
            if let progress {
                await progress(0, 0)
            }
            return 0
        }

        let snapshot = savedItems
        var updatedCount = 0

        for (offset, index) in targetIndices.enumerated() {
            try await gate?()

            let item = savedItems[index]
            let context = snapshot.enumerated()
                .filter { $0.offset != index }
                .map(\.element)

            let result = libraryClassifier.classify(
                title: item.title,
                body: [item.fullText, item.summary].joined(separator: "\n"),
                sourceType: item.sourceType,
                existingItems: context
            )

            if result.primaryCategorySlug != Category.uncategorizedSlug {
                savedItems[index].primaryCategorySlug = result.primaryCategorySlug
                savedItems[index].tags = result.tags
                savedItems[index].secondaryTopics = result.secondaryTopics
                if savedItems[index].summary.isEmpty || savedItems[index].summary == item.title {
                    savedItems[index].summary = result.summary
                }
                if savedItems[index].reviewState != .ready {
                    savedItems[index].reviewState = result.reviewState
                }
                updatedCount += 1
            }

            if let progress {
                await progress(offset + 1, targetIndices.count)
            }
            if offset.isMultiple(of: 20) {
                await Task.yield()
            }
        }

        if updatedCount > 0 {
            save()
        }
        return updatedCount
    }

    public func reclassifyAllSavedItemsProgressively(
        progress: ((Int, Int) async -> Void)? = nil,
        gate: (() async throws -> Void)? = nil
    ) async throws {
        savedItems = try await libraryClassifier.reclassifyProgressively(items: savedItems, progress: progress, gate: gate)
        save()
    }

    public func categoryName(for slug: String) -> String {
        categories.first(where: { $0.slug == slug })?.name ?? "未分类"
    }

    public func updateXHSSyncSettings(_ update: (inout XHSSyncSettings) -> Void) {
        update(&xhsSyncSettings)
        save()
    }

    public func existingSavedItem(for canonicalKey: String) -> SavedItem? {
        savedItems.first(where: { $0.canonicalKey == canonicalKey })
    }

    public func ensureDefaultCategories() {
        if categories.isEmpty {
            categories = Category.defaultCategories.enumerated().map { index, category in
                Category(slug: category.slug, name: category.name, sortOrder: index)
            }
            save()
        }
    }

    private func merge(_ existing: SavedItem, with item: SavedItem) -> SavedItem {
        var merged = existing
        if merged.fullText.count < item.fullText.count {
            merged.fullText = item.fullText
        }
        if merged.summary.count < item.summary.count {
            merged.summary = item.summary
        }
        if merged.imageAssets.isEmpty {
            merged.imageAssets = item.imageAssets
        }
        if merged.videoAssets.isEmpty {
            merged.videoAssets = item.videoAssets
        }
        merged.hasVideo = merged.hasVideo || item.hasVideo || !merged.videoAssets.isEmpty
        if merged.tags.count < item.tags.count {
            merged.tags = item.tags
        }
        if merged.primaryCategorySlug == Category.uncategorizedSlug && item.primaryCategorySlug != Category.uncategorizedSlug {
            merged.primaryCategorySlug = item.primaryCategorySlug
        }
        if item.isCategoryManual {
            merged.primaryCategorySlug = item.primaryCategorySlug
            merged.isCategoryManual = true
        }
        merged.isPinned = merged.isPinned || item.isPinned
        merged.isRead = merged.isRead || item.isRead
        if merged.sourceURL == nil {
            merged.sourceURL = item.sourceURL
        } else if let incomingURL = item.sourceURL,
                  let existingURL = merged.sourceURL,
                  !existingURL.contains("xsec_token"),
                  incomingURL.contains("xsec_token") {
            merged.sourceURL = incomingURL
        }
        if merged.sourceApp == "手动导入" {
            merged.sourceApp = item.sourceApp
        }
        if !item.tags.isEmpty && !merged.isCategoryManual {
            merged.tags = item.tags
            merged.secondaryTopics = item.secondaryTopics
        }
        merged.reviewState = rankedState(lhs: merged.reviewState, rhs: item.reviewState)
        return merged
    }

    private func rankedState(lhs: ReviewState, rhs: ReviewState) -> ReviewState {
        let rank: [ReviewState: Int] = [.ready: 2, .needsReview: 1, .pending: 0]
        return (rank[lhs] ?? 0) >= (rank[rhs] ?? 0) ? lhs : rhs
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let snapshot = try? decoder.decode(LibrarySnapshot.self, from: data)
        else {
            return
        }
        categories = snapshot.categories
        savedItems = snapshot.savedItems
        importItems = snapshot.importItems
        xhsSyncSettings = snapshot.xhsSyncSettings
    }

    private func save() {
        let snapshot = LibrarySnapshot(
            categories: categories,
            savedItems: savedItems,
            importItems: importItems,
            xhsSyncSettings: xhsSyncSettings
        )
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }
}
