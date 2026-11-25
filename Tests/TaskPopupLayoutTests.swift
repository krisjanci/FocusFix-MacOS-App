import CoreGraphics

@main struct TaskPopupLayoutTests {
    static func main() {
        let compact = CGRect(x: 120, y: 80, width: 490, height: 620)
        let expanded = CGRect(x: 120, y: 80, width: 850, height: 620)
        let popup = CGSize(width: 420, height: 410)
        let original = TaskPopupLayout.origin(parentContent: compact, popupSize: popup)
        precondition(original == TaskPopupLayout.origin(parentContent: expanded, popupSize: popup),
                     "Opening a side panel must not move a task popup")
        precondition(original.x + popup.width / 2 == compact.midX)
        precondition(original.y + popup.height / 2 == compact.midY)
        let taller = CGSize(width: 420, height: 450)
        let resized = TaskPopupLayout.origin(parentContent: expanded, popupSize: taller)
        precondition(resized.x == original.x && resized.y + taller.height / 2 == compact.midY)
        let moved = TaskPopupLayout.origin(parentContent: compact.offsetBy(dx: -60, dy: 30), popupSize: popup)
        precondition(moved.x == original.x - 60 && moved.y == original.y + 30)
        let narrow = CGRect(x: 0, y: 0, width: 450, height: 620)
        precondition(TaskPopupLayout.origin(parentContent: narrow, popupSize: popup).x == 15)
        print("TaskPopupLayoutTests passed: compact/expanded stability, centering, content resize and parent movement")
    }
}
