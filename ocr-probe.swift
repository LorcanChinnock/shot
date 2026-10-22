import CoreGraphics
import CoreML
import CoreText
import Foundation
import Vision

func textImage() -> CGImage {
    let context = CGContext(data: nil, width: 600, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 600, height: 200))
    let font = CTFontCreateWithName("Helvetica" as CFString, 28, nil)
    let string = NSAttributedString(string: "Save changes", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)])
    context.textPosition = CGPoint(x: 40, y: 100)
    CTLineDraw(CTLineCreateWithAttributedString(string), context)
    return context.makeImage()!
}

let image = textImage()
print("devices:", MLComputeDevice.allComputeDevices)

func run(_ name: String, level: RecognizeTextRequest.RecognitionLevel, cpu: Bool) async {
    var request = RecognizeTextRequest()
    request.recognitionLevel = level
    if cpu {
        print("  \(name) stages:", request.supportedComputeStageDevices)
        for (stage, devices) in request.supportedComputeStageDevices {
            if let device = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
                request.setComputeDevice(device, for: stage)
            }
        }
    }
    do {
        let lines = try await request.perform(on: image).compactMap { $0.topCandidates(1).first.map { "\($0.string) \($0.confidence)" } }
        print("PROBE \(name): OK \(lines)")
    } catch {
        print("PROBE \(name): FAIL \(error)")
    }
}

await run("accurate-default", level: .accurate, cpu: false)
await run("accurate-cpu", level: .accurate, cpu: true)
await run("fast-default", level: .fast, cpu: false)
await run("fast-cpu", level: .fast, cpu: true)

let legacy = VNRecognizeTextRequest()
legacy.recognitionLevel = .accurate
do {
    try VNImageRequestHandler(cgImage: image).perform([legacy])
    print("PROBE legacy-accurate: OK \(legacy.results?.compactMap { $0.topCandidates(1).first.map { "\($0.string) \($0.confidence)" } } ?? [])")
} catch {
    print("PROBE legacy-accurate: FAIL \(error)")
}

print("supported revisions:", RecognizeTextRequest.supportedRevisions)
for revision in RecognizeTextRequest.supportedRevisions.sorted(by: { "\($0)" < "\($1)" }) {
    for usesCorrection in [true, false] {
        var request = RecognizeTextRequest(revision)
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = usesCorrection
        do {
            let lines = try await request.perform(on: image).compactMap { $0.topCandidates(1).first.map { "\($0.string) \($0.confidence)" } }
            print("PROBE accurate \(revision) correction=\(usesCorrection): OK \(lines)")
        } catch {
            print("PROBE accurate \(revision) correction=\(usesCorrection): FAIL \(error)")
        }
    }
}
for revision in VNRecognizeTextRequest.supportedRevisions {
    let legacy = VNRecognizeTextRequest()
    legacy.revision = revision
    legacy.recognitionLevel = .accurate
    do {
        try VNImageRequestHandler(cgImage: image).perform([legacy])
        print("PROBE legacy accurate revision \(revision): OK \(legacy.results?.compactMap { $0.topCandidates(1).first.map { "\($0.string) \($0.confidence)" } } ?? [])")
    } catch {
        print("PROBE legacy accurate revision \(revision): FAIL \(error)")
    }
}
