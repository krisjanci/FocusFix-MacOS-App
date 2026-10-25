import AppKit
import Combine

@MainActor
final class ProfileController: ObservableObject {
    static let shared = ProfileController()
    @Published private(set) var profile: UserProfile?
    @Published private(set) var notice: String?
    private var store: ProfileStore?

    init() {
        do {
            let store = try ProfileStore.local()
            self.store = store
            profile = try store.load()
        } catch { notice = "Your saved profile could not be opened. You can save a new profile; recordings are unaffected." }
    }

    @discardableResult
    func save(_ draft: UserProfile) -> Bool {
        do {
            let valid = try draft.validated()
            guard let store else { throw CocoaError(.fileWriteUnknown) }
            try store.save(valid)
            profile = valid
            notice = nil
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    // Decode locally, resize to a square avatar, and re-encode without source EXIF metadata.
    static func photo(from url: URL) throws -> Data {
        let info = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = info.fileSize, size <= 10 * 1024 * 1024,
              let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            throw ProfileError.invalid
        }
        let side = 256
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw ProfileError.invalid }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        let scale = max(CGFloat(side) / image.size.width, CGFloat(side) / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        image.draw(in: NSRect(x: (CGFloat(side) - width) / 2, y: (CGFloat(side) - height) / 2,
            width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        guard let data = bitmap.representation(using: .png, properties: [:]), data.count <= 1_048_576 else {
            throw ProfileError.invalid
        }
        return data
    }
}
