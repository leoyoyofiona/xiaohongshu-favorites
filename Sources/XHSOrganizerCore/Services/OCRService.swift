import AppKit
import Foundation
import ImageIO
import Vision

public struct OCRService: Sendable {
    public init() {}

    public func recognizeText(from imageURLs: [URL]) async -> String {
        var segments: [String] = []
        for imageURL in imageURLs {
            if let text = await recognizeText(from: imageURL), !text.isEmpty {
                segments.append(text)
            }
        }
        return segments.joined(separator: "\n\n")
    }

    public func recognizeText(from imageURL: URL) async -> String? {
        guard let cgImage = loadCGImage(from: imageURL) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
