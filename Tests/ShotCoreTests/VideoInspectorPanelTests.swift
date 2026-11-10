import Foundation
import Testing
@testable import ShotCore

@Test func videoSidePanelsTakeTurns() {
    #expect(VideoSidePanel.toggling(.inspector, from: nil) == .inspector)
    #expect(VideoSidePanel.toggling(.inspector, from: .export) == .inspector)
    #expect(VideoSidePanel.toggling(.export, from: .inspector) == .export)
    #expect(VideoSidePanel.toggling(.export, from: .export) == nil)
    #expect(VideoSidePanel.toggling(.inspector, from: .inspector) == nil)
}

@Test func videoInspectorShowsTheFrameWithNothingSelected() {
    #expect(VideoInspectorPanel.sections(selection: nil, hasKeyframes: false, animates: true, canStyle: true) == [.frame])
}

@Test func videoInspectorShowsEveryClipSection() {
    let sections = VideoInspectorPanel.sections(selection: .clip, hasKeyframes: true, animates: true, canStyle: true)
    #expect(sections == [.properties, .keyframes, .animations, .style, .crop])
}

@Test func videoInspectorLeavesOutKeyframesUntilThereAreSome() {
    let sections = VideoInspectorPanel.sections(selection: .clip, hasKeyframes: false, animates: true, canStyle: true)
    #expect(!sections.contains(.keyframes))
}

@Test func videoInspectorGivesAnAnnotationNoCrop() {
    let sections = VideoInspectorPanel.sections(selection: .annotation, hasKeyframes: false, animates: true, canStyle: true)
    #expect(sections == [.properties, .animations, .style])
    let plain = VideoInspectorPanel.sections(selection: .annotation, hasKeyframes: false, animates: false, canStyle: false)
    #expect(plain == [.properties])
}

@Test func videoInspectorGivesASoundOnlyItsVolumeAndKeyframes() {
    #expect(VideoInspectorPanel.sections(selection: .sound, hasKeyframes: false, animates: true, canStyle: true) == [.properties])
    #expect(VideoInspectorPanel.sections(selection: .sound, hasKeyframes: true, animates: true, canStyle: true) == [.properties, .keyframes])
}

@Test func videoInspectorScaleSliderPutsOneTimesInTheMiddle() throws {
    let range = try #require(VideoInspectorPanel.sliderRange(.scale))
    #expect(VideoInspectorPanel.sliderValue(.scale, of: PropertyValues()) == 0)
    #expect(range.lowerBound < 0 && range.upperBound > 0)
    let doubled = VideoInspectorPanel.setting(.scale, slider: 1, in: PropertyValues())
    #expect(doubled.scale == 2)
}

@Test func videoInspectorSlidersRoundTrip() {
    let values = PropertyValues(position: CGSize(width: 10, height: -4), scale: 1.5, rotation: .pi / 4, opacity: 0.5, volume: 1.4, reveal: 0.25)
    for property in AnimatedProperty.allCases where property != .position {
        let slider = VideoInspectorPanel.sliderValue(property, of: values)
        let back = VideoInspectorPanel.setting(property, slider: slider, in: values)
        #expect(abs(VideoInspectorPanel.sliderValue(property, of: back) - slider) < 1e-9, "\(property)")
    }
}

@Test func videoInspectorPositionHasNoSlider() {
    #expect(VideoInspectorPanel.sliderRange(.position) == nil)
    let values = PropertyValues(position: CGSize(width: 3, height: 4))
    #expect(VideoInspectorPanel.setting(.position, slider: 9, in: values) == values)
}

@Test func videoInspectorSliderStaysInItsRange() {
    let wild = PropertyValues(scale: 1000, rotation: 4 * .pi, volume: 9)
    #expect(VideoInspectorPanel.sliderValue(.scale, of: wild) == PropertyValues.scaleDoublings.upperBound)
    #expect(VideoInspectorPanel.sliderValue(.rotation, of: wild) == 180)
    #expect(VideoInspectorPanel.sliderValue(.volume, of: wild) == 2)
}

@Test func videoInspectorLabelsEachValue() {
    let values = PropertyValues(position: CGSize(width: 120.4, height: -40), scale: 1.5, rotation: -.pi / 4, opacity: 0.8, volume: 1.25, reveal: 0)
    #expect(VideoInspectorPanel.label(.position, of: values) == "120, −40")
    #expect(VideoInspectorPanel.label(.scale, of: values) == "1.50×")
    #expect(VideoInspectorPanel.label(.rotation, of: values) == "−45°")
    #expect(VideoInspectorPanel.label(.opacity, of: values) == "80%")
    #expect(VideoInspectorPanel.label(.volume, of: values) == "125%")
    #expect(VideoInspectorPanel.label(.reveal, of: values) == "0%")
}

@Test func videoInspectorLabelNeverReadsMinusZero() {
    let values = PropertyValues(position: CGSize(width: -0.2, height: 0), rotation: -0.001)
    #expect(VideoInspectorPanel.label(.position, of: values) == "0, 0")
    #expect(VideoInspectorPanel.label(.rotation, of: values) == "0°")
}
