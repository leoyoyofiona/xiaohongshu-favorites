import Foundation

public enum TextProcessing {
    public static func normalizedText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public static func normalizedTokens(_ text: String) -> [String] {
        let normalized = normalizedText(text)
        let pattern = #"[a-z0-9]{2,}|[\p{Han}]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        let chunks: [String] = regex.matches(in: normalized, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: normalized) else { return nil }
            return String(normalized[matchRange])
        }
        return Array(NSOrderedSet(array: chunks)) as? [String] ?? chunks
    }

    public static func firstSentences(from text: String, maxLength: Int = 180) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxLength else { return cleaned }

        let delimiters = CharacterSet(charactersIn: "。！？.!?\n")
        let segments = cleaned.components(separatedBy: delimiters).filter { !$0.isEmpty }
        var buffer = ""
        for segment in segments {
            let candidate = buffer.isEmpty ? segment : "\(buffer)。\(segment)"
            if candidate.count > maxLength {
                break
            }
            buffer = candidate
        }
        if !buffer.isEmpty {
            return buffer
        }
        return String(cleaned.prefix(maxLength)) + "…"
    }

    public static func canonicalKey(from raw: String) -> String {
        if let url = URL(string: raw),
           let host = url.host()?.lowercased(),
           (host.contains("xiaohongshu.com") || host.contains("xhslink.com") || host.contains("xhs.cn")) {
            let path = url.path.lowercased()
            if path.contains("/explore/") || path.contains("/discovery/item/") {
                let segments = url.pathComponents.filter { $0 != "/" }
                if let noteID = segments.last, !noteID.isEmpty {
                    return "xhs-note:\(noteID.lowercased())"
                }
            }
        }

        let normalized = normalizedText(raw)
        if normalized.isEmpty {
            return UUID().uuidString.lowercased()
        }
        return String(normalized.prefix(240))
    }
}
