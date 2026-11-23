import SwiftUI
import AppKit

struct ProjectColorChooser: View {
    @Binding var selection: String
    var inline = false
    @State private var showingPalette = false
    @State private var customPicker = ProjectCustomColorPicker()
    private let names = ["Teal", "Purple", "Orange", "Rose", "Blue", "Green", "Brown", "Slate"]

    var body: some View {
        Group {
            if inline { palette }
            else {
                Button { showingPalette.toggle() } label: {
                    Circle().fill(Color(tagHex: selection)).frame(width: 23, height: 23)
                        .overlay { Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1) }
                }.buttonStyle(.plain).accessibilityLabel("Choose project color")
                    .popover(isPresented: $showingPalette) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Project color").font(.headline)
                            palette
                        }.padding(18)
                    }
            }
        }
        .onDisappear { customPicker.closeIfOwned() }
    }

    private var palette: some View {
        HStack(spacing: 9) {
            ForEach(Array(SessionTags.palette.enumerated()), id: \.element) { index, hex in
                Button {
                    selection = hex; showingPalette = false; customPicker.closeIfOwned()
                } label: {
                    Circle().fill(Color(tagHex: hex)).frame(width: 23, height: 23)
                        .overlay {
                            if selection.uppercased() == hex { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white) }
                        }
                }.buttonPressFeedback().buttonStyle(.plain)
                    .accessibilityLabel("\(names[index]) project color")
                    .accessibilityValue(selection.uppercased() == hex ? "Selected" : "")
            }
            Button {
                let binding = $selection
                showingPalette = false
                customPicker.present(color: selection) { binding.wrappedValue = $0 }
            } label: {
                Circle().fill(Color(nsColor: .windowBackgroundColor)).frame(width: 23, height: 23)
                    .overlay { Circle().stroke(Color.secondary.opacity(0.45), lineWidth: 1) }
                    .overlay { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary) }
            }.buttonPressFeedback().buttonStyle(.plain)
                .accessibilityLabel("Choose custom project color").help("Custom color")
        }
    }
}

@MainActor private final class ProjectCustomColorPicker: NSObject {
    private static weak var active: ProjectCustomColorPicker?
    private var change: ((String) -> Void)?
    private var configuring = false

    func present(color: String, change: @escaping (String) -> Void) {
        self.change = change
        Self.active = self
        let panel = NSColorPanel.shared
        configuring = true
        panel.setTarget(self); panel.setAction(#selector(colorChanged(_:)))
        panel.showsAlpha = false; panel.isContinuous = true
        panel.color = NSColor(Color(tagHex: color))
        configuring = false
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard !configuring else { return }
        change?(Color(nsColor: sender.color).tagHex)
    }

    func closeIfOwned() {
        guard Self.active === self else { return }
        NSColorPanel.shared.orderOut(nil)
        NSColorPanel.shared.setTarget(nil); NSColorPanel.shared.setAction(nil)
        change = nil; Self.active = nil
    }
}
