#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeKit
import BfmeWorkshopKit
import BfmeOnlineKit
import BfmeOnlineKitUI

/// Port of `Pages/Primary/About.xaml.cs`. Shows the launcher's version and
/// links to community social accounts.
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("BFME All In One Launcher")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text("Native macOS Apple Silicon port")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))

                Divider().padding(.vertical, 8)

                Group {
                    moduleRow("BfmeKit",         version: BfmeKit.moduleVersion)
                    moduleRow("BfmeWorkshopKit", version: BfmeWorkshopKit.moduleVersion)
                    moduleRow("BfmeOnlineKit",   version: BfmeOnlineKit.moduleVersion)
                    moduleRow("BfmeOnlineKitUI", version: BfmeOnlineKitUI.moduleVersion)
                }

                Divider().padding(.vertical, 8)

                HStack(spacing: 16) {
                    socialLink(icon: "discord", url: "https://discord.gg/bfmeladder")
                    socialLink(icon: "github",  url: "https://github.com/IngridMorstrad/BfmeFoundationProject")
                    socialLink(icon: "twitch",  url: "https://twitch.tv/bfmeladder")
                    socialLink(icon: "youtube", url: "https://youtube.com/@bfmeladder")
                    socialLink(icon: "moddb",   url: "https://www.moddb.com")
                }
            }
            .padding(24)
        }
    }

    private func moduleRow(_ name: String, version: String) -> some View {
        HStack {
            Text(name).foregroundStyle(.white).font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(version).foregroundStyle(.white.opacity(0.6)).font(.system(size: 14))
        }
    }

    private func socialLink(icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Image(icon, bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}
#endif
