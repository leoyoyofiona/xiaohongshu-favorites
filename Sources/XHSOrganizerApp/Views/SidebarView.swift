import SwiftUI
import XHSOrganizerCore

struct SidebarView: View {
    let categories: [XHSOrganizerCore.Category]
    let savedItems: [SavedItem]
    let failedImports: [ImportItem]
    let recentSyncedItemIDs: [UUID]
    @Binding var selection: SidebarSelection

    var body: some View {
        let selectionBinding = Binding<SidebarSelection?>(
            get: { selection },
            set: { selection = $0 ?? .all }
        )

        return List(selection: selectionBinding) {
            Section("浏览") {
                row(label: "全部收藏", systemImage: "square.grid.2x2", badge: savedItems.count)
                    .tag(SidebarSelection.all)
                row(label: "最近同步", systemImage: "clock.arrow.circlepath", badge: recentSyncCount)
                    .tag(SidebarSelection.recentSync)
                row(label: "重点收藏", systemImage: "heart", badge: savedItems.filter(\.isPinned).count)
                    .tag(SidebarSelection.pinned)
                row(label: "已读", systemImage: "checkmark.circle", badge: savedItems.filter(\.isRead).count)
                    .tag(SidebarSelection.read)
                row(label: "未分类", systemImage: "folder", badge: count(for: Category.uncategorizedSlug))
                    .tag(SidebarSelection.category(Category.uncategorizedSlug))
                row(label: "解析失败", systemImage: "xmark.octagon", badge: failedImports.count)
                    .tag(SidebarSelection.failures)
            }

            Section("主分类") {
                ForEach(visibleCategories) { category in
                    row(
                        label: category.name,
                        systemImage: icon(for: category.slug),
                        badge: count(for: category.slug)
                    )
                    .tag(SidebarSelection.category(category.slug))
                }
            }

        }
        .listStyle(.sidebar)
        .navigationTitle("收藏导航")
    }

    private var visibleCategories: [XHSOrganizerCore.Category] {
        categories
            .filter { category in
                let itemCount = count(for: category.slug)
                return itemCount > 0 || category.slug == Category.uncategorizedSlug
            }
            .sorted { lhs, rhs in
                let lhsCount = count(for: lhs.slug)
                let rhsCount = count(for: rhs.slug)
                if lhsCount == rhsCount {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhsCount > rhsCount
            }
    }

    private func row(label: String, systemImage: String, badge: Int) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer(minLength: 12)
            Text("\(badge)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func count(for slug: String) -> Int {
        savedItems.filter { $0.primaryCategorySlug == slug }.count
    }

    private var recentSyncCount: Int {
        let idSet = Set(recentSyncedItemIDs)
        return savedItems.reduce(into: 0) { partialResult, item in
            if idSet.contains(item.id) {
                partialResult += 1
            }
        }
    }

    private func icon(for slug: String) -> String {
        switch slug {
        case "education": "book"
        case "paper": "doc.text"
        case "travel": "airplane"
        case "business": "briefcase"
        case "tools": "hammer"
        case "technology": "desktopcomputer"
        case "design": "paintpalette"
        case "lifestyle": "sparkles"
        default: "folder"
        }
    }
}
