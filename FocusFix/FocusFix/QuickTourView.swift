import SwiftUI
import AppKit

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
        }.help("Try a short spotlight practice tour")
    }
}

struct PracticeAnchorKey: PreferenceKey {
    static var defaultValue: [QuickTourPhase: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [QuickTourPhase: Anchor<CGRect>],
                       nextValue: () -> [QuickTourPhase: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func practiceTarget(_ phase: QuickTourPhase) -> some View {
        anchorPreference(key: PracticeAnchorKey.self, value: .bounds) { [phase: $0] }.id(phase)
    }
}

// The root installs this as an overlay: it never participates in window sizing.
struct QuickTourView: View {
    @ObservedObject private var tour = QuickTourController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var practiceNameFocused: Bool
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        GeometryReader { container in
            ScrollViewReader { reader in
                ScrollView {
                    QuickTourDemoView(tour: tour, nameFocus: $practiceNameFocused)
                        .padding(.horizontal, 24).padding(.top, 64).padding(.bottom, 24)
                        .frame(maxWidth: .infinity, minHeight: container.size.height)
                }
                .scrollDisabled(true)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlayPreferenceValue(PracticeAnchorKey.self) { anchors in
                    GeometryReader { geometry in
                        if let anchor = anchors[tour.phase] {
                            let hole = QuickTourLayout.spotlight(geometry[anchor], in: geometry.size)
                            if !hole.isNull && !hole.isEmpty {
                                let bubble = QuickTourLayout.caption(target: hole, in: geometry.size,
                                    hasButton: tour.phase.offersNext || tour.phase.offersDone)
                                spotlight(hole)
                                caption.frame(width: bubble.width, height: bubble.height)
                                    .position(x: bubble.midX, y: bubble.midY)
                            } else {
                                Color.black.opacity(0.45).onTapGesture { }
                            }
                        } else {
                            Color.black.opacity(0.45).onTapGesture { }
                        }
                    }
                }
                .overlay(alignment: .top) { navigation.padding(12) }
                .task(id: "\(tour.visit.uuidString)-\(tour.phase.rawValue)") {
                    let phase = tour.phase
                    let visit = tour.visit
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    reader.scrollTo(phase, anchor: .center)
                    practiceNameFocused = false
                    if phase == .name {
                        await Task.yield()
                        guard !Task.isCancelled, tour.phase == phase, tour.visit == visit else { return }
                        practiceNameFocused = true
                    }
                    if phase == .work {
                        if reduceMotion { tour.illustrate(phase: phase, visit: visit, reducedMotion: true) }
                        else {
                            for _ in 0..<5 {
                                do { try await Task.sleep(nanoseconds: 140_000_000) } catch { return }
                                guard !Task.isCancelled else { return }
                                withAnimation(.easeOut(duration: 0.14)) { tour.illustrate(phase: phase, visit: visit) }
                            }
                        }
                    } else if phase == .progress {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) {
                            tour.illustrate(phase: phase, visit: visit)
                        }
                    }
                }
            }
        }.tint(teal)
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            Text("Practice · nothing saved").font(.caption.weight(.medium))
            Spacer(minLength: 4)
            Text(tour.position).font(.caption).monospacedDigit().accessibilityLabel("Step \(tour.index + 1) of 7")
            Button("Back") { tour.back() }.disabled(tour.isFirst)
                .keyboardShortcut("[", modifiers: .command)
            Button { tour.finish() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Close practice tour").keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var caption: some View {
        let phase = tour.phase
        let visit = tour.visit
        return VStack(alignment: .leading, spacing: 12) {
            Text(phase.caption).font(.system(size: 16, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if phase.offersNext || phase.offersDone {
                HStack {
                    Spacer()
                    Button(phase.offersDone ? "Done" : "Next") {
                        tour.perform(phase.offersDone ? .done : .next, phase: phase, visit: visit)
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(teal.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    private func spotlight(_ rect: CGRect) -> some View {
        let mask = PracticeSpotlight(hole: rect)
        return ZStack {
            mask.fill(.black.opacity(0.48), style: FillStyle(eoFill: true))
                .contentShape(mask, eoFill: true).onTapGesture { }
                .accessibilityHidden(true)
            RoundedRectangle(cornerRadius: 12).stroke(teal.opacity(0.85), lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY).allowsHitTesting(false).accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: rect)
    }
}

private struct PracticeSpotlight: Shape {
    var hole: CGRect
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(hole.minX, hole.minY), .init(hole.width, hole.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second,
                            width: newValue.second.first, height: newValue.second.second) }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: 12, height: 12))
        return path
    }
}
