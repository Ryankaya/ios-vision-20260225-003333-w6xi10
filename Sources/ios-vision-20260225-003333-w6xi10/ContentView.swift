import SwiftUI
import PhotosUI
import UIKit
import Vision

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Vision OCR Utility")
                        .font(.title2.weight(.semibold))

                    Text("Pick a photo that contains text (receipt, note, sign), extract text, then copy results.")
                        .foregroundStyle(.secondary)

                    Group {
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 180)
                                .overlay(
                                    Text("No image selected")
                                        .foregroundStyle(.secondary)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)

                    PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                        Text("Choose Photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Use Sample Image") {
                        let image = renderSampleImage(text: sampleText)
                        selectedImage = image
                        Task { await runOCR(on: image) }
                    }
                    .buttonStyle(.bordered)

                    Button("Run OCR") {
                        guard let image = selectedImage else { return }
                        Task { await runOCR(on: image) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedImage == nil || isProcessing)

                    if isProcessing {
                        ProgressView("Recognizing text...")
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        Text("Recognized lines")
                            .font(.headline)

                        if recognizedLines.isEmpty {
                            Text("No text recognized yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(recognizedLines.enumerated()), id: \.offset) { _, line in
                                Text("• \(line)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button("Copy All Text") {
                                UIPasteboard.general.string = recognizedLines.joined(separator: "\n")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Vision Demo")
            .task(id: selectedItem) {
                await loadSelectedPhoto()
            }
            .task {
                if selectedImage == nil {
                    let image = renderSampleImage(text: sampleText)
                    selectedImage = image
                    await runOCR(on: image)
                }
            }
        }
    }

    @MainActor
    private func loadSelectedPhoto() async {
        guard let item = selectedItem else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Could not load that photo."
                return
            }
            selectedImage = image
            await runOCR(on: image)
        } catch {
            errorMessage = "Photo load failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func runOCR(on image: UIImage) async {
        isProcessing = true
        errorMessage = nil

        do {
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
                continuation.resume(returning: lines.filter { !$0.isEmpty })
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
