import CoreGraphics

nonisolated enum TaskPopupLayout {
    // The original collector stays on the left when Groups or Analytics adds width.
    static func origin(parentContent: CGRect, popupSize: CGSize, collectorWidth: CGFloat = 490) -> CGPoint {
        CGPoint(x: parentContent.minX + min(collectorWidth, parentContent.width) / 2 - popupSize.width / 2,
                y: parentContent.midY - popupSize.height / 2)
    }
}
