import AVFoundation
import os
import ShotCore
import SwiftUI

/// The latest microphone level from 0 to 1, written from a capture queue and read by `LevelMeter`.
final class AudioMeter: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: 0.0)

    var level: Double { state.withLock { $0 } }

    func reset() {
        state.withLock { $0 = 0 }
    }

    /// Peaks show at once and fall back over a few hundred milliseconds, so speech reads as steady.
    func measure(_ sampleBuffer: CMSampleBuffer) {
        guard let rms = Self.rms(of: sampleBuffer) else {
            return
        }
        let level = AudioLevel.meter(rms: rms)
        state.withLock { $0 = max(level, $0 * 0.9) }
    }

    /// Handles the float and integer PCM formats microphones deliver, interleaved or not.
    private static func rms(of sampleBuffer: CMSampleBuffer) -> Float? {
        guard let description = sampleBuffer.formatDescription, sampleBuffer.numSamples > 0 else {
            return nil
        }
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(cmAudioFormatDescription: description), frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList) == noErr else {
            return nil
        }
        // The first channel, or every channel when interleaved.
        let count = Int(frames) * buffer.stride
        if let data = buffer.floatChannelData {
            return AudioLevel.rms(UnsafeBufferPointer(start: data[0], count: count))
        }
        if let data = buffer.int16ChannelData {
            return AudioLevel.rms(UnsafeBufferPointer(start: data[0], count: count).lazy.map { Float($0) / Float(Int16.max) })
        }
        if let data = buffer.int32ChannelData {
            return AudioLevel.rms(UnsafeBufferPointer(start: data[0], count: count).lazy.map { Float($0) / Float(Int32.max) })
        }
        return nil
    }
}

/// A row of bars filled to the meter's level: mint, then yellow, then red near clipping. Grey while `muted`.
struct LevelMeter: View {
    let meter: AudioMeter
    var muted = false
    private static let bars = 8

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { _ in
            let lit = Int((meter.level * Double(Self.bars)).rounded(.up))
            HStack(spacing: 2) {
                ForEach(0..<Self.bars, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .circular)
                        .fill(index < lit ? color(index) : Brutal.well)
                        .inkBorder(RoundedRectangle(cornerRadius: 1.5, style: .circular), width: 1)
                        .frame(width: 5, height: 16)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(muted ? "Microphone level, muted" : "Microphone level"))
    }

    private func color(_ index: Int) -> Color {
        if muted {
            return Brutal.ink.opacity(0.3)
        }
        switch index {
        case ..<5: return Brutal.mint
        case ..<7: return Brutal.yellow
        default: return Brutal.red
        }
    }
}

/// The setup bar's microphone level (Record › Check before recording): ten 5 × 4 pt bars, lit success green and amber for
/// the top two, near clipping, over white at 18%. It only redraws while `active`, so a microphone that's off costs nothing.
struct MicLevelBars: View {
    let meter: AudioMeter
    var active = true
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.textSize) private var textSize

    /// The board's amber, which reads as a warning without taking record red, kept for recording and loss.
    static let loud = Color(hex: 0xFFB648)

    var body: some View {
        let scale = CGFloat(textSize.scale)
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active)) { _ in
            let lit = active ? LevelBars.lit(meter.level) : 0
            HStack(spacing: 2) {
                ForEach(0..<LevelBars.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(color(index, lit: index < lit))
                        .frame(width: (5 * scale).rounded(), height: (4 * scale).rounded())
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ index: Int, lit: Bool) -> Color {
        guard lit else {
            return Color.white.opacity(contrast == .increased ? 0.4 : 0.18)
        }
        return index >= LevelBars.loudFrom ? Self.loud : Brutal.success
    }
}

/// The recording controls' microphone level (Record › While recording): four 3 pt columns rising from 5 to 14 pt, lit
/// success green from the shortest as the level rises, with the tallest amber, near clipping. Unlit columns are white at
/// 25% (40% with Increase Contrast). It only redraws while `active`, so a muted or paused microphone costs nothing.
struct MicLevelColumns: View {
    let meter: AudioMeter
    var active = true
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.textSize) private var textSize

    private static let heights: [CGFloat] = [5, 8, 11, 14]

    var body: some View {
        let scale = CGFloat(textSize.scale)
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active)) { _ in
            let lit = active ? LevelBars.lit(meter.level, of: Self.heights.count) : 0
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Self.heights.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(color(index, lit: index < lit))
                        .frame(width: (3 * scale).rounded(), height: (Self.heights[index] * scale).rounded())
                }
            }
            .frame(height: (14 * scale).rounded(), alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func color(_ index: Int, lit: Bool) -> Color {
        guard lit else {
            return Color.white.opacity(contrast == .increased ? 0.4 : 0.25)
        }
        return index == Self.heights.count - 1 ? MicLevelBars.loud : Brutal.success
    }
}
