import SwiftUI

// Illustrative artwork only: this placeholder never reads recordings or fetches data.
struct AnalyticsPanel: View {
    let close: () -> Void
    var allowsCollapsing = true
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("ANALYTICS").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                Spacer()
                if allowsCollapsing {
                Button(action: close) { Image(systemName: "sidebar.right") }.buttonPressFeedback()
                    .buttonStyle(.plain).help("Collapse Analytics")
                    .accessibilityLabel("Collapse Analytics")
                }
            }
            Text("Your focus, over time").font(.title2.weight(.semibold))
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
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
