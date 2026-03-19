import AppKit
import Foundation
import Observation
import XHSOrganizerCore

@MainActor
@Observable
final class BrowserSyncController {
    private(set) var isRunning = false
    private(set) var serviceStatusText = "尚未连接到 Chrome 收藏夹同步"
    private(set) var actionStatusText = "还没有执行同步"
    private(set) var lastImportText = "还没有接收到 Chrome 同步"
    private(set) var lastReceivedCount = 0
    private(set) var isImporting = false

    private let fileManager: FileManager
    private let importService = BrowserSyncImportService()
    private let filenamePrefix = "xhs-organizer-sync-"
    private let filenameSuffix = ".json"
    private let pollInterval: TimeInterval = 2.0

    private var timer: Timer?
    private var store: LibraryStore?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func startIfNeeded(store: LibraryStore) {
        self.store = store
        isRunning = true
        serviceStatusText = "准备就绪。请先在 Chrome 打开小红书收藏夹页。"
    }

    func scanInbox() async {
        guard let store else {
            isRunning = false
            serviceStatusText = "本地数据存储尚未就绪"
            return
        }

        guard !isImporting else {
            return
        }

        prepareDirectories()
        isRunning = true

        let files = pendingSyncFiles()
        if files.isEmpty {
            serviceStatusText = "正在监听 \(watchedFolderPath())，等待新的同步文件"
            return
        }

        isImporting = true
        defer { isImporting = false }
        serviceStatusText = "正在处理同步文件…"
        actionStatusText = "已检测到 \(files.count) 个同步文件，开始批量导入"

        var processedFiles = 0
        var importedCount = 0
        var duplicateCount = 0
        var failedCount = 0
        var lastRequest: BrowserSyncImportRequest?

        for fileURL in files {
            do {
                let data = try Data(contentsOf: fileURL)
                let request = try JSONDecoder().decode(BrowserSyncImportRequest.self, from: data)
                let result = await importService.importNotes(request, into: store) { [weak self] progress in
                    await MainActor.run {
                        guard let self else { return }
                        self.lastReceivedCount = request.notes.count
                        self.serviceStatusText = "正在处理同步文件…"
                        self.actionStatusText = "\(progress.phase)：\(progress.processedCount)/\(progress.totalCount)，新增 \(progress.importedCount)，合并 \(progress.duplicateCount)，失败 \(progress.failedCount)"
                    }
                }
                lastReceivedCount = request.notes.count
                importedCount += result.importedCount
                duplicateCount += result.duplicateCount
                failedCount += result.failedCount
                processedFiles += 1
                lastRequest = request
                try archive(fileURL: fileURL, to: processedDirectoryURL())
            } catch {
                failedCount += 1
                actionStatusText = "同步文件 \(fileURL.lastPathComponent) 解析失败，已移到失败目录。"
                try? archive(fileURL: fileURL, to: failedDirectoryURL())
            }
        }

        if processedFiles > 0 {
            let message = "文件同步完成：处理 \(processedFiles) 个文件，新增 \(importedCount) 条，合并 \(duplicateCount) 条，失败 \(failedCount) 条。"
            lastImportText = message
            actionStatusText = "最近一次导入了 \(processedFiles) 个同步文件"
            serviceStatusText = "监听中，最近一次扫描已处理 \(processedFiles) 个同步文件"
            store.updateXHSSyncSettings { settings in
                settings.lastFavoritesURL = lastRequest?.pageURL ?? settings.lastFavoritesURL
                settings.lastSyncAt = .now
                settings.lastSyncSummary = message
            }
        }
    }

    func syncFromChromeFavorites() async {
        guard let store else {
            isRunning = false
            serviceStatusText = "本地数据存储尚未就绪"
            return
        }
        guard !isImporting else { return }

        isImporting = true
        defer { isImporting = false }
        isRunning = true
        serviceStatusText = "正在读取 Chrome 当前页面…"
        actionStatusText = "请保持 Chrome 停在你的小红书收藏夹页"

        do {
            let pageURL = try chromeActiveTabURL()
            guard pageURL.contains("xiaohongshu.com"),
                  pageURL.contains("tab=fav") || pageURL.contains("subTab=note")
            else {
                serviceStatusText = "当前 Chrome 页面不是收藏夹"
                actionStatusText = "请先在 Chrome 打开小红书“我的收藏”页，再回 App 点同步。"
                return
            }

            let request = try await collectFavoritesRequestFromChrome(pageURL: pageURL)
            lastReceivedCount = request.notes.count
            lastImportText = "已从 Chrome 识别 \(request.notes.count) 条，正在导入和整理…"

            let result = await importService.importNotes(request, into: store) { [weak self] progress in
                await MainActor.run {
                    guard let self else { return }
                    self.serviceStatusText = "正在同步 Chrome 当前收藏夹页…"
                    let progressText: String
                    if progress.totalCount > 0 {
                        progressText = "\(progress.phase)：\(progress.processedCount)/\(progress.totalCount)"
                    } else {
                        progressText = progress.phase
                    }
                    self.actionStatusText = "\(progressText)，新增 \(progress.importedCount)，合并 \(progress.duplicateCount)，失败 \(progress.failedCount)"
                }
            }

            lastImportText = result.message
            serviceStatusText = "Chrome 收藏夹页同步完成"
            actionStatusText = result.message
        } catch {
            serviceStatusText = "同步失败"
            actionStatusText = error.localizedDescription
        }
    }

