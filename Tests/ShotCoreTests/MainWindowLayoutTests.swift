import Testing
@testable import ShotCore

@Test func mainWindowSidebarFitsBesideAWidePage() {
    #expect(MainWindowLayout.sidebarFits(windowWidth: 1224, sidebarWidth: 228))
    #expect(MainWindowLayout.sidebarFits(windowWidth: 788, sidebarWidth: 228))
    #expect(!MainWindowLayout.sidebarFits(windowWidth: 787, sidebarWidth: 228))
    #expect(!MainWindowLayout.sidebarFits(windowWidth: 720, sidebarWidth: 228))
}

@Test func mainWindowSidebarFollowsItsButtonWhereItFits() {
    #expect(MainWindowLayout.showsSidebar(windowWidth: 1224, sidebarWidth: 228, wanted: true, revealed: false))
    #expect(!MainWindowLayout.showsSidebar(windowWidth: 1224, sidebarWidth: 228, wanted: false, revealed: true))
}

@Test func mainWindowSidebarHidesInANarrowWindowUntilRevealed() {
    #expect(!MainWindowLayout.showsSidebar(windowWidth: 720, sidebarWidth: 228, wanted: true, revealed: false))
    #expect(MainWindowLayout.showsSidebar(windowWidth: 720, sidebarWidth: 228, wanted: false, revealed: true))
}

@Test func mainWindowNarrowestWidthHidesTheSidebar() {
    #expect(!MainWindowLayout.sidebarFits(windowWidth: MainWindowLayout.minWidth, sidebarWidth: 150))
}
