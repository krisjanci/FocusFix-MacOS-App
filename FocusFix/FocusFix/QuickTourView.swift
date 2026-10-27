import SwiftUI
import AppKit

struct QuickTourButton: View {
    @Environment(\.openWindow) private var openWindow
    var beforeOpen: () -> Void = {}
    var body: some View {
        Button {
            beforeOpen()
            Task { @MainActor in
                await Task.yield()
                QuickTourController.shared.restart()
                openWindow(id: "collector")
                NSApp.activate(ignoringOtherApps: true)
            }
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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    // Isolated previews can exercise this mode without changing macOS settings.
    var forceReducedMotion = false
    private var reduceMotion: Bool { systemReduceMotion || forceReducedMotion }
    @FocusState private var practiceNameFocused: Bool
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    @State private var captionSize = CGSize.zero
    @State private var docked = false

    var body: some View {
        GeometryReader { container in
            let captionWidth = min(248, max(1, container.size.width - 24))
            VStack(spacing: 0) {
                navigation.padding(12)
                if docked {
                    caption.frame(width: captionWidth).padding(.bottom, 12)
                }
                practiceArea(size: container.size)
            }
            .overlay(alignment: .topLeading) {
                // Measure the complete caption at its rendered width before placing it.
                caption.frame(width: captionWidth).fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { geometry in
                        Color.clear
                            .onAppear { captionSize = geometry.size }
                            .onChange(of: geometry.size) { _, value in captionSize = value }
                    })
                    .hidden().disabled(true).allowsHitTesting(false).accessibilityHidden(true)
            }
            .onChange(of: container.size) { _, _ in docked = false }
            .onChange(of: tour.phase) { _, _ in docked = false }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipped()
        }.tint(teal)
    }

    private func practiceArea(size: CGSize) -> some View {
        GeometryReader { viewport in
            ScrollViewReader { reader in
                ScrollView {
                    QuickTourDemoView(tour: tour, reduceMotion: reduceMotion, nameFocus: $practiceNameFocused)
                        .padding(24)
                        .frame(maxWidth: .infinity, minHeight: viewport.size.height)
                }
                .overlayPreferenceValue(PracticeAnchorKey.self) { anchors in
                    GeometryReader { geometry in
                        if let anchor = anchors[tour.phase] {
                            let target = geometry[anchor]
                            let hole = QuickTourLayout.spotlight(target, in: geometry.size)
                            let measured = captionSize
                            let bubble = QuickTourLayout.caption(target: hole, in: geometry.size,
                                                                 measured: measured)
                            if !hole.isNull && !hole.isEmpty {
                                spotlight(hole)
                                if !docked, let bubble {
                                    caption.frame(width: bubble.width)
                                        .position(x: bubble.midX, y: bubble.midY)
                                }
                            } else {
                                Color.black.opacity(0.45).allowsHitTesting(false)
                            }
                            Color.clear.allowsHitTesting(false)
                                .task(id: "\(tour.phase)-\(target)-\(captionSize)-\(docked)") {
                                    if !docked && bubble == nil && measured.height > 0 { docked = true }
                                }
                        }
                    }
                }
                .clipped()
                .task(id: "\(tour.visit)-\(tour.phase)-\(size)-\(docked)-\(captionSize)") {
                    // This also runs after resizing or docking so the target stays visible.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    reader.scrollTo(tour.phase, anchor: .center)
                }
                .task(id: "\(tour.visit)-\(tour.phase)-\(reduceMotion)") {
                    let phase = tour.phase
                    let visit = tour.visit
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
        }
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            Text("Practice · nothing saved").font(.caption.weight(.medium))
            Spacer(minLength: 4)
            Text(tour.position).font(.caption).monospacedDigit().accessibilityLabel("Step \(tour.index + 1) of 10")
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
            if phase.offersDone {
                PracticeCompletionMark(color: teal, reduceMotion: reduceMotion)
            }
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
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
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
            PracticeTargetRing(color: teal, phase: tour.phase, visit: tour.visit, reduceMotion: reduceMotion)
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

private struct PracticeTargetRing: View {
    let color: Color
    let phase: QuickTourPhase
    let visit: UUID
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(color.opacity(pulse ? 1 : 0.7), lineWidth: pulse ? 4 : 1.5)
            .shadow(color: color.opacity(pulse ? 0.35 : 0), radius: 6)
            .task(id: "\(visit)-\(phase)-\(reduceMotion)") {
                pulse = false
                guard !reduceMotion else { return }
                for _ in 0..<2 {
                    withAnimation(.easeInOut(duration: 0.3)) { pulse = true }
                    do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { pulse = false }
                    do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
                    guard !Task.isCancelled else { return }
                }
            }
    }
}

private struct PracticeCompletionMark: View {
    let color: Color
    let reduceMotion: Bool
    @State private var appeared = false
    var body: some View {
        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(color)
            .scaleEffect(reduceMotion || appeared ? 1 : 0.65)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.25)) { appeared = true }
            }
    }
}
