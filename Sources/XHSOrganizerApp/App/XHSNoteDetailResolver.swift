import AppKit
import Foundation

@MainActor
final class XHSNoteDetailResolver {
    static let shared = XHSNoteDetailResolver()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9,en;q=0.8"
        ]
        self.session = URLSession(configuration: configuration)
    }

    func resolve(url: URL) async throws -> ResolvedNoteContent {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw ResolverError.requestFailed
        }

        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw ResolverError.invalidPayload
        }

        let normalizedHTML = html.replacingOccurrences(of: "\r", with: "")
        let bodyText = stripHTML(normalizedHTML)
        let blocked = bodyText.contains("当前笔记暂时无法浏览")
            || bodyText.contains("请打开小红书App扫码查看")
            || bodyText.contains("访问频繁，请稍后再试")
            || bodyText.contains("安全限制")

        if blocked {
            throw ResolverError.blocked
        }

        let title = extractTitle(from: normalizedHTML)
        let text = extractBody(from: normalizedHTML)
        let images = extractImages(from: normalizedHTML)

        guard (!text.isEmpty && !looksLikeCorruptedText(text)) || !images.isEmpty else {
            throw ResolverError.noContent
        }

        return ResolvedNoteContent(
            title: title,
            text: text,
            images: images,
            blocked: false
        )
    }

    private func extractTitle(from html: String) -> String {
        if let title = firstMatch(in: html, pattern: #"<title>(.*?)</title>"#, options: [.dotMatchesLineSeparators]) {
            return cleanupText(title.replacingOccurrences(of: " - 小红书", with: ""))
        }
        if let title = firstMatch(in: html, pattern: #"id="detail-title"[^>]*>(.*?)</"#, options: [.dotMatchesLineSeparators]) {
            return cleanupText(title)
        }
        return ""
    }

    private func extractBody(from html: String) -> String {
        let fragments = [
            extractDetailDescription(from: html),
            extractJSONField(from: html, key: "desc")
        ]
        let combined = fragments
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: "\n\n")
        return cleanupResolvedBody(combined)
    }

    private func extractDetailDescription(from html: String) -> String? {
        guard let raw = firstMatch(
            in: html,
            pattern: #"id="detail-desc"[^>]*>(.*?)</div>"#,
            options: [.dotMatchesLineSeparators]
        ) else {
            return nil
        }
        return cleanupText(stripHTML(raw))
    }

    private func extractJSONField(from html: String, key: String) -> String? {
        guard let raw = firstMatch(in: html, pattern: #"""# + key + #""\s*:\s*"((?:\\.|[^"])*)""#) else {
            return nil
        }
        return cleanupText(unescapeJSON(raw))
    }

    private func extractImages(from html: String) -> [String] {
        let matches = allMatches(
            in: html,
            pattern: #""imageScene":"WB_DFT","url":"((?:\\.|[^"])*)""#
        ) + allMatches(
            in: html,
            pattern: #""imageScene":"WB_PRV","url":"((?:\\.|[^"])*)""#
        )

        let images = matches
            .map(unescapeJSON)
            .map { $0.replacingOccurrences(of: "http://", with: "https://") }
            .filter { $0.hasPrefix("http") }

        return Array(NSOrderedSet(array: images)) as? [String] ?? images
    }

    private func cleanupResolvedBody(_ text: String) -> String {
        let lines = cleanupText(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let badFragments = [
            "沪ICP备", "营业执照", "网安备案", "增值电信业务经营许可证", "医疗器械网络交易服务第三方平台备案",
            "互联网药品信息服务资格证书", "违法不良信息举报", "互联网举报中心", "网上有害信息举报专区",
            "网络文化经营许可证", "个性化推荐算法", "行吟信息科技", "公司地址", "电话：",
            "广告屏蔽插件", "请移除插件", "我知道了", "问题反馈", "返回首页", "打开小红书App扫码查看"
        ]

        let filtered = lines.filter { line in
            line.count >= 2 && !badFragments.contains(where: { line.contains($0) })
        }

        let unique = Array(NSOrderedSet(array: filtered)) as? [String] ?? filtered
        return unique.joined(separator: "\n")
    }

    private func cleanupText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func unescapeJSON(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: #"\\n"#, with: "\n")
            .replacingOccurrences(of: #"\\r"#, with: "")
            .replacingOccurrences(of: #"\\t"#, with: " ")

        if let data = "\"\(result)\"".data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            result = decoded
        }
        return result
    }

    private func stripHTML(_ html: String) -> String {
        var text = html
        let replacements: [(String, String)] = [
            ("<br\\s*/?>", "\n"),
            ("</p>", "\n"),
            ("</div>", "\n"),
            ("</li>", "\n"),
            ("</h[1-6]>", "\n"),
            ("<!--.*?-->", ""),
            ("<[^>]+>", "")
        ]

        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private func looksLikeCorruptedText(_ text: String) -> Bool {
        let suspiciousFragments = ["锟", "鐨", "閿", "娴", "鈥", "€", "", "", "闁", "顏", "鏂", "涔"]
        let suspiciousCount = suspiciousFragments.reduce(0) { partial, fragment in
            partial + text.components(separatedBy: fragment).count - 1
        }
        let privateUseCount = text.unicodeScalars.filter { scalar in
            (0xE000...0xF8FF).contains(Int(scalar.value))
        }.count
        return suspiciousCount >= 8 || privateUseCount >= 4
    }

    private func firstMatch(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[matchRange])
    }

    private func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[matchRange])
        }
    }
}

private enum ResolverError: LocalizedError {
    case invalidPayload
    case blocked
    case noContent
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "详情页返回的数据不是有效内容"
        case .blocked:
            return "这篇笔记当前无法在网页端直接补抓正文"
        case .noContent:
            return "这篇笔记详情页没有解析出正文"
        case .requestFailed:
            return "请求笔记详情页失败"
        }
    }
}

struct ResolvedNoteContent: Decodable {
    let title: String
    let text: String
    let images: [String]
    let blocked: Bool
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
