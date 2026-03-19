import SwiftUI
import XHSOrganizerCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let store: LibraryStore
    let browserSync: BrowserSyncController
    let onOpenSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设置")
                .font(.largeTitle.weight(.bold))

            VStack(alignment: .leading, spacing: 12) {
                Text("小红书连接")
                    .font(.headline)
                Text(store.xhsSyncSettings.lastSyncSummary)
                    .foregroundStyle(.secondary)
                Text(browserSync.serviceStatusText)
                    .font(.footnote)
                    .foregroundStyle(browserSync.isRunning ? .green : .red)
                if let lastFavoritesURL = store.xhsSyncSettings.lastFavoritesURL {
                    Text(lastFavoritesURL)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Label("现在默认用浏览器辅助同步。请在 Chrome 里打开已经登录的小红书收藏夹，点脚本按钮导出，App 会自动导入并整理。", systemImage: "globe")
                    .foregroundStyle(.secondary)
                Button("打开同步小红书") {
                    dismiss()
                    onOpenSync()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 12) {
                Text("当前能力")
                    .font(.headline)
                Text("支持浏览器同步小红书收藏夹，自动去重、分类、搜索和手动调整归类。")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 500, height: 340)
    }
}
