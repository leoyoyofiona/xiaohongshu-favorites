import SwiftUI
import UniformTypeIdentifiers
import XHSOrganizerCore

private enum ImportTab: String, CaseIterable, Identifiable {
    case links
    case text
    case images

    var id: String { rawValue }

    var title: String {
        switch self {
        case .links: "链接"
        case .text: "文本"
        case .images: "截图"
        }
    }
}

struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: ImportTab = .links
    @State private var linkInput = ""
    @State private var textTitle = ""
    @State private var textInput = ""
    @State private var textSourceURL = ""
    @State private var selectedImageURLs: [URL] = []
    @State private var resultSummary: String?
    @State private var isProcessing = false
    @State private var isImportingFiles = false
    @State private var isDropTargeted = false

    let store: LibraryStore
    var onCompleted: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("统一收件箱")
                    .font(.largeTitle.weight(.bold))
                Spacer()
                Button("关闭") { dismiss() }
            }

            Picker("导入类型", selection: $selectedTab) {
                ForEach(ImportTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedTab {
                case .links:
                    linkImportForm
                case .text:
                    textImportForm
                case .images:
                    imageImportForm
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if let resultSummary {
                Text(resultSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("导入") {
                    startImport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || isActionDisabled)
            }
        }
        .padding(28)
        .frame(width: 720, height: 560)
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                selectedImageURLs = urls
            }
        }
    }

    private var linkImportForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("批量粘贴链接，每行一个。")
                .font(.headline)
            TextEditor(text: $linkInput)
                .font(.body.monospaced())
                .macEditorCard()
        }
    }

    private var textImportForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacInputField(placeholder: "标题（可选）", text: $textTitle, systemImage: "textformat")
            MacInputField(placeholder: "来源链接（可选）", text: $textSourceURL, systemImage: "link")
            TextEditor(text: $textInput)
                .font(.body)
                .macEditorCard()
        }
    }

    private var imageImportForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("选择截图") {
                isImportingFiles = true
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 10) {
                Text("拖拽图片到下面区域，或用按钮选择。")
                    .font(.headline)
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.16))
                    .frame(height: 210)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 36))
                            Text(selectedImageURLs.isEmpty ? "把截图拖进来" : "已选 \(selectedImageURLs.count) 张图片")
                                .font(.headline)
                            if !selectedImageURLs.isEmpty {
                                Text(selectedImageURLs.map(\.lastPathComponent).joined(separator: "\n"))
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                        }
                    }
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop)
            }
        }
    }

    private var isActionDisabled: Bool {
        switch selectedTab {
        case .links:
            linkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .text:
            textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .images:
            selectedImageURLs.isEmpty
        }
    }

    private func startImport() {
        isProcessing = true
        resultSummary = "正在解析…"

        Task { @MainActor in
            let pipeline = ImportPipeline(store: store)
            let result: ImportBatchResult
            switch selectedTab {
            case .links:
                result = await pipeline.importLinks(from: linkInput)
                linkInput = ""
            case .text:
                result = await pipeline.importText(
                    title: textTitle.nilIfEmpty,
                    body: textInput,
                    sourceURL: textSourceURL.nilIfEmpty
                )
                textTitle = ""
                textInput = ""
                textSourceURL = ""
            case .images:
                result = await pipeline.importImages(at: selectedImageURLs)
                selectedImageURLs = []
            }

            let message = result.summary
            resultSummary = message
            onCompleted(message)
            isProcessing = false
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task {
            let urls = await loadDroppedURLs(from: providers)
            await MainActor.run {
                selectedImageURLs = urls
            }
        }
        return true
    }

    private func loadDroppedURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadDroppedURL(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    private func loadDroppedURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard
                    let data,
                    let url = URL(dataRepresentation: data, relativeTo: nil),
                    url.conforms(to: .image)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }
}

private extension URL {
    func conforms(to type: UTType) -> Bool {
        guard let inferred = UTType(filenameExtension: pathExtension) else {
            return false
        }
        return inferred.conforms(to: type)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
