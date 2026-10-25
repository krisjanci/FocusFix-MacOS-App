import Foundation
import AppKit

@main
@MainActor
struct UserProfileTests {
    static func main() throws {
        let profile = try UserProfile(name: "  Kris  ", symbol: "leaf.fill", color: "blue").validated()
        precondition(profile.name == "Kris")
        for draft in [UserProfile(name: "  "), UserProfile(name: String(repeating: "x", count: 41)),
                      UserProfile(name: "Name\nNewline"), UserProfile(name: "Name", symbol: "unknown"),
                      UserProfile(name: "Name", color: "unknown"), UserProfile(name: "Name", photo: Data()),
                      UserProfile(name: "Name", photo: Data(repeating: 0, count: 1_048_577))] {
            do { _ = try draft.validated(); preconditionFailure("Invalid profile accepted") } catch { }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(url: root.appendingPathComponent("profile.json"))
        let missing = try store.load()
        precondition(missing == nil)
        try store.save(profile)
        let loaded = try store.load()
        precondition(loaded == profile)
        var edited = profile
        edited.name = "New name"
        try store.save(edited)
        precondition(tryLoad(store) == edited)
        do { try store.save(UserProfile(name: "")); preconditionFailure("Invalid save succeeded") } catch { }
        precondition(tryLoad(store) == edited)
        // Only presentation fields are persisted, never a participant ID or recording data.
        let fields = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as! [String: Any]
        precondition(Set(fields.keys) == Set(["name", "symbol", "color"]))
        let corrupt = Data("unreadable".utf8)
        try corrupt.write(to: store.url)
        do { _ = try store.load(); preconditionFailure("Expected decoding error") } catch { }
        let kept = try Data(contentsOf: store.url)
        precondition(kept == corrupt)
        let blocker = root.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        do {
            try ProfileStore(url: blocker.appendingPathComponent("profile.json")).save(profile)
            preconditionFailure("Expected write error")
        } catch { }
        // The importer always emits a bounded square PNG, even from a rectangular source.
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let source = root.appendingPathComponent("photo.png")
        try image.representation(using: .png, properties: [:])!.write(to: source)
        let avatar = try ProfileController.photo(from: source)
        let rendered = NSBitmapImageRep(data: avatar)!
        precondition(rendered.pixelsWide == 256 && rendered.pixelsHigh == 256)
        precondition(avatar.count <= 1_048_576)
        let invalidImage = root.appendingPathComponent("invalid.png")
        try Data("invalid image".utf8).write(to: invalidImage)
        do { _ = try ProfileController.photo(from: invalidImage); preconditionFailure("Invalid image accepted") } catch { }
        print("User profile validation, photo import and persistence passed")
    }
    static func tryLoad(_ store: ProfileStore) -> UserProfile? { try! store.load() }
}
