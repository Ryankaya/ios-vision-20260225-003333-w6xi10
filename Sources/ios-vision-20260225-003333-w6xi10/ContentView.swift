import SwiftUI
import UIKit
import Vision

struct ContentView: View {
    @State private var recognizedLines: [String] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private let sampleText = """
    Weekly Unique iOS Repo
    Feature: Vision OCR
    Date: 2026-02-25
    """

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Vision Text Recognition")
                    .font(.title2.weight(.semibold))

                Text("The app renders a sample image in memory and runs `VNRecognizeTextRequest`.")
                    .foregroundStyle(.secondary)

                if isProcessing {
                    ProgressView("Recognizing text...")
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("Recognized lines")
                        .font(.headline)

                    if recognizedLines.isEmpty {
                        Text("No text recognized.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(recognizedLines.enumerated()), id: \.offset) { _, line in
                            Text("• \(line)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                Button("Run OCR Again") {
                    Task { await runOCR() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            }
            .padding()
            .navigationTitle("Vision Demo")
            .task {
                await runOCR()
            }
        }
    }

    @MainActor
    private func runOCR() async {
        isProcessing = true
        errorMessage = nil

        do {
            let image = renderSampleImage(text: sampleText)
            recognizedLines = try await recognizeText(in: image)
        } catch {
            recognizedLines = []
            errorMessage = "Recognition failed: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    private func renderSampleImage(text: String) -> UIImage {
        let bounds = CGRect(x: 0, y: 0, width: 720, height: 300)
        let renderer = UIGraphicsImageRenderer(size: bounds.size)

        return renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(bounds)

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 8
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 38, weight: .semibold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ]
            text.draw(in: bounds.insetBy(dx: 30, dy: 30), withAttributes: attributes)
        }
    }

    private func recognizeText(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "VisionDemo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create image buffer"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // Sort in natural reading order: top-to-bottom, then left-to-right.
                let sorted = observations.sorted { lhs, rhs in
                    let yDiff = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                    if yDiff > 0.02 {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                let lines = sorted.compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
