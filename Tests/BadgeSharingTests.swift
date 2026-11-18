import SwiftUI
import AppKit

@main struct BadgeSharingTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("focusfix-share-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let joined = FocusBadge.all[0]
        precondition(BadgeShare.caption(for: joined) == "I just joined FocusFix! Can't wait to see how it'll transform my work habits!")
        for badge in FocusBadge.all {
            let share = try BadgeShare.prepare(badge, directory: root)
            if badge.days > 0 { precondition(share.caption.contains("\(badge.days)-day work streak")) }
            precondition(!share.caption.contains("\n"))
            let components = URLComponents(url: BadgeShare.composerURL(caption: share.caption), resolvingAgainstBaseURL: false)!
            precondition(components.host == "www.linkedin.com" && components.path == "/feed/")
            precondition(components.queryItems?.first(where: { $0.name == "text" })?.value == share.caption)
            let bitmap = NSBitmapImageRep(data: try Data(contentsOf: share.imageURL))!
            precondition(bitmap.pixelsWide == 1200 && bitmap.pixelsHigh == 1200)
            precondition(share.imageURL.lastPathComponent == "FocusFix-\(badge.id).png")
            _ = try BadgeShare.prepare(badge, directory: root) // Repeated sharing replaces the same cached file.
        }
        let unusual = "Focus & fix + habits? #1 — can't wait!"
        precondition(URLComponents(url: BadgeShare.composerURL(caption: unusual), resolvingAgainstBaseURL: false)?.queryItems?.last?.value == unusual)
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        do {
            _ = try BadgeShare.prepare(joined, directory: blocked)
            preconditionFailure("An unwritable export must report failure")
        } catch {}
        // Optional artifacts for visual inspection; no browser is opened and nothing is posted.
        if let path = ProcessInfo.processInfo.environment["BADGE_SHARE_PREVIEW_DIR"] {
            for badge in [joined, FocusBadge.all.last!] {
                _ = try BadgeShare.prepare(badge, directory: URL(fileURLWithPath: path))
            }
        }
        print("Badge sharing tests passed: captions, URL encoding, all PNGs, repeats, and export failure")
    }
}
