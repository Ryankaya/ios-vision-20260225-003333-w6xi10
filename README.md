# ios-vision-20260225-003333-w6xi10

SwiftUI iOS sample demonstrating a practical **Vision OCR** flow using `VNRecognizeTextRequest`.

## Feature Focus
- Feature: Vision
- Demo behavior:
- Lets the user pick a photo from the photo library.
- Runs `VNRecognizeTextRequest` on the selected image.
- Displays recognized text in reading order.
- Provides a "Copy All Text" action for reuse.
- Includes a sample image fallback for quick testing.

## Practical Use Cases
- Scan receipt totals into a notes app.
- Copy text from signs, whiteboards, or printed pages.
- Digitize short paper notes into editable text.

## Apple Documentation Used
- https://developer.apple.com/documentation/vision
- https://developer.apple.com/documentation/vision/vnrecognizetextrequest
- https://developer.apple.com/documentation/vision/vnrecognizedtextobservation

## Run
1. Generate the Xcode project: `xcodegen generate`
2. Open `ios-vision-20260225-003333-w6xi10.xcodeproj` in Xcode.
3. Build and run on an iOS simulator (iOS 17+).
