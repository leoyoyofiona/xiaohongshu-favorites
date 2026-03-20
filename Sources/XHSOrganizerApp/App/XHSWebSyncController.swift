import Foundation
import Observation
import WebKit
import XHSOrganizerCore

@MainActor
@Observable
final class XHSWebSyncController: NSObject, WKNavigationDelegate {
    let webView: WKWebView

    private let importService = BrowserSyncImportService()
    private var store: LibraryStore?

    private(set) var currentURLString = ""
    private(set) var pageTitle = "小红书"
    private(set) var statusText = "在这个窗口里登录小红书，然后点“打开收藏夹”或手动进入收藏页。"
    private(set) var lastSyncText = "还没有执行页面同步"
    private(set) var lastDetectedCount = 0
    private(set) var pendingUnsyncedCount = 0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var isSyncingAll = false
    private(set) var isFavoritesPage = false
    private(set) var lastSyncMode = "未开始"
    private(set) var syncProgressText = "等待开始"
    private(set) var syncProgressCount = 0
    private(set) var syncTotalCount = 0
    private(set) var importedCount = 0
    private(set) var duplicateCount = 0
    private(set) var failedCount = 0
    private(set) var currentRound = 0
    private(set) var isRateLimited = false

    override init() {
        let configuration = AppWebSession.makeConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
    }

    func attach(store: LibraryStore) {
        self.store = store
        pendingUnsyncedCount = store.xhsSyncSettings.pendingUnsyncedCount
    }

    func loadHome() {
        guard let url = URL(string: "https://www.xiaohongshu.com/explore") else { return }
        statusText = "正在打开小红书首页"
        webView.load(URLRequest(url: url))
    }

    func load(url: URL) {
        statusText = "正在打开指定页面"
        webView.load(URLRequest(url: url))
    }

