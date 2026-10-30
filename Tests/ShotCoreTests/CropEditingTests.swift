import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let content = CGRect(x: 0, y: 0, width: 200, height: 100)
private let frame = CGRect(x: 10, y: 10, width: 100, height: 50)
private let image = UUID()

@Test func theCropToolGoesBackToTheToolBeforeIt() {
    #expect(CropEditing.toolBefore(taking: .arrow) == .arrow)
    #expect(CropEditing.toolBefore(taking: .select) == .select)
}

@Test func theCropToolTakenFromItselfGoesBackToSelect() {
    #expect(CropEditing.toolBefore(taking: .crop) == .select)
}

@Test func cropStartsOnAnImageThenTheFrameThenAllTheContent() {
    let bounds = CGRect(x: 5, y: 5, width: 20, height: 20)
    #expect(CropEditing.startingDraft(imageBounds: bounds, frameCrop: frame, contentRect: content) == bounds)
    #expect(CropEditing.startingDraft(imageBounds: nil, frameCrop: frame, contentRect: content) == frame)
    #expect(CropEditing.startingDraft(imageBounds: nil, frameCrop: nil, contentRect: content) == content)
}

@Test func anUnchangedFrameCropChangesNothing() {
    #expect(CropEditing.outcome(draft: frame, image: nil, frameCrop: frame, contentRect: content, isFrameCropHidden: false) == .nothing)
    #expect(CropEditing.outcome(draft: content, image: nil, frameCrop: nil, contentRect: content, isFrameCropHidden: false) == .nothing)
}

@Test func aChangedDraftCropsTheFrame() {
    let draft = CGRect(x: 20, y: 20, width: 60, height: 40)
    #expect(CropEditing.outcome(draft: draft, image: nil, frameCrop: frame, contentRect: content, isFrameCropHidden: false) == .cropFrame(draft))
}

@Test func aDraftThatRoundsToTheFrameCropChangesNothing() {
    let draft = CGRect(x: 10.2, y: 10.2, width: 99.6, height: 49.6)
    #expect(draft.integral == frame)
    #expect(CropEditing.outcome(draft: draft, image: nil, frameCrop: frame, contentRect: content, isFrameCropHidden: false) == .nothing)
}

@Test func applyingAHiddenFrameCropBringsItBack() {
    #expect(CropEditing.outcome(draft: frame, image: nil, frameCrop: frame, contentRect: content, isFrameCropHidden: true) == .cropFrame(frame))
}

@Test func aChangedDraftCropsThePlacedImage() {
    let bounds = CGRect(x: 0, y: 0, width: 50, height: 50)
    let draft = CGRect(x: 0, y: 0, width: 25, height: 50)
    #expect(CropEditing.outcome(draft: draft, image: (image, bounds), frameCrop: frame, contentRect: content, isFrameCropHidden: false) == .cropImage(image, draft))
}

@Test func anUnchangedImageDraftChangesNothingEvenWhenTheFrameCropIsHidden() {
    let bounds = CGRect(x: 0, y: 0, width: 50, height: 50)
    #expect(CropEditing.outcome(draft: bounds, image: (image, bounds), frameCrop: frame, contentRect: content, isFrameCropHidden: true) == .nothing)
}

@Test func aCropOfAnImageThatIsGoneChangesNothing() {
    #expect(CropEditing.outcome(draft: frame, image: (image, nil), frameCrop: nil, contentRect: content, isFrameCropHidden: false) == .nothing)
}

@Test func freeLeavesTheDraftAsItIs() {
    #expect(CropEditing.draft(frame, holding: .free) == frame)
}

@Test func aShapeFitsTheLargestCropInsideTheDraft() {
    let fitted = CropEditing.draft(CGRect(x: 0, y: 0, width: 200, height: 100), holding: .square)
    #expect(fitted.width == fitted.height)
    #expect(fitted.height == 100)
    #expect(CGRect(x: 0, y: 0, width: 200, height: 100).contains(fitted))
}

@Test func resetIsOfferedWhileTheDraftIsNotAllOfTheContent() {
    #expect(!CropEditing.canReset(draft: content, fullRect: nil, contentRect: content, hasFrameCrop: true))
    #expect(CropEditing.canReset(draft: frame, fullRect: nil, contentRect: content, hasFrameCrop: false))
}

@Test func withNoDraftResetIsOfferedForAFrameCrop() {
    #expect(CropEditing.canReset(draft: nil, fullRect: nil, contentRect: content, hasFrameCrop: true))
    #expect(!CropEditing.canReset(draft: nil, fullRect: nil, contentRect: content, hasFrameCrop: false))
}

@Test func cropAnImageIsResetAgainstItsWholeRect() {
    let full = CGRect(x: 0, y: 0, width: 50, height: 50)
    #expect(!CropEditing.canReset(draft: full, fullRect: full, contentRect: content, hasFrameCrop: true))
    #expect(CropEditing.canReset(draft: CGRect(x: 0, y: 0, width: 10, height: 10), fullRect: full, contentRect: content, hasFrameCrop: false))
    #expect(!CropEditing.canReset(draft: nil, fullRect: full, contentRect: content, hasFrameCrop: true))
}

@Test func resetPutsBackTheWholeImageElseAllTheContent() {
    let full = CGRect(x: 0, y: 0, width: 50, height: 50)
    #expect(CropEditing.resetDraft(fullRect: full, contentRect: content) == full)
    #expect(CropEditing.resetDraft(fullRect: nil, contentRect: content) == content)
}
