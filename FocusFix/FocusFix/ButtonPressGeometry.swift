import Foundation
import CoreGraphics

// NSView.visibleRect may include space outside an unclipped view's own bounds.
// Feedback must remain inside both the control and its visible clipping region.
nonisolated enum ButtonPressGeometry {
    static func contains(_ point: CGPoint, bounds: CGRect, visibleRect: CGRect) -> Bool {
        bounds.contains(point) && visibleRect.contains(point)
    }
}
