import SwiftUI
import XHSOrganizerCore

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @State private var store = LibraryStore()
    @State private var browserSync = BrowserSyncController()
    @State private var embeddedBrowser = XHSWebSyncController()
    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @State private var lastShownBrowserImportText = ""
    @State private var hasReclassifiedUncategorized = false

    var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let failedImports = viewModel.failedImports(from: store.importItems)
            let hits = viewModel.searchHits(
                items: store.savedItems,
                recentSyncedItemIDs: store.xhsSyncSettings.recentSyncedItemIDs
            )
            let selectedImportItem = failedImports.first(where: { $0.id == viewModel.selectedImportItemID })
            let visibleSavedItemIDs = hits.map(\.item.id)
            let visibleSavedItems = hits.map(\.item)

            ZStack {
                NavigationSplitView(columnVisibility: $splitVisibility) {
                    SidebarView(
                        categories: store.categories,
                        savedItems: store.savedItems,
                        failedImports: failedImports,
                        recentSyncedItemIDs: store.xhsSyncSettings.recentSyncedItemIDs,
                        selection: Binding(
                            get: { viewModel.sidebarSelection },
                            set: { viewModel.sidebarSelection = $0 }
                        )
                    )
                    .navigationSplitViewColumnWidth(
                        min: sidebarColumnWidth(for: totalWidth).min,
                        ideal: sidebarColumnWidth(for: totalWidth).ideal,
                        max: sidebarColumnWidth(for: totalWidth).max
                    )
                } content: {
                    ItemListView(
                        title: viewModel.title(for: viewModel.sidebarSelection, categories: store.categories),
                        selection: viewModel.sidebarSelection,
                        hits: hits,
                        failedImports: failedImports,
                        pendingUnsyncedCount: store.xhsSyncSettings.pendingUnsyncedCount,
                        onSyncXHS: {
                            viewModel.xhsSyncPresented = true
                        },
                        selectedSavedItemID: Binding(
                            get: { viewModel.selectedSavedItemID },
                            set: { viewModel.selectedSavedItemID = $0 }
                        ),
                        selectedImportItemID: Binding(
                            get: { viewModel.selectedImportItemID },
                            set: { viewModel.selectedImportItemID = $0 }
                        )
                    )
                    .navigationSplitViewColumnWidth(
                        min: listColumnWidth(for: totalWidth).min,
                        ideal: listColumnWidth(for: totalWidth).ideal,
                        max: listColumnWidth(for: totalWidth).max
                    )
                } detail: {
                    DetailView(
                        selection: viewModel.sidebarSelection,
                        savedItem: selectedSavedItemBinding(),
                        importItem: selectedImportItem,
                        categories: store.categories,
                        store: store,
                        visibleSavedItemIDs: visibleSavedItemIDs,
                        onSelectSavedItemID: { id in
                            viewModel.selectedSavedItemID = id
                        }
                    )
                    .navigationSplitViewColumnWidth(
                        min: detailColumnWidth(for: totalWidth).min,
                        ideal: detailColumnWidth(for: totalWidth).ideal,
                        max: detailColumnWidth(for: totalWidth).max
                    )
                }
                .navigationSplitViewStyle(.automatic)

                if viewModel.xhsBrowserPresented {
                    XHSBrowserSheet(
                        store: store,
                        controller: embeddedBrowser,
                        onClose: { viewModel.xhsBrowserPresented = false }
                    )
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }

                if viewModel.xhsSyncPresented {
                    XHSSyncSheet(
                        store: store,
                        browserSync: browserSync,
                        onClose: { viewModel.xhsSyncPresented = false }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(9)
                }
            }
            .onAppear {
                updateSplitVisibility(for: totalWidth)
            }
            .onChange(of: totalWidth) { _, newValue in
                updateSplitVisibility(for: newValue)
            }
            .searchable(text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ), prompt: "例如：论文写作、留学申请、Notion 模板")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.xhsBrowserPresented = true
                    } label: {
                        Text("小红书")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.red.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.xhsSyncPresented = true
                    } label: {
                        Label(syncButtonTitle, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let importFeedback = viewModel.importFeedback {
                    Text(importFeedback)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.importSheetPresented },
                set: { viewModel.importSheetPresented = $0 }
            )) {
                ImportSheet(store: store) { message in
                    withAnimation(.snappy) {
                        viewModel.importFeedback = message
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        await MainActor.run {
                            withAnimation(.easeOut) {
                                viewModel.importFeedback = nil
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.settingsPresented },
                set: { viewModel.settingsPresented = $0 }
            )) {
                SettingsView(store: store, browserSync: browserSync) {
                    viewModel.xhsSyncPresented = true
                }
            }
            .task {
                browserSync.startIfNeeded(store: store)
                embeddedBrowser.attach(store: store)
                viewModel.syncSelection(visibleSavedItems: visibleSavedItems, failedImports: failedImports)
                guard !hasReclassifiedUncategorized else { return }
                hasReclassifiedUncategorized = true
                let moved = store.reclassifyUncategorizedSavedItems()
                if moved > 0 {
                    showImportFeedback("已重新整理未分类 \(moved) 条。")
                }
            }
            .onChange(of: store.savedItems) { _, _ in
                viewModel.syncSelection(visibleSavedItems: visibleSavedItems, failedImports: failedImports)
            }
            .onChange(of: store.importItems) { _, _ in
                viewModel.syncSelection(visibleSavedItems: visibleSavedItems, failedImports: failedImports)
            }
            .onChange(of: viewModel.sidebarSelection) { _, _ in
                viewModel.syncSelection(visibleSavedItems: visibleSavedItems, failedImports: failedImports)
            }
            .onChange(of: browserSync.lastImportText) { _, newValue in
                guard newValue != "还没有接收到浏览器同步",
                      newValue != lastShownBrowserImportText
                else {
                    return
                }
                lastShownBrowserImportText = newValue
                showImportFeedback(newValue)
            }
        }
    }

    private func showImportFeedback(_ message: String) {
        withAnimation(.snappy) {
            viewModel.importFeedback = message
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                withAnimation(.easeOut) {
                    if viewModel.importFeedback == message {
                        viewModel.importFeedback = nil
                    }
                }
            }
        }
    }

    private var syncButtonTitle: String {
        let count = store.xhsSyncSettings.pendingUnsyncedCount
        return count > 0 ? "同步小红书 \(count)" : "同步小红书"
    }

    private func updateSplitVisibility(for totalWidth: CGFloat) {
        if totalWidth < 1180, splitVisibility == .all {
            splitVisibility = .doubleColumn
            return
        }
        if totalWidth > 1260, splitVisibility != .all {
            splitVisibility = .all
        }
    }

    private func sidebarColumnWidth(for totalWidth: CGFloat) -> (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        if totalWidth < 1180 {
            return (min: 130, ideal: 150, max: 170)
        }
        return (min: 180, ideal: 210, max: 240)
    }

    private func listColumnWidth(for totalWidth: CGFloat) -> (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        if totalWidth < 1180 {
            return (min: 210, ideal: 240, max: 300)
        }
        return (min: 280, ideal: 320, max: 360)
    }

    private func detailColumnWidth(for totalWidth: CGFloat) -> (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        if totalWidth < 1180 {
            return (min: 360, ideal: 500, max: .infinity)
        }
        return (min: 640, ideal: 820, max: .infinity)
    }

    private func selectedSavedItemBinding() -> Binding<SavedItem>? {
        guard let id = viewModel.selectedSavedItemID,
              let index = store.savedItems.firstIndex(where: { $0.id == id })
        else {
            return nil
        }

        return Binding(
            get: { store.savedItems[index] },
            set: { updated in
                store.updateSavedItem(updated)
            }
        )
    }
}
