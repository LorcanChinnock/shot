import CoreGraphics
import Foundation
import ImageIO
import ShotCore
import UniformTypeIdentifiers

// Replays scenario folders made by scripts/scroll-lab/frames.cjs through ScrollStitcher, writes the stitched image and
// a picture of where it differs from the truth, and prints one line per scenario.
// Usage: scroll-lab <framesDir> <outDir> [filter]

struct Manifest: Decodable {
    struct Point: Decodable { var x: Double; var y: Double }
    struct Size: Decodable { var width: Double; var height: Double }
    var name: String
    var truth: String
    var dpr: Int
    var view: Size
    var offsets: [Point]
    var pinTop: Double?
    var pinBottom: Double?
    var maxX: Double?
    var maxY: Double?
}

struct Pixels {
    var width: Int, height: Int
    var data: [UInt8] // RGBA, premultiplied last (opaque for frames)
}

func load(_ url: URL) -> Pixels? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return pixels(of: image)
}

func pixels(of image: CGImage) -> Pixels {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    data.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return Pixels(width: w, height: h, data: data)
}

func write(_ p: Pixels, to url: URL, maxSide: Int = 4000) {
    var data = p.data
    let image: CGImage? = data.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: p.width, height: p.height, bitsPerComponent: 8, bytesPerRow: p.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }
    guard let image, let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

struct Score {
    var name: String
    var frames = 0
    var size = ""
    var expected = ""
    var bad = 0.0         // percent of expected pixels that differ a lot
    var worstBand = 0.0   // percent bad in the worst 24px band, rows or columns
    var worstAt = ""
    var unseen = 0.0      // percent of the area that should be painted and is clear
    var extra = 0.0       // percent of the image outside what any frame covered
    var warnings = ""
    var msPerFrame = 0.0
    var ok: Bool { bad < 0.6 && worstBand < 6 && unseen < 0.3 }
}

