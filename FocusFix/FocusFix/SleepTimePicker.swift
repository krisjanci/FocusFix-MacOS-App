import SwiftUI
import AppKit

// A compact timer-style wheel; the calendar day remains an explicit choice.
struct SleepTimePicker: View {
    @Binding var bedtime: Date
    @Binding var wakeTime: Date
    @State private var editingWakeTime = false
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)
    private var selection: Binding<Date> { editingWakeTime ? $wakeTime : $bedtime }
    private var calendar: Calendar { .current }
    private var hour: Int { calendar.component(.hour, from: selection.wrappedValue) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                timeButton("Went to bed", date: bedtime, isWake: false)
                timeButton("Woke up", date: wakeTime, isWake: true)
            }
            HStack(spacing: 0) {
                wheel("Hour", values: (1...12).map(String.init), index: Binding(
                    get: { (hour + 11) % 12 },
                    set: { setTime(hour: ($0 + 1) % 12 + (hour >= 12 ? 12 : 0)) }))
                Text(":").font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(teal)
                    .accessibilityHidden(true)
                wheel("Minute", values: (0..<60).map { String(format: "%02d", $0) }, index: Binding(
                    get: { calendar.component(.minute, from: selection.wrappedValue) },
                    set: { setTime(minute: $0) }))
                wheel("AM or PM", values: [calendar.amSymbol, calendar.pmSymbol], index: Binding(
                    get: { hour >= 12 ? 1 : 0 },
                    set: { setTime(hour: hour % 12 + $0 * 12) }))
            }
            .background {
                RoundedRectangle(cornerRadius: 10).fill(teal.opacity(0.10)).frame(height: 32)
            }
            .id(editingWakeTime)
            DatePicker(editingWakeTime ? "Wake date" : "Bedtime date", selection: selection,
                in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.field)
                .font(.callout)
        }
    }

    private func timeButton(_ title: String, date: Date, isWake: Bool) -> some View {
        Button { editingWakeTime = isWake } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption)
                Text(date, format: .dateTime.hour().minute()).font(.callout.weight(.semibold)).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .foregroundStyle(editingWakeTime == isWake ? teal : Color.primary)
                .background(editingWakeTime == isWake ? teal.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
            .accessibilityLabel("\(title), \(date.formatted(date: .abbreviated, time: .shortened))")
            .accessibilityAddTraits(editingWakeTime == isWake ? .isSelected : [])
    }

    private func wheel(_ label: String, values: [String], index: Binding<Int>) -> some View {
        TimeWheel(label: label, values: values, selection: index)
            .frame(maxWidth: .infinity)
    }

    private func setTime(hour: Int? = nil, minute: Int? = nil) {
        let date = selection.wrappedValue
        if let updated = calendar.date(bySettingHour: hour ?? calendar.component(.hour, from: date),
            minute: minute ?? calendar.component(.minute, from: date), second: 0, of: date) {
            selection.wrappedValue = updated
        }
    }
}

private struct TimeWheel: View {
    let label: String
    let values: [String]
    @Binding var selection: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NativeTimeWheel(values: values, selection: $selection, reduceMotion: reduceMotion)
            .frame(height: 96)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25),
                .init(color: .black, location: 0.75), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(values[selection])
            .accessibilityAdjustableAction { direction in
                selection = min(values.count - 1, max(0, selection + (direction == .increment ? 1 : -1)))
            }
            .focusable()
            .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
            .onKeyPress(.downArrow) { selection = min(values.count - 1, selection + 1); return .handled }
    }
}

private struct NativeTimeWheel: NSViewRepresentable {
    let values: [String]
    @Binding var selection: Int
    let reduceMotion: Bool

    func makeNSView(context: Context) -> WheelScrollView {
        let view = WheelScrollView(values: values, selection: selection)
        view.changed = { selection = $0 }
        return view
    }

    func updateNSView(_ view: WheelScrollView, context: Context) {
        view.changed = { selection = $0 }
        view.reduceMotion = reduceMotion
        if view.selected != selection { view.select(selection, animated: !reduceMotion) }
    }
}

private final class WheelScrollView: NSScrollView {
    var changed: ((Int) -> Void)?
    var reduceMotion = false
    private(set) var selected: Int
    private let rows: [WheelLabel]
    private let canvas = WheelCanvas()
    private var snap: DispatchWorkItem?
    private var movingProgrammatically = false

    init(values: [String], selection: Int) {
        selected = selection
        rows = values.map { WheelLabel(labelWithString: $0) }
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = false; hasHorizontalScroller = false
        verticalScrollElasticity = .none; horizontalScrollElasticity = .none
        automaticallyAdjustsContentInsets = false
        documentView = canvas
        rows.forEach { canvas.addSubview($0) }
        canvas.clicked = { [weak self] index in
            guard let self else { return }
            let value = min(self.rows.count - 1, max(0, index))
            self.select(value, animated: !self.reduceMotion)
            self.changed?(value)
        }
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: contentView)
        updateLabels()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = contentSize.width
        let resized = canvas.frame.width != width || canvas.frame.height != CGFloat(rows.count + 2) * 32
        canvas.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat(rows.count + 2) * 32)
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(index + 1) * 32 + 2, width: width, height: 29)
        }
        if resized { select(selected, animated: false) }
    }

    override func scrollWheel(with event: NSEvent) {
        // Consume scrolling here so a wheel never scrolls the surrounding survey.
        snap?.cancel()
        movingProgrammatically = false
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8)
        let maximum = max(0, canvas.bounds.height - contentSize.height)
        let y = min(maximum, max(0, contentView.bounds.minY - delta))
        contentView.scroll(to: NSPoint(x: 0, y: y))
        reflectScrolledClipView(contentView)
    }

    func select(_ value: Int, animated: Bool) {
        snap?.cancel()
        selected = value
        updateLabels()
        movingProgrammatically = true
        let target = NSPoint(x: 0, y: CGFloat(value) * 32)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.16 : 0
            contentView.animator().setBoundsOrigin(target)
        } completionHandler: { [weak self] in self?.movingProgrammatically = false }
        reflectScrolledClipView(contentView)
    }

    @objc private func scrolled() {
        guard !movingProgrammatically else { return }
        let value = min(rows.count - 1, max(0, Int((contentView.bounds.minY / 32).rounded())))
        if selected != value {
            selected = value; updateLabels(); changed?(value)
        }
        snap?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.select(self.selected, animated: !self.reduceMotion)
        }
        snap = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: task)
    }

    private func updateLabels() {
        for (index, row) in rows.enumerated() {
            let font = NSFont.systemFont(ofSize: 23, weight: index == selected ? .semibold : .regular)
            row.font = NSFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 23)
            row.alignment = .center
            row.textColor = index == selected ? .labelColor : .secondaryLabelColor.withAlphaComponent(0.55)
        }
    }
}

private final class WheelLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class WheelCanvas: NSView {
    var clicked: ((Int) -> Void)?
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) {
        clicked?(Int(((convert(event.locationInWindow, from: nil).y - 48) / 32).rounded()))
    }
}
