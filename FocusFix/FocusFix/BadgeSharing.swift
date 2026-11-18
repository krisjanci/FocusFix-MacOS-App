import SwiftUI
import AppKit

struct BadgeShare: Identifiable {
    let badge: FocusBadge
    let imageURL: URL
    var id: String { badge.id }
    var caption: String { Self.caption(for: badge) }

    static func caption(for badge: FocusBadge) -> String {
        badge.days == 0
            ? "I just joined FocusFix! Can't wait to see how it'll transform my work habits!"
            : "I just completed a \(badge.days)-day work streak with FocusFix! Can't wait to keep building better work habits!"
    }

    // LinkedIn's web composer may ignore text parameters; the sharing panel also offers Copy caption.
    static func composerURL(caption: String) -> URL {
        var components = URLComponents(string: "https://www.linkedin.com/feed/")!
        components.queryItems = [URLQueryItem(name: "shareActive", value: "true"), URLQueryItem(name: "text", value: caption)]
        return components.url!
    }

    @MainActor static func prepare(_ badge: FocusBadge, directory: URL? = nil) throws -> BadgeShare {
        let root = try directory ?? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
            .appendingPathComponent("FocusFix/BadgeShares", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: BadgeShareCard(badge: badge).environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = root.appendingPathComponent("FocusFix-\(badge.id).png")
        try png.write(to: url, options: .atomic)
        return BadgeShare(badge: badge, imageURL: url)
    }
}

private struct BadgeShareCard: View {
    let badge: FocusBadge
    var body: some View {
        VStack(spacing: 12) {
            Text("FocusFix").font(.system(size: 28, weight: .semibold)).foregroundStyle(Color(red: 0.01, green: 0.37, blue: 0.36))
            BadgeArtwork(badge: badge).frame(width: 390, height: 390)
            Text(badge.name).font(.system(size: 30, weight: .bold)).foregroundStyle(.black)
            Text(badge.description).font(.system(size: 18)).foregroundStyle(.black.opacity(0.65))
        }
        .frame(width: 600, height: 600)
        .background(Color(red: 0.96, green: 0.99, blue: 0.98))
    }
}

struct BadgeSharePanel: View {
    let share: BadgeShare
    @Environment(\.dismiss) private var dismiss
    @State private var browserFailed = false
    @State private var copied = false
    init(share: BadgeShare, browserFailed: Bool = false) {
        self.share = share
        _browserFailed = State(initialValue: browserFailed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share your badge").font(.title2.bold())
            BadgeArtwork(badge: share.badge).frame(width: 150, height: 150).frame(maxWidth: .infinity)
            Text("Attach the badge image in LinkedIn, then publish your post.")
            Text(share.caption).textSelection(.enabled).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Text("If LinkedIn leaves the caption blank, copy it here and paste it into your post.")
                .font(.callout).foregroundStyle(.secondary)
            if browserFailed { Text("LinkedIn couldn't open. Please try again.").foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
            HStack {
                Button(copied ? "Caption copied" : "Copy caption") {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(share.caption, forType: .string)
                }
                Button("Show badge image") { NSWorkspace.shared.activateFileViewerSelecting([share.imageURL]) }
                Button("Open LinkedIn") {
                    browserFailed = !NSWorkspace.shared.open(BadgeShare.composerURL(caption: share.caption))
                }
            }
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(24).frame(width: 470)
    }
}