func run(_ dir: URL, outDir: URL) -> Score? {
    guard let manifestData = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")), let m = try? JSONDecoder().decode(Manifest.self, from: manifestData) else { return nil }
    var score = Score(name: m.name)
    let dpr = m.dpr
    let fw = Int(m.view.width) * dpr, fh = Int(m.view.height) * dpr
    let stitcher = ScrollStitcher(width: fw, height: fh, scale: dpr, byteOrder: .rgba)
    let diag = ProcessInfo.processInfo.environment["DIAG"].map { m.name.contains($0) } ?? false
    stitcher.collectsDiagnostics = diag
    var statuses: [ScrollCaptureStatus: Int] = [:]
    let start = ContinuousClock.now
    for i in 0..<m.offsets.count {
        guard let frame = load(dir.appendingPathComponent(String(format: "f%04d.png", i))) else { continue }
        precondition(frame.width == fw && frame.height == fh, "frame \(i) is \(frame.width)x\(frame.height), not \(fw)x\(fh)")
        let update = frame.data.withUnsafeBytes { raw in
            stitcher.process(ScrollFrame(width: fw, height: fh, bytesPerRow: fw * 4, pixels: raw))
        }
        statuses[update.status, default: 0] += 1
        if ProcessInfo.processInfo.environment["DRIFT"].map({ m.name.contains($0) }) ?? false {
            // Where the stitcher put this frame against where the page really was, in device pixels from the first frame.
            let expected = (m.offsets[i].y - m.offsets[0].y) * Double(dpr), expectedX = (m.offsets[i].x - m.offsets[0].x) * Double(dpr)
            let gotY = Double(update.viewport.minY) - Double(stitcher.viewport.minY) + Double(update.viewport.minY)
            _ = gotY
            print("[\(m.name) f\(i)] expected \(expectedX),\(expected) viewport \(update.viewport.minX),\(update.viewport.minY) status \(update.status)")
        }
        if diag { print("[\(m.name) f\(i) off \(m.offsets[i].x),\(m.offsets[i].y)] \(update.status) \(Int(update.size.width))x\(Int(update.size.height)) \(stitcher.diagnostics)") }
        score.frames += 1
    }
    score.msPerFrame = Double((ContinuousClock.now - start).components.attoseconds / 1_000_000_000_000_000) / Double(max(1, score.frames))
    score.warnings = statuses.filter { $0.key.isWarning || $0.key == .sizeLimit }.map { "\($0.key)×\($0.value)" }.sorted().joined(separator: " ")
    guard let cg = stitcher.image(), let truth = load(URL(fileURLWithPath: m.truth)) else { score.size = "no image"; score.bad = 100; return score }
    let result = pixels(of: cg)
    score.size = "\(result.width)x\(result.height)"
    // The stitched image's top left is the least offset any frame had, in device pixels.
    let minX = Int((m.offsets.map(\.x).min()! * Double(dpr)).rounded()), minY = Int((m.offsets.map(\.y).min()! * Double(dpr)).rounded())
    let maxX = Int((m.offsets.map(\.x).max()! * Double(dpr)).rounded()) + fw, maxY = Int((m.offsets.map(\.y).max()! * Double(dpr)).rounded()) + fh
    let ew = min(maxX, truth.width) - minX, eh = min(maxY, truth.height) - minY
    score.expected = "\(ew)x\(eh)"
    // Which 8px cells any frame covered.
    let cell = 8
    let cw = (ew + cell - 1) / cell, ch = (eh + cell - 1) / cell
    var covered = [Bool](repeating: false, count: cw * ch)
    for o in m.offsets {
        let x0 = max(0, Int((o.x * Double(dpr)).rounded()) - minX), y0 = max(0, Int((o.y * Double(dpr)).rounded()) - minY)
        for cy in (y0 / cell)..<min(ch, (y0 + fh + cell - 1) / cell) { for cx in (x0 / cell)..<min(cw, (x0 + fw + cell - 1) / cell) { covered[cy * cw + cx] = true } }
    }
    // Pinned bands stick to the image's edge, so they only match the truth where the capture reaches the page's edge.
    let ignoreTop = (m.offsets.map(\.y).min()! > 0.5) ? Int((m.pinTop ?? 0) * Double(dpr)) : 0
    let ignoreBottom = (m.offsets.map(\.y).max()! < (m.maxY ?? 0) - 0.5) ? Int((m.pinBottom ?? 0) * Double(dpr)) : 0
    var diff = Pixels(width: result.width, height: result.height, data: [UInt8](repeating: 255, count: result.width * result.height * 4))
    var badCount = 0, total = 0, unseen = 0, extra = 0
    let band = 24
    var rowBad = [Int](repeating: 0, count: (result.height + band - 1) / band), rowTotal = rowBad
    var colBad = [Int](repeating: 0, count: (result.width + band - 1) / band), colTotal = colBad
    for y in 0..<result.height {
        for x in 0..<result.width {
            let ri = (y * result.width + x) * 4
            let inside = x < ew && y < eh
            let tx = minX + x, ty = minY + y
            let isCovered = inside && covered[(y / cell) * cw + (x / cell)]
            if result.data[ri + 3] < 250 {
                if isCovered { unseen += 1; diff.data[ri] = 255; diff.data[ri + 1] = 0; diff.data[ri + 2] = 255 } else { diff.data[ri] = 235; diff.data[ri + 1] = 235; diff.data[ri + 2] = 235 }
                continue
            }
            guard inside, tx < truth.width, ty < truth.height else { extra += 1; diff.data[ri] = 0; diff.data[ri + 1] = 160; diff.data[ri + 2] = 255; continue }
            if y < ignoreTop || y >= result.height - ignoreBottom { diff.data[ri] = 200; diff.data[ri + 1] = 230; diff.data[ri + 2] = 200; continue }
            let ti = (ty * truth.width + tx) * 4
            let d = (abs(Int(result.data[ri]) - Int(truth.data[ti])) + abs(Int(result.data[ri + 1]) - Int(truth.data[ti + 1])) + abs(Int(result.data[ri + 2]) - Int(truth.data[ti + 2]))) / 3
            total += 1; rowTotal[y / band] += 1; colTotal[x / band] += 1
            if d > 48 { badCount += 1; rowBad[y / band] += 1; colBad[x / band] += 1; diff.data[ri] = 255; diff.data[ri + 1] = 40; diff.data[ri + 2] = 40 }
            else { let g = UInt8(255 - min(120, d * 2)); diff.data[ri] = g; diff.data[ri + 1] = g; diff.data[ri + 2] = g }
        }
    }
    // Cells that should be painted but lie outside the image count as unseen too.
    for cy in 0..<ch { for cx in 0..<cw where covered[cy * cw + cx] && (cx * cell >= result.width || cy * cell >= result.height) { unseen += cell * cell } }
    score.bad = total > 0 ? Double(badCount) * 100 / Double(total) : 100
    score.unseen = Double(unseen) * 100 / Double(max(1, ew * eh))
    score.extra = Double(extra) * 100 / Double(max(1, result.width * result.height))
    var worst = 0.0
    for (i, b) in rowBad.enumerated() where rowTotal[i] > 0 { let v = Double(b) * 100 / Double(rowTotal[i]); if v > worst { worst = v; score.worstAt = "y\(i * band)" } }
    for (i, b) in colBad.enumerated() where colTotal[i] > 0 { let v = Double(b) * 100 / Double(colTotal[i]); if v > worst { worst = v; score.worstAt = "x\(i * band)" } }
    score.worstBand = worst
    write(result, to: outDir.appendingPathComponent("\(m.name).result.png"))
    write(diff, to: outDir.appendingPathComponent("\(m.name).diff.png"))
    // CROP=y0,height also writes that slice of the result and the diff side by side, for a close look.
    if let crop = ProcessInfo.processInfo.environment["CROP"]?.split(separator: ",").compactMap({ Int($0) }), crop.count == 2 {
        let y0 = min(crop[0], result.height - 1), h = min(crop[1], result.height - y0)
        var both = Pixels(width: result.width * 2 + 8, height: h, data: [UInt8](repeating: 120, count: (result.width * 2 + 8) * h * 4))
        for y in 0..<h { for x in 0..<result.width {
            let src = ((y0 + y) * result.width + x) * 4
            for (k, img) in [result, diff].enumerated() {
                let dst = (y * both.width + x + k * (result.width + 8)) * 4
                for c in 0..<4 { both.data[dst + c] = img.data[src + c] }
            }
        } }
        write(both, to: outDir.appendingPathComponent("\(m.name).crop.png"))
    }
    return score
}

