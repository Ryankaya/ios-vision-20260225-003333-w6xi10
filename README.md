# ios-vision-20260225-003333-w6xi10

Minimal SwiftUI iOS sample demonstrating **Vision** text recognition with `VNRecognizeTextRequest`.

## Feature Focus
- Feature: Vision
- Demo behavior:
- Renders an image in memory that contains multiple lines of text.
- Runs `VNRecognizeTextRequest` on that image.
- Displays recognized lines in SwiftUI.
- Includes a button to rerun OCR.

## Apple Documentation Used
- https://developer.apple.com/documentation/vision
- https://developer.apple.com/documentation/vision/vnrecognizetextrequest
- https://developer.apple.com/documentation/vision/vnrecognizedtextobservation

## Run
1. Generate the Xcode project: `xcodegen generate`
2. Open `ios-vision-20260225-003333-w6xi10.xcodeproj` in Xcode.
3. Build and run on an iOS simulator (iOS 17+).