    private func collectFavoritesRequestFromChrome(pageURL: String) async throws -> BrowserSyncImportRequest {
        var notesByID: [String: BrowserSyncNotePayload] = [:]
        var staleRounds = 0
        let maxRounds = 80

        for round in 1...maxRounds {
            let rawJSON = try executeChromeJavaScript(syncExtractionScript())
            guard let data = rawJSON.data(using: .utf8) else {
                throw NSError(domain: "BrowserSyncController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chrome 返回的同步结果为空"])
            }
            let snapshot = try JSONDecoder().decode(BrowserSyncImportRequest.self, from: data)

            var addedThisRound = 0
            for note in snapshot.notes {
                let key = noteIdentity(for: note.url)
                if let existing = notesByID[key] {
                    notesByID[key] = merged(note: existing, with: note)
                } else {
                    notesByID[key] = note
                    addedThisRound += 1
                }
            }

            serviceStatusText = "正在读取 Chrome 收藏夹页…"
            actionStatusText = "抓取第 \(round) 轮，已识别 \(notesByID.count) 条"

            if addedThisRound == 0 {
                staleRounds += 1
            } else {
                staleRounds = 0
            }

            if staleRounds >= 4 {
                break
            }

            let rawScrollState = try executeChromeJavaScript(scrollCollectionScript())
            let scrollState = try JSONDecoder().decode(ChromeScrollState.self, from: Data(rawScrollState.utf8))
            if scrollState.atEnd {
                break
            }

            try await Task.sleep(for: .milliseconds(850))
        }

