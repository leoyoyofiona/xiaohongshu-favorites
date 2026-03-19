import AppKit
import SwiftUI

struct RemoteAssetImage: View {
    let asset: String?
    let placeholderSystemImage: String

    @StateObject private var loader = RemoteAssetLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.secondary.opacity(0.08))

            if let image = localImage ?? loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSystemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: asset) {
            guard localImage == nil else { return }
            await loader.load(asset: asset)
        }
    }

    private var localImage: NSImage? {
        guard let asset, !asset.hasPrefix("http") else { return nil }
        return NSImage(contentsOfFile: asset)
    }
}

@MainActor
private final class RemoteAssetLoader: ObservableObject {
    @Published var image: NSImage?

    func load(asset: String?) async {
        image = nil

        guard let asset,
              asset.hasPrefix("http"),
              let url = URL(string: asset)
        else {
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10

        do {
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<400 ~= httpResponse.statusCode else {
                return
            }
            image = NSImage(data: data)
        } catch {
            image = nil
        }
    }
}
