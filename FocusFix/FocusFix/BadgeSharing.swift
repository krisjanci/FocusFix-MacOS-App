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
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                FocusFixLaunchLogo(ready: true).frame(width: 48, height: 48)
                Text("FocusFix")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.01, green: 0.30, blue: 0.30))
            }
            BadgeArtwork(badge: badge).frame(width: 390, height: 390)
            Text(badge.name)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color(red: 0.05, green: 0.15, blue: 0.23))
                .lineLimit(1)
        }
        .frame(width: 600, height: 600)
        .background(BadgeShareSpaceBackground())
    }
}

// Keep orbital details and stars at the edges so artwork and lettering stay clear.
private struct BadgeShareSpaceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.93, green: 0.96, blue: 1),
                                    Color(red: 0.96, green: 0.99, blue: 0.98),
                                    Color(red: 0.94, green: 0.93, blue: 0.99)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.8), .white.opacity(0)],
                           center: .center, startRadius: 90, endRadius: 300)
            Canvas { context, size in
                let ink = Color(red: 0.23, green: 0.39, blue: 0.52)
                let stars: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.08, 0.12, 2), (0.18, 0.23, 1.3), (0.88, 0.10, 1.5),
                    (0.94, 0.29, 2), (0.07, 0.43, 1.2), (0.92, 0.56, 1.3),
                    (0.12, 0.72, 2), (0.85, 0.77, 1.4), (0.07, 0.91, 1.2),
                    (0.91, 0.94, 2), (0.22, 0.93, 1), (0.77, 0.08, 1)
                ]
                for (x, y, radius) in stars {
                    let point = CGPoint(x: x * size.width, y: y * size.height)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                       width: radius * 2, height: radius * 2)),
                                 with: .color(ink.opacity(0.28)))
                }
                for (x, y) in [(0.13, 0.12), (0.89, 0.68), (0.12, 0.85)] {
                    let point = CGPoint(x: x * size.width, y: y * size.height)
                    var star = Path()
                    star.move(to: CGPoint(x: point.x - 5, y: point.y))
                    star.addLine(to: CGPoint(x: point.x + 5, y: point.y))
                    star.move(to: CGPoint(x: point.x, y: point.y - 5))
                    star.addLine(to: CGPoint(x: point.x, y: point.y + 5))
                    context.stroke(star, with: .color(ink.opacity(0.32)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
                let orbit = CGRect(x: -size.width * 0.63, y: size.height * 0.16,
                                   width: size.width * 0.78, height: size.height * 0.78)
                context.stroke(Path(ellipseIn: orbit), with: .color(ink.opacity(0.10)), lineWidth: 1)
                let planet = CGRect(x: size.width * 0.86, y: size.height * 0.17, width: 27, height: 27)
                context.stroke(Path(ellipseIn: planet), with: .color(ink.opacity(0.18)), lineWidth: 1)
            }
        }.clipped()
    }
}

struct BadgeSharePanel: View {
    let share: BadgeShare
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
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
            .foregroundStyle(.primary)
            .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
    }
}
