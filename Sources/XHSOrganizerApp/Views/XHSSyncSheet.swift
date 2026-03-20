import SwiftUI
import XHSOrganizerCore

struct XHSSyncSheet: View {
    @Environment(\.openURL) private var openURL
    let store: LibraryStore
    let browserSync: BrowserSyncController
    let onClose: () -> Void
    @State private var xhsURLString = "https://www.xiaohongshu.com/explore"

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statusPanel
                    actionsPanel
                    tipsPanel
                }
                .padding(24)
            }
            .frame(maxWidth: 920)
            .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 30, y: 12)
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("同步小红书")
                    .font(.largeTitle.weight(.bold))
                Text("先在 Chrome 打开你的小红书收藏夹页，再回这里点一次同步。程序会直接读取当前 Chrome 页面并自动导入。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("关闭") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: browserSync.isImporting ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(browserSync.isImporting ? .orange : .green)
                Text(browserSync.serviceStatusText)
                    .font(.headline)
            }

            statusRow(title: "当前状态", value: browserSync.actionStatusText)
            statusRow(title: "最近导入", value: browserSync.lastImportText)

            HStack(spacing: 8) {
                StatusPill(title: "最近收到", value: "\(browserSync.lastReceivedCount) 条")
                if let lastSyncAt = store.xhsSyncSettings.lastSyncAt {
                    StatusPill(title: "更新于", value: lastSyncAt.formatted(date: .numeric, time: .shortened))
                }
            }
        }
        .padding(18)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 18))
        .overlay(panelStroke)
    }

    private var actionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                MacInputField(
                    placeholder: "输入小红书地址",
                    text: $xhsURLString,
                    systemImage: "link",
                    onSubmit: openTypedXHSURL
                )

                Button("打开小红书") {
                    openTypedXHSURL()
                }
                .buttonStyle(.bordered)
                .disabled(normalizedTypedXHSURL == nil)
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await browserSync.syncFromChromeFavorites()
                    }
                } label: {
                    Label("从当前 Chrome 收藏夹同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(browserSync.isImporting)

                Button("打开下载文件夹") {
                    browserSync.openWatchedFolder()
                }
                .buttonStyle(.bordered)

                Button("扫描旧同步文件") {
                    Task {
                        await browserSync.scanInbox()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(browserSync.isImporting)
            }
        }
        .padding(18)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 18))
        .overlay(panelStroke)
    }

    private var tipsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("怎么用")
                .font(.headline)
            tip("1. 在 Chrome 打开你的小红书收藏夹页。")
            tip("2. 回到这个窗口，点“从当前 Chrome 收藏夹同步”。")
            tip("3. 同步完成后回主界面看分类和内容。")
            tip("如果 Chrome 当前页不是收藏夹，这里会直接提示，不会卡住。")
        }
        .padding(18)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 18))
        .overlay(panelStroke)
    }

    private func statusRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tip(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var panelFill: Color {
        Color(NSColor.controlBackgroundColor)
    }

    private var panelStroke: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(Color.black.opacity(0.06), lineWidth: 1)
    }

    private func openTypedXHSURL() {
        guard let url = normalizedTypedXHSURL else { return }
        openURL(url)
    }

    private var normalizedTypedXHSURL: URL? {
        let trimmed = xhsURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        return URL(string: normalized)
    }
}

private struct StatusPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}
