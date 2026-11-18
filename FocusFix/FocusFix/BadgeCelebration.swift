import SwiftUI
import AppKit

struct AnalyticsBadgeAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

struct BadgeCelebrationHost: ViewModifier {
    @ObservedObject var badges: BadgeController
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var reduceMotionOverride: Bool? = nil
    var showsCelebration = true
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @State private var flight: CGFloat = 0
    @State private var dismissing = false
    @State private var comingSoon = false
    @State private var active = NSApp.isActive

    func body(content: Content) -> some View {
        let badge = badges.celebration
        content
            .blur(radius: badge != nil && active ? 8 * (1 - flight) : 0)
            .allowsHitTesting(badge == nil || !active)
            .disabled(badge != nil && active)
            .accessibilityHidden(badge != nil && active)
            .overlayPreferenceValue(AnalyticsBadgeAnchor.self) { anchor in
                GeometryReader { geometry in
                    if let badge, active, showsCelebration {
                        let destination = anchor.map { CGPoint(x: geometry[$0].midX, y: geometry[$0].midY) }
                            ?? CGPoint(x: geometry.size.width - 65, y: geometry.size.height - 45)
                        celebration(badge, size: geometry.size, destination: destination)
                    }
                }
            }
            .background(BadgeEscapeHandler(enabled: badge != nil && active && showsCelebration) {
                if let badge { dismiss(badge) }
            })
            .onAppear { active = NSApp.isActive }
            .onChange(of: badge?.id) { _, _ in flight = 0; dismissing = false; comingSoon = false }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in active = true }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in active = false }
    }

    private func celebration(_ badge: FocusBadge, size: CGSize, destination: CGPoint) -> some View {
        let start = CGPoint(x: size.width / 2, y: size.height / 2 - 55)
        return ZStack(alignment: .topLeading) {
            Button { dismiss(badge) } label: {
                Color(nsColor: .windowBackgroundColor).opacity(0.35 * (1 - flight)).contentShape(Rectangle())
            }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Dismiss badge celebration")
            Text("You've gained a badge!")
                .font(.title2.weight(.semibold)).frame(width: size.width)
                .position(x: size.width / 2, y: max(30, start.y - 150))
                .opacity(1 - flight).allowsHitTesting(false)
            BadgeArtwork(badge: badge).frame(width: 250, height: 250)
                .modifier(BadgeFlight(progress: flight, start: start, destination: destination, arc: !reduceMotion))
                .opacity(reduceMotion ? 1 - flight : 1)
                .allowsHitTesting(false)
            VStack(spacing: 8) {
                Text(badge.name).font(.title.weight(.semibold))
                Text(badge.description).font(.callout).foregroundStyle(.secondary)
            }.frame(width: size.width).position(x: size.width / 2, y: start.y + 148)
                .opacity(1 - flight).allowsHitTesting(false).accessibilityElement(children: .combine)
            BadgeLinkedInButton(comingSoon: $comingSoon)
                .disabled(dismissing)
                .position(x: size.width / 2, y: start.y + 210).opacity(1 - flight)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onExitCommand { dismiss(badge) }
    }

    private func dismiss(_ badge: FocusBadge) {
        guard !dismissing else { return }; dismissing = true
        withAnimation(.easeInOut(duration: reduceMotion ? 0.16 : 0.7)) { flight = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 160 : 700))
            badges.dismissCelebration(badge)
            flight = 0; dismissing = false; comingSoon = false
        }
    }
}

private struct BadgeFlight: GeometryEffect {
    var progress: CGFloat
    let start: CGPoint
    let destination: CGPoint
    let arc: Bool
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let scale = arc ? 1 - progress * 0.96 : 1
        let x = arc ? start.x + (destination.x - start.x) * progress : start.x
        let y = arc ? start.y + (destination.y - start.y) * progress - sin(progress * .pi) * 130 : start.y
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y)
            .scaledBy(x: scale, y: scale).translatedBy(x: -size.width / 2, y: -size.height / 2))
    }
}

struct BadgeLinkedInButton: View {
    @Binding var comingSoon: Bool
    var body: some View {
        Button { comingSoon = true } label: {
            HStack(spacing: 9) {
                LinkedInMark().frame(width: 20, height: 20)
                Text(comingSoon ? "Coming soon" : "Share to LinkedIn").font(.callout.weight(.medium))
            }.padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.12)))
        }.buttonStyle(.plain)
            .accessibilityLabel(comingSoon ? "LinkedIn sharing coming soon" : "Share to LinkedIn")
    }
}

// Compact vector rendering of LinkedIn's familiar white “in” mark on its blue square.
private struct LinkedInMark: View {
    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width
            ZStack {
                RoundedRectangle(cornerRadius: unit * 0.08).fill(Color(red: 0.04, green: 0.40, blue: 0.76))
                Text("in").font(.system(size: unit * 0.75, weight: .bold, design: .default))
                    .foregroundStyle(.white).offset(y: -unit * 0.035)
            }
        }.accessibilityHidden(true)
    }
}
