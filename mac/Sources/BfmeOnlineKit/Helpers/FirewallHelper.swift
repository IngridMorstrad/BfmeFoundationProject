import Foundation

/// Port of `FirewallHelper.cs`. The Windows implementation shells out to
/// `netsh advfirewall firewall add rule ...` to punch TCP/UDP holes for
/// the arena binary. On macOS the Application Firewall does not require
/// per-app rules for outbound traffic; inbound listeners prompt the user
/// on first bind and are managed through System Settings. There is also
/// no scriptable equivalent available without an elevated helper tool.
///
/// The signature is preserved so the call sites in `ArenaProcessHelper`
/// don't need to change; the body is a log-only no-op on macOS / Linux.
public enum FirewallHelper {
    public static var lastLoggedMessage: String?

    public static func addFirewallRule(name: String, program: String) {
        let message = "FirewallHelper.addFirewallRule is a no-op on macOS. "
            + "On Windows this would run: netsh advfirewall firewall add rule "
            + "name=\"\(name)\" program=\"\(program)\" dir=in/out action=allow."
        lastLoggedMessage = message
        print(message)
    }
}
