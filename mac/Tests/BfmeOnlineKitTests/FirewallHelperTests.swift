import XCTest
@testable import BfmeOnlineKit

final class FirewallHelperTests: XCTestCase {
    func testAddFirewallRuleRecordsTheWouldBeNetshCommand() {
        FirewallHelper.lastLoggedMessage = nil
        FirewallHelper.addFirewallRule(
            name: "BFME Arena",
            program: "/Applications/BfmeFoundationProject_OnlineArena.exe"
        )
        let msg = FirewallHelper.lastLoggedMessage ?? ""
        XCTAssertTrue(msg.contains("netsh advfirewall"),
                      "macOS implementation should log the would-be netsh command: \(msg)")
        XCTAssertTrue(msg.contains("BFME Arena"))
        XCTAssertTrue(msg.contains("OnlineArena.exe"))
    }
}
