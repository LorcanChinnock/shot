import Foundation
import Testing
@testable import ShotCore

private let home = URL(fileURLWithPath: "/Users/sam")

@Test func galleryFolderPathStartsFromTheHomeFolder() {
    #expect(Gallery.folderPath(URL(fileURLWithPath: "/Users/sam/Pictures/Shot"), home: home) == "Pictures/Shot")
    #expect(Gallery.folderPath(URL(fileURLWithPath: "/Users/sam/Pictures/Shot/"), home: URL(fileURLWithPath: "/Users/sam/")) == "Pictures/Shot")
}

@Test func galleryFolderPathIsWholeOutsideTheHomeFolder() {
    #expect(Gallery.folderPath(URL(fileURLWithPath: "/Volumes/Work/Shots"), home: home) == "/Volumes/Work/Shots")
    // A folder whose name only starts with the home folder's isn't inside it.
    #expect(Gallery.folderPath(URL(fileURLWithPath: "/Users/samuel/Shots"), home: home) == "/Users/samuel/Shots")
}

@Test func galleryFolderPathUsesTheNamesFinderShows() {
    let german = ["/Users/sam/Pictures": "Bilder", "/Users/sam": "sam"]
    let path = Gallery.folderPath(URL(fileURLWithPath: "/Users/sam/Pictures/Shot"), home: home) { german[$0] ?? ($0 as NSString).lastPathComponent }
    #expect(path == "Bilder/Shot")
    #expect(Gallery.folderPath(home, home: home) { german[$0] ?? "?" } == "sam")
}

@Test func galleryTrashFanShowsUpToThreeCards() {
    #expect(Gallery.trashFan(count: 0).isEmpty)
    #expect(Gallery.trashFan(count: 1).count == 1)
    #expect(Gallery.trashFan(count: 2) == [-6, 5])
    #expect(Gallery.trashFan(count: 40).count == 3)
}

@Test func keyComboKeycapsListModifiersInMenuOrder() {
    let shot = KeyCombo(keyCode: 21, modifiers: KeyCombo.command | KeyCombo.shift)
    #expect(shot.keycaps == ["⇧", "⌘", "4"])
    let all = KeyCombo(keyCode: 0, modifiers: KeyCombo.command | KeyCombo.shift | KeyCombo.option | KeyCombo.control)
    #expect(all.keycaps == ["⌃", "⌥", "⇧", "⌘", "A"])
    #expect(KeyCombo(keyCode: 122, modifiers: 0).keycaps == ["F1"])
}