        return BrowserSyncImportRequest(
            source: "chrome-direct-sync",
            pageURL: pageURL,
            pageTitle: "Chrome 收藏夹同步",
            notes: Array(notesByID.values)
        )
    }

    func copyTampermonkeyScript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tampermonkeyScript(), forType: .string)
        actionStatusText = "Tampermonkey 脚本已复制。安装后会把当前收藏页导出成同步文件，App 会自动导入。"
    }

    func copyBookmarklet() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bookmarklet(), forType: .string)
        actionStatusText = "书签脚本已复制。把它粘到浏览器书签 URL 里，然后在收藏页点击即可导出同步文件。"
    }

    func openWatchedFolder() {
        NSWorkspace.shared.open(watchedDirectoryURL())
    }

    func watchedFolderPath() -> String {
        watchedDirectoryURL().path(percentEncoded: false)
    }

    func processedFolderPath() -> String {
        processedDirectoryURL().path(percentEncoded: false)
    }

    func syncFilePatternDescription() -> String {
        "\(filenamePrefix)*\(filenameSuffix)"
    }

    func tampermonkeyScript() -> String {
        if let data = try? Data(contentsOf: userscriptFileURL()),
           let script = String(data: data, encoding: .utf8) {
            return script
        }

        return "// 用户脚本文件读取失败，请直接打开 scripts/xhs_sync_tampermonkey.user.js"
    }

    private func bookmarklet() -> String {
        let payload = """
        javascript:(function(){const normalize=(t)=>(t||'').replace(/\\s+/g,' ').trim();const notes=[];const seen=new Set();document.querySelectorAll('a[href]').forEach((anchor)=>{const raw=anchor.getAttribute('href');if(!raw)return;const href=new URL(raw,location.href).href;if(!(href.includes('/explore/')||href.includes('/discovery/item/')||href.includes('xhslink.com')))return;if(seen.has(href))return;const container=anchor.closest('section,article,li,div');const titleNode=container?.querySelector('img[alt],h1,h2,h3,h4,[class*="title"],[class*="desc"],[class*="note"]');const imageNode=anchor.querySelector('img')||container?.querySelector('img');const authorNode=container?.querySelector('[class*="author"],[class*="user"],[class*="name"]');const titleFromAlt=titleNode&&typeof titleNode.getAttribute==='function'?titleNode.getAttribute('alt'):'';const text=normalize(container?.innerText||anchor.innerText||'');const title=normalize(titleFromAlt||titleNode?.innerText||anchor.innerText||text).slice(0,120);if(!title)return;seen.add(href);notes.push({url:href,title,text:text.slice(0,500),coverImageURL:imageNode?.src||'',author:normalize(authorNode?.innerText||'')});});if(!notes.length){alert('当前页面没有识别到可同步的笔记卡片');return;}const payload={source:'bookmarklet-file-sync',pageURL:location.href,pageTitle:document.title,notes};const blob=new Blob([JSON.stringify(payload,null,2)],{type:'application/json'});const url=URL.createObjectURL(blob);const anchor=document.createElement('a');anchor.href=url;anchor.download=`xhs-organizer-sync-${Date.now()}.json`;document.body.appendChild(anchor);anchor.click();anchor.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);alert(`已导出 ${notes.length} 条到下载文件夹，回到 App 等待自动导入`);})();
        """
        return payload.replacingOccurrences(of: "\n", with: "")
    }

    private func pendingSyncFiles() -> [URL] {
        let watchedDirectory = watchedDirectoryURL()
        guard let urls = try? fileManager.contentsOfDirectory(
            at: watchedDirectory,
            includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix(filenamePrefix) && name.hasSuffix(filenameSuffix)
            }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return lhsDate < rhsDate
            }
    }

    private func watchedDirectoryURL() -> URL {
        if let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Downloads", isDirectory: true)
    }

    private func processedDirectoryURL() -> URL {
        appSupportDirectory().appendingPathComponent("ProcessedSyncFiles", isDirectory: true)
    }

    private func failedDirectoryURL() -> URL {
        appSupportDirectory().appendingPathComponent("FailedSyncFiles", isDirectory: true)
    }

    private func appSupportDirectory() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport.appendingPathComponent("XHSOrganizer", isDirectory: true)
    }

    private func userscriptFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("xhs_sync_tampermonkey.user.js")
    }

    private func prepareDirectories() {
        try? fileManager.createDirectory(at: watchedDirectoryURL(), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: processedDirectoryURL(), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: failedDirectoryURL(), withIntermediateDirectories: true)
    }

    private func chromeActiveTabURL() throws -> String {
        try runOSA(script: #"tell application "Google Chrome" to get URL of active tab of front window"#)
    }

    private func executeChromeJavaScript(_ javaScript: String) throws -> String {
        let script = """
        on run argv
            set js to item 1 of argv
            tell application "Google Chrome"
                return execute active tab of front window javascript js
            end tell
        end run
        """
        return try runOSA(script: script, arguments: [javaScript])
    }

    private func runOSA(script: String, arguments: [String] = []) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "BrowserSyncController", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: stderr.isEmpty ? "执行 Chrome 同步失败" : stderr
            ])
        }

        return stdout
    }

    private func noteIdentity(for url: String) -> String {
        if let match = url.range(of: #"/explore/([^/?#]+)"#, options: .regularExpression) {
            return String(url[match]).replacingOccurrences(of: "/explore/", with: "")
        }
        if let match = url.range(of: #"/user/profile/[^/]+/([^/?#]+)"#, options: .regularExpression) {
            return String(url[match]).components(separatedBy: "/").last ?? url
        }
        return url
    }

    private func merged(note lhs: BrowserSyncNotePayload, with rhs: BrowserSyncNotePayload) -> BrowserSyncNotePayload {
        BrowserSyncNotePayload(
            url: lhs.url.contains("xsec_token=") ? lhs.url : rhs.url,
            title: lhs.title.count >= rhs.title.count ? lhs.title : rhs.title,
            text: lhs.text.count >= rhs.text.count ? lhs.text : rhs.text,
            coverImageURL: lhs.coverImageURL ?? rhs.coverImageURL,
            author: lhs.author ?? rhs.author
        )
    }

    private func syncExtractionScript() -> String {
        """
        (() => {
          const normalize = (text) => (text || '').replace(/\\s+/g, ' ').trim();
          const unique = (items) => Array.from(new Set(items.filter(Boolean)));
          const extractNoteId = (value) => {
            const text = typeof value === 'string' ? value : '';
            const match =
              text.match(/\\/user\\/profile\\/[^/]+\\/([^/?#]+)/i) ||
              text.match(/\\/(?:explore|discovery\\/item)\\/([^/?#]+)/i) ||
              text.match(/^([0-9a-f]{24,})$/i);
            return match ? match[1] : '';
          };
          const buildTokenMap = () => {
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
          };
          const resolveNoteURL = (rawHref, tokenMap) => {
            const resolved = new URL(rawHref, location.href);
            const noteId = extractNoteId(resolved.pathname);
            if (!noteId) return resolved.href;
            const normalized = new URL(`/explore/${noteId}`, location.origin);

            if (resolved.searchParams.get('xsec_token')) {
              normalized.searchParams.set('xsec_token', resolved.searchParams.get('xsec_token'));
            }
            if (resolved.searchParams.get('xsec_source')) {
              normalized.searchParams.set('xsec_source', resolved.searchParams.get('xsec_source'));
            }

            if (!resolved.searchParams.get('xsec_token')) {
              const token = tokenMap.get(noteId);
              if (token) {
                normalized.searchParams.set('xsec_token', token);
              }
            }

            if (!normalized.searchParams.get('xsec_source')) {
              if (resolved.searchParams.get('xsec_source')) {
                normalized.searchParams.set('xsec_source', resolved.searchParams.get('xsec_source'));
              } else {
                normalized.searchParams.set('xsec_source', 'pc_collect');
              }
            }

            return normalized.href;
          };
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
            candidates.sort((lhs, rhs) => lhs.score === rhs.score ? rhs.textLength - lhs.textLength : rhs.score - lhs.score);
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
            const nodes = container ? Array.from(container.querySelectorAll('h1,h2,h3,h4,p,span,div,img[alt],[class*="title"],[class*="desc"],[class*="content"],[class*="note"],[class*="text"]')) : [];
            for (const node of nodes) {
              if (node.tagName === 'IMG') pushText(node.getAttribute('alt'));
              else pushText(node.innerText || node.textContent || '');
            }
            pushText(container?.innerText || '');
            const segments = unique(textCandidates.flatMap((value) => value.split(/\\n+/)).map((value) => normalize(value)).filter((value) => value.length >= 2));
            const title = (segments.find((value) => value.length >= 4) || normalize(anchor.innerText) || '未命名收藏').slice(0, 120);
            const bodyLines = segments.filter((value) => value !== title);
            const text = bodyLines.join('\\n').slice(0, 1800);
            return {
              title,
              text,
              coverImageURL: imageNode?.src || imageNode?.getAttribute('src') || '',
              author: normalize(authorNode?.innerText || '')
            };
          };
          const tokenMap = buildTokenMap();
          const anchors = Array.from(document.querySelectorAll('a[href]')).filter((anchor) => {
            const href = anchor.getAttribute('href') || '';
            if (!(href.includes('/explore/') || href.includes('/discovery/item/') || href.includes('/user/profile/') || href.includes('xhslink.com'))) {
              return false;
            }
            const style = window.getComputedStyle(anchor);
            if (style.display === 'none' || style.visibility === 'hidden') {
              return false;
            }
            return true;
          });
          const notes = [];
          const seen = new Set();
          for (const anchor of anchors) {
            const rawHref = anchor.getAttribute('href');
            if (!rawHref) continue;
            const href = resolveNoteURL(rawHref, tokenMap);
            if (!(href.includes('/explore/') || href.includes('/discovery/item/') || href.includes('xhslink.com'))) continue;
            const noteId = extractNoteId(href);
            const dedupeKey = noteId || href;
            if (seen.has(dedupeKey)) continue;
            const note = extractNote(anchor);
            if (!note.title) continue;
            seen.add(dedupeKey);
            notes.push({
              url: href,
              title: note.title,
              text: note.text,
              coverImageURL: note.coverImageURL,
              author: note.author
            });
          }
          return JSON.stringify({
            source: 'chrome-direct-sync',
            pageURL: location.href,
            pageTitle: document.title,
            notes
          });
        })()
        """
    }

    private func scrollCollectionScript() -> String {
        """
        (() => {
          const currentY = window.scrollY || document.documentElement.scrollTop || 0;
          const viewport = window.innerHeight || 900;
          const maxY = Math.max(
            document.body.scrollHeight,
            document.documentElement.scrollHeight
          ) - viewport;
          const nextY = Math.min(currentY + Math.max(viewport * 1.6, 1200), maxY);
          window.scrollTo({ top: nextY, behavior: 'auto' });
          return JSON.stringify({
            currentY,
            nextY,
            maxY,
            atEnd: nextY >= maxY - 24
          });
        })()
        """
    }

    private func archive(fileURL: URL, to directory: URL) throws {
        let destinationURL = uniqueDestinationURL(for: fileURL, in: directory)
        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: fileURL, to: destinationURL)
    }

    private func uniqueDestinationURL(for fileURL: URL, in directory: URL) -> URL {
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension
        var candidate = directory.appendingPathComponent(fileURL.lastPathComponent)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = directory.appendingPathComponent("\(baseName)-\(index).\(ext)")
            index += 1
        }
        return candidate
    }
}

private struct ChromeScrollState: Decodable {
    let currentY: Double
    let nextY: Double
    let maxY: Double
    let atEnd: Bool
}
