import Foundation

public struct LibraryClassificationService: Sendable {
    private let baseClassifier = ClassificationService()

    public init() {}

    public func classify(
        title: String,
        body: String,
        sourceType: SourceType,
        existingItems: [SavedItem]
    ) -> ClassificationOutput {
        let base = baseClassifier.classify(title: title, body: body, sourceType: sourceType)
        let profiles = categoryProfiles(from: existingItems)
        let tokens = Set(TextProcessing.normalizedTokens([title, body].joined(separator: " ")))
        let keywordScores = baseClassifier.keywordScores(title: title, body: body)
        let titleScores = baseClassifier.titleKeywordScores(title: title)

        if let forcedByTitle = titleScores.max(by: { $0.value < $1.value }),
           forcedByTitle.key != Category.uncategorizedSlug,
           forcedByTitle.value >= 12 {
            return ClassificationOutput(
                summary: base.summary,
                tags: mergeTags(base.tags, with: [title]),
                primaryCategorySlug: forcedByTitle.key,
                secondaryTopics: Array(mergeTags(base.secondaryTopics, with: [title]).prefix(4)),
                reviewState: body.count < 20 ? .needsReview : base.reviewState
            )
        }

        guard !profiles.isEmpty, !tokens.isEmpty else {
            return fallbackFromKeywords(base, keywordScores: keywordScores, tokenCount: tokens.count)
        }

        var scores: [String: Int] = [:]
        for (slug, profile) in profiles {
            let overlapScore = tokens.reduce(into: 0) { partialResult, token in
                partialResult += profile[token] ?? 0
            }
            if overlapScore > 0 {
                scores[slug] = overlapScore
            }
        }

        for (slug, keywordScore) in keywordScores {
            scores[slug, default: 0] += keywordScore * 2
        }

        let baseBoost = base.primaryCategorySlug == Category.uncategorizedSlug ? 0 : 12
        if baseBoost > 0 {
            scores[base.primaryCategorySlug, default: 0] += baseBoost
        }

        guard let best = scores.max(by: { $0.value < $1.value }) else {
            return fallbackFromKeywords(base, keywordScores: keywordScores, tokenCount: tokens.count)
        }

        let topScores = scores.values.sorted(by: >)
        let secondScore = topScores.dropFirst().first ?? 0

        let resolvedCategory: String
        if shouldTrustProfileMatch(
            bestCategory: best.key,
            bestScore: best.value,
            secondScore: secondScore,
            baseCategory: base.primaryCategorySlug,
            tokenCount: tokens.count
        ) {
            resolvedCategory = best.key
        } else {
            resolvedCategory = base.primaryCategorySlug
        }

        let output = ClassificationOutput(
            summary: base.summary,
            tags: mergeTags(base.tags, with: topProfileTags(for: resolvedCategory, profiles: profiles, matching: tokens)),
            primaryCategorySlug: resolvedCategory,
            secondaryTopics: Array(mergeTags(base.secondaryTopics, with: Array(tokens.prefix(4))).prefix(4)),
            reviewState: base.reviewState
        )
        let normalized = normalizeUncertain(
            output,
            bestScore: best.value,
            secondScore: secondScore,
            tokenCount: tokens.count,
            keywordScores: keywordScores
        )
        return rescueUncategorized(
            normalized,
            title: title,
            body: body,
            profiles: profiles,
            keywordScores: keywordScores
        )
    }

    public func reclassify(items: [SavedItem]) -> [SavedItem] {
        items.enumerated().map { index, item in
            guard !item.isCategoryManual else { return item }

            let context = items.enumerated()
                .filter { $0.offset != index }
                .map(\.element)

            let result = classify(
                title: item.title,
                body: [item.fullText, item.summary].joined(separator: "\n"),
                sourceType: item.sourceType,
                existingItems: context
            )

            var updated = item
            updated.primaryCategorySlug = result.primaryCategorySlug
            updated.tags = result.tags
            updated.secondaryTopics = result.secondaryTopics
            if updated.summary.isEmpty || updated.summary == item.title {
                updated.summary = result.summary
            }
            if updated.reviewState != .ready {
                updated.reviewState = result.reviewState
            }
            return updated
        }
    }

    @MainActor
    public func reclassifyProgressively(
        items: [SavedItem],
        progress: ((Int, Int) async -> Void)? = nil,
        gate: (() async throws -> Void)? = nil
    ) async throws -> [SavedItem] {
        var updatedItems: [SavedItem] = []
        updatedItems.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            try await gate?()

            if item.isCategoryManual {
                updatedItems.append(item)
            } else {
                let context = items.enumerated()
                    .filter { $0.offset != index }
                    .map(\.element)

                let result = classify(
                    title: item.title,
                    body: [item.fullText, item.summary].joined(separator: "\n"),
                    sourceType: item.sourceType,
                    existingItems: context
                )

                var updated = item
                updated.primaryCategorySlug = result.primaryCategorySlug
                updated.tags = result.tags
                updated.secondaryTopics = result.secondaryTopics
                if updated.summary.isEmpty || updated.summary == item.title {
                    updated.summary = result.summary
                }
                if updated.reviewState != .ready {
                    updated.reviewState = result.reviewState
                }
                updatedItems.append(updated)
            }

            if let progress {
                await progress(index + 1, items.count)
            }
            if index.isMultiple(of: 20) {
                await Task.yield()
            }
        }

