import SwiftUI
import PhotosUI
import UIKit
import Vision

private enum ScanMode: String, CaseIterable, Identifiable {
    case quick = "Quick"
    case receipt = "Receipt"
    case card = "Card"
    case notes = "Notes"

    var id: String { rawValue }
}

private struct ReceiptSummary {
    let merchant: String?
    let date: String?
    let subtotal: String?
    let tax: String?
    let total: String?

    var hasAnyValue: Bool {
        merchant != nil || date != nil || subtotal != nil || tax != nil || total != nil
    }

    var formattedSummary: String {
        [
            "Receipt Summary",
            "Merchant: \(merchant ?? "Not found")",
            "Date: \(date ?? "Not found")",
            "Subtotal: \(subtotal ?? "Not found")",
            "Tax: \(tax ?? "Not found")",
            "Total: \(total ?? "Not found")"
        ].joined(separator: "\n")
    }
}

private struct DetectedDetails {
    let emails: [String]
    let phones: [String]
    let links: [String]
    let addresses: [String]
    let dates: [String]
    let times: [String]
    let amounts: [String]
    let cardNumbers: [String]
    let cardIssuers: [String]
    let cardExpiryDates: [String]
    let securityCodes: [String]
    let receiptIDs: [String]
    let paymentMethods: [String]

    var hasAnyValue: Bool {
        !emails.isEmpty
            || !phones.isEmpty
            || !links.isEmpty
            || !addresses.isEmpty
            || !dates.isEmpty
            || !times.isEmpty
            || !amounts.isEmpty
            || !cardNumbers.isEmpty
            || !cardIssuers.isEmpty
            || !cardExpiryDates.isEmpty
            || !securityCodes.isEmpty
            || !receiptIDs.isEmpty
            || !paymentMethods.isEmpty
    }
}

