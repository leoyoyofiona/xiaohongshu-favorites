import SwiftUI
import XHSOrganizerCore

struct ItemListView: View {
    let title: String
    let selection: SidebarSelection
    let hits: [SearchHit]
    let failedImports: [ImportItem]
    let pendingUnsyncedCount: Int
    let onSyncXHS: () -> Void
    @Binding var selectedSavedItemID: UUID?
    @Binding var selectedImportItemID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            switch selection {
            case .failures:
                failedImportList
            default:
                savedItemList
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if pendingUnsyncedCount > 0 {
                    Text("还有 \(pendingUnsyncedCount) 条待同步")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            Button("同步") {
                onSyncXHS()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    private var savedItemList: some View {
        Group {
            if hits.isEmpty {
                VStack(spacing: 18) {
                    ContentUnavailableView(
                        "还没有收藏内容",
                        systemImage: "magnifyingglass",
                        description: Text("先同步你的小红书收藏夹，系统会自动整理分类。")
                    )

                    Button("同步小红书收藏夹") {
                        onSyncXHS()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedSavedItemID) {
                    ForEach(hits) { hit in
                        SavedItemRow(
                            hit: hit,
                            showReadState: selection == .recentSync
                        )
                            .tag(hit.item.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var failedImportList: some View {
        Group {
            if failedImports.isEmpty {
                ContentUnavailableView("没有失败任务", systemImage: "checkmark.circle", description: Text("最近导入都成功了。"))
            } else {
                List(selection: $selectedImportItemID) {
                    ForEach(failedImports) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.sourceURL ?? item.rawText.nilIfEmpty ?? "导入失败")
                                .font(.headline)
                                .lineLimit(2)
                            Text(item.errorReason ?? "未知错误")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(item.importedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 6)
                        .tag(item.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var summaryText: String {
        switch selection {
        case .failures:
            "共 \(failedImports.count) 条解析失败记录"
        default:
            "共 \(hits.count) 条内容"
        }
    }
}

private struct SavedItemRow: View {
    let hit: SearchHit
    let showReadState: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AssetThumb(asset: hit.item.imageAssets.first)
            VStack(alignment: .leading, spacing: 8) {
                Text(hit.item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if showReadState {
                        Text(hit.item.isRead ? "已读" : "未读")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(hit.item.isRead ? .green : .secondary)
                    }
                    if hit.item.reviewState == .needsReview {
                        Text("待复核")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var previewText: String {
        let text = hit.item.fullText.nilIfEmpty ?? hit.item.summary.nilIfEmpty ?? "打开右侧查看内容"
        return text
    }

    private var categoryName: String {
        switch hit.item.primaryCategorySlug {
        case "education": "教育"
        case "paper": "论文"
        case "travel": "旅行"
        case "business": "商业"
        case "tools": "工具"
        case "technology": "技术"
        case "design": "设计"
        case "lifestyle": "生活"
        default: "未分类"
        }
    }
}

private struct AssetThumb: View {
    let asset: String?

    var body: some View {
        RemoteAssetImage(asset: asset, placeholderSystemImage: "photo")
        .frame(width: 82, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TagBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
