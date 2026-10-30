import Foundation
import UIKit
import Vision

/// 截图里的取件码识别。
///
/// 用 Vision 而不是自己拼 OCR：中文识别质量足够，而且是系统框架，
/// 不增加包体积，也不用担心第三方 SDK 的隐私合规问题。
enum TextRecognizer {

    enum Failure: LocalizedError {
        case badImage
        case noText

        var errorDescription: String? {
            switch self {
            case .badImage: return "这张图片读不出来，换一张试试"
            case .noText: return "图片里没找到文字"
            }
        }
    }

    static func recognize(image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw Failure.badImage }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let text = observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")

                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.resume(throwing: Failure.noText)
                    } else {
                        continuation.resume(returning: text)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