let args = CommandLine.arguments
// scroll-lab compare <result.png> <truth.png> <diff-out.png>: finds where the result sits in the truth, then scores it.
if args.count == 5, args[1] == "compare" {
    guard let result = load(URL(fileURLWithPath: args[2])), let truth = load(URL(fileURLWithPath: args[3])) else { print("can't load"); exit(1) }
    func sampleDiff(_ y0: Int, rows: Int) -> Double {
        var sum = 0.0, n = 0
        for y in stride(from: 0, to: min(result.height, rows), by: 5) { for x in stride(from: 0, to: min(result.width, truth.width), by: 7) {
            let ri = (y * result.width + x) * 4, ti = ((y0 + y) * truth.width + x) * 4
            sum += Double(abs(Int(result.data[ri]) - Int(truth.data[ti])) + abs(Int(result.data[ri + 1]) - Int(truth.data[ti + 1]))); n += 1
        } }
        return sum / Double(max(1, n))
    }
    var bestY = 0, best = Double.infinity
    // The top of the result is the page's top unless the capture started part way down: search the truth for its first rows.
    for y0 in 0...max(0, truth.height - result.height) { let d = sampleDiff(y0, rows: 120); if d < best { best = d; bestY = y0 } }
    var diff = Pixels(width: result.width, height: result.height, data: [UInt8](repeating: 255, count: result.width * result.height * 4))
    var bad = 0, total = 0
    let band = 24
    var rowBad = [Int](repeating: 0, count: (result.height + band - 1) / band), rowTotal = rowBad
    for y in 0..<(result.height - 24) where bestY + y < truth.height { for x in 0..<min(result.width, truth.width) {
        let ri = (y * result.width + x) * 4, ti = ((bestY + y) * truth.width + x) * 4
        let d = (abs(Int(result.data[ri]) - Int(truth.data[ti])) + abs(Int(result.data[ri + 1]) - Int(truth.data[ti + 1])) + abs(Int(result.data[ri + 2]) - Int(truth.data[ti + 2]))) / 3
        total += 1; rowTotal[y / band] += 1
        if d > 48 { bad += 1; rowBad[y / band] += 1; diff.data[ri] = 255; diff.data[ri + 1] = 40; diff.data[ri + 2] = 40 } else { let g = UInt8(255 - min(120, d * 2)); diff.data[ri] = g; diff.data[ri + 1] = g; diff.data[ri + 2] = g }
    } }
    var worst = 0.0, at = 0
    for (i, b) in rowBad.enumerated() where rowTotal[i] > 0 { let v = Double(b) * 100 / Double(rowTotal[i]); if v > worst { worst = v; at = i * band } }
    write(diff, to: URL(fileURLWithPath: args[4]))
    print("result \(result.width)x\(result.height) at truth y\(bestY) (sample diff \(String(format: "%.2f", best))): bad \(String(format: "%.2f", Double(bad) * 100 / Double(max(1, total))))%, worst band \(String(format: "%.1f", worst))% at y\(at)")
    exit(0)
}
guard args.count >= 3 else { print("usage: scroll-lab <framesDir> <outDir> [filter]"); exit(2) }
let frames = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2]), filter = args.count > 3 ? args[3] : ""
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let names = ((try? FileManager.default.contentsOfDirectory(atPath: frames.path)) ?? []).sorted().filter { !$0.hasSuffix(".png") && (filter.isEmpty || $0.contains(filter)) }
var results = [Score?](repeating: nil, count: names.count)
let lock = NSLock()
DispatchQueue.concurrentPerform(iterations: names.count) { i in
    let s = run(frames.appendingPathComponent(names[i]), outDir: out)
    lock.lock(); results[i] = s; lock.unlock()
}
func f(_ v: Double, _ w: Int = 6) -> String { String(format: "%\(w).2f", v) }
print("scenario".padding(toLength: 22, withPad: " ", startingAt: 0) + " ok  frames  ms/fr   bad%  band%  at      unseen%  extra%  size / expected    warnings")
var failed = 0
for s in results.compactMap({ $0 }) {
    if !s.ok { failed += 1 }
    print(s.name.padding(toLength: 22, withPad: " ", startingAt: 0), s.ok ? "✓ " : "✗ ", String(format: "%5d", s.frames), f(s.msPerFrame, 7), f(s.bad), f(s.worstBand), s.worstAt.padding(toLength: 7, withPad: " ", startingAt: 0), f(s.unseen, 7), f(s.extra, 7), "\(s.size) / \(s.expected)", s.warnings)
}
print("\(results.count - failed)/\(results.count) scenarios pass")
