import Foundation

public enum SourceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case link
    case image
    case text

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .link: "链接"
        case .image: "截图"
        case .text: "文本"
        }
    }
}

public enum ParseStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case processing
    case succeeded
    case failed
    case duplicate

    public var displayName: String {
        switch self {
        case .pending: "待处理"
        case .processing: "处理中"
        case .succeeded: "已入库"
        case .failed: "解析失败"
        case .duplicate: "已合并"
        }
    }
}

public enum ReviewState: String, Codable, CaseIterable, Hashable, Sendable {
    case pending
    case ready
    case needsReview

    public var displayName: String {
        switch self {
        case .pending: "收件箱"
        case .ready: "已整理"
        case .needsReview: "待复核"
        }
    }
}

public enum ItemSortMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case relevance
    case latest
    case pinned

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .relevance: "相关度"
        case .latest: "最近导入"
        case .pinned: "置顶优先"
        }
    }
}

public struct SearchQuery: Sendable {
    public var text: String
    public var categoryFilters: Set<String>
    public var tagFilters: Set<String>
    public var sourceFilters: Set<SourceType>
    public var sortMode: ItemSortMode

    public init(
        text: String = "",
        categoryFilters: Set<String> = [],
        tagFilters: Set<String> = [],
        sourceFilters: Set<SourceType> = [],
        sortMode: ItemSortMode = .relevance
    ) {
        self.text = text
        self.categoryFilters = categoryFilters
        self.tagFilters = tagFilters
        self.sourceFilters = sourceFilters
        self.sortMode = sortMode
    }
}

public struct ImportItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var sourceType: SourceType
    public var sourceURL: String?
    public var rawText: String
    public var imagePaths: [String]
    public var importedAt: Date
    public var parseStatus: ParseStatus
    public var errorReason: String?

    public init(
        id: UUID = UUID(),
        sourceType: SourceType,
        sourceURL: String? = nil,
        rawText: String = "",
        imagePaths: [String] = [],
        importedAt: Date = .now,
        parseStatus: ParseStatus = .pending,
        errorReason: String? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.rawText = rawText
        self.imagePaths = imagePaths
        self.importedAt = importedAt
        self.parseStatus = parseStatus
        self.errorReason = errorReason
    }
}

public struct SavedItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var canonicalKey: String
    public var title: String
    public var sourceApp: String
    public var sourceURL: String?
    public var summary: String
    public var fullText: String
    public var imageAssets: [String]
    public var tags: [String]
    public var primaryCategorySlug: String
    public var secondaryTopics: [String]
    public var collectedAt: Date?
    public var importedAt: Date
    public var embeddingRef: String?
    public var reviewState: ReviewState
    public var note: String
    public var isPinned: Bool
    public var isRead: Bool
    public var isCategoryManual: Bool
    public var sourceType: SourceType
    public var hasVideo: Bool
    public var videoAssets: [String]

    public init(
        id: UUID = UUID(),
        canonicalKey: String,
        title: String,
        sourceApp: String = "小红书",
        sourceURL: String? = nil,
        summary: String = "",
        fullText: String = "",
        imageAssets: [String] = [],
        tags: [String] = [],
        primaryCategorySlug: String = Category.uncategorizedSlug,
        secondaryTopics: [String] = [],
        collectedAt: Date? = nil,
        importedAt: Date = .now,
        embeddingRef: String? = nil,
        reviewState: ReviewState = .pending,
        note: String = "",
        isPinned: Bool = false,
        isRead: Bool = false,
        isCategoryManual: Bool = false,
        sourceType: SourceType = .text,
        hasVideo: Bool = false,
        videoAssets: [String] = []
    ) {
        self.id = id
        self.canonicalKey = canonicalKey
        self.title = title
        self.sourceApp = sourceApp
        self.sourceURL = sourceURL
        self.summary = summary
        self.fullText = fullText
        self.imageAssets = imageAssets
        self.tags = tags
        self.primaryCategorySlug = primaryCategorySlug
        self.secondaryTopics = secondaryTopics
        self.collectedAt = collectedAt
        self.importedAt = importedAt
        self.embeddingRef = embeddingRef
        self.reviewState = reviewState
        self.note = note
        self.isPinned = isPinned
        self.isRead = isRead
        self.isCategoryManual = isCategoryManual
        self.sourceType = sourceType
        self.hasVideo = hasVideo
        self.videoAssets = videoAssets
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case canonicalKey
        case title
        case sourceApp
        case sourceURL
        case summary
        case fullText
        case imageAssets
        case tags
        case primaryCategorySlug
        case secondaryTopics
        case collectedAt
        case importedAt
        case embeddingRef
        case reviewState
        case note
        case isPinned
        case isRead
        case isCategoryManual
        case sourceType
        case hasVideo
        case videoAssets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        canonicalKey = try container.decode(String.self, forKey: .canonicalKey)
        title = try container.decode(String.self, forKey: .title)
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp) ?? "小红书"
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        fullText = try container.decodeIfPresent(String.self, forKey: .fullText) ?? ""
        imageAssets = try container.decodeIfPresent([String].self, forKey: .imageAssets) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        primaryCategorySlug = try container.decodeIfPresent(String.self, forKey: .primaryCategorySlug) ?? Category.uncategorizedSlug
        secondaryTopics = try container.decodeIfPresent([String].self, forKey: .secondaryTopics) ?? []
        collectedAt = try container.decodeIfPresent(Date.self, forKey: .collectedAt)
        importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt) ?? .now
        embeddingRef = try container.decodeIfPresent(String.self, forKey: .embeddingRef)
        reviewState = try container.decodeIfPresent(ReviewState.self, forKey: .reviewState) ?? .pending
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        isCategoryManual = try container.decodeIfPresent(Bool.self, forKey: .isCategoryManual) ?? false
        sourceType = try container.decodeIfPresent(SourceType.self, forKey: .sourceType) ?? .text
        hasVideo = try container.decodeIfPresent(Bool.self, forKey: .hasVideo) ?? false
        videoAssets = try container.decodeIfPresent([String].self, forKey: .videoAssets) ?? []
    }
}

