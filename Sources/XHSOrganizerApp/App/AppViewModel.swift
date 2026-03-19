import Foundation
import Observation
import XHSOrganizerCore

enum SidebarSelection: Hashable {
    case all
    case read
    case needsReview
    case pinned
    case failures
    case category(String)
    case dynamicTopic(String)
}

struct DynamicTopic: Identifiable, Hashable {
    let slug: String
    let name: String
    let subtitle: String
    let systemImage: String
    let count: Int

    var id: String { slug }
}

@MainActor
@Observable
final class AppViewModel {
    var sidebarSelection: SidebarSelection = .all
    var selectedSavedItemID: UUID?
    var selectedImportItemID: UUID?
    var searchText = ""
    var sourceFilter: SourceType?
    var sortMode: ItemSortMode = .relevance
    var importSheetPresented = false
    var settingsPresented = false
    var xhsSyncPresented = false
    var importFeedback: String?

    private let searchService = SearchService()
    private let excludedTopicTerms: Set<String> = [
        "教育", "论文", "旅行", "商业", "工具", "技术", "设计", "生活", "未分类",
        "链接", "截图", "文本", "收件箱", "待复核", "已整理"
    ]

    func searchHits(items: [SavedItem]) -> [SearchHit] {
        let query = SearchQuery(
            text: searchText,
            categoryFilters: selectionCategoryFilter(),
            sourceFilters: selectionSourceFilter(),
            sortMode: sortMode
        )
        return searchService.search(items: filteredBySelection(items), query: query)
    }

    func failedImports(from imports: [ImportItem]) -> [ImportItem] {
        imports
            .filter { $0.parseStatus == .failed }
            .sorted { $0.importedAt > $1.importedAt }
    }

    func title(for selection: SidebarSelection, categories: [XHSOrganizerCore.Category]) -> String {
        switch selection {
        case .all: "全部收藏"
        case .read: "已读"
        case .needsReview: "待复核"
        case .pinned: "重点收藏"
        case .failures: "解析失败"
        case .category(let slug):
            categories.first(where: { $0.slug == slug })?.name ?? "分类"
        case .dynamicTopic(let topic):
            topic
        }
    }

    func dynamicTopics(items: [SavedItem], categories: [XHSOrganizerCore.Category]) -> [DynamicTopic] {
        let categoryNames = Set(categories.map(\.name))
        var counts: [String: Int] = [:]
        var labels: [String: String] = [:]
        var sampleTitles: [String: [String]] = [:]
        var categoryCounts: [String: [String: Int]] = [:]

        for item in items {
            let candidates = item.secondaryTopics + item.tags
            for raw in candidates {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2,
                      !excludedTopicTerms.contains(trimmed),
                      !categoryNames.contains(trimmed),
                      !trimmed.allSatisfy(\.isNumber)
                else {
                    continue
                }
                let slug = TextProcessing.normalizedText(trimmed)
                guard slug.count >= 2 else { continue }
                counts[slug, default: 0] += 1
                labels[slug] = preferredLabel(current: labels[slug], candidate: trimmed)
                categoryCounts[slug, default: [:]][item.primaryCategorySlug, default: 0] += 1
                if sampleTitles[slug, default: []].count < 2 {
                    sampleTitles[slug, default: []].append(item.title)
                }
            }
        }

        return counts
            .compactMap { slug, count in
                guard count >= 2, let name = labels[slug] else { return nil }
                let dominantCategory = categoryCounts[slug]?.max(by: { $0.value < $1.value })?.key ?? Category.uncategorizedSlug
                let subtitle = topicSubtitle(
                    dominantCategory: dominantCategory,
                    titles: sampleTitles[slug] ?? [],
                    count: count
                )
                return DynamicTopic(
                    slug: slug,
                    name: displayTopicName(name),
                    subtitle: subtitle,
                    systemImage: icon(for: dominantCategory),
                    count: count
                )
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.count > rhs.count
            }
            .prefix(8)
            .map { $0 }
    }

    func syncSelection(savedItems: [SavedItem], failedImports: [ImportItem]) {
        if let selectedSavedItemID, !savedItems.contains(where: { $0.id == selectedSavedItemID }) {
            self.selectedSavedItemID = savedItems.first?.id
        } else if selectedSavedItemID == nil {
            self.selectedSavedItemID = savedItems.first?.id
        }

        if let selectedImportItemID, !failedImports.contains(where: { $0.id == selectedImportItemID }) {
            self.selectedImportItemID = failedImports.first?.id
        } else if selectedImportItemID == nil {
            self.selectedImportItemID = failedImports.first?.id
        }
    }

    private func filteredBySelection(_ items: [SavedItem]) -> [SavedItem] {
        let selected = items.filter { item in
            switch sidebarSelection {
            case .all:
                return true
            case .read:
                return item.isRead
            case .needsReview:
                return item.reviewState == .needsReview
            case .pinned:
                return item.isPinned
            case .failures:
                return false
            case .category(let slug):
                return item.primaryCategorySlug == slug
            case .dynamicTopic(let topic):
                let normalizedTopic = TextProcessing.normalizedText(topic)
                let fields = item.secondaryTopics + item.tags + [item.title]
                return fields.contains { TextProcessing.normalizedText($0).contains(normalizedTopic) }
            }
        }

        if let sourceFilter {
            return selected.filter { $0.sourceType == sourceFilter }
        }
        return selected
    }

    private func selectionCategoryFilter() -> Set<String> {
        switch sidebarSelection {
        case .category(let slug): [slug]
        default: []
        }
    }

    private func selectionSourceFilter() -> Set<SourceType> {
        guard let sourceFilter else { return [] }
        return [sourceFilter]
    }

    private func preferredLabel(current: String?, candidate: String) -> String {
        guard let current else { return candidate }
        if candidate.count < current.count {
            return candidate
        }
        return current
    }

    private func displayTopicName(_ raw: String) -> String {
        if raw.count <= 6 {
            return raw
        }
        return String(raw.prefix(6))
    }

    private func topicSubtitle(dominantCategory: String, titles: [String], count: Int) -> String {
        if let firstTitle = titles.first, !firstTitle.isEmpty {
            let clipped = firstTitle.count > 12 ? String(firstTitle.prefix(12)) + "…" : firstTitle
            return "\(categoryLabel(for: dominantCategory)) · \(clipped)"
        }
        return "\(categoryLabel(for: dominantCategory)) · \(count) 条"
    }

    private func categoryLabel(for slug: String) -> String {
        switch slug {
        case "education": "教育"
        case "paper": "论文"
        case "travel": "旅行"
        case "business": "商业"
        case "tools": "工具"
        case "technology": "技术"
        case "design": "设计"
        case "lifestyle": "生活"
        default: "主题"
        }
    }

    private func icon(for slug: String) -> String {
        switch slug {
        case "education": "book.closed"
        case "paper": "doc.text"
        case "travel": "airplane"
        case "business": "briefcase"
        case "tools": "hammer"
        case "technology": "desktopcomputer"
        case "design": "paintpalette"
        case "lifestyle": "sparkles"
        default: "sparkle.magnifyingglass"
        }
    }
}
