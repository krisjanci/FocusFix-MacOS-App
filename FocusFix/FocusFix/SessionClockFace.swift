import SwiftUI

// Shared by the real clock and the isolated practice clock; rendering has no side effects.
struct SessionClockFace: View {
    let time: String
    var body: some View {
        VStack(spacing: 16) {
            Text("SESSION TIME").font(.caption2.weight(.medium)).tracking(2).foregroundStyle(.secondary)
            Text(time).font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
        }
    }
}
