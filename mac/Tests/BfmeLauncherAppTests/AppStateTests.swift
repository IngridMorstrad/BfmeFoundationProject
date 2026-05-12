import XCTest
@testable import BfmeLauncherApp

final class AppStateTests: XCTestCase {
    func testInitialState() async {
        let state = await AppState()
        let currentTab = await state.currentTab
        let selectedGame = await state.selectedGame
        let popupCount = await state.popupStack.count
        let currentPopup = await state.currentPopup
        let isSyncing = await state.isSyncing

        XCTAssertEqual(currentTab, .offline)
        XCTAssertEqual(selectedGame, .bfme1)
        XCTAssertEqual(popupCount, 0)
        XCTAssertNil(currentPopup)
        XCTAssertFalse(isSyncing)
    }

    func testTabSwitching() async {
        let state = await AppState()
        await state.selectTab(.online)
        let afterOnline = await state.currentTab
        XCTAssertEqual(afterOnline, .online)

        await state.selectTab(.about)
        let afterAbout = await state.currentTab
        XCTAssertEqual(afterAbout, .about)
    }

    func testPopupStackPushPop() async {
        let state = await AppState()
        let a = PopupEntry(kind: "A") { "payload-a" }
        let b = PopupEntry(kind: "B") { "payload-b" }

        _ = await state.present(a)
        let count1 = await state.popupStack.count
        let top1 = await state.currentPopup?.kind
        XCTAssertEqual(count1, 1)
        XCTAssertEqual(top1, "A")

        _ = await state.present(b)
        // Second popup queues behind the first per PopupVisualizer semantics.
        let count2 = await state.popupStack.count
        let top2 = await state.currentPopup?.kind
        XCTAssertEqual(count2, 1)
        XCTAssertEqual(top2, "A")

        await state.dismissTopPopup()
        let count3 = await state.popupStack.count
        let top3 = await state.currentPopup?.kind
        XCTAssertEqual(count3, 1)
        XCTAssertEqual(top3, "B")

        await state.dismissTopPopup()
        let count4 = await state.popupStack.count
        let top4 = await state.currentPopup
        XCTAssertEqual(count4, 0)
        XCTAssertNil(top4)
    }

    func testDismissAllClearsStackAndQueue() async {
        let state = await AppState()
        for i in 0..<3 {
            _ = await state.present(PopupEntry(kind: "P\(i)") { "p\(i)" })
        }
        await state.dismissAllPopups()
        let count = await state.popupStack.count
        let top = await state.currentPopup
        XCTAssertEqual(count, 0)
        XCTAssertNil(top)
    }

    func testSyncGate() async {
        let state = await AppState()
        let initial = await state.isSyncing
        XCTAssertFalse(initial)
        await state.onSyncBegin()
        let afterBegin = await state.isSyncing
        XCTAssertTrue(afterBegin)
        await state.onSyncEnd()
        let afterEnd = await state.isSyncing
        XCTAssertFalse(afterEnd)
    }
}
