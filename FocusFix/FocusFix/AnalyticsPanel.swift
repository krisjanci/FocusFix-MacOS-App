import SwiftUI

struct AnalyticsPanel: View {
    let close: () -> Void
    var anchorsCelebration = false
    @ObservedObject var badges: BadgeController = .shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingBadges = false
    @State private var selectedBadge: FocusBadge?
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    if showingBadges {
                        Button { showingBadges = false } label: {
                            Image(systemName: "arrow.left").frame(width: 28, height: 22)
                        }.buttonStyle(.bordered).keyboardShortcut(.cancelAction).accessibilityLabel("Back to graph analytics")
                    }
                    Text(showingBadges ? "BADGES" : "ANALYTICS")
                        .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                        .anchorPreference(key: AnalyticsBadgeAnchor.self, value: .bounds) { anchorsCelebration ? $0 : nil }
                    Spacer()
                    Button(action: close) { Image(systemName: "sidebar.right") }
                        .buttonPressFeedback().buttonStyle(.plain).help("Collapse Analytics")
                        .accessibilityLabel("Collapse Analytics")
                }
                if showingBadges {
                    collection
                } else {
                    Text("Your focus, over time").font(.title2.weight(.semibold))
                    graphs
                    Spacer(minLength: 0)
                    Button { openBadges() } label: {
                        HStack {
                            Label("Badges", systemImage: "seal")
                            if badges.hasUnread { BadgeUnreadDot() }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }.padding(16).frame(maxWidth: .infinity)
                            .background(teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).buttonPressFeedback()
                    .accessibilityLabel(badges.hasUnread ? "Badges, new badges" : "Badges")
                }
            }
            .blur(radius: selectedBadge == nil ? 0 : 7)
            .allowsHitTesting(selectedBadge == nil)
            .disabled(selectedBadge != nil)
            .accessibilityHidden(selectedBadge != nil)
            .padding(18)
            if let badge = selectedBadge {
                Button { selectedBadge = nil } label: {
                    Color(nsColor: .windowBackgroundColor).opacity(0.78).contentShape(Rectangle())
                }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Dismiss badge details")
                VStack(spacing: 12) {
                    VStack(spacing: 12) {
                        BadgeArtwork(badge: badge, earned: badges.isEarned(badge)).frame(width: 240, height: 240)
                        Text(badge.name).font(.title2.weight(.semibold))
                        Text(badges.isEarned(badge) ? badge.description : badge.requirement)
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if !badges.isEarned(badge) { Label("Locked", systemImage: "lock.fill").font(.caption) }
                    }.allowsHitTesting(false).accessibilityElement(children: .combine)
                    if badges.isEarned(badge) { BadgeLinkedInButton(badge: badge) }
                }.padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedBadge)
        .background(BadgeEscapeHandler(enabled: badges.celebration == nil && (selectedBadge != nil || showingBadges)) {
            if selectedBadge != nil { selectedBadge = nil } else { showingBadges = false }
        })
        .onExitCommand { if selectedBadge != nil { selectedBadge = nil } else if showingBadges { showingBadges = false } }
        .onChange(of: badges.collectionRequest) { _, _ in openBadges() }
        .onAppear { if badges.collectionRequested { openBadges() } }
    }

    private func openBadges() {
        selectedBadge = nil; showingBadges = true
        badges.openCollection()
    }
    private var collection: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(FocusBadge.all) { badge in
                    Button { selectedBadge = badge } label: {
                        VStack(spacing: 4) {
                            BadgeArtwork(badge: badge, earned: badges.isEarned(badge)).frame(height: 210)
                            Text(badge.name).font(.headline)
                            if badges.isEarned(badge) {
                                Label("Earned", systemImage: "checkmark.seal.fill").foregroundStyle(teal)
                            } else {
                                Label(badge.days == 0 ? "Sign in to unlock" : "\(badge.days)-day work streak", systemImage: "lock.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }.font(.caption).padding(.vertical, 12).frame(maxWidth: .infinity)
                            .background(teal.opacity(badges.isEarned(badge) ? 0.06 : 0.025), in: RoundedRectangle(cornerRadius: 16))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .accessibilityLabel("\(badge.name), \(badges.isEarned(badge) ? "earned" : "locked")")
                    .accessibilityHint("Show badge description")
                }
            }
        }
    }
    // Illustrative artwork only; badge data does not enable graph analytics.
    private var graphs: some View {
            ZStack {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Work over time").font(.headline)
                        HStack(alignment: .bottom, spacing: 12) {
                            ForEach(Array([0.35, 0.62, 0.48, 0.85, 0.57, 0.72, 0.94].enumerated()), id: \.offset) { _, height in
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(teal.opacity(0.7)).frame(height: height * 100)
                            }
                        }.frame(height: 100, alignment: .bottom)
                    }
                    .padding(20).background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Break rhythm").font(.headline)
                        GeometryReader { geometry in
                            Path { path in
                                let width = geometry.size.width, height = geometry.size.height
                                path.move(to: CGPoint(x: 0, y: height * 0.8))
                                path.addCurve(to: CGPoint(x: width * 0.5, y: height * 0.5),
                                              control1: CGPoint(x: width * 0.2, y: height * 0.1),
                                              control2: CGPoint(x: width * 0.3, y: height * 0.95))
                                path.addCurve(to: CGPoint(x: width, y: height * 0.15),
                                              control1: CGPoint(x: width * 0.7, y: height * 0.05),
                                              control2: CGPoint(x: width * 0.8, y: height * 0.7))
                            }.stroke(teal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        }.frame(height: 95)
                    }
                    .padding(20).background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }
                .blur(radius: 5).opacity(0.45)
                .allowsHitTesting(false).accessibilityHidden(true)

                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 28, weight: .light)).foregroundStyle(teal)
                    Text("Coming soon").font(.title2.weight(.semibold))
                    Text("A clearer view of your work and breaks.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(24).frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.06)))
                .padding(.horizontal, 12)
                .accessibilityElement(children: .combine)
            }
    }
}