public struct Category: Identifiable, Codable, Hashable, Sendable {
    public var slug: String
    public var name: String
    public var sortOrder: Int
    public var isSystem: Bool

    public var id: String { slug }

    public init(slug: String, name: String, sortOrder: Int, isSystem: Bool = false) {
        self.slug = slug
        self.name = name
        self.sortOrder = sortOrder
        self.isSystem = isSystem
    }

    public static let uncategorizedSlug = "uncategorized"

    public static let defaultCategories: [(slug: String, name: String)] = [
        ("education", "教育"),
        ("paper", "论文"),
        ("travel", "旅行"),
        ("business", "商业"),
        ("tools", "工具"),
        ("technology", "技术"),
        ("design", "设计"),
        ("lifestyle", "生活"),
        (uncategorizedSlug, "未分类")
    ]
}

public struct LibrarySnapshot: Codable, Sendable {
    public var categories: [Category]
    public var savedItems: [SavedItem]
    public var importItems: [ImportItem]
    public var xhsSyncSettings: XHSSyncSettings

    public init(
        categories: [Category] = [],
        savedItems: [SavedItem] = [],
        importItems: [ImportItem] = [],
        xhsSyncSettings: XHSSyncSettings = .init()
    ) {
        self.categories = categories
        self.savedItems = savedItems
        self.importItems = importItems
        self.xhsSyncSettings = xhsSyncSettings
    }
}

public struct XHSSyncSettings: Codable, Hashable, Sendable {
    public var lastFavoritesURL: String?
    public var lastSyncAt: Date?
    public var lastSyncSummary: String
    public var lastCheckedAt: Date?
    public var lastKnownRemoteCount: Int
    public var pendingUnsyncedCount: Int
    public var recentSyncedItemIDs: [UUID]

    public init(
        lastFavoritesURL: String? = nil,
        lastSyncAt: Date? = nil,
        lastSyncSummary: String = "尚未连接小红书",
        lastCheckedAt: Date? = nil,
        lastKnownRemoteCount: Int = 0,
        pendingUnsyncedCount: Int = 0,
        recentSyncedItemIDs: [UUID] = []
    ) {
        self.lastFavoritesURL = lastFavoritesURL
        self.lastSyncAt = lastSyncAt
        self.lastSyncSummary = lastSyncSummary
        self.lastCheckedAt = lastCheckedAt
        self.lastKnownRemoteCount = lastKnownRemoteCount
        self.pendingUnsyncedCount = pendingUnsyncedCount
        self.recentSyncedItemIDs = recentSyncedItemIDs
    }

    private enum CodingKeys: String, CodingKey {
        case lastFavoritesURL
        case lastSyncAt
        case lastSyncSummary
        case lastCheckedAt
        case lastKnownRemoteCount
        case pendingUnsyncedCount
        case recentSyncedItemIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastFavoritesURL = try container.decodeIfPresent(String.self, forKey: .lastFavoritesURL)
        lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        lastSyncSummary = try container.decodeIfPresent(String.self, forKey: .lastSyncSummary) ?? "尚未连接小红书"
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastKnownRemoteCount = try container.decodeIfPresent(Int.self, forKey: .lastKnownRemoteCount) ?? 0
        pendingUnsyncedCount = try container.decodeIfPresent(Int.self, forKey: .pendingUnsyncedCount) ?? 0
        recentSyncedItemIDs = try container.decodeIfPresent([UUID].self, forKey: .recentSyncedItemIDs) ?? []
    }
}
