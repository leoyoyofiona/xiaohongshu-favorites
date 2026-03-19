import Foundation

public struct ClassificationOutput: Sendable {
    public var summary: String
    public var tags: [String]
    public var primaryCategorySlug: String
    public var secondaryTopics: [String]
    public var reviewState: ReviewState

    public init(
        summary: String,
        tags: [String],
        primaryCategorySlug: String,
        secondaryTopics: [String],
        reviewState: ReviewState
    ) {
        self.summary = summary
        self.tags = tags
        self.primaryCategorySlug = primaryCategorySlug
        self.secondaryTopics = secondaryTopics
        self.reviewState = reviewState
    }
}

public struct ClassificationService: Sendable {
    public static let categoryKeywords: [String: [String]] = [
        "education": ["教育", "学习", "课程", "备考", "雅思", "托福", "留学", "老师", "教案", "培训", "申请", "简历", "面试", "英语", "学校", "上岸", "教学", "小学数学", "数理化", "竞赛", "听力", "单词", "课堂", "教师", "课题", "五线谱", "数学", "物理", "化学"],
        "paper": ["论文", "开题", "文献", "学术", "research", "paper", "写作", "投稿", "答辩", "引用", "sci", "文献综述", "研究方法", "选题", "学报", "知网", "科研", "量化", "结构方程模型", "偏最小二乘", "实证", "理论基础", "归纳", "演绎", "问卷", "量表", "信度", "文本分析", "知识图谱", "中介效应", "统计学", "概率分布", "回归"],
        "travel": ["旅行", "攻略", "酒店", "机票", "景点", "出行", "自由行", "签证", "citywalk", "路线", "民宿", "航班", "打卡"],
        "business": ["商业", "副业", "创业", "运营", "营销", "变现", "品牌", "生意", "管理", "选品", "流量", "投放", "私域", "复盘", "自媒体", "生产力", "转行", "红利"],
        "tools": ["工具", "效率", "模板", "notion", "obsidian", "excel", "自动化", "workflow", "app", "软件", "插件", "表格", "清单", "网站", "神器", "下载", "随机点名", "绘图", "宝藏网站", "苹果备忘录", "chrome", "iwatch", "apple watch", "番茄钟", "电脑支架", "垂直标签页"],
        "technology": ["编程", "代码", "swift", "python", "ai", "算法", "开发", "技术", "数据库", "前端", "后端", "接口", "脚本", "工程化", "提示词", "开源爬虫", "vpn", "翻墙", "外网", "人工智能", "led", "智能眼镜"],
        "design": ["设计", "排版", "海报", "ui", "figma", "配色", "字体", "视觉", "版式", "灵感", "插画", "品牌设计", "手工", "绘图", "诗词"],
        "lifestyle": ["生活", "居家", "收纳", "穿搭", "护肤", "健身", "习惯", "效率生活", "饮食", "通勤", "日常", "vlog", "搞笑", "宿舍", "新年祝福语", "朋友圈", "物欲", "午休", "喂", "美剧", "震撼", "睡魔", "喉咙", "病毒"]
    ]

    public static let titlePhrases: [String: [String]] = [
        "education": ["留学申请", "语言备考", "托福备考", "雅思备考", "面试技巧", "简历修改", "申请材料", "学习方法", "课程推荐", "上岸经验", "课堂互动", "教学模式", "化学竞赛", "听力速记", "背完3500词", "国际证书", "五行", "数理化", "五线谱"],
        "paper": ["论文写作", "文献综述", "开题报告", "选题思路", "研究方法", "答辩技巧", "投稿经验", "论文润色", "论文降重", "学术写作", "研究现状", "结构方程模型", "偏最小二乘法", "拒稿率极低", "知网", "实证研究框架", "中介效应模型", "李克特量表", "文本分析", "统计学基础框架", "人工智能素养问卷"],
        "travel": ["旅行攻略", "citywalk路线", "酒店推荐", "自由行攻略", "签证攻略", "机票攻略", "民宿推荐", "周末出游", "旅游路线"],
        "business": ["副业运营", "创业项目", "品牌营销", "变现路径", "私域运营", "流量增长", "选品思路", "商业模式", "复盘方法", "新质生产力", "要不要转行"],
        "tools": ["notion模板", "obsidian模板", "效率工具", "自动化工作流", "excel模板", "app推荐", "插件推荐", "软件清单", "工具合集", "宝藏网站", "随机点名", "下载全球视频", "绘图网站", "冷门网站", "苹果备忘录", "chrome浏览器", "垂直标签页", "番茄钟"],
        "technology": ["python教程", "swift开发", "ai工具", "编程入门", "代码实现", "接口调试", "脚本自动化", "前端开发", "后端开发", "苏格拉底提示词", "开源爬虫", "翻墙上外网", "vpn翻墙", "智能眼镜"],
        "design": ["ui设计", "排版灵感", "figma教程", "配色方案", "字体搭配", "海报设计", "版式设计", "视觉设计", "品牌设计", "手工回形针"],
        "lifestyle": ["穿搭分享", "护肤流程", "健身计划", "收纳技巧", "居家布置", "日常vlog", "饮食记录", "生活习惯", "宿舍搞笑", "新年祝福语", "看完后物欲没了", "睡魔的搏斗"]
    ]

