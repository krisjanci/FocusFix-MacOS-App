import AppKit
import SwiftUI

@main struct RenderRecordingPreviews {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let states: [(CaptureState, ActivityContext, InterventionPhase)] = [
            (.recording, .unknown, .normal), (.recording, .work, .normal), (.recording, .nonWork, .normal),
            (.userPaused, .unknown, .normal), (.idlePaused, .unknown, .normal),
            (.permissionUnavailable, .unknown, .normal), (.recording, .work, .explicitBreak)
        ]
        let content = HStack(alignment: .top, spacing: 0) {
            ForEach([false, true], id: \.self) { dark in
                VStack(alignment: .leading, spacing: 18) {
                    Text(dark ? "Dark · narrow" : "Light · narrow").font(.title2)
                    ForEach(states.indices, id: \.self) { index in
                        RecordingStatusPanel(state: states[index].0, mode: .automatic,
                            context: states[index].1, phase: states[index].2)
                            .padding(12).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Text("A long custom activity label wraps without becoming evidence of work or changing recording status.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Text("Legacy / empty history: context unknown. Missing coverage is unavailable.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }.padding(20).frame(width: 270).frame(maxHeight: .infinity, alignment: .top)
                    .background(dark ? Color.black : Color.white)
                    .environment(\.colorScheme, dark ? .dark : .light)
            }
        }.fixedSize()
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No preview") }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
