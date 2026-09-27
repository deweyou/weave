#if os(macOS)
    import Foundation
    import Testing

    @testable import Weave

    @MainActor
    struct MacWorkspaceNavigationTests {
        @Test func traversesPagesAndDocumentsWithoutAddingHistory() {
            let navigation = MacWorkspaceNavigation()
            let noteID = UUID()
            #expect(navigation.canGoBack == false)
            #expect(navigation.canGoForward == false)
            navigation.goBack()
            navigation.goForward()
            #expect(navigation.destination == .home)
            navigation.select(.documents)
            navigation.openNote(noteID)
            navigation.select(.settings)
            navigation.goBack()
            #expect(navigation.destination == .documents)
            #expect(navigation.editorID == noteID)
            navigation.goBack()
            #expect(navigation.editorID == nil)
            navigation.goBack()
            #expect(navigation.destination == .home)
            #expect(navigation.canGoBack == false)
            navigation.goForward()
            navigation.goForward()
            #expect(navigation.editorID == noteID)
            navigation.goForward()
            #expect(navigation.destination == .settings)
            #expect(navigation.canGoForward == false)
        }

        @Test func newDestinationReplacesForwardHistory() {
            let navigation = MacWorkspaceNavigation()
            navigation.select(.documents)
            navigation.select(.settings)
            navigation.goBack()
            navigation.select(.tasks)
            #expect(navigation.canGoForward == false)
            navigation.goForward()
            #expect(navigation.destination == .tasks)
            navigation.goBack()
            #expect(navigation.destination == .documents)
        }

        @Test func revisitingCurrentLocationPreservesHistoryAndWindowsAreIndependent() {
            let navigation = MacWorkspaceNavigation()
            let otherWindow = MacWorkspaceNavigation()
            let noteID = UUID()
            navigation.select(.documents)
            navigation.openNote(noteID)
            navigation.openNote(noteID)
            navigation.goBack()
            #expect(navigation.editorID == nil)
            navigation.select(.documents)
            #expect(navigation.canGoForward)
            navigation.goForward()
            #expect(navigation.editorID == noteID)
            #expect(otherWindow.destination == .home)
            #expect(otherWindow.canGoBack == false)
        }
    }
#endif