    public init() {}

    public func classify(title: String, body: String, sourceType: SourceType) -> ClassificationOutput {
        let fullText = [title, body].joined(separator: "\n")
        let normalized = TextProcessing.normalizedText(fullText)
        let category = bestCategory(for: normalized, title: title, body: body)
        let tags = suggestedTags(from: fullText, category: category)
        let summary = TextProcessing.firstSentences(from: body.isEmpty ? title : body, maxLength: 180)

        let needsReview = body.count < 40 || category == Category.uncategorizedSlug || sourceType == .image && body.count < 80

        return ClassificationOutput(
            summary: summary.isEmpty ? title : summary,
            tags: tags,
            primaryCategorySlug: category,
            secondaryTopics: Array(tags.prefix(3)),
            reviewState: needsReview ? .needsReview : .pending
        )
    }

    public func keywordScores(title: String, body: String) -> [String: Int] {
        let fullText = [title, body].joined(separator: "\n")
        let normalized = TextProcessing.normalizedText(fullText)
        var scores = keywordScores(for: normalized, title: title, body: body)
        for (slug, phraseScore) in titlePhraseScores(title: title) {
            scores[slug, default: 0] += phraseScore
        }
        return scores
    }

    private func bestCategory(for text: String, title: String, body: String) -> String {
        let titleOnlyScores = titleKeywordScores(title: title)
        if let strongTitleCategory = preferredCategory(from: titleOnlyScores, minimumScore: 8, minimumLead: 3) {
            return strongTitleCategory
        }

        var bestSlug = Category.uncategorizedSlug
        var bestScore = 0

        for (slug, score) in keywordScores(for: text, title: title, body: body) {
            if score > bestScore {
                bestScore = score
                bestSlug = slug
            }
        }

        return bestSlug
    }

    public func titleKeywordScores(title: String) -> [String: Int] {
        var scores: [String: Int] = [:]
        let normalizedTitle = TextProcessing.normalizedText(title)

        for (slug, keywords) in Self.categoryKeywords {
            let score = keywords.reduce(into: 0) { partialResult, keyword in
                let normalizedKeyword = keyword.lowercased()
                partialResult += (normalizedTitle.components(separatedBy: normalizedKeyword).count - 1) * 8
            }
            if score > 0 {
                scores[slug, default: 0] += score
            }
        }

        for (slug, phraseScore) in titlePhraseScores(title: title) {
            scores[slug, default: 0] += phraseScore
        }

        return scores
    }

    private func keywordScores(for normalizedText: String, title: String, body: String) -> [String: Int] {
        let normalizedTitle = TextProcessing.normalizedText(title)
        let normalizedBody = TextProcessing.normalizedText(body)
        var scores: [String: Int] = [:]

        for (slug, keywords) in Self.categoryKeywords {
            let score = keywords.reduce(into: 0) { partialResult, keyword in
                let normalizedKeyword = keyword.lowercased()
                partialResult += (normalizedTitle.components(separatedBy: normalizedKeyword).count - 1) * 8
                partialResult += (normalizedBody.components(separatedBy: normalizedKeyword).count - 1) * 2
                partialResult += normalizedText.components(separatedBy: normalizedKeyword).count - 1
            }
            if score > 0 {
                scores[slug] = score
            }
        }

        return scores
    }

    public func titlePhraseScores(title: String) -> [String: Int] {
        let normalizedTitle = TextProcessing.normalizedText(title)
        var scores: [String: Int] = [:]

        for (slug, phrases) in Self.titlePhrases {
            let score = phrases.reduce(into: 0) { partialResult, phrase in
                let normalizedPhrase = phrase.lowercased()
                partialResult += (normalizedTitle.components(separatedBy: normalizedPhrase).count - 1) * 20
            }
            if score > 0 {
                scores[slug] = score
            }
        }

        return scores
    }

    private func preferredCategory(from scores: [String: Int], minimumScore: Int, minimumLead: Int) -> String? {
        let ranked = scores.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }
        guard let first = ranked.first, first.value >= minimumScore else {
            return nil
        }
        let second = ranked.dropFirst().first?.value ?? 0
        guard first.value - second >= minimumLead else {
            return nil
        }
        return first.key
    }

    private func suggestedTags(from text: String, category: String) -> [String] {
        var tags: [String] = []
        if let categoryTerms = Self.categoryKeywords[category] {
            for keyword in categoryTerms where text.localizedCaseInsensitiveContains(keyword) {
                tags.append(keyword)
            }
        }

        let tokens = TextProcessing.normalizedTokens(text)
        let fallback = tokens
            .filter { !$0.allSatisfy(\.isNumber) }
            .prefix(6)
            .map { $0.capitalized }
        tags.append(contentsOf: fallback)

        let unique = Array(NSOrderedSet(array: tags)) as? [String] ?? tags
        return Array(unique.prefix(8))
    }
}
