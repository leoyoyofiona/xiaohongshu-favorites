import AppKit
import SwiftUI
import XHSOrganizerCore

struct DetailView: View {
    let selection: SidebarSelection
    let savedItem: Binding<SavedItem>?
    let importItem: ImportItem?
    let categories: [XHSOrganizerCore.Category]
    let store: LibraryStore
    let visibleSavedItemIDs: [UUID]
    let onSelectSavedItemID: (UUID) -> Void

    var body: some View {
        VStack {
            switch selection {
            case .failures:
                if let importItem {
                    ImportFailureDetail(importItem: importItem)
                } else {
                    placeholder(title: "没有失败详情", subtitle: "选择一条失败记录查看具体原因。")
                }
            default:
                if let savedItem {
                    SavedItemDetailPane(
                        item: savedItem,
                        categories: categories,
                        store: store,
                        visibleSavedItemIDs: visibleSavedItemIDs,
                        onSelectSavedItemID: onSelectSavedItemID
                    )
                } else {
                    placeholder(title: "选择一条收藏", subtitle: "右侧会按接近原文的方式显示图片和正文。")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(title: String, subtitle: String) -> some View {
        ContentUnavailableView(title, systemImage: "sidebar.right", description: Text(subtitle))
    }
}

private struct ImportFailureDetail: View {
    let importItem: ImportItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("导入失败")
                    .font(.largeTitle.weight(.bold))
                metaRow(title: "来源", value: importItem.sourceType.displayName)
                if let sourceURL = importItem.sourceURL {
                    metaRow(title: "输入内容", value: sourceURL)
                }
                metaRow(title: "时间", value: importItem.importedAt.formatted(date: .abbreviated, time: .shortened))
                metaRow(title: "失败原因", value: importItem.errorReason ?? "未知错误")
                if !importItem.rawText.isEmpty {
                    Text("原始内容")
                        .font(.headline)
                    Text(importItem.rawText)
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(28)
        }
    }

    private func metaRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct SavedItemDetailPane: View {
    @Environment(\.openURL) private var openURL
    @Binding var item: SavedItem
    let categories: [XHSOrganizerCore.Category]
    let store: LibraryStore
    let visibleSavedItemIDs: [UUID]
    let onSelectSavedItemID: (UUID) -> Void
    @State private var deleteConfirmationPresented = false
    @State private var resolvedText = ""
    @State private var resolvedImages: [String] = []
    @State private var resolveStatusText: String?
    @State private var isResolvingOriginal = false
    @State private var exportStatusText: String?
    @State private var isExporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            actionBar
            categoryBar
            fallbackOriginalCard
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .task(id: item.id) {
            markAsReadIfNeeded()
            await resolveOriginalIfNeeded()
        }
        .confirmationDialog("删除这篇收藏？", isPresented: $deleteConfirmationPresented) {
            Button("删除", role: .destructive) {
                store.deleteSavedItem(id: item.id)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后不会再出现在这个收藏导航里。")
        }
    }

    private var fallbackOriginalCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                originalCard
            }
            .frame(maxWidth: 920, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Text(item.importedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(item.sourceType.displayName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let host = sourceHost {
                        Text(host)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            actionButton(
                title: item.isRead ? "已读" : "标记已读",
                systemImage: item.isRead ? "checkmark.circle.fill" : "checkmark.circle"
            ) {
                item.isRead.toggle()
                persistChanges()
            }

            actionButton(
                title: item.isPinned ? "重点收藏" : "标为重点",
                systemImage: item.isPinned ? "heart.fill" : "heart"
            ) {
                item.isPinned.toggle()
                persistChanges()
            }

            Button {
                selectPrevious()
            } label: {
                Label("上一篇", systemImage: "chevron.up")
            }
            .buttonStyle(.bordered)
            .disabled(previousItemID == nil)

            Button {
                selectNext()
            } label: {
                Label("下一篇", systemImage: "chevron.down")
            }
            .buttonStyle(.bordered)
            .disabled(nextItemID == nil)

            Button {
                Task {
                    await exportCurrentItem()
                }
            } label: {
                Label(isExporting ? "导出中…" : "下载原文", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(isExporting)

            Spacer(minLength: 0)

            if let url = URL(string: item.sourceURL ?? "") {
                Button("打开原文") {
                    openURL(url)
                }
                .buttonStyle(.borderedProminent)
            }

            Button("删除", role: .destructive) {
                deleteConfirmationPresented = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var categoryBar: some View {
        HStack(spacing: 12) {
            TagBadge(text: categoryName(for: item.primaryCategorySlug), tint: .green)

            Picker("分类", selection: categoryBinding) {
                ForEach(categories.sorted(by: { $0.sortOrder < $1.sortOrder })) { category in
                    Text(category.name).tag(category.slug)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180, alignment: .leading)

            if item.isCategoryManual {
                Button("恢复自动分类") {
                    item.isCategoryManual = false
                    persistChanges()
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var originalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let resolveStatusText {
                Text(resolveStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let exportStatusText {
                Text(exportStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let bodyText = displayText.nilIfEmpty {
                Text(bodyText)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(isResolvingOriginal ? "正在获取这篇笔记的原文内容…" : "这条收藏目前只抓到了标题、封面或简短预览，还没有更完整的正文内容。")
                    .foregroundStyle(.secondary)
            }

            if !displayImages.isEmpty {
                imageGallery
            }

            if let sourceURL = item.sourceURL {
                Text(sourceURL)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(22)
        .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    private var imageGallery: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(displayImages, id: \.self) { asset in
                    AssetImageView(asset: asset)
                        .frame(width: 360, height: 460)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        }
                }
            }
        }
    }

    private var displayText: String {
        if let resolved = resolvedText.nilIfEmpty,
           resolved.count >= 16,
           !looksLikeNoiseText(resolved),
           !looksLikeCorruptedText(resolved) {
            return resolved
        }
        if let fullText = item.fullText.nilIfEmpty,
           fullText.count >= 16,
           !looksLikeNoiseText(fullText),
           !looksLikeCorruptedText(fullText) {
            return fullText
        }
        if let summary = item.summary.nilIfEmpty,
           summary != item.title,
           !looksLikeNoiseText(summary),
           !looksLikeCorruptedText(summary) {
            return summary
        }
        if let fallback = item.fullText.nilIfEmpty,
           !looksLikeNoiseText(fallback),
           !looksLikeCorruptedText(fallback) {
            return fallback
        }
        if let fallback = item.summary.nilIfEmpty,
           !looksLikeNoiseText(fallback),
           !looksLikeCorruptedText(fallback) {
            return fallback
        }
        return ""
    }

    private var displayImages: [String] {
        if !resolvedImages.isEmpty {
            return resolvedImages
        }
        return item.imageAssets
    }

    private var sourceHost: String? {
        guard let raw = item.sourceURL,
              let url = URL(string: raw),
              let host = url.host
        else {
            return nil
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { item.primaryCategorySlug },
            set: {
                item.primaryCategorySlug = $0
                item.isCategoryManual = true
                persistChanges()
            }
        )
    }

    private func categoryName(for slug: String) -> String {
        categories.first(where: { $0.slug == slug })?.name ?? "未分类"
    }

    private func persistChanges() {
        store.updateSavedItem(item)
    }

    private var currentVisibleIndex: Int? {
        visibleSavedItemIDs.firstIndex(of: item.id)
    }

    private var previousItemID: UUID? {
        guard let currentVisibleIndex, currentVisibleIndex > 0 else { return nil }
        return visibleSavedItemIDs[currentVisibleIndex - 1]
    }

    private var nextItemID: UUID? {
        guard let currentVisibleIndex, currentVisibleIndex + 1 < visibleSavedItemIDs.count else { return nil }
        return visibleSavedItemIDs[currentVisibleIndex + 1]
    }

    private func selectPrevious() {
        guard let previousItemID else { return }
        onSelectSavedItemID(previousItemID)
    }

    private func selectNext() {
        guard let nextItemID else { return }
        onSelectSavedItemID(nextItemID)
    }

    private func markAsReadIfNeeded() {
        guard !item.isRead else { return }
        item.isRead = true
        persistChanges()
    }

    private func resolveOriginalIfNeeded() async {
        resolvedText = ""
        resolvedImages = []
        resolveStatusText = nil

        guard let raw = item.sourceURL,
              let url = URL(string: raw),
              raw.contains("xiaohongshu.com/explore/"),
              raw.contains("xsec_token=")
        else {
            return
        }

        let currentText = item.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUsefulResolvedText = resolvedText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 120
        let looksLikePreviewOnly = currentText.components(separatedBy: .newlines).count <= 6 && currentText.count < 400
        let shouldResolve = !hasUsefulResolvedText && (currentText.isEmpty || looksLikeNoiseText(currentText) || looksLikeCorruptedText(currentText) || looksLikePreviewOnly)
        guard shouldResolve else { return }

        isResolvingOriginal = true
        resolveStatusText = "正在获取这篇笔记的原文内容…"
        defer { isResolvingOriginal = false }

        do {
            let resolved = try await XHSNoteDetailResolver.shared.resolve(url: url)
            if !resolved.text.isEmpty {
                resolvedText = resolved.text
                item.fullText = resolved.text
                if item.summary.isEmpty || item.summary == item.title {
                    item.summary = String(resolved.text.prefix(220))
                }
            }
            if !resolved.images.isEmpty {
                resolvedImages = resolved.images
                item.imageAssets = resolved.images
            }
            if !resolved.title.isEmpty, item.title.count < resolved.title.count {
                item.title = resolved.title
            }
            persistChanges()
            resolveStatusText = "已获取这篇笔记的详情内容。"
        } catch {
            resolveStatusText = "暂时没拿到更完整的原文内容，先显示当前已保存内容。"
        }
    }

    private func exportCurrentItem() async {
        isExporting = true
        exportStatusText = "正在导出原文和图片…"
        defer { isExporting = false }

        do {
            let exportDirectory = try await SavedItemExportService.export(
                item: item,
                displayText: displayText,
                displayImages: displayImages
            )
            exportStatusText = "已导出到 \(exportDirectory.path(percentEncoded: false))"
        } catch {
            exportStatusText = error.localizedDescription
        }
    }

    private func looksLikeNoiseText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let fragments = [
            "沪ICP备", "营业执照", "网安备案", "增值电信业务经营许可证", "医疗器械网络交易服务第三方平台备案",
            "互联网药品信息服务资格证书", "违法不良信息举报", "互联网举报中心", "网络文化经营许可证",
            "个性化推荐算法", "行吟信息科技", "公司地址", "广告屏蔽插件", "请移除插件", "我知道了"
        ]
        let hitCount = fragments.reduce(0) { partialResult, fragment in
            partialResult + (text.contains(fragment) ? 1 : 0)
        }
        return hitCount >= 2
    }

    private func looksLikeCorruptedText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let suspiciousFragments = ["锟", "鐨", "閿", "娴", "鈥", "€", "", "", "闁", "顏", "鏂", "涔"]
        let suspiciousCount = suspiciousFragments.reduce(0) { partial, fragment in
            partial + text.components(separatedBy: fragment).count - 1
        }
        let privateUseCount = text.unicodeScalars.filter { scalar in
            (0xE000...0xF8FF).contains(Int(scalar.value))
        }.count
        return suspiciousCount >= 8 || privateUseCount >= 4
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
    }
}

private struct AssetImageView: View {
    let asset: String

    var body: some View {
        RemoteAssetImage(asset: asset, placeholderSystemImage: "photo")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
