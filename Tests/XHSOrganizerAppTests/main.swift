import Foundation
import XHSOrganizerCore

@main
struct XHSOrganizerCoreCheck {
    static func main() {
        do {
            try classificationRecognizesPaperCategory()
            try searchMatchesSemanticPaperQuery()
            try searchFiltersBySourceType()
            print("XHSOrganizerCoreCheck passed")
        } catch {
            fputs("XHSOrganizerCoreCheck failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func classificationRecognizesPaperCategory() throws {
        let service = ClassificationService()
        let output = service.classify(
            title: "论文写作框架",
            body: "整理了文献综述、开题报告、投稿修改和答辩准备的方法。",
            sourceType: .text
        )

        try expect(output.primaryCategorySlug == "paper", "分类没有命中 paper")
        try expect(output.tags.contains { $0.localizedCaseInsensitiveContains("论文") || $0.localizedCaseInsensitiveContains("写作") }, "标签没有覆盖论文写作")
    }

    private static func searchMatchesSemanticPaperQuery() throws {
        let service = SearchService()
        let items = [
            SavedItem(
                canonicalKey: "paper-1",
                title: "学术写作流程",
                summary: "从文献综述到开题报告的整理方法",
                fullText: "论文研究常见流程包括选题、文献、开题、写作和答辩。",
                tags: ["学术", "写作"],
                primaryCategorySlug: "paper",
                reviewState: .ready,
                sourceType: .link
            ),
            SavedItem(
                canonicalKey: "travel-1",
                title: "京都旅行攻略",
                summary: "酒店和机票清单",
                fullText: "自由行路线和城市漫步建议。",
                tags: ["旅行"],
                primaryCategorySlug: "travel",
                reviewState: .ready,
                sourceType: .link
            )
        ]

        let hits = service.search(items: items, query: SearchQuery(text: "论文写作", sortMode: .relevance))
        try expect(hits.first?.item.canonicalKey == "paper-1", "论文查询没有把学术写作排在第一")
    }

    private static func searchFiltersBySourceType() throws {
        let service = SearchService()
        let items = [
            SavedItem(
                canonicalKey: "img-1",
                title: "AI 论文截图",
                summary: "OCR 摘要",
                fullText: "论文截图识别内容",
                tags: ["论文"],
                primaryCategorySlug: "paper",
                reviewState: .pending,
                sourceType: .image
            ),
            SavedItem(
                canonicalKey: "txt-1",
                title: "课程笔记",
                summary: "学习总结",
                fullText: "教育课程整理",
                tags: ["教育"],
                primaryCategorySlug: "education",
                reviewState: .ready,
                sourceType: .text
            )
        ]

        let hits = service.search(
            items: items,
            query: SearchQuery(text: "", sourceFilters: [.image], sortMode: .latest)
        )
        try expect(hits.count == 1 && hits.first?.item.canonicalKey == "img-1", "来源筛选没有只保留图片")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw VerificationError(message: message)
        }
    }
}

private struct VerificationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
