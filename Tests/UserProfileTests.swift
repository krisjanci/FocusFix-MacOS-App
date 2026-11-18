import Foundation
import AppKit

@main
@MainActor
struct UserProfileTests {
    static func main() throws {
        let suite = "focusfix.test.photo-visibility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = UUID()
        let visibility = GroupPhotoVisibilityPreference(defaults: defaults, accountID: owner, origin: "https://example.invalid")
        precondition(visibility.isEnabled(for: nil))
        visibility.save(false)
        precondition(!visibility.isEnabled(for: nil))
        let restoredVisibility = GroupPhotoVisibilityPreference(defaults: defaults, accountID: owner, origin: "https://example.invalid")
        precondition(!restoredVisibility.isEnabled(for: UserProfile(name: "No photo")))
        precondition(GroupPhotoVisibilityPreference(defaults: defaults, accountID: UUID(), origin: "https://example.invalid").isEnabled(for: nil))
        precondition(GroupPhotoVisibilityPreference(defaults: defaults, accountID: owner, origin: "https://other.invalid").isEnabled(for: nil))
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
        precondition(profile.groupPhoto == nil)
        let thumbnail = try ProfileController.groupPhoto(from: avatar)
        let groupImage = NSBitmapImageRep(data: thumbnail)!
        precondition(groupImage.pixelsWide == 64 && groupImage.pixelsHigh == 64 && thumbnail.count <= 32_768)
        let shared = try UserProfile(name: "Group photo", photo: avatar, groupPhoto: thumbnail).validated()
        precondition(visibility.isEnabled(for: shared)) // Saved visibility wins over local defaults.
        precondition(!visibility.isEnabled(for: UserProfile(name: "Private", photo: avatar)))
        visibility.save(true)
        precondition(visibility.isEnabled(for: UserProfile(name: "No photo")))
        try store.save(shared)
        precondition(tryLoad(store) == shared)
        for bad in [UserProfile(name: "No photo", groupPhoto: thumbnail),
                    UserProfile(name: "Too large", photo: avatar, groupPhoto: Data(repeating: 1, count: 32_769))] {
            do { _ = try bad.validated(); preconditionFailure("Invalid group thumbnail accepted") } catch { }
        }
        let legacy = try JSONDecoder().decode(UserProfile.self, from: Data("{\"name\":\"Legacy\",\"symbol\":\"leaf.fill\",\"color\":\"teal\"}".utf8))
        precondition(legacy.groupPhoto == nil)
        // Adding a shared photo creates the thumbnail; private replacements clear it.
        let added = try ProfileController.replacingPhoto(in: profile, from: source, shareWithGroups: true)
        precondition(added.photo != nil && added.groupPhoto != nil)
        let addedThumbnail = NSBitmapImageRep(data: added.groupPhoto!)!
        precondition(addedThumbnail.pixelsWide == 64 && addedThumbnail.pixelsHigh == 64)
        let privateReplacement = try ProfileController.replacingPhoto(in: added, from: source, shareWithGroups: false)
        precondition(privateReplacement.photo != nil && privateReplacement.groupPhoto == nil)
        let sharedReplacement = try ProfileController.replacingPhoto(in: added, from: source, shareWithGroups: true)
        precondition(sharedReplacement.groupPhoto != nil)
        let privateImport = try ProfileController.replacingPhoto(in: profile, from: source, shareWithGroups: false)
        precondition(privateImport.photo != nil && privateImport.groupPhoto == nil)
        let invalidImage = root.appendingPathComponent("invalid.png")
        try Data("invalid image".utf8).write(to: invalidImage)
        do { _ = try ProfileController.photo(from: invalidImage); preconditionFailure("Invalid image accepted") } catch { }
        var unchanged = added
        do {
            unchanged = try ProfileController.replacingPhoto(in: unchanged, from: invalidImage, shareWithGroups: true)
            preconditionFailure("Invalid replacement accepted")
        } catch { }
        precondition(unchanged == added)
        print("User profile validation, atomic photo replacement, group visibility and persistence passed")
    }
    static func tryLoad(_ store: ProfileStore) -> UserProfile? { try! store.load() }
}
