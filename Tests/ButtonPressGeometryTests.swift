import Foundation
import CoreGraphics

@main struct ButtonPressGeometryTests {
    static func main() {
        // Captured from the native preview: every marker's visibleRect covered
        // the entire window, despite belonging to one small button.
        let controls = [
            CGRect(x: 185.5, y: 107, width: 95, height: 22),
            CGRect(x: 157.5, y: 149, width: 115.5, height: 28),
            CGRect(x: 92, y: 107.5, width: 77.5, height: 21),
            CGRect(x: 296.5, y: 107, width: 41.5, height: 22)
        ]
        let window = CGRect(x: 0, y: 0, width: 430, height: 352)
        func matches(_ point: CGPoint) -> [Int] {
            controls.indices.filter { index in
                let rect = controls[index]
                let local = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
                let bounds = CGRect(origin: .zero, size: rect.size)
                let visible = window.offsetBy(dx: -rect.minX, dy: -rect.minY)
                return ButtonPressGeometry.contains(local, bounds: bounds, visibleRect: visible)
            }
        }
        precondition(matches(CGPoint(x: 215, y: 162.5)) == [1]) // Primary button only.
        for index in controls.indices {
            precondition(matches(CGPoint(x: controls[index].midX, y: controls[index].midY)) == [index])
        }
        precondition(matches(CGPoint(x: 215, y: 75)).isEmpty) // Other/disabled control region.
        precondition(matches(CGPoint(x: 10, y: 330)).isEmpty) // Empty window space.
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 30)
        let clipped = CGRect(x: 40, y: 0, width: 60, height: 30)
        precondition(!ButtonPressGeometry.contains(CGPoint(x: 10, y: 15), bounds: bounds, visibleRect: clipped))
        precondition(ButtonPressGeometry.contains(CGPoint(x: 60, y: 15), bounds: bounds, visibleRect: clipped))
        precondition(!ButtonPressGeometry.contains(.zero, bounds: .zero, visibleRect: window))
        print("PASS: only the clicked button responds, oversized native visible regions, sibling controls and clipping")
    }
}
