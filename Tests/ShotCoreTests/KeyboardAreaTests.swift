import Foundation
import Testing
@testable import ShotCore

private let screen = CGRect(x: 0, y: 0, width: 800, height: 600)

@Test func aKeyboardAreaStartsCentredOnThePointer() {
    let rect = KeyboardArea.start(at: CGPoint(x: 400, y: 300), ratio: nil, in: screen)
    #expect(rect.midX == 400 && rect.midY == 300)
    #expect(rect.width == 240 && rect.height == 160)
}

@Test func aKeyboardAreaStartingNearAnEdgeStaysOnScreen() {
    let rect = KeyboardArea.start(at: CGPoint(x: 5, y: 595), ratio: nil, in: screen)
    #expect(screen.contains(rect))
}

@Test func aKeyboardAreaStartHonoursTheRatio() {
    let rect = KeyboardArea.start(at: CGPoint(x: 400, y: 300), ratio: 16.0 / 9, in: screen)
    #expect(abs(rect.width / rect.height - 16.0 / 9) < 0.001)
}

@Test func aKeyboardAreaStartFitsADisplaySmallerThanItsDefault() {
    let small = CGRect(x: 0, y: 0, width: 100, height: 50)
    #expect(small.contains(KeyboardArea.start(at: CGPoint(x: 50, y: 25), ratio: nil, in: small)))
}

@Test func nudgingAKeyboardAreaStopsAtTheDisplayEdge() {
    let rect = CGRect(x: 10, y: 10, width: 100, height: 100)
    let moved = KeyboardArea.moved(rect, dx: -50, dy: 700, in: screen)
    #expect(moved.minX == 0)
    #expect(moved.maxY == 600)
    #expect(moved.size == rect.size)
}

@Test func resizingAKeyboardAreaKeepsItsCornerAndStaysOnScreen() {
    let rect = CGRect(x: 700, y: 500, width: 50, height: 50)
    let grown = KeyboardArea.resized(rect, dw: 100, dh: 100, ratio: nil, in: screen)
    #expect(grown.origin == rect.origin)
    #expect(grown.maxX == 800 && grown.maxY == 600)
}

@Test func resizingAKeyboardAreaNeverShrinksItBelowTheMinimum() {
    let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
    let shrunk = KeyboardArea.resized(rect, dw: -100, dh: -100, ratio: nil, in: screen)
    #expect(shrunk.width == KeyboardArea.minimumSide && shrunk.height == KeyboardArea.minimumSide)
}

@Test func resizingAKeyboardAreaWithARatioKeepsTheRatio() {
    let rect = CGRect(x: 0, y: 0, width: 160, height: 90)
    let wider = KeyboardArea.resized(rect, dw: 32, dh: 0, ratio: 16.0 / 9, in: screen)
    #expect(abs(wider.width / wider.height - 16.0 / 9) < 0.001)
    let taller = KeyboardArea.resized(rect, dw: 0, dh: 9, ratio: 16.0 / 9, in: screen)
    #expect(abs(taller.width / taller.height - 16.0 / 9) < 0.001)
    let portrait = CGRect(x: 0, y: 0, width: 90, height: 160)
    let grown = KeyboardArea.resized(portrait, dw: 0, dh: 16, ratio: 16.0 / 9, in: screen)
    #expect(abs(grown.height / grown.width - 16.0 / 9) < 0.001)
}

@Test func steppingInATopLeftSpaceMovesUpOnScreen() {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
    #expect(KeyboardArea.stepped(rect, right: 10, up: 0, resizing: false, ratio: nil, in: bounds) == CGRect(x: 110, y: 100, width: 200, height: 100))
    #expect(KeyboardArea.stepped(rect, right: 0, up: 10, resizing: false, ratio: nil, in: bounds) == CGRect(x: 100, y: 90, width: 200, height: 100))
    #expect(KeyboardArea.stepped(CGRect(x: 0, y: 0, width: 200, height: 100), right: -10, up: 10, resizing: false, ratio: nil, in: bounds).origin == .zero)
}

@Test func resizingInATopLeftSpaceKeepsTheBottomEdge() {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
    let taller = KeyboardArea.stepped(rect, right: 0, up: 10, resizing: true, ratio: nil, in: bounds)
    #expect(taller == CGRect(x: 100, y: 90, width: 200, height: 110))
    let wider = KeyboardArea.stepped(rect, right: 10, up: 0, resizing: true, ratio: nil, in: bounds)
    #expect(wider == CGRect(x: 100, y: 100, width: 210, height: 100))
}

@Test func resizingKeepsAPortraitRatioGivenEitherWay() {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let portrait = CGRect(x: 100, y: 100, width: 90, height: 160)
    for ratio: CGFloat in [16.0 / 9, 9.0 / 16] {
        let grown = KeyboardArea.stepped(portrait, right: 0, up: 16, resizing: true, ratio: ratio, in: bounds)
        #expect(abs(grown.width / grown.height - 9.0 / 16) < 0.001)
        #expect(grown.maxY == portrait.maxY)
    }
}

