import Foundation
import Vision

/// Text recognition with Vision, one image at a time on a background queue.
final class OCRService: @unchecked Sendable {
    static let shared = OCRService()
    private let queue = DispatchQueue(label: "co.il.ckdigital360.snapbar.ocr", qos: .utility)

    /// Recognizes the shot's text in the background and stores it in the index.
    func recognize(shot: Shot) {
        let id = shot.id
        let url = shot.url
        queue.async {
            let start = Date()
            let text = OCRService.recognizeSync(url: url)
            Log.info("ocr done id=\(id.uuidString) chars=\(text.count) ms=\(Log.ms(since: start))")
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ShotStore.shared.setOCR(id, text: text) }
            }
        }
    }

    static func recognizeSync(url: URL) -> String {
        guard let image = ImageTools.loadCGImage(url: url) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let wanted = ["he-IL", "he", "en-US"].filter { supported.contains($0) }
        if !wanted.isEmpty { request.recognitionLanguages = wanted }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    static func supportedLanguages() -> [String] {
        (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
    }
}
