import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

@Test func theToolGroupHoldsThirteenButtonsInTheBoardsOrder() {
    #expect(EditorToolbarLayout.drawingTools == [.select, .arrow, .line, .shape, .pen, .text, .note, .highlight, .spotlight, .redact, .counter])
    #expect(EditorToolbarLayout.afterDivider == [.crop])
    // Add image is the one button in the group that isn't a tool.
    #expect(EditorToolbarLayout.groupedTools.count + 1 == 13)
}

@Test func everyToolButTheHandHasOneButton() {
    let grouped = EditorToolbarLayout.groupedTools
    #expect(Set(grouped).count == grouped.count)
    #expect(Set(grouped) == Set(EditorTool.allCases).subtracting([.hand]))
}

@Test func everyButtonedToolKeepsItsOwnKey() {
    let keys = EditorToolbarLayout.groupedTools.map(\.key)
    #expect(Set(keys).count == keys.count)
    for tool in EditorToolbarLayout.groupedTools {
        #expect(EditorTool(key: String(tool.key).uppercased()) == tool)
    }
}

@Test func theHandToolSelectsNoButton() {
    #expect(EditorToolbarLayout.selectedButton(for: .hand) == nil)
    #expect(EditorToolbarLayout.selectedButton(for: .crop) == .crop)
    #expect(EditorToolbarLayout.selectedButton(for: .arrow) == .arrow)
}

@Test func theSizeLabelGroupsThousandsForTheLocale() {
    let size = CGSize(width: 1040, height: 600)
    #expect(EditorToolbarLayout.sizeLabel(size, locale: Locale(identifier: "en_US")) == "1,040 × 600")
    #expect(EditorToolbarLayout.sizeLabel(size, locale: Locale(identifier: "de_DE")) == "1.040 × 600")
    #expect(EditorToolbarLayout.sizeLabel(CGSize(width: 99.6, height: 12.2), locale: Locale(identifier: "en_US")) == "100 × 12")
}

@Test func theShareMenuMatchesTheBoard() {
    #expect(EditorShareAction.allCases == [.copyImage, .copyPath, .saveAs, .showInFinder, .pin])
    #expect(EditorShareAction.allCases.filter(\.startsSection) == [.saveAs])
    #expect(EditorShareAction.allCases.compactMap(\.shortcut) == ["⌘C"])
}

@Test func onlyTheActionsThatPointAtTheFileSaveFirst() {
    #expect(EditorShareAction.allCases.filter { $0.savesFirst(isDirty: true) } == [.copyPath, .showInFinder])
    #expect(EditorShareAction.allCases.allSatisfy { !$0.savesFirst(isDirty: false) })
}
