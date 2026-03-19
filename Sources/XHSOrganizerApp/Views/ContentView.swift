import SwiftUI
import XHSOrganizerCore

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @State private var store = LibraryStore()
    @State private var browserSync = BrowserSyncController()
    @State private var lastShownBrowserImportText = ""
    @State private var hasReclassifiedUncategorized = false

    var body: some View {
        let failedImports = viewModel.failedImports(from: store.importItems)
        let hits = viewModel.searchHits(items: store.savedItems)
        let selectedImportItem = failedImports.first(where: { $0.id == viewModel.selectedImportItemID })
        let visibleSavedItemIDs = hits.map(\.item.id)

        NavigationSplitView {
            SidebarView(
                categories: store.categories,
                savedItems: store.savedItems,
                failedImports: failedImports,
                selection: Binding(
                    get: { viewModel.sidebarSelection },
                    set: { viewModel.sidebarSelection = $0 }
                )
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
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
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
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
            .navigationSplitViewColumnWidth(min: 640, ideal: 820, max: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: Binding(
            get: { viewModel.searchText },
            set: { viewModel.searchText = $0 }
        ), prompt: "例如：论文写作、留学申请、Notion 模板")
        .toolbar {
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
        .sheet(isPresented: Binding(
            get: { viewModel.xhsSyncPresented },
            set: { viewModel.xhsSyncPresented = $0 }
        )) {
            XHSSyncSheet(store: store, browserSync: browserSync)
        }
        .task {
            browserSync.startIfNeeded(store: store)
            viewModel.syncSelection(savedItems: store.savedItems, failedImports: failedImports)
            guard !hasReclassifiedUncategorized else { return }
            hasReclassifiedUncategorized = true
            let moved = store.reclassifyUncategorizedSavedItems()
            if moved > 0 {
                showImportFeedback("已重新整理未分类 \(moved) 条。")
            }
        }
        .onChange(of: store.savedItems) { _, _ in
            viewModel.syncSelection(savedItems: store.savedItems, failedImports: failedImports)
        }
        .onChange(of: store.importItems) { _, _ in
            viewModel.syncSelection(savedItems: store.savedItems, failedImports: failedImports)
        }
        .onChange(of: viewModel.sidebarSelection) { _, _ in
            viewModel.syncSelection(savedItems: store.savedItems, failedImports: failedImports)
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