        return updatedItems
    }

    private func categoryProfiles(from items: [SavedItem]) -> [String: [String: Int]] {
        var profiles: [String: [String: Int]] = [:]

        for item in items where item.primaryCategorySlug != Category.uncategorizedSlug {
            let text = [item.title, item.summary, item.fullText, item.tags.joined(separator: " ")]
                .joined(separator: " ")
            let tokens = TextProcessing.normalizedTokens(text)
            for token in tokens {
                profiles[item.primaryCategorySlug, default: [:]][token, default: 0] += item.isCategoryManual ? 3 : 1
            }
        }

        return profiles
    }

    private func topProfileTags(
        for slug: String,
        profiles: [String: [String: Int]],
        matching tokens: Set<String>
    ) -> [String] {
        let profile = profiles[slug] ?? [:]
        let tags = tokens
            .filter { (profile[$0] ?? 0) > 0 }
            .sorted { (profile[$0] ?? 0) > (profile[$1] ?? 0) }
        return Array(tags.prefix(4))
    }

    private func mergeTags(_ lhs: [String], with rhs: [String]) -> [String] {
        let unique = Array(NSOrderedSet(array: lhs + rhs)) as? [String] ?? (lhs + rhs)
        return unique.filter { !$0.isEmpty }
    }

    private func shouldTrustProfileMatch(
        bestCategory: String,
        bestScore: Int,
        secondScore: Int,
        baseCategory: String,
        tokenCount: Int
    ) -> Bool {
        if bestCategory == Category.uncategorizedSlug {
            return false
        }
        if bestScore >= 16 {
            return true
        }
        if bestScore >= 10 && bestScore - secondScore >= 3 {
            return true
        }
        if baseCategory == bestCategory && bestScore >= 7 {
            return true
        }
        if baseCategory != Category.uncategorizedSlug && bestScore >= 6 && tokenCount >= 5 {
            return true
        }
        return false
    }

    private func normalizeUncertain(
        _ output: ClassificationOutput,
        bestScore: Int,
        secondScore: Int,
        tokenCount: Int,
        keywordScores: [String: Int]
    ) -> ClassificationOutput {
        if let keywordBest = keywordScores.max(by: { $0.value < $1.value }),
           keywordBest.key != Category.uncategorizedSlug,
           keywordBest.value >= 2 {
            return ClassificationOutput(
                summary: output.summary,
                tags: output.tags,
                primaryCategorySlug: keywordBest.key,
                secondaryTopics: output.secondaryTopics,
                reviewState: output.reviewState
            )
        }

        let weakSignal = bestScore < 5 || (bestScore - secondScore < 2 && bestScore < 9) || tokenCount < 1
        guard weakSignal else { return output }

        return ClassificationOutput(
            summary: output.summary,
            tags: output.tags,
            primaryCategorySlug: Category.uncategorizedSlug,
            secondaryTopics: output.secondaryTopics,
            reviewState: .needsReview
        )
    }

    private func fallbackFromKeywords(
        _ base: ClassificationOutput,
        keywordScores: [String: Int],
        tokenCount: Int
    ) -> ClassificationOutput {
        if let keywordBest = keywordScores.max(by: { $0.value < $1.value }),
           keywordBest.key != Category.uncategorizedSlug,
           keywordBest.value >= 2 {
            return ClassificationOutput(
                summary: base.summary,
                tags: base.tags,
                primaryCategorySlug: keywordBest.key,
                secondaryTopics: base.secondaryTopics,
                reviewState: tokenCount < 2 ? .needsReview : base.reviewState
            )
        }

        let normalized = normalizeUncertain(base, bestScore: 0, secondScore: 0, tokenCount: tokenCount, keywordScores: keywordScores)
        return rescueUncategorized(normalized, title: "", body: "", profiles: [:], keywordScores: keywordScores)
    }

    private func rescueUncategorized(
        _ output: ClassificationOutput,
        title: String,
        body: String,
        profiles: [String: [String: Int]],
        keywordScores: [String: Int]
    ) -> ClassificationOutput {
        guard output.primaryCategorySlug == Category.uncategorizedSlug else { return output }

        let titleTokens = Set(TextProcessing.normalizedTokens(title))
        let contentTokens = Set(
            TextProcessing.normalizedTokens(
                [title, body, output.tags.joined(separator: " "), output.secondaryTopics.joined(separator: " ")]
                    .joined(separator: " ")
            )
        )

        var rescueScores: [String: Int] = [:]

        for (slug, profile) in profiles where slug != Category.uncategorizedSlug {
            let titleScore = titleTokens.reduce(into: 0) { partialResult, token in
                partialResult += (profile[token] ?? 0) * 4
            }
            let contentScore = contentTokens.reduce(into: 0) { partialResult, token in
                partialResult += (profile[token] ?? 0) * 2
            }
            let keywordScore = (keywordScores[slug] ?? 0) * 3
            let total = titleScore + contentScore + keywordScore
            if total > 0 {
                rescueScores[slug] = total
            }
        }

        guard let best = rescueScores.max(by: { $0.value < $1.value }) else { return output }
        let sortedScores = rescueScores.values.sorted(by: >)
        let secondScore = sortedScores.dropFirst().first ?? 0
        let confident = best.value >= 6 || (best.value >= 4 && best.value - secondScore >= 1)
        guard confident else { return output }

        return ClassificationOutput(
            summary: output.summary,
            tags: output.tags,
            primaryCategorySlug: best.key,
            secondaryTopics: output.secondaryTopics,
            reviewState: .needsReview
        )
    }
}
