import SwiftUI
import AppKit

// All entry points route to the collector, never to a separate tutorial window.
struct QuickTourButton: View {
    @Environment(\.openWindow) private var openWindow
    var beforeOpen: () -> Void = {}

    var body: some View {
        Button {
            beforeOpen()
            QuickTourController.shared.restart()
            openWindow(id: "collector")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Quick tour", systemImage: "book.closed")
        }.help("Explore FocusFix with comments and arrows, from the beginning")
    }
}

// Anchors follow the actual controls as the main screen scrolls and changes layout.
struct QuickTourAnchorKey: PreferenceKey {
    static var defaultValue: [QuickTourTarget: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [QuickTourTarget: Anchor<CGRect>],
                       nextValue: () -> [QuickTourTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    @ViewBuilder func quickTourTarget(_ target: QuickTourTarget, enabled: Bool = true) -> some View {
        if enabled {
            self.anchorPreference(key: QuickTourAnchorKey.self, value: .bounds) { [target: $0] }
                .id(target)
        } else { self }
    }
}

struct QuickTourView: View {
    @ObservedObject var tracker: ActivityTracker
    @ObservedObject private var tour = QuickTourController.shared
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Quick tour", systemImage: "book.closed").font(.headline)
                Spacer()
                Text(tour.position).font(.caption).foregroundStyle(.secondary)
                Button("Close tour") { tour.finish() }.keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 24).padding(.vertical, 14)
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    guidedScreen
                        // Even VoiceOver and keyboard activation cannot trigger real actions here.
                        .disabled(true).allowsHitTesting(false).accessibilityHidden(true)
                        .padding(.vertical, 14).frame(maxWidth: .infinity)
                }
                .overlayPreferenceValue(QuickTourAnchorKey.self) { anchors in
                    GeometryReader { geometry in
                        if let anchor = anchors[tour.step.target] {
                            highlight(geometry[anchor], in: geometry.size)
                        }
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
                .task(id: "\(tour.visit.uuidString)-\(tour.index)-\(tracker.isRecording)-\(tracker.breakPhase)") {
                    // Resolve the new screen's layout before revealing the target.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    reader.scrollTo(tour.step.target, anchor: .center)
                }
            }.frame(height: 310).clipped()
            Divider()
            comments
        }
        .frame(width: 680, height: 720)
        .background(Color(nsColor: .windowBackgroundColor)).tint(teal)
    }

    @ViewBuilder private var guidedScreen: some View {
        switch tour.step.target {
        case .profile:
            SharingView()
        case .sessions:
            SessionLibraryView(tracker: tracker).frame(width: 660, height: 410)
        default:
            ContentView(tracker: tracker)
        }
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: tour.step.symbol).foregroundStyle(teal).accessibilityHidden(true)
                Text(tour.step.title).font(.system(size: 22, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
            }
            Text(tour.step.subtitle).foregroundStyle(.secondary)
            Text(tracker.isRecording
                 ? "Recording continues. Close the tour to use the highlighted controls."
                 : "Follow the arrow above. Close the tour to use the highlighted controls.")
                .font(.caption).foregroundStyle(teal)
            if tracker.isRecording && tour.step.target == .start {
                Text("This button currently says Stop & save. Start session appears here when you're idle.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(tour.step.tips.indices, id: \.self) { index in
                        let tip = tour.step.tips[index]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tip.title).font(.callout.weight(.semibold)).accessibilityAddTraits(.isHeader)
                            Text(tip.detail).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.id("\(tour.visit.uuidString)-\(tour.index)")
            HStack {
                Button("Back") { tour.back() }.disabled(tour.isFirst)
                    .keyboardShortcut("[", modifiers: .command)
                Spacer()
                Button(tour.isLast ? "Done" : "Next") {
                    if tour.isLast { tour.finish() } else { tour.next() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .accessibilityValue(tour.position)
            }.controlSize(.large)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func highlight(_ bounds: CGRect, in size: CGSize) -> some View {
        let visible = bounds.insetBy(dx: -5, dy: -5)
            .intersection(CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6))
        return ZStack {
            if !visible.isNull && !visible.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(teal, lineWidth: 3)
                    .frame(width: visible.width, height: visible.height)
                    .position(x: visible.midX, y: visible.midY)
                let tip = CGPoint(x: visible.midX, y: min(size.height - 28, visible.maxY + 8))
                Path { path in
                    path.move(to: CGPoint(x: tip.x, y: size.height - 4))
                    path.addLine(to: tip)
                    path.move(to: CGPoint(x: tip.x - 7, y: tip.y + 9))
                    path.addLine(to: tip)
                    path.addLine(to: CGPoint(x: tip.x + 7, y: tip.y + 9))
                }.stroke(teal, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
