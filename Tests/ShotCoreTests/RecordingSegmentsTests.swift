import Foundation
import Testing
@testable import ShotCore

private func url(_ name: String) -> URL {
    URL(fileURLWithPath: "/tmp/\(name)")
}

private func audio(_ name: String) -> VideoConcatenator.SegmentAudio {
    VideoConcatenator.SegmentAudio(system: url("\(name)-system.mov"), microphone: url("\(name)-microphone.mov"))
}

@Test func segmentsKeepTheirOrder() {
    var segments = RecordingSegments()
    segments.append(url("a.mp4"), audio: nil)
    segments.append(url("b.mp4"), audio: nil)
    #expect(segments.videos == [url("a.mp4"), url("b.mp4")])
}

@Test func audioIsJoinedWhenEverySegmentHasSome() {
    var segments = RecordingSegments()
    segments.append(url("a.mp4"), audio: audio("a"))
    segments.append(url("b.mp4"), audio: audio("b"))
    #expect(segments.joinableAudio.map(\.system) == [url("a-system.mov"), url("b-system.mov")])
}

@Test func audioIsLeftOutWhenASegmentHasNone() {
    var segments = RecordingSegments()
    segments.append(url("a.mp4"), audio: audio("a"))
    segments.append(url("b.mp4"), audio: nil)
    #expect(segments.joinableAudio.isEmpty)
}

@Test func segmentsWithoutAudioJoinNoAudio() {
    var segments = RecordingSegments()
    segments.append(url("a.mp4"), audio: nil)
    #expect(segments.joinableAudio.isEmpty)
}

@Test func removingTheLastSegmentTakesItsAudioToo() {
    var segments = RecordingSegments()
    segments.append(url("a.mp4"), audio: audio("a"))
    segments.append(url("b.mp4"), audio: audio("b"))
    let removed = segments.removeLast()
    #expect(removed?.video == url("b.mp4"))
    #expect(removed?.audio?.microphone == url("b-microphone.mov"))
    #expect(segments.videos == [url("a.mp4")])
    #expect(segments.audio.count == 1)
}

@Test func removingTheLastSegmentLeavesEarlierAudioWhenItHasNone() {
    var segments = RecordingSegments()
    segments.append(url("a.mp4"), audio: audio("a"))
    segments.append(url("b.mp4"), audio: nil)
    let removed = segments.removeLast()
    #expect(removed?.video == url("b.mp4"))
    #expect(removed?.audio == nil)
    #expect(segments.audio.count == 1)
}

@Test func removingFromNoSegmentsReturnsNothing() {
    var segments = RecordingSegments()
    #expect(segments.removeLast() == nil)
}

@Test func aSegmentGetsSeparateAudioFilesOnlyWithTheMicrophoneAndSystemAudioBoth() {
    let folder = URL(fileURLWithPath: "/tmp/segments")
    let both = RecordingSegments.files(in: folder, id: "x", microphone: true, systemAudio: true)
    #expect(both.video == folder.appendingPathComponent("x.mp4"))
    #expect(both.audio?.system == folder.appendingPathComponent("x-system.mov"))
    #expect(both.audio?.microphone == folder.appendingPathComponent("x-microphone.mov"))
    #expect(RecordingSegments.files(in: folder, id: "x", microphone: true, systemAudio: false).audio == nil)
    #expect(RecordingSegments.files(in: folder, id: "x", microphone: false, systemAudio: true).audio == nil)
    #expect(RecordingSegments.files(in: folder, id: "x", microphone: false, systemAudio: false).audio == nil)
}