private enum DetailKind {
    case email
    case phone
    case link
    case address
    case date
    case time
    case amount
    case cardNumber
    case text
}

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var recognizedLines: [String] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var copiedMessage = ""
    @State private var showsCopyBanner = false
    @State private var isShowingCamera = false
    @State private var isShowingImageViewer = false
    @State private var showCameraUnavailableAlert = false
    @State private var scanMode: ScanMode = .quick

    private var sampleTextForCurrentMode: String {
        switch scanMode {
        case .quick:
            return """
            Weekly Unique iOS Repo
            Feature: Vision OCR
            Date: 2026-02-25
            """
        case .receipt:
            return """
            Corner Market
            02/24/2026
            Subtotal $18.40
            Tax $1.47
            Total $19.87
            """
        case .card:
            return """
            Cardholder: Jane Doe
            Card Number: 4111 1111 1111 1111
            Exp: 08/29
            CVV: 123
            """
        case .notes:
            return """
            Sprint Notes
            - finalize OCR flow by Friday
            - verify camera permissions on device
            - prepare v1 launch checklist
            """
        }
    }

    private var recognizedText: String {
        recognizedLines.joined(separator: "\n")
    }

    private var receiptSummary: ReceiptSummary? {
        guard scanMode == .receipt, !recognizedLines.isEmpty else { return nil }
        return extractReceiptSummary(from: recognizedLines)
    }

    private var detectedDetails: DetectedDetails {
        extractDetectedDetails(from: recognizedLines)
    }

    private var outputText: String {
        if scanMode == .receipt,
           let receiptSummary,
           receiptSummary.hasAnyValue {
            return "\(receiptSummary.formattedSummary)\n\nRaw OCR:\n\(recognizedText)"
        }
        return recognizedText
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [Color.blue.opacity(0.14), Color.teal.opacity(0.10), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        headerArea
                        modeArea
                        previewArea
                        actionArea
                        statusArea
                        resultsArea
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("SnapScan")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: selectedItem) {
                await loadSelectedPhoto()
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraCaptureView { image in
                    isShowingCamera = false
                    selectedImage = image
                    Task { await runOCR(on: image) }
                } onCancel: {
                    isShowingCamera = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isShowingImageViewer) {
                if let selectedImage {
                    ZoomablePhotoSheet(image: selectedImage)
                }
            }
            .alert("Camera Not Available", isPresented: $showCameraUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Use Choose Photo on this device.")
            }
            .task {
                if selectedImage == nil {
                    let image = renderSampleImage(text: sampleTextForCurrentMode)
                    selectedImage = image
                    await runOCR(on: image)
                }
            }
            .overlay(alignment: .bottom) {
                if showsCopyBanner {
                    Text(copiedMessage)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.85), in: Capsule())
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var headerArea: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Scan text in seconds")
                    .font(.subheadline.weight(.semibold))
                Text("Camera OCR with quick copy/share")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .appCard()
    }

    private var modeArea: some View {
        Picker("Mode", selection: $scanMode) {
            ForEach(ScanMode.allCases) { mode in
                Text(mode.rawValue)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .appCard()
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

    private var previewArea: some View {
        VStack {
            if let image = selectedImage {
                Button {
                    isShowingImageViewer = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Label("Zoom", systemImage: "plus.magnifyingglass")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 200)
                    .overlay(
                        Text("No image")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .appCard()
    }

    private var actionArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                    Label("Choose", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openCamera()
                } label: {
                    Label("Camera", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            }

            HStack(spacing: 10) {
                Button {
                    let image = renderSampleImage(text: sampleTextForCurrentMode)
                    selectedImage = image
                    Task { await runOCR(on: image) }
                } label: {
                    Label("Sample", systemImage: "doc.text.image")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    guard let image = selectedImage else { return }
                    Task { await runOCR(on: image) }
                } label: {
                    Label("Rescan", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(selectedImage == nil || isProcessing)
            }
        }
        .appCard()
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCameraUnavailableAlert = true
            return
        }
        isShowingCamera = true
    }

    @ViewBuilder
    private var statusArea: some View {
        if isProcessing {
            HStack(spacing: 10) {
                ProgressView()
                Text("Scanning...")
                    .font(.subheadline)
                Spacer()
            }
            .appCard()
        } else if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .font(.subheadline)
                .appCard()
        }
    }

    private var resultsArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Results")
                    .font(.headline)
                Spacer()
                if !recognizedLines.isEmpty {
                    Text("\(recognizedLines.count) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if recognizedLines.isEmpty {
                Text("Scan a photo to begin.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                if scanMode == .receipt {
                    receiptSummaryArea
                }

                if detectedDetails.hasAnyValue {
                    categorizedDetailsArea
                }

                Text("Text")
                    .font(.subheadline.weight(.semibold))
                Text("Long press a line for Copy or Share.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                rawLinesArea
                outputActionsArea
            }
        }
        .appCard()
    }

    @ViewBuilder
    private var receiptSummaryArea: some View {
        if let receiptSummary, receiptSummary.hasAnyValue {
            VStack(alignment: .leading, spacing: 8) {
                Text("Receipt")
                    .font(.subheadline.weight(.semibold))
                receiptFieldRow(title: "Merchant", value: receiptSummary.merchant)
                receiptFieldRow(title: "Date", value: receiptSummary.date)
                receiptFieldRow(title: "Subtotal", value: receiptSummary.subtotal)
                receiptFieldRow(title: "Tax", value: receiptSummary.tax)
                receiptFieldRow(title: "Total", value: receiptSummary.total)

                Button {
                    UIPasteboard.general.string = receiptSummary.formattedSummary
                    showCopyBanner(message: "Summary copied")
                } label: {
                    Label("Copy Summary", systemImage: "doc.plaintext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
    }

    private func receiptFieldRow(title: String, value: String?) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "Not found")
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var categorizedDetailsArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detected Details")
                .font(.subheadline.weight(.semibold))

            switch scanMode {
            case .card:
                detailGroup(title: "Card Numbers", values: detectedDetails.cardNumbers, kind: .cardNumber)
                detailGroup(title: "Card Issuers", values: detectedDetails.cardIssuers, kind: .text)
                detailGroup(title: "Expiry Dates", values: detectedDetails.cardExpiryDates, kind: .date)
                detailGroup(title: "Security Codes", values: detectedDetails.securityCodes, kind: .text)
                detailGroup(title: "Emails", values: detectedDetails.emails, kind: .email)
                detailGroup(title: "Phones", values: detectedDetails.phones, kind: .phone)
            case .receipt:
                detailGroup(title: "Receipt IDs", values: detectedDetails.receiptIDs, kind: .text)
                detailGroup(title: "Payment Methods", values: detectedDetails.paymentMethods, kind: .text)
                detailGroup(title: "Dates", values: detectedDetails.dates, kind: .date)
                detailGroup(title: "Times", values: detectedDetails.times, kind: .time)
                detailGroup(title: "Amounts", values: detectedDetails.amounts, kind: .amount)
                detailGroup(title: "Addresses", values: detectedDetails.addresses, kind: .address)
            case .quick, .notes:
                detailGroup(title: "Emails", values: detectedDetails.emails, kind: .email)
                detailGroup(title: "Phones", values: detectedDetails.phones, kind: .phone)
                detailGroup(title: "Links", values: detectedDetails.links, kind: .link)
                detailGroup(title: "Addresses", values: detectedDetails.addresses, kind: .address)
                detailGroup(title: "Dates", values: detectedDetails.dates, kind: .date)
                detailGroup(title: "Times", values: detectedDetails.times, kind: .time)
                detailGroup(title: "Amounts", values: detectedDetails.amounts, kind: .amount)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    @ViewBuilder
    private func detailGroup(title: String, values: [String], kind: DetailKind) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(values, id: \.self) { value in
                    detailRow(value: value, kind: kind)
                }
            }
        }
    }

    private func detailRow(value: String, kind: DetailKind) -> some View {
        HStack {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(kind == .link || kind == .address ? .blue : .primary)
            Spacer()
            if kind == .link || kind == .address {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if kind == .link || kind == .address {
                runPrimaryAction(for: value, kind: kind)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = value
                showCopyBanner(message: "Copied")
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            ShareLink(item: value) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            if let label = actionLabel(for: kind) {
                Button {
                    runPrimaryAction(for: value, kind: kind)
                } label: {
                    Label(label.title, systemImage: label.icon)
                }
            }
        }
    }

    private var rawLinesArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(recognizedLines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                    Text(line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = line
                        showCopyBanner(message: "Line copied")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    ShareLink(item: line) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    if let link = firstLink(in: line) {
                        Button {
                            openWebLink(link)
                        } label: {
                            Label("Open Link", systemImage: "link")
                        }
                    }

                    if let email = firstEmail(in: line) {
                        Button {
                            openEmail(email)
                        } label: {
                            Label("Send Email", systemImage: "envelope")
                        }
                    }

                    if let phone = firstPhone(in: line) {
                        Button {
                            callPhone(phone)
                        } label: {
                            Label("Call", systemImage: "phone")
                        }
                    }

                    if let address = firstAddress(in: line) {
                        Button {
                            openDirections(to: address)
                        } label: {
                            Label("Directions", systemImage: "map")
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
        }
    }

    private var outputActionsArea: some View {
        HStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = outputText
                showCopyBanner(message: "Copied")
            } label: {
                Label("Copy", systemImage: "doc.on.doc.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            ShareLink(item: outputText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func actionLabel(for kind: DetailKind) -> (title: String, icon: String)? {
        switch kind {
        case .email:
            return ("Send Email", "envelope")
        case .phone:
            return ("Call", "phone")
        case .link:
            return ("Open Link", "link")
        case .address:
            return ("Directions", "map")
        case .date, .time, .amount, .cardNumber, .text:
            return nil
        }
    }

    private func runPrimaryAction(for value: String, kind: DetailKind) {
        switch kind {
        case .email:
            openEmail(value)
        case .phone:
            callPhone(value)
        case .link:
            openWebLink(value)
        case .address:
            openDirections(to: value)
        case .date, .time, .amount, .cardNumber, .text:
            break
        }
    }

    private func openWebLink(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            openURL(url)
            return
        }
        if let url = URL(string: "https://\(trimmed)") {
            openURL(url)
        }
    }

    private func openEmail(_ rawEmail: String) {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:\(encoded)") else {
            return
        }
        openURL(url)
    }

    private func callPhone(_ rawPhone: String) {
        let digits = rawPhone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard !digits.isEmpty,
              let url = URL(string: "tel://\(digits)") else {
            return
        }
        openURL(url)
    }

    private func openDirections(to rawAddress: String) {
        let address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty,
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?daddr=\(encoded)") else {
            return
        }
        openURL(url)
    }

    private static let addressDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.address.rawValue
    )
    private static let lineDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
    )

    private static let detailsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func extractDetectedDetails(from lines: [String]) -> DetectedDetails {
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else {
            return DetectedDetails(
                emails: [],
                phones: [],
                links: [],
                addresses: [],
                dates: [],
                times: [],
                amounts: [],
                cardNumbers: [],
                cardIssuers: [],
                cardExpiryDates: [],
                securityCodes: [],
                receiptIDs: [],
                paymentMethods: []
            )
        }

        var emails: [String] = []
        var phones: [String] = []
        var links: [String] = []
        var addresses: [String] = []
        var dates: [String] = []
        var times: [String] = []
        var amounts: [String] = []
        var cardNumbers: [String] = []
        var cardIssuers: [String] = []
        var cardExpiryDates: [String] = []
        var securityCodes: [String] = []
        var receiptIDs: [String] = []
        var paymentMethods: [String] = []

        var emailSeen = Set<String>()
        var phoneSeen = Set<String>()
        var linkSeen = Set<String>()
        var addressSeen = Set<String>()
        var dateSeen = Set<String>()
        var timeSeen = Set<String>()
        var amountSeen = Set<String>()
        var cardNumberSeen = Set<String>()
        var issuerSeen = Set<String>()
        var expirySeen = Set<String>()
        var securityCodeSeen = Set<String>()
        var receiptIDSeen = Set<String>()
        var paymentSeen = Set<String>()

        func appendUnique(_ value: String, to values: inout [String], seen: inout Set<String>) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            if seen.insert(normalized).inserted {
                values.append(normalized)
            }
        }

        for email in matches(
            of: #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            in: text
        ) {
            appendUnique(email, to: &emails, seen: &emailSeen)
        }

        for amount in matches(
            of: #"(?:[$€£]\s?)?\d{1,3}(?:,\d{3})*(?:\.\d{2})|(?:USD|EUR|GBP)\s?\d+(?:\.\d{2})|\b\d+\.\d{2}\b"#,
            in: text
        ) {
            appendUnique(amount.replacingOccurrences(of: " ", with: ""), to: &amounts, seen: &amountSeen)
        }

        for time in matches(
            of: #"\b\d{1,2}:\d{2}(?:\s?[APap][Mm])?\b"#,
            in: text
        ) {
            appendUnique(time, to: &times, seen: &timeSeen)
        }

        for expiry in matches(
            of: #"\b(0?[1-9]|1[0-2])\s*[/\-]\s*(\d{2}|\d{4})\b"#,
            in: text
        ) {
            appendUnique(normalizeExpiry(expiry), to: &cardExpiryDates, seen: &expirySeen)
        }

        for number in extractCardNumberCandidates(from: text) {
            appendUnique(number, to: &cardNumbers, seen: &cardNumberSeen)
            let digitsOnly = number.filter(\.isNumber)
            if let issuer = cardIssuer(for: digitsOnly) {
                appendUnique(issuer, to: &cardIssuers, seen: &issuerSeen)
            }
        }

        for code in extractSecurityCodes(from: text) {
            appendUnique(code, to: &securityCodes, seen: &securityCodeSeen)
        }

        for receiptID in extractReceiptIDs(from: text) {
            appendUnique(receiptID, to: &receiptIDs, seen: &receiptIDSeen)
        }

        for method in extractPaymentMethods(from: lines, hasCardNumber: !cardNumbers.isEmpty) {
            appendUnique(method, to: &paymentMethods, seen: &paymentSeen)
        }

        let detectorTypes = NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.date.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue

        if let detector = try? NSDataDetector(types: detectorTypes) {
            let range = NSRange(text.startIndex..., in: text)
            detector.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
                guard let result else { return }

                switch result.resultType {
                case .link:
                    guard let url = result.url else { return }
                    if url.scheme?.lowercased() == "mailto" {
                        let email = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
                        appendUnique(email, to: &emails, seen: &emailSeen)
                    } else {
                        appendUnique(url.absoluteString, to: &links, seen: &linkSeen)
                    }
                case .phoneNumber:
                    guard let phoneNumber = result.phoneNumber else { return }
                    appendUnique(phoneNumber, to: &phones, seen: &phoneSeen)
                case .date:
                    guard let date = result.date else { return }
                    appendUnique(Self.detailsDateFormatter.string(from: date), to: &dates, seen: &dateSeen)
                case .address:
                    if let address = formatAddress(from: result) {
                        appendUnique(address, to: &addresses, seen: &addressSeen)
                    }
                default:
                    break
                }
            }
        }

        return DetectedDetails(
            emails: emails,
            phones: phones,
            links: links,
            addresses: addresses,
            dates: dates,
            times: times,
            amounts: amounts,
            cardNumbers: cardNumbers,
            cardIssuers: cardIssuers,
            cardExpiryDates: cardExpiryDates,
            securityCodes: securityCodes,
            receiptIDs: receiptIDs,
            paymentMethods: paymentMethods
        )
    }

    private func matches(
        of pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { result in
            guard let matchRange = Range(result.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private func extractCardNumberCandidates(from text: String) -> [String] {
        let rawCandidates = matches(
            of: #"(?:[0-9OoQqDIlL|!SsBbGg][ -]?){13,24}"#,
            in: text
        )
        var formattedNumbers: [String] = []
        var seen = Set<String>()

        for raw in rawCandidates {
            let digits = normalizeOCRDigits(raw)
            guard (13...19).contains(digits.count) else { continue }
            guard isValidCardNumber(digits) else { continue }
            guard seen.insert(digits).inserted else { continue }
            formattedNumbers.append(formatCardNumber(digits))
        }

        return formattedNumbers
    }

    private func isValidCardNumber(_ digits: String) -> Bool {
        let reversed = digits.reversed().compactMap { $0.wholeNumberValue }
        guard reversed.count == digits.count else { return false }

        let checksum = reversed.enumerated().reduce(0) { partial, item in
            let (index, digit) = item
            if index % 2 == 1 {
                let doubled = digit * 2
                return partial + (doubled > 9 ? doubled - 9 : doubled)
            }
            return partial + digit
        }
        return checksum % 10 == 0
    }

    private func formatCardNumber(_ digits: String) -> String {
        if digits.count == 15 {
            // Typical AMEX grouping: 4-6-5
            let first = digits.prefix(4)
            let second = digits.dropFirst(4).prefix(6)
            let third = digits.suffix(5)
            return "\(first) \(second) \(third)"
        }

        var groups: [String] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 4, limitedBy: digits.endIndex) ?? digits.endIndex
            groups.append(String(digits[index..<next]))
            index = next
        }
        return groups.joined(separator: " ")
    }

    private func cardIssuer(for digits: String) -> String? {
        if digits.hasPrefix("4") {
            return "Visa"
        }

        if let firstTwo = Int(digits.prefix(2)),
           (51...55).contains(firstTwo) {
            return "Mastercard"
        }

        if let firstFour = Int(digits.prefix(4)),
           (2221...2720).contains(firstFour) {
            return "Mastercard"
        }

        if digits.hasPrefix("34") || digits.hasPrefix("37") {
            return "American Express"
        }

        if digits.hasPrefix("6011") || digits.hasPrefix("65") {
            return "Discover"
        }

        if let firstThree = Int(digits.prefix(3)),
           (644...649).contains(firstThree) {
            return "Discover"
        }

        return nil
    }

    private func extractSecurityCodes(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(?:cvv2?|cvc2?|cid|security(?:\s*code)?|sec(?:urity)?\s*code)\b[\s:#-]*([0-9OoQqDIlL|!SsBbGg]{3,4})\b"#
        ) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let matchRange = Range(result.range(at: 1), in: text) else { return nil }
            let normalized = normalizeOCRDigits(String(text[matchRange]))
            guard (3...4).contains(normalized.count) else { return nil }
            return normalized
        }
    }

    private func extractReceiptIDs(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(?:receipt|invoice|order|transaction|trans|ref(?:erence)?)\s*(?:no\.?|number|#|id)?\s*[:#-]?\s*([A-Z0-9][A-Z0-9\-\/]{2,})\b"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let matchRange = Range(result.range(at: 1), in: text) else { return nil }
            return String(text[matchRange]).uppercased()
        }
    }

    private func extractPaymentMethods(from lines: [String], hasCardNumber: Bool) -> [String] {
        let methods: [(keyword: String, label: String)] = [
            ("cash", "Cash"),
            ("visa", "Visa"),
            ("mastercard", "Mastercard"),
            ("master card", "Mastercard"),
            ("amex", "American Express"),
            ("american express", "American Express"),
            ("discover", "Discover"),
            ("debit", "Debit"),
            ("credit", "Credit"),
            ("tap to pay", "Tap to Pay"),
            ("contactless", "Contactless"),
            ("apple pay", "Apple Pay"),
            ("google pay", "Google Pay"),
            ("paypal", "PayPal")
        ]

        var found: [String] = []
        var seen = Set<String>()
        let joined = lines.joined(separator: "\n").lowercased()
        for method in methods where joined.contains(method.keyword) {
            if seen.insert(method.label).inserted {
                found.append(method.label)
            }
        }
        if hasCardNumber && !found.contains(where: { ["Visa", "Mastercard", "American Express", "Discover", "Debit", "Credit"].contains($0) }) {
            found.append("Card")
        }
        return found
    }

    private func normalizeOCRDigits(_ value: String) -> String {
        var digits = ""
        for char in value {
            switch char {
            case "0"..."9":
                digits.append(char)
            case "O", "o", "Q", "q", "D":
                digits.append("0")
            case "I", "l", "L", "|", "!":
                digits.append("1")
            case "S", "s":
                digits.append("5")
            case "B", "b":
                digits.append("8")
            case "G", "g":
                digits.append("6")
            default:
                continue
            }
        }
        return digits
    }

    private func normalizeExpiry(_ raw: String) -> String {
        let compact = raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "/")
        let parts = compact.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return compact }
        let month = parts[0].count == 1 ? "0\(parts[0])" : parts[0]
        return "\(month)/\(parts[1])"
    }

    private func firstEmail(in text: String) -> String? {
        matches(of: #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: text).first
    }

    private func firstLink(in text: String) -> String? {
        guard let detector = Self.lineDetector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        for match in matches where match.resultType == .link {
            guard let url = match.url else { continue }
            if url.scheme?.lowercased() != "mailto" {
                return url.absoluteString
            }
        }
        return nil
    }

    private func firstPhone(in text: String) -> String? {
        guard let detector = Self.lineDetector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.first(where: { $0.resultType == .phoneNumber })?.phoneNumber
    }

    private func firstAddress(in text: String) -> String? {
        guard let detector = Self.addressDetector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        for match in matches where match.resultType == .address {
            if let address = formatAddress(from: match) {
                return address
            }
        }
        return nil
    }

    private func formatAddress(from match: NSTextCheckingResult) -> String? {
        guard let components = match.addressComponents else { return nil }
        let order: [NSTextCheckingKey] = [.name, .organization, .street, .city, .state, .zip, .country]
        var parts: [String] = []
        for key in order {
            guard let value = components[key] else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }
        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }
        return nil
    }

    private func extractReceiptSummary(from lines: [String]) -> ReceiptSummary {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let merchant = detectMerchant(in: cleaned)
        let date = cleaned.compactMap(extractDate).first
        let subtotal = amountForKeywords(in: cleaned, keywords: ["subtotal", "sub total"])
        let tax = amountForKeywords(in: cleaned, keywords: ["tax", "vat", "gst"])
        let total = amountForKeywords(
            in: cleaned,
            keywords: ["grand total", "amount due", "balance due", "total"],
            excluding: ["subtotal", "sub total", "tax", "vat", "gst"]
        ) ?? cleaned.reversed().compactMap(extractLastAmount).first

        return ReceiptSummary(
            merchant: merchant,
            date: date,
            subtotal: subtotal,
            tax: tax,
            total: total
        )
    }

    private func detectMerchant(in lines: [String]) -> String? {
        let blockedKeywords = [
            "total", "subtotal", "sub total", "tax", "vat", "gst",
            "amount", "balance", "cash", "change", "visa", "mastercard",
            "receipt", "invoice", "date", "time"
        ]

        if let candidate = lines.first(where: { line in
            hasLetters(line) &&
            !containsAnyKeyword(line, keywords: blockedKeywords) &&
            extractDate(from: line) == nil &&
            extractLastAmount(from: line) == nil
        }) {
            return candidate
        }

        return lines.first(where: hasLetters)
    }

    private func amountForKeywords(in lines: [String], keywords: [String], excluding: [String] = []) -> String? {
        for line in lines.reversed() {
            guard containsAnyKeyword(line, keywords: keywords) else { continue }
            if !excluding.isEmpty && containsAnyKeyword(line, keywords: excluding) { continue }
            if let amount = extractLastAmount(from: line) {
                return amount
            }
        }
        return nil
    }

    private func containsAnyKeyword(_ line: String, keywords: [String]) -> Bool {
        let lowered = line.lowercased()
        return keywords.contains(where: { lowered.contains($0) })
    }

    private func hasLetters(_ value: String) -> Bool {
        value.range(of: "[A-Za-z]", options: .regularExpression) != nil
    }

    private func extractDate(from line: String) -> String? {
        let patterns: [(String, NSRegularExpression.Options)] = [
            (#"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#, []),
            (#"\b\d{4}[/-]\d{1,2}[/-]\d{1,2}\b"#, []),
            (#"\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2},?\s+\d{4}\b"#, [.caseInsensitive])
        ]

        for (pattern, options) in patterns {
            if let match = firstMatch(of: pattern, in: line, options: options) {
                return match
            }
        }

        return nil
    }

    private func extractLastAmount(from line: String) -> String? {
        let pattern = #"(?:[$€£]\s?)?\d{1,3}(?:,\d{3})*(?:\.\d{2})|(?:[$€£]\s?)?\d+(?:\.\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, options: [], range: range)
        guard let last = matches.last,
              let matchRange = Range(last.range, in: line) else {
            return nil
        }
        return String(line[matchRange]).replacingOccurrences(of: " ", with: "")
    }

    private func firstMatch(
        of pattern: String,
        in line: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let matchRange = Range(match.range, in: line) else {
            return nil
        }
        return String(line[matchRange])
    }

    private func showCopyBanner(message: String) {
        copiedMessage = message
        withAnimation(.easeOut(duration: 0.2)) {
            showsCopyBanner = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    showsCopyBanner = false
                }
            }
        }
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
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
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
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct AppCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private extension View {
    func appCard() -> some View {
        modifier(AppCardModifier())
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

private struct ZoomablePhotoSheet: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var zoomScale: CGFloat = 1
    @State private var baseZoomScale: CGFloat = 1
    @State private var contentOffset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoomScale)
                .offset(contentOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomScale = min(max(baseZoomScale * value, 1), 6)
                        }
                        .onEnded { _ in
                            baseZoomScale = zoomScale
                            if zoomScale == 1 {
                                contentOffset = .zero
                                baseOffset = .zero
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard zoomScale > 1 else { return }
                            contentOffset = CGSize(
                                width: baseOffset.width + value.translation.width,
                                height: baseOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            if zoomScale > 1 {
                                baseOffset = contentOffset
                            } else {
                                contentOffset = .zero
                                baseOffset = .zero
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if zoomScale > 1 {
                            zoomScale = 1
                            baseZoomScale = 1
                            contentOffset = .zero
                            baseOffset = .zero
                        } else {
                            zoomScale = 2
                            baseZoomScale = 2
                        }
                    }
                }

            VStack {
                HStack(spacing: 14) {
                    Button {
                        zoomOut()
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.title3.weight(.semibold))
                    }

                    Button {
                        zoomIn()
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.title3.weight(.semibold))
                    }

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(.top, 10)
                .padding(.horizontal, 16)

                Spacer()
            }
        }
    }

    private func zoomIn() {
        let next = min(zoomScale + 0.5, 6)
        zoomScale = next
        baseZoomScale = next
    }

    private func zoomOut() {
        let next = max(zoomScale - 0.5, 1)
        zoomScale = next
        baseZoomScale = next
        if next == 1 {
            contentOffset = .zero
            baseOffset = .zero
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            } else {
                parent.onCancel()
            }
        }
    }
}
