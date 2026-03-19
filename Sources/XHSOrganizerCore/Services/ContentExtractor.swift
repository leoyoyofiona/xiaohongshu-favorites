import Foundation

public struct ExtractedContent: Sendable {
    public var title: String
    public var summary: String
    public var fullText: String
    public var imageURLs: [String]
    public var canonicalKey: String
    public var sourceApp: String
    public var sourceURL: String
    public var collectedAt: Date?

    public init(
        title: String,
        summary: String,
        fullText: String,
        imageURLs: [String],
        canonicalKey: String,
        sourceApp: String,
        sourceURL: String,
        collectedAt: Date? = nil
    ) {
        self.title = title
        self.summary = summary
        self.fullText = fullText
        self.imageURLs = imageURLs
        self.canonicalKey = canonicalKey
        self.sourceApp = sourceApp
        self.sourceURL = sourceURL
        self.collectedAt = collectedAt
    }
}

public enum ContentExtractionError: LocalizedError {
    case invalidResponse
    case emptyContent

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "链接无法访问或返回异常响应"
        case .emptyContent: "链接内容为空，无法提取正文"
        }
    }
}

public struct ContentExtractor: Sendable {
    public init() {}

    public func extract(from url: URL) async throws -> ExtractedContent {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<400 ~= httpResponse.statusCode else {
            throw ContentExtractionError.invalidResponse
        }

        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let cleanedHTML = html.replacingOccurrences(of: "\u{0000}", with: "")

        let title = firstNonEmpty([
            content(ofMetaProperty: "og:title", in: cleanedHTML),
            content(ofMetaName: "twitter:title", in: cleanedHTML),
            content(ofMetaName: "description", in: cleanedHTML),
            content(ofTag: "title", in: cleanedHTML)
        ]) ?? url.lastPathComponent

        let summary = firstNonEmpty([
            content(ofMetaProperty: "og:description", in: cleanedHTML),
            content(ofMetaName: "description", in: cleanedHTML),
            content(ofMetaName: "twitter:description", in: cleanedHTML)
        ]) ?? ""

        let bodyText = visibleText(from: cleanedHTML)
        guard !bodyText.isEmpty || !summary.isEmpty else {
            throw ContentExtractionError.emptyContent
        }

        let imageURLs = extractImageURLs(from: cleanedHTML)
        let normalizedURL = normalize(url: url).absoluteString
        let sourceApp = sourceAppName(for: url)

        return ExtractedContent(
            title: title.decodedHTMLEntities(),
            summary: TextProcessing.firstSentences(from: summary.isEmpty ? bodyText : summary, maxLength: 220),
            fullText: bodyText.isEmpty ? summary : bodyText,
            imageURLs: imageURLs,
            canonicalKey: TextProcessing.canonicalKey(from: normalizedURL),
            sourceApp: sourceApp,
            sourceURL: normalizedURL,
            collectedAt: nil
        )
    }

    private func normalize(url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        if let queryItems = components.queryItems, !queryItems.isEmpty {
            let filtered = queryItems.filter { !$0.name.lowercased().hasPrefix("utm_") }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        return components.url ?? url
    }

    private func sourceAppName(for url: URL) -> String {
        let host = url.host()?.lowercased() ?? ""
        if host.contains("xiaohongshu") || host.contains("xhslink") || host.contains("xhs.cn") {
            return "小红书"
        }
        return host.isEmpty ? "网页" : host
    }

    private func content(ofMetaProperty property: String, in html: String) -> String? {
        captureFirst(
            in: html,
            patterns: [
                "<meta[^>]*property=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>",
                "<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*property=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"'][^>]*>"
            ]
        )
    }

    private func content(ofMetaName name: String, in html: String) -> String? {
        captureFirst(
            in: html,
            patterns: [
                "<meta[^>]*name=[\"']\(NSRegularExpression.escapedPattern(for: name))[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>",
                "<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*name=[\"']\(NSRegularExpression.escapedPattern(for: name))[\"'][^>]*>"
            ]
        )
    }

    private func content(ofTag tag: String, in html: String) -> String? {
        captureFirst(in: html, patterns: ["<\(tag)[^>]*>(.*?)</\(tag)>"])
    }

    private func visibleText(from html: String) -> String {
        var value = html
        let patterns = [
            "<script[\\s\\S]*?</script>",
            "<style[\\s\\S]*?</style>",
            "<noscript[\\s\\S]*?</noscript>",
            "<svg[\\s\\S]*?</svg>",
            "<[^>]+>"
        ]
        for pattern in patterns {
            value = value.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        value = value.decodedHTMLEntities()
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractImageURLs(from html: String) -> [String] {
        let patterns = [
            "<meta[^>]*property=[\"']og:image[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>",
            "<img[^>]*src=[\"']([^\"']+)[\"'][^>]*>"
        ]
        var matches: [String] = []
        for pattern in patterns {
            matches.append(contentsOf: captureAll(in: html, pattern: pattern))
        }
        let filtered = matches.filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
        return Array(NSOrderedSet(array: filtered)) as? [String] ?? filtered
    }

    private func firstNonEmpty(_ candidates: [String?]) -> String? {
        candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func captureFirst(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let match = captureAll(in: text, pattern: pattern).first {
                return match
            }
        }
        return nil
    }

    private func captureAll(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private extension String {
    func decodedHTMLEntities() -> String {
        guard let data = data(using: .utf8) else { return self }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return (try? NSAttributedString(data: data, options: options, documentAttributes: nil).string) ?? self
    }
}
