import SwiftUI
import WebKit
import XHSOrganizerCore

struct XHSBrowserSheet: View {
    let store: LibraryStore
    let controller: XHSWebSyncController
    let onClose: () -> Void
    @State private var urlText = "https://www.xiaohongshu.com/explore"

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            WebContainerView(webView: controller.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            controller.attach(store: store)
            if controller.currentURLString.isEmpty {
                controller.loadHome()
            } else {
                urlText = controller.currentURLString
            }
        }
        .onChange(of: controller.currentURLString) { _, newValue in
            if !newValue.isEmpty {
                urlText = newValue
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button("返回整理") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)

                Button {
                    controller.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!controller.canGoBack)

                Button {
                    controller.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(!controller.canGoForward)

                MacInputField(
                    placeholder: "输入小红书地址",
                    text: $urlText,
                    systemImage: "link",
                    onSubmit: openTypedURL
                )

                Button("打开") {
                    openTypedURL()
                }
                .buttonStyle(.bordered)
                .disabled(normalizedTypedURL == nil)

                Button("首页") {
                    controller.loadHome()
                }
                .buttonStyle(.bordered)

                Button("收藏夹") {
                    controller.openFavorites(store: store)
                }
                .buttonStyle(.bordered)

                Button("刷新") {
                    controller.reload()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)

            HStack {
                Text(controller.pageTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(controller.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func openTypedURL() {
        guard let url = normalizedTypedURL else { return }
        controller.webView.load(URLRequest(url: url))
    }

    private var normalizedTypedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        return URL(string: normalized)
    }
}

private struct WebContainerView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
    }
}
