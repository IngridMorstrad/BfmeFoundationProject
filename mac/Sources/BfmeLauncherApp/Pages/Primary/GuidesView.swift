#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Pages/Primary/Guides.xaml.cs`. The WPF page was a list of
/// hyperlink buttons to community guides — we replicate that as a SwiftUI
/// list of `Link`s.
struct GuidesView: View {
    struct Entry: Identifiable { let id = UUID(); let title: String; let url: URL }

    let entries: [Entry] = [
        Entry(title: "BFME1 Setup Guide",  url: URL(string: "https://bfmeladder.com/guides/bfme1")!),
        Entry(title: "BFME2 Setup Guide",  url: URL(string: "https://bfmeladder.com/guides/bfme2")!),
        Entry(title: "RotWK Setup Guide",  url: URL(string: "https://bfmeladder.com/guides/rotwk")!),
        Entry(title: "Workshop Packages",  url: URL(string: "https://bfmeladder.com/guides/workshop")!),
        Entry(title: "macOS Compatibility",url: URL(string: "https://bfmeladder.com/guides/macos")!)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(entries) { entry in
                    Link(destination: entry.url) {
                        Text(entry.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }
}
#endif
