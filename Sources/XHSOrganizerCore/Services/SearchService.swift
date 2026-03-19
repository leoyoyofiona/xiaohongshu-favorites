import Foundation

public struct SearchHit: Identifiable, Sendable {
    public let id: UUID
    public let item: SavedItem
    public let score: Double
    public let matchedTerms: [String]

    public init(item: SavedItem, score: Double, matchedTerms: [String]) {
        self.id = item.id
        self.item = item
        self.score = score
        self.matchedTerms = matchedTerms
    }
}

public struct SearchService: Sendable {
    private let synonymMap: [String: [String]] = [
        "论文": ["paper", "research", "文献", "开题", "学术", "写作", "投稿", "答辩"],
        "写作": ["表达", "大纲", "结构", "论证", "修改", "论文"],
        "教育": ["学习", "课程", "老师", "备考", "留学", "培训"],
        "工具": ["效率", "模板", "app", "软件", "workflow", "自动化"],
        "副业": ["创业", "变现", "商业", "赚钱", "项目"],
        "旅行": ["酒店", "出行", "攻略", "签证", "机票"]
    ]

    public init() {}

    public func search(items: [SavedItem], query: SearchQuery) -> [SearchHit] {
        let filtered = items.filter { item in
            (query.categoryFilters.isEmpty || query.categoryFilters.contains(item.primaryCategorySlug)) &&
            (query.sourceFilters.isEmpty || query.sourceFilters.contains(item.sourceType)) &&
            (query.tagFilters.isEmpty || !Set(item.tags).isDisjoint(with: query.tagFilters))
        }

        let normalizedQuery = TextProcessing.normalizedText(query.text)
        let terms = expandedTerms(for: normalizedQuery)

        let hits = filtered.compactMap { item -> SearchHit? in
            let searchable = SearchableItem(item: item)
            let score = score(item: searchable, terms: terms, rawQuery: normalizedQuery)

            if normalizedQuery.isEmpty {
                return SearchHit(item: item, score: defaultScore(for: item, sortMode: query.sortMode), matchedTerms: [])
            }
            guard score > 0 else { return nil }
            let matched = terms.filter { searchable.combinedText.contains($0) }
            return SearchHit(item: item, score: score, matchedTerms: matched)
        }

        return hits.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return rhs.item.importedAt < lhs.item.importedAt
            }
            return lhs.score > rhs.score
        }
    }

    private func defaultScore(for item: SavedItem, sortMode: ItemSortMode) -> Double {
        switch sortMode {
        case .latest:
            return item.importedAt.timeIntervalSince1970
        case .pinned:
            return item.isPinned ? 100 : item.importedAt.timeIntervalSince1970
        case .relevance:
            return item.isPinned ? 10 : item.importedAt.timeIntervalSince1970
        }
    }

    private func expandedTerms(for query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        var terms = TextProcessing.normalizedTokens(query)
        if terms.isEmpty {
            terms = [query]
        }
        for term in terms {
            if let synonyms = synonymMap[term] {
                terms.append(contentsOf: synonyms.map { TextProcessing.normalizedText($0) })
            }
            for (key, synonyms) in synonymMap where term.contains(key) || key.contains(term) || query.contains(key) {
                terms.append(TextProcessing.normalizedText(key))
                terms.append(contentsOf: synonyms.map { TextProcessing.normalizedText($0) })
            }
        }
        let unique = Array(NSOrderedSet(array: terms)) as? [String] ?? terms
        return unique.filter { !$0.isEmpty }
    }

    private func score(item: SearchableItem, terms: [String], rawQuery: String) -> Double {
        guard !terms.isEmpty else { return 0 }
        var score = 0.0
        for term in terms {
            if item.title.contains(term) { score += 8 }
            if item.summary.contains(term) { score += 5 }
            if item.fullText.contains(term) { score += 3 }
            if item.tags.contains(where: { $0.contains(term) }) { score += 4 }
            if item.category.contains(term) { score += 2 }
        }

        if !rawQuery.isEmpty, item.combinedText.contains(rawQuery) {
            score += 6
        }
        if item.isPinned {
            score += 1
        }
        return score
    }
}

private struct SearchableItem {
    let title: String
    let summary: String
    let fullText: String
    let tags: [String]
    let category: String
    let combinedText: String
    let isPinned: Bool

    init(item: SavedItem) {
        self.title = TextProcessing.normalizedText(item.title)
        self.summary = TextProcessing.normalizedText(item.summary)
        self.fullText = TextProcessing.normalizedText(item.fullText)
        self.tags = item.tags.map(TextProcessing.normalizedText)
        self.category = TextProcessing.normalizedText(item.primaryCategorySlug)
        self.combinedText = [title, summary, fullText, tags.joined(separator: " "), category].joined(separator: " ")
        self.isPinned = item.isPinned
    }
}