    func openProfilePage() {
        if let currentURL = webView.url, currentURL.host?.contains("xiaohongshu.com") == true {
            statusText = "正在当前页面里尝试打开“我/我的页面”"
            triggerProfileNavigation()
        } else {
            loadHome()
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    self.triggerProfileNavigation()
                }
            }
        }
    }

    func openFavorites(store: LibraryStore) {
        attach(store: store)

        if let lastFavoritesURL = store.xhsSyncSettings.lastFavoritesURL,
           let url = URL(string: lastFavoritesURL) {
            statusText = "正在打开上次同步过的收藏页"
            webView.load(URLRequest(url: url))
            return
        }

        if let currentURL = webView.url, currentURL.host?.contains("xiaohongshu.com") == true {
            statusText = "正在当前页面里尝试打开收藏夹"
            triggerFavoritesNavigation()
        } else {
            loadHome()
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    self.triggerFavoritesNavigation()
                }
            }
        }
    }

    func rememberCurrentPageAsFavorites(store: LibraryStore) {
        attach(store: store)
        guard let currentURL = webView.url?.absoluteString, !currentURL.isEmpty else {
            statusText = "当前还没有可记住的页面。先进入你的收藏夹页面。"
            return
        }

        store.updateXHSSyncSettings { settings in
            settings.lastFavoritesURL = currentURL
            settings.lastSyncSummary = "已记住这个收藏夹页面，下次会优先直接打开。"
        }
        statusText = "已记住当前页面为你的收藏夹页。下次点“打开收藏夹”会直接回来。"
    }

    func reload() {
        webView.reload()
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func checkForUnsynced(store: LibraryStore) {
        attach(store: store)
        Task {
            lastSyncMode = "检查新增"
            syncProgressText = "准备检查新增"
            syncProgressCount = 0
            syncTotalCount = 0
            importedCount = 0
            duplicateCount = 0
            failedCount = 0
            currentRound = 0
            isRateLimited = false
            statusText = "正在检查收藏夹里有多少新增内容…"
            do {
                try await ensureFavoritesPage()
                let request = try await collectAllFavoritesRequest()
                let unsyncedCount = request.notes.reduce(into: 0) { result, note in
                    let key = TextProcessing.canonicalKey(from: note.url)
                    if store.existingSavedItem(for: key) == nil {
                        result += 1
                    }
                }

                pendingUnsyncedCount = unsyncedCount
                lastDetectedCount = request.notes.count
                syncTotalCount = request.notes.count
                syncProgressCount = request.notes.count - unsyncedCount
                syncProgressText = "已识别 \(request.notes.count) 条，待同步 \(unsyncedCount) 条"
                lastSyncText = "检查完成：当前收藏页共识别 \(request.notes.count) 条，待同步 \(unsyncedCount) 条。"
                statusText = lastSyncText
                store.updateXHSSyncSettings { settings in
                    settings.lastFavoritesURL = request.pageURL ?? settings.lastFavoritesURL
                    settings.lastCheckedAt = .now
                    settings.lastKnownRemoteCount = request.notes.count
                    settings.pendingUnsyncedCount = unsyncedCount
                    settings.lastSyncSummary = lastSyncText
                }
            } catch {
                statusText = "检查新增失败：\(error.localizedDescription)"
            }
        }
    }

    func syncCurrentPage(store: LibraryStore) {
        attach(store: store)
        Task {
            lastSyncMode = "当前页同步"
            syncProgressText = "读取当前页"
            syncProgressCount = 0
            syncTotalCount = 0
            importedCount = 0
            duplicateCount = 0
            failedCount = 0
            currentRound = 0
            isRateLimited = false
            statusText = "正在同步当前页面可见内容…"
            do {
                try await ensureFavoritesPage()
                let request = try await collectCurrentPageRequest()
                lastDetectedCount = request.notes.count
                syncTotalCount = request.notes.count
                syncProgressCount = 0
                syncProgressText = "当前页识别到 \(request.notes.count) 条"
                guard !request.notes.isEmpty else {
                    lastSyncText = "当前页面没有识别到可导入的收藏内容。"
                    statusText = lastSyncText
                    return
                }

                let result = await importService.importNotes(request, into: store) { progress in
                    await MainActor.run {
                        self.apply(progress: progress)
                    }
                }
                pendingUnsyncedCount = max(0, store.xhsSyncSettings.pendingUnsyncedCount)
                lastSyncText = result.message
                statusText = "当前页同步完成，本次识别 \(request.notes.count) 条"
            } catch {
                statusText = "页面同步失败：\(error.localizedDescription)"
            }
        }
    }

    func syncAllFavorites(store: LibraryStore) {
        attach(store: store)
        isSyncingAll = true

        Task {
            lastSyncMode = "全量同步"
            syncProgressText = "从顶部开始准备扫描"
            syncProgressCount = 0
            syncTotalCount = 0
            importedCount = 0
            duplicateCount = 0
            failedCount = 0
            currentRound = 0
            isRateLimited = false
            statusText = "正在从当前收藏夹顶部开始抓取全部内容…"
            defer { isSyncingAll = false }

            do {
                try await ensureFavoritesPage()
                let request = try await collectAllFavoritesRequest()
                lastDetectedCount = request.notes.count
                syncTotalCount = request.notes.count

                guard !request.notes.isEmpty else {
                    lastSyncText = "没有识别到可同步的收藏内容。"
                    statusText = lastSyncText
                    return
                }

                syncProgressText = "全量抓取完成，开始统一去重和分类"
                syncProgressCount = 0
                statusText = "已抓取 \(request.notes.count) 条，正在统一处理…"

                let result = await importService.importNotes(request, into: store) { progress in
                    await MainActor.run {
                        self.apply(progress: progress)
                    }
                }
                pendingUnsyncedCount = 0
                syncProgressText = "全部处理完成"
                syncProgressCount = request.notes.count
                lastSyncText = "全量同步完成：收藏页识别 \(request.notes.count) 条，新增 \(result.importedCount) 条。"
                statusText = lastSyncText
                store.updateXHSSyncSettings { settings in
                    settings.lastFavoritesURL = request.pageURL ?? settings.lastFavoritesURL
                    settings.lastCheckedAt = .now
                    settings.lastKnownRemoteCount = request.notes.count
                    settings.pendingUnsyncedCount = 0
                    settings.lastSyncSummary = lastSyncText
                }
            } catch {
                statusText = "全量同步失败：\(error.localizedDescription)"
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        refreshNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        pageTitle = webView.title ?? "小红书"
        currentURLString = webView.url?.absoluteString ?? ""
        refreshNavigationState()
        Task {
            await normalizeXHSPageLayoutIfNeeded()
            await refreshFavoritesFlag()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        statusText = "页面加载失败：\(error.localizedDescription)"
        refreshNavigationState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        statusText = "页面加载失败：\(error.localizedDescription)"
        refreshNavigationState()
    }

    private func refreshNavigationState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURLString = webView.url?.absoluteString ?? currentURLString
        pageTitle = webView.title ?? pageTitle
    }

    private func refreshFavoritesFlag() async {
        do {
            if try await isAccessLimited() {
                isRateLimited = true
                isFavoritesPage = false
                statusText = "小红书当前触发了安全限制 300013。先停一会儿，再手动重试同步。"
                return
            }
            let result = try await evaluateString(script: favoritesDetectionScript())
            isFavoritesPage = result == "true"
            if isFavoritesPage {
                statusText = "当前页面已识别为你的收藏夹，可以检查新增或同步。"
            }
        } catch {
            isFavoritesPage = false
        }
    }

    private func normalizeXHSPageLayoutIfNeeded() async {
        guard currentURLString.contains("xiaohongshu.com") else { return }
        _ = try? await evaluateString(script: xhsLayoutNormalizationScript())
        try? await Task.sleep(for: .milliseconds(350))
        _ = try? await evaluateString(script: xhsLayoutNormalizationScript())
        try? await Task.sleep(for: .milliseconds(900))
        _ = try? await evaluateString(script: xhsLayoutNormalizationScript())
    }

    private func ensureFavoritesPage() async throws {
        if try await isAccessLimited() {
            isRateLimited = true
            throw NSError(
                domain: "XHSWebSync",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "小红书当前触发了安全限制 300013。请稍后再试，不要连续频繁同步。"]
            )
        }
        let result = try await evaluateString(script: favoritesDetectionScript())
        isFavoritesPage = result == "true"
        guard isFavoritesPage else {
            throw NSError(
                domain: "XHSWebSync",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "当前不是你的收藏夹页面。请先在内置页面里打开“我的收藏/收藏夹”，再执行同步。"]
            )
        }
    }

    private func xhsLayoutNormalizationScript() -> String {
        """
        (() => {
          try {
            const root = document.documentElement;
            const body = document.body;
            if (body) {
              body.style.zoom = '1';
            }
            if (root) {
              root.style.scrollBehavior = 'auto';
            }
            const normalize = () => {
              const viewportHeight = window.innerHeight || 0;
              const viewportWidth = window.innerWidth || 0;
              const candidates = Array.from(document.querySelectorAll('div, section, aside, article'))
                .filter((element) => {
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  const isOverlay = style.position === 'fixed' || style.position === 'absolute';
                  const isVisible = rect.bottom > 0 && rect.right > 0 && rect.top < viewportHeight && rect.left < viewportWidth;
                  const isLarge = rect.width > Math.min(520, viewportWidth * 0.32) && rect.height > Math.min(240, viewportHeight * 0.22);
                  const isHighLayer = (parseInt(style.zIndex || '0', 10) || 0) >= 10 || style.position === 'fixed';
                  return isOverlay && isVisible && isLarge && isHighLayer;
                })
                .sort((lhs, rhs) => {
                  const leftRect = lhs.getBoundingClientRect();
                  const rightRect = rhs.getBoundingClientRect();
                  return rightRect.width * rightRect.height - leftRect.width * leftRect.height;
                });

              candidates.forEach((element) => {
                const rect = element.getBoundingClientRect();
                const tooLow = rect.top > viewportHeight * 0.04 || rect.bottom > viewportHeight * 0.84;
                const tallOverlay = rect.height > viewportHeight * 0.52;
                if (tooLow || tallOverlay) {
                  const notePanel = rect.width > viewportWidth * 0.66 && rect.height > viewportHeight * 0.58;
                  const extremelyTall = rect.height > viewportHeight * 0.90 || rect.bottom > viewportHeight * 0.99;
                  element.style.setProperty('position', 'fixed', 'important');
                  element.style.setProperty('left', '50%', 'important');
                  element.style.setProperty('right', 'auto', 'important');
                  element.style.setProperty('margin', '0', 'important');

                  if (notePanel) {
                    // Note dialogs should move up, but keep their internal scroll behavior intact.
                    element.style.setProperty('top', '2%', 'important');
                    element.style.setProperty('bottom', '2%', 'important');
                    element.style.setProperty('transform', 'translateX(-50%)', 'important');
                    element.style.setProperty('transform-origin', 'center top', 'important');
                    element.style.setProperty('max-height', '98vh', 'important');
                    // Force vertical scrolling on long note details (text + images).
                    element.style.setProperty('overflow-y', 'auto', 'important');
                    element.style.setProperty('overflow-x', 'hidden', 'important');
                    element.style.setProperty('overscroll-behavior', 'contain', 'important');
                    element.style.setProperty('min-height', '0', 'important');

                    // Keep inner scrollers alive, otherwise long text+image notes stop halfway.
                    const innerScrollables = Array.from(element.querySelectorAll('div, section, article'))
                      .filter((node) => {
                        const style = window.getComputedStyle(node);
                        const rect = node.getBoundingClientRect();
                        const canScroll = node.scrollHeight > node.clientHeight + 48;
                        const likelyScrollable =
                          style.overflowY === 'auto' || style.overflowY === 'scroll' || canScroll;
                        return likelyScrollable && rect.height > viewportHeight * 0.22;
                      });
                    innerScrollables.forEach((node) => {
                      node.style.setProperty('max-height', '90vh', 'important');
                      node.style.setProperty('overflow-y', 'auto', 'important');
                      node.style.setProperty('overflow-x', 'hidden', 'important');
                      node.style.setProperty('min-height', '0', 'important');
                      node.style.setProperty('overscroll-behavior', 'contain', 'important');
                    });

                    // Let mouse wheel always drive the deepest scrollable container.
                    if (!element.__xhsOrganizerWheelBound) {
                      element.addEventListener(
                        'wheel',
                        (event) => {
                          const target = innerScrollables
                            .slice()
                            .sort((a, b) => b.clientHeight - a.clientHeight)
                            .find((node) => node.scrollHeight > node.clientHeight + 16);
                          if (!target) { return; }
                          target.scrollTop += event.deltaY;
                          event.preventDefault();
                        },
                        { passive: false }
                      );
                      element.__xhsOrganizerWheelBound = true;
                    }
                  } else {
                    const top = extremelyTall ? '14%' : '22%';
                    const shift = extremelyTall ? '-14%' : '-22%';
                    const scale = extremelyTall ? ' scale(0.98)' : '';
                    element.style.setProperty('top', top, 'important');
                    element.style.setProperty('bottom', 'auto', 'important');
                    element.style.setProperty('transform', `translate(-50%, ${shift})${scale}`, 'important');
                    element.style.setProperty('transform-origin', 'center top', 'important');
                    element.style.setProperty('max-height', '78vh', 'important');
                    element.style.setProperty('overflow', 'auto', 'important');
                  }
                }
              });
            };

            normalize();
            if (!window.__xhsOrganizerOverlayObserver) {
              const observer = new MutationObserver(() => {
                requestAnimationFrame(normalize);
              });
              observer.observe(document.body, { childList: true, subtree: true, attributes: true });
              window.__xhsOrganizerOverlayObserver = observer;
              window.__xhsOrganizerOverlayTimer = window.setInterval(normalize, 800);
            }

            return 'ok';
          } catch (error) {
            return 'error';
          }
        })();
        """
    }

    private func triggerFavoritesNavigation() {
        webView.evaluateJavaScript(openFavoritesScript()) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                switch result as? String {
                case "clicked":
                    self.statusText = "已经尝试打开收藏夹；如果页面没有跳转，请在页面里手动点“收藏”或“收藏夹”。"
                case "clicked-profile":
                    self.statusText = "先进入了“我/我的页面”，接着继续尝试打开收藏夹。"
                    Task {
                        try? await Task.sleep(for: .seconds(1.8))
                        await MainActor.run {
                            self.triggerFavoritesNavigation()
                        }
                    }
                default:
                    self.statusText = "没找到明显的收藏入口。你可以先点“打开我的页面”，再手动进入收藏夹，并点“记住当前页为收藏夹”。"
                }
            }
        }
    }

    private func triggerProfileNavigation() {
        webView.evaluateJavaScript(openProfileScript()) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                if let result = result as? String, result == "clicked" {
                    self.statusText = "已经尝试打开“我/我的页面”。"
                } else {
                    self.statusText = "没找到明显的“我/我的页面”入口。你也可以自己手动进入个人页。"
                }
            }
        }
    }

    private func collectAllFavoritesRequest() async throws -> BrowserSyncImportRequest {
        _ = try await evaluateString(script: beginFullFavoritesCollectionScript())
        let startTime = Date()

        while true {
            let snapshotJSON = try await evaluateString(script: collectionProgressSnapshotScript())
            let snapshotData = snapshotJSON.data(using: .utf8) ?? Data("{}".utf8)
            let snapshot = (try? JSONDecoder().decode(CollectionProgressSnapshot.self, from: snapshotData)) ?? .empty

            syncProgressText = snapshot.message
            syncProgressCount = snapshot.count
            if let totalHint = snapshot.totalHint, totalHint > 0 {
                syncTotalCount = max(syncTotalCount, totalHint)
            } else {
                syncTotalCount = max(syncTotalCount, snapshot.count)
            }
            currentRound = snapshot.round
            lastDetectedCount = snapshot.count

            if let error = snapshot.error, !error.isEmpty {
                if error.contains("300013") || error.contains("访问频繁") || error.contains("安全限制") {
                    isRateLimited = true
                }
                throw NSError(domain: "XHSWebSync", code: 4, userInfo: [NSLocalizedDescriptionKey: error])
            }

            if snapshot.completed, let payload = snapshot.payload {
                guard let data = payload.data(using: .utf8) else {
                    throw NSError(domain: "XHSWebSync", code: 3, userInfo: [NSLocalizedDescriptionKey: "全量同步返回的数据不是有效文本"])
                }
                return try JSONDecoder().decode(BrowserSyncImportRequest.self, from: data)
            }

            if Date().timeIntervalSince(startTime) > 180 {
                throw NSError(domain: "XHSWebSync", code: 5, userInfo: [NSLocalizedDescriptionKey: "全量同步超时。页面可能没有继续加载，可以滚动到更下面后再试。"])
            }

            try await Task.sleep(for: .milliseconds(220))
        }
    }

    private func collectCurrentPageRequest() async throws -> BrowserSyncImportRequest {
        if try await isAccessLimited() {
            isRateLimited = true
            throw NSError(domain: "XHSWebSync", code: 7, userInfo: [NSLocalizedDescriptionKey: "小红书当前触发了安全限制 300013。请稍后再试。"])
        }
        let json = try await evaluateString(script: syncExtractionScript())
        guard let data = json.data(using: .utf8) else {
            throw NSError(domain: "XHSWebSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "页面返回的数据不是有效文本"])
        }
        return try JSONDecoder().decode(BrowserSyncImportRequest.self, from: data)
    }

    private func isAccessLimited() async throws -> Bool {
        let result = try await evaluateString(script: accessLimitDetectionScript())
        return result == "true"
    }

    private func evaluateString(script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }

    private func evaluateAsyncString(script: String) async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return result as? String ?? ""
    }

    private func openFavoritesScript() -> String {
        """
        (() => {
          const candidates = Array.from(document.querySelectorAll('a, button, [role="button"], div, span'));
          const normalizedText = (node) => (node.innerText || node.textContent || '').replace(/\\s+/g, ' ').trim();
          const hrefTarget = candidates.find((node) => {
            const href = (node.getAttribute && (node.getAttribute('href') || node.getAttribute('data-href'))) || '';
            return ['collect', 'favorite', 'fav', 'save'].some(keyword => href.toLowerCase().includes(keyword));
          });
          if (hrefTarget) {
            hrefTarget.click();
            return 'clicked';
          }

          const favoritesTarget = candidates.find((node) => {
            const text = normalizedText(node);
            return ['收藏夹', '我的收藏', '收藏的笔记', '收藏'].some(keyword => text.includes(keyword));
          });
          if (favoritesTarget) {
            favoritesTarget.click();
            return 'clicked';
          }

          const profileTarget = candidates.find((node) => {
            const text = normalizedText(node);
            return ['我', '我的', '个人主页'].some(keyword => text === keyword || text.includes(keyword));
          });
          if (profileTarget) {
            profileTarget.click();
            return 'clicked-profile';
          }

          return 'not-found';
        })()
        """
    }

    private func openProfileScript() -> String {
        """
        (() => {
          const candidates = Array.from(document.querySelectorAll('a, button, [role="button"], div, span'));
          const target = candidates.find((node) => {
            const text = (node.innerText || node.textContent || '').replace(/\\s+/g, ' ').trim();
            const href = (node.getAttribute && (node.getAttribute('href') || '')) || '';
            return ['我', '我的', '个人主页'].some(keyword => text === keyword || text.includes(keyword))
              || ['user', 'profile', 'mine', 'me'].some(keyword => href.toLowerCase().includes(keyword));
          });
          if (target) {
            target.click();
            return 'clicked';
          }
          return 'not-found';
        })()
        """
    }

    private func favoritesDetectionScript() -> String {
        """
        (() => {
          const url = location.href;
          const title = (document.title || '').toLowerCase();
          const text = (document.body?.innerText || '').replace(/\\s+/g, ' ').trim();
          const urlMatched = ['collect', 'favorite', 'favs', 'save'].some(keyword => url.toLowerCase().includes(keyword));
          const textMatched = ['收藏夹', '我的收藏', '收藏的笔记', '收藏'].some(keyword => text.includes(keyword) || title.includes(keyword));
          return (urlMatched || textMatched) ? 'true' : 'false';
        })()
        """
    }

    private func accessLimitDetectionScript() -> String {
        """
        (() => {
          const text = (document.body?.innerText || '').replace(/\\s+/g, ' ').trim();
          const title = (document.title || '').replace(/\\s+/g, ' ').trim();
          const matched = ['安全限制', '访问频繁', '300013'].some(keyword => text.includes(keyword) || title.includes(keyword));
          return matched ? 'true' : 'false';
        })()
        """
    }

    private func syncExtractionScript() -> String {
        """
        (() => {
          const normalize = (text) => (text || '').replace(/\\s+/g, ' ').trim();
          const unique = (items) => Array.from(new Set(items.filter(Boolean)));
          const extractNoteId = (value) => {
            const text = typeof value === 'string' ? value : '';
            const match = text.match(/\\/(?:explore|discovery\\/item)\\/([^/?#]+)/i) || text.match(/^([0-9a-f]{24,})$/i);
            return match ? match[1] : '';
          };
          const tokenMap = (() => {
            const roots = [window.__INITIAL_STATE__, window.__INITIAL_SSR_STATE__, window.__INITIAL_SERVER_STATE__].filter(Boolean);
            const visited = new Set();
            const stack = [...roots];
            const map = new Map();
            while (stack.length) {
              const current = stack.pop();
              if (!current || typeof current !== 'object' || visited.has(current)) continue;
              visited.add(current);
              if (Array.isArray(current)) {
                for (const item of current) stack.push(item);
                continue;
              }
              const noteId = extractNoteId(current.id) || extractNoteId(current.noteId) || extractNoteId(current.note_id);
              const token = typeof current.xsecToken === 'string' ? current.xsecToken : (typeof current.xsec_token === 'string' ? current.xsec_token : '');
              if (noteId && token && !map.has(noteId)) {
                map.set(noteId, token);
              }
              for (const value of Object.values(current)) {
                if (value && typeof value === 'object') stack.push(value);
              }
            }
            return map;
          })();
          const resolveNoteURL = (rawHref) => {
            const resolved = new URL(rawHref, location.href);
            const noteId = extractNoteId(resolved.pathname);
            if (!noteId) return resolved.href;
            if (!resolved.searchParams.get('xsec_token')) {
              const token = tokenMap.get(noteId);
              if (token) {
                resolved.searchParams.set('xsec_token', token);
                if (!resolved.searchParams.get('xsec_source')) {
                  resolved.searchParams.set('xsec_source', 'pc_feed');
                }
              }
            }
            return resolved.href;
          };
          const pickContainer = (anchor) => {
            let current = anchor;
            let bestCandidates = [];
            for (let depth = 0; current && depth < 8; depth += 1, current = current.parentElement) {
              const text = normalize(current.innerText || '');
              if (!text) continue;
              const linkCount = current.querySelectorAll ? current.querySelectorAll('a[href]').length : 0;
              const imageCount = current.querySelectorAll ? current.querySelectorAll('img').length : 0;
              const score = Math.min(text.length, 900) - Math.max(0, (linkCount - 3) * 60) + imageCount * 10;
              bestCandidates.push({ node: current, score, textLength: text.length });
            }
            bestCandidates.sort((lhs, rhs) => {
              if (lhs.score === rhs.score) return rhs.textLength - lhs.textLength;
              return rhs.score - lhs.score;
            });
            return bestCandidates[0]?.node || anchor;
          };
          const extractNote = (anchor) => {
            const container = pickContainer(anchor);
            const imageNode = anchor.querySelector('img') || container?.querySelector('img');
            const authorNode = container?.querySelector('[class*="author"], [class*="user"], [class*="name"], [data-testid*="author"]');
            const textCandidates = [];
            const pushText = (value) => {
              const normalized = normalize(value);
              if (normalized) textCandidates.push(normalized);
            };

            pushText(anchor.getAttribute?.('aria-label'));
            pushText(anchor.innerText);
            pushText(container?.getAttribute?.('aria-label'));

            const nodes = container
              ? Array.from(container.querySelectorAll('h1, h2, h3, h4, p, span, div, img[alt], [class*="title"], [class*="desc"], [class*="content"], [class*="note"], [class*="text"]'))
              : [];

            for (const node of nodes) {
              if (node.tagName === 'IMG') {
                pushText(node.getAttribute('alt'));
              } else {
                pushText(node.innerText || node.textContent || '');
              }
            }

            pushText(container?.innerText || '');

            const segments = unique(
              textCandidates
                .flatMap((value) => value.split(/\\n+/))
                .map((value) => normalize(value))
                .filter((value) => value.length >= 2)
            );

            const title = (segments.find((value) => value.length >= 4) || normalize(anchor.innerText) || '未命名收藏').slice(0, 120);
            const bodyLines = segments.filter((value) => value !== title);
            const text = bodyLines.join('\\n').slice(0, 1600);

            return {
              title,
              text,
              coverImageURL: imageNode?.src || '',
              author: normalize(authorNode?.innerText || '')
            };
          };
          const anchors = Array.from(document.querySelectorAll('a[href]'));
          const notes = [];
          const seen = new Set();

          for (const anchor of anchors) {
            const rawHref = anchor.getAttribute('href');
            if (!rawHref) continue;
            const href = resolveNoteURL(rawHref);
            if (!(href.includes('/explore/') || href.includes('/discovery/item/') || href.includes('xhslink.com'))) continue;
            if (seen.has(href)) continue;
            const note = extractNote(anchor);
            if (!note.title) continue;

            seen.add(href);
            notes.push({
              url: href,
              title: note.title,
              text: note.text,
              coverImageURL: note.coverImageURL,
              author: note.author
            });
          }

          return JSON.stringify({
            source: 'in-app-webview',
            pageURL: location.href,
            pageTitle: document.title,
            notes
          });
        })()
        """
    }

    private func beginFullFavoritesCollectionScript() -> String {
        return """
        (() => {
          if (window.__xhsOrganizerCollectionState && window.__xhsOrganizerCollectionState.running) {
            return 'already-running';
          }

          window.__xhsOrganizerCollectionState = {
            running: true,
            completed: false,
            count: 0,
            totalHint: 0,
            round: 0,
            message: '从顶部开始准备扫描',
            payload: null,
            error: null
          };

          (async () => {
            const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));
            const normalize = (text) => (text || '').replace(/\\s+/g, ' ').trim();
            const isAccessLimited = () => {
              const text = normalize(document.body?.innerText || '');
              const title = normalize(document.title || '');
              return ['安全限制', '访问频繁', '300013'].some((keyword) => text.includes(keyword) || title.includes(keyword));
            };
            const extractNoteId = (value) => {
              const text = typeof value === 'string' ? value : '';
              const match = text.match(/\\/(?:explore|discovery\\/item)\\/([^/?#]+)/i) || text.match(/^([0-9a-f]{24,})$/i);
              return match ? match[1] : '';
            };
            const tokenMap = (() => {
              const roots = [window.__INITIAL_STATE__, window.__INITIAL_SSR_STATE__, window.__INITIAL_SERVER_STATE__].filter(Boolean);
              const visited = new Set();
              const stack = [...roots];
              const map = new Map();
              while (stack.length) {
                const current = stack.pop();
                if (!current || typeof current !== 'object' || visited.has(current)) continue;
                visited.add(current);
                if (Array.isArray(current)) {
                  for (const item of current) stack.push(item);
                  continue;
                }
                const noteId = extractNoteId(current.id) || extractNoteId(current.noteId) || extractNoteId(current.note_id);
                const token = typeof current.xsecToken === 'string' ? current.xsecToken : (typeof current.xsec_token === 'string' ? current.xsec_token : '');
                if (noteId && token && !map.has(noteId)) {
                  map.set(noteId, token);
                }
                for (const value of Object.values(current)) {
                  if (value && typeof value === 'object') stack.push(value);
                }
              }
              return map;
            })();
            const resolveNoteURL = (rawHref) => {
              const resolved = new URL(rawHref, location.href);
              const noteId = extractNoteId(resolved.pathname);
              if (!noteId) return resolved.href;
              if (!resolved.searchParams.get('xsec_token')) {
                const token = tokenMap.get(noteId);
                if (token) {
                  resolved.searchParams.set('xsec_token', token);
                  if (!resolved.searchParams.get('xsec_source')) {
                    resolved.searchParams.set('xsec_source', 'pc_feed');
                  }
                }
              }
              return resolved.href;
            };
            const scrollRoot = (() => {
              const candidates = [document.scrollingElement, document.documentElement, document.body]
                .concat(Array.from(document.querySelectorAll('*')).filter((node) => {
                  if (!(node instanceof HTMLElement)) return false;
                  const style = getComputedStyle(node);
                  const scrollable = ['auto', 'scroll', 'overlay'].includes(style.overflowY);
                  return scrollable && node.scrollHeight > node.clientHeight + 300;
                }));
              return candidates
                .filter(Boolean)
                .sort((lhs, rhs) => (rhs.scrollHeight - rhs.clientHeight) - (lhs.scrollHeight - lhs.clientHeight))[0] || document.scrollingElement || document.documentElement;
            })();
            const detectTotalHint = () => {
              const text = normalize(document.body?.innerText || '');
              const title = normalize(document.title || '');
              const patterns = [
                /收藏(?:夹|的笔记)?[^0-9]{0,8}(\\d{2,6})/g,
                /(?:共|共有)[^0-9]{0,4}(\\d{2,6})[^0-9]{0,2}(?:篇|条|个)/g,
                /(\\d{2,6})[^0-9]{0,2}(?:篇|条|个)[^\\n]{0,8}收藏/g
              ];
              let best = 0;
              for (const source of [text, title]) {
                for (const pattern of patterns) {
                  const matches = source.matchAll(pattern);
                  for (const match of matches) {
                    const value = Number(match[1] || 0);
                    if (Number.isFinite(value) && value > best) best = value;
                  }
                }
              }
              return best;
            };
            const rootHeight = () => Math.max(scrollRoot.scrollHeight || 0, document.body.scrollHeight, document.documentElement.scrollHeight);
            const rootTop = () => scrollRoot.scrollTop || window.scrollY || 0;
            const rootViewport = () => scrollRoot.clientHeight || window.innerHeight || 0;
            const percentText = (count, hint) => {
              if (!hint) return `${count}`;
              const percent = Math.round((count / hint) * 100);
              return `${count}/${hint} (${percent}%)`;
            };
            const scrollToTop = () => {
              if (typeof scrollRoot.scrollTo === 'function') {
                scrollRoot.scrollTo({ top: 0, behavior: 'auto' });
              } else {
                scrollRoot.scrollTop = 0;
              }
              window.scrollTo({ top: 0, behavior: 'auto' });
            };
            const scrollToNext = (nextTop) => {
              if (typeof scrollRoot.scrollTo === 'function') {
                scrollRoot.scrollTo({ top: nextTop, behavior: 'auto' });
              } else {
                scrollRoot.scrollTop = nextTop;
              }
              window.scrollTo({ top: nextTop, behavior: 'auto' });
            };
            const unique = (items) => Array.from(new Set(items.filter(Boolean)));
            const pickContainer = (anchor) => {
              let current = anchor;
              const candidates = [];
              for (let depth = 0; current && depth < 8; depth += 1, current = current.parentElement) {
                const text = normalize(current.innerText || '');
                if (!text) continue;
                const linkCount = current.querySelectorAll ? current.querySelectorAll('a[href]').length : 0;
                const imageCount = current.querySelectorAll ? current.querySelectorAll('img').length : 0;
                const score = Math.min(text.length, 900) - Math.max(0, (linkCount - 3) * 60) + imageCount * 10;
                candidates.push({ node: current, score, textLength: text.length });
              }
              candidates.sort((lhs, rhs) => {
                if (lhs.score === rhs.score) return rhs.textLength - lhs.textLength;
                return rhs.score - lhs.score;
              });
              return candidates[0]?.node || anchor;
            };
            const extractNote = (anchor) => {
              const container = pickContainer(anchor);
              const imageNode = anchor.querySelector('img') || container?.querySelector('img');
              const authorNode = container?.querySelector('[class*="author"], [class*="user"], [class*="name"], [data-testid*="author"]');
              const textCandidates = [];
              const pushText = (value) => {
                const normalized = normalize(value);
                if (normalized) textCandidates.push(normalized);
              };

              pushText(anchor.getAttribute?.('aria-label'));
              pushText(anchor.innerText);
              pushText(container?.getAttribute?.('aria-label'));

              const nodes = container
                ? Array.from(container.querySelectorAll('h1, h2, h3, h4, p, span, div, img[alt], [class*="title"], [class*="desc"], [class*="content"], [class*="note"], [class*="text"]'))
                : [];

              for (const node of nodes) {
                if (node.tagName === 'IMG') {
                  pushText(node.getAttribute('alt'));
                } else {
                  pushText(node.innerText || node.textContent || '');
                }
              }

              pushText(container?.innerText || '');

              const segments = unique(
                textCandidates
                  .flatMap((value) => value.split(/\\n+/))
                  .map((value) => normalize(value))
                  .filter((value) => value.length >= 2)
              );

              const title = (segments.find((value) => value.length >= 4) || normalize(anchor.innerText) || '未命名收藏').slice(0, 120);
              const bodyLines = segments.filter((value) => value !== title);
              const text = bodyLines.join('\\n').slice(0, 1600);

              return {
                title,
                text,
                coverImageURL: imageNode?.src || '',
                author: normalize(authorNode?.innerText || '')
              };
            };

            const collect = () => {
              const anchors = Array.from(document.querySelectorAll('a[href]'));
              const notes = [];
              const seen = new Set();

              for (const anchor of anchors) {
                const rawHref = anchor.getAttribute('href');
                if (!rawHref) continue;
                const href = resolveNoteURL(rawHref);
                if (!(href.includes('/explore/') || href.includes('/discovery/item/') || href.includes('xhslink.com'))) continue;
                if (seen.has(href)) continue;
                const note = extractNote(anchor);
                if (!note.title) continue;

                seen.add(href);
                notes.push({
                  url: href,
                  title: note.title,
                  text: note.text,
                  coverImageURL: note.coverImageURL,
                  author: note.author
                });
              }

              return notes;
            };

            const tryNext = () => {
              const candidates = Array.from(document.querySelectorAll('button, a, [role="button"]'));
              const target = candidates.find((node) => {
                const text = (node.innerText || node.textContent || '').replace(/\\s+/g, ' ').trim();
                const disabled = node.disabled || node.getAttribute('aria-disabled') === 'true';
                return !disabled && ['下一页', '下一页>', '更多', '加载更多'].some(keyword => text.includes(keyword));
              });
              if (target) {
                target.click();
                return true;
              }
              return false;
            };

            scrollToTop();
            await sleep(400);

            const merged = new Map();
            let totalHint = detectTotalHint();
            let stableRounds = 0;
            let nearBottomRounds = 0;
            let stagnantRounds = 0;
            let lastCount = 0;
            let lastHeight = 0;

            for (let round = 0; round < 2200; round++) {
              if (isAccessLimited()) {
                throw new Error('小红书当前触发了安全限制 300013，请稍后再试');
              }

              for (const note of collect()) {
                merged.set(note.url, note);
              }

              const count = merged.size;
              const height = rootHeight();
              const viewportBottom = rootTop() + rootViewport();
              const isNearBottom = viewportBottom >= height - 240;
              totalHint = Math.max(totalHint, detectTotalHint());
              window.__xhsOrganizerCollectionState = {
                ...window.__xhsOrganizerCollectionState,
                count,
                totalHint,
                round: round + 1,
                message: totalHint > 0
                  ? `第 ${round + 1} 轮，已抓到 ${percentText(count, totalHint)}`
                  : `第 ${round + 1} 轮，已抓到 ${count} 条`
              };

              if (count > lastCount || height > lastHeight) {
                stableRounds = 0;
                nearBottomRounds = 0;
                stagnantRounds = 0;
                lastCount = count;
                lastHeight = height;
              } else {
                stableRounds += 1;
                stagnantRounds += 1;
                if (isNearBottom) {
                  nearBottomRounds += 1;
                }
              }

              if (totalHint > 0 && count >= totalHint) {
                break;
              }

              if (stagnantRounds >= 80 && totalHint > 0 && count >= Math.floor(totalHint * 0.9)) {
                window.__xhsOrganizerCollectionState = {
                  ...window.__xhsOrganizerCollectionState,
                  count,
                  totalHint,
                  round: round + 1,
                  message: `已抓到 ${percentText(count, totalHint)}，页面长时间没有继续加载，开始处理`
                };
                break;
              }

              if (stagnantRounds >= 140) {
                window.__xhsOrganizerCollectionState = {
                  ...window.__xhsOrganizerCollectionState,
                  count,
                  totalHint,
                  round: round + 1,
                  message: totalHint > 0
                    ? `已抓到 ${percentText(count, totalHint)}，页面停止增长，开始处理`
                    : `已抓到 ${count} 条，页面停止增长，开始处理`
                };
                break;
              }

              if (stableRounds >= 24 || nearBottomRounds >= 10) {
                const clicked = tryNext();
                if (clicked) {
                  stableRounds = 0;
                  nearBottomRounds = 0;
                  stagnantRounds = 0;
                  window.__xhsOrganizerCollectionState = {
                    ...window.__xhsOrganizerCollectionState,
                    message: totalHint > 0
                      ? `已抓到 ${percentText(count, totalHint)}，正在进入下一页`
                      : `已抓到 ${count} 条，正在进入下一页`
                    };
                  await sleep(1800);
                  continue;
                }
                if (isNearBottom) {
                  await sleep(2000);
                  const retryCount = collect().length;
                  const closeToHint = totalHint > 0 ? retryCount >= Math.floor(totalHint * 0.9) : true;
                  if (retryCount <= count && closeToHint) {
                    window.__xhsOrganizerCollectionState = {
                      ...window.__xhsOrganizerCollectionState,
                      count,
                      totalHint,
                      round: round + 1,
                      message: totalHint > 0
                        ? `已抓到 ${percentText(count, totalHint)}，接近总量，开始处理`
                        : `已抓到 ${count} 条，开始处理`
                    };
                    break;
                  }
                }
              }

              const nextTop = Math.min(height, rootTop() + Math.max(rootViewport() * 2.2, 1800));
              scrollToNext(nextTop);
              await sleep(360);
            }

            return JSON.stringify({
              source: 'in-app-webview-all',
              pageURL: location.href,
              pageTitle: document.title,
              notes: Array.from(merged.values())
            });
          })()
            .then((payload) => {
              window.__xhsOrganizerCollectionState = {
                ...window.__xhsOrganizerCollectionState,
                running: false,
                completed: true,
                payload,
                message: '全量抓取完成'
              };
            })
            .catch((error) => {
              window.__xhsOrganizerCollectionState = {
                ...window.__xhsOrganizerCollectionState,
                running: false,
                completed: false,
                error: error?.message || String(error),
                message: '抓取失败'
              };
            });

          return 'started';
        })()
        """
    }

    private func collectionProgressSnapshotScript() -> String {
        """
        (() => {
          const state = window.__xhsOrganizerCollectionState || {
            running: false,
            completed: false,
            count: 0,
            round: 0,
            message: '等待开始',
            payload: null,
            error: null
          };
          return JSON.stringify(state);
        })()
        """
    }

    private func apply(progress: BrowserSyncImportProgress) {
        importedCount = progress.importedCount
        duplicateCount = progress.duplicateCount
        failedCount = progress.failedCount

        switch progress.phase {
        case "智能分类":
            syncTotalCount = progress.totalCount
            syncProgressCount = progress.processedCount
            syncProgressText = "正在按标题和内容自动分类 \(progress.processedCount)/\(progress.totalCount)"
            statusText = "已导入 \(importedCount) 条，重复 \(duplicateCount) 条，失败 \(failedCount) 条"
        case "完成":
            syncProgressText = "同步完成，共处理 \(progress.totalCount) 条"
            syncProgressCount = progress.totalCount
            statusText = "同步完成：新增 \(importedCount) 条，重复 \(duplicateCount) 条，失败 \(failedCount) 条"
        default:
            syncTotalCount = progress.totalCount
            syncProgressCount = progress.processedCount
            pendingUnsyncedCount = progress.remainingCount
            syncProgressText = "已处理 \(progress.processedCount)/\(progress.totalCount)，剩余 \(progress.remainingCount)"
            statusText = "正在导入：新增 \(importedCount) 条，重复 \(duplicateCount) 条，失败 \(failedCount) 条"
        }
    }
}

private struct CollectionProgressSnapshot: Decodable {
    var running: Bool
    var completed: Bool
    var count: Int
    var totalHint: Int?
    var round: Int
    var message: String
    var payload: String?
    var error: String?

    static let empty = CollectionProgressSnapshot(
        running: false,
        completed: false,
        count: 0,
        totalHint: nil,
        round: 0,
        message: "等待开始",
        payload: nil,
        error: nil
    )
}
