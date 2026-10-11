import Foundation
import os
import ShotCore

private let log = Logger.shot("agents")

/// Writes the `.shot.json` an agent reads beside a capture, off the main actor, once the Agents setting is on. A write
/// that fails is logged and never shown: the capture itself is already saved, and nothing may hold up or fail it.
enum SidecarWriter {
    /// Writes `sidecar` next to `capture`. With `original`, a sidecar with no `source` takes the one next to that file, so
    /// a version saved from the editor still says which app and window the capture came from.
    static func write(_ sidecar: CaptureSidecar, for capture: URL, sourceFrom original: URL? = nil) {
        Task.detached {
            var sidecar = sidecar
            if sidecar.source == nil, let original, let data = try? Data(contentsOf: CaptureSidecar.url(for: original)) {
                sidecar.source = (try? CaptureSidecar.decoded(from: data))?.source
            }
            write(sidecar, to: CaptureSidecar.url(for: capture))
        }
    }

    /// Writes the sidecar for a finished recording, once its size has been read from the file.
    static func write(recording url: URL, source: CaptureSidecar.Source?) {
        Task.detached {
            guard let media = try? await MediaProbe.probe(url) else {
                log.error("Could not read \(url.lastPathComponent, privacy: .public) for its .shot.json")
                return
            }
            let size = media.size ?? .zero
            // The region is in points and the file in pixels, so their ratio is the display's scale.
            let scale = source?.screenFrame.map { $0.width > 0 ? (size.width / $0.width * 10).rounded() / 10 : 1 } ?? 1
            let sidecar = CaptureSidecar(
                file: url.lastPathComponent, kind: "video", created: Date(),
                size: CaptureSidecar.Size(width: Int(size.width), height: Int(size.height)), scale: scale, source: source
            )
            write(sidecar, to: CaptureSidecar.url(for: url))
        }
    }

    private static func write(_ sidecar: CaptureSidecar, to url: URL) {
        do {
            try sidecar.encoded().write(to: url, options: .atomic)
        } catch {
            log.error("Could not write \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
