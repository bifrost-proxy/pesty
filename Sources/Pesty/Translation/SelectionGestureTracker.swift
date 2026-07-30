import AppKit

struct SelectionGestureEndpoint: Equatable {
    let point: NSPoint
    let occurredAt: Date
    let sourceBundleIdentifier: String?
    let dragDistance: CGFloat
    let clickCount: Int
    let usedShiftModifier: Bool

    var isLikelyTextSelection: Bool {
        dragDistance >= 4
            || clickCount >= 2
            || usedShiftModifier
    }
}

@MainActor
final class SelectionGestureTracker {
    static let shared = SelectionGestureTracker()

    static let maximumAnchorAge: TimeInterval = 5
    static let minimumSelectionDragDistance: CGFloat = 4

    private var globalMonitor: Any?
    private var mouseDownPoint: NSPoint?
    private var mouseDownBundleIdentifier: String?
    private var mouseDownClickCount = 0
    private var maximumDragDistance: CGFloat = 0
    private var usedShiftModifier = false
    private(set) var latestEndpoint: SelectionGestureEndpoint?

    private init() {}

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { event in
            Task { @MainActor in
                self.consume(
                    event,
                    point: NSEvent.mouseLocation,
                    sourceBundleIdentifier:
                        NSWorkspace.shared.frontmostApplication?
                            .bundleIdentifier,
                    occurredAt: Date()
                )
            }
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        resetActiveGesture()
    }

    func bestAnchorPoint(
        for sourceBundleIdentifier: String?,
        now: Date = Date()
    ) -> NSPoint? {
        guard let endpoint = latestEndpoint,
              endpoint.isLikelyTextSelection,
              now.timeIntervalSince(endpoint.occurredAt) >= 0,
              now.timeIntervalSince(endpoint.occurredAt) <= Self.maximumAnchorAge,
              endpoint.sourceBundleIdentifier == sourceBundleIdentifier else {
            return nil
        }
        return endpoint.point
    }

    func recordMouseDown(
        at point: NSPoint,
        sourceBundleIdentifier: String?,
        clickCount: Int = 1,
        shiftPressed: Bool = false
    ) {
        mouseDownPoint = point
        mouseDownBundleIdentifier = sourceBundleIdentifier
        mouseDownClickCount = clickCount
        maximumDragDistance = 0
        usedShiftModifier = shiftPressed
    }

    func recordMouseDragged(
        to point: NSPoint,
        shiftPressed: Bool = false
    ) {
        guard let mouseDownPoint else { return }
        maximumDragDistance = max(
            maximumDragDistance,
            hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
        )
        usedShiftModifier = usedShiftModifier || shiftPressed
    }

    func recordMouseUp(
        at point: NSPoint,
        sourceBundleIdentifier: String?,
        clickCount: Int = 1,
        shiftPressed: Bool = false,
        occurredAt: Date = Date()
    ) {
        guard let mouseDownPoint else { return }
        let finalDistance = hypot(
            point.x - mouseDownPoint.x,
            point.y - mouseDownPoint.y
        )
        latestEndpoint = SelectionGestureEndpoint(
            point: point,
            occurredAt: occurredAt,
            sourceBundleIdentifier:
                mouseDownBundleIdentifier ?? sourceBundleIdentifier,
            dragDistance: max(maximumDragDistance, finalDistance),
            clickCount: max(mouseDownClickCount, clickCount),
            usedShiftModifier: usedShiftModifier || shiftPressed
        )
        resetActiveGesture()
    }

    private func consume(
        _ event: NSEvent,
        point: NSPoint,
        sourceBundleIdentifier: String?,
        occurredAt: Date
    ) {
        let shiftPressed = event.modifierFlags.contains(.shift)
        switch event.type {
        case .leftMouseDown:
            recordMouseDown(
                at: point,
                sourceBundleIdentifier: sourceBundleIdentifier,
                clickCount: event.clickCount,
                shiftPressed: shiftPressed
            )
        case .leftMouseDragged:
            recordMouseDragged(
                to: point,
                shiftPressed: shiftPressed
            )
        case .leftMouseUp:
            recordMouseUp(
                at: point,
                sourceBundleIdentifier: sourceBundleIdentifier,
                clickCount: event.clickCount,
                shiftPressed: shiftPressed,
                occurredAt: occurredAt
            )
        default:
            break
        }
    }

    private func resetActiveGesture() {
        mouseDownPoint = nil
        mouseDownBundleIdentifier = nil
        mouseDownClickCount = 0
        maximumDragDistance = 0
        usedShiftModifier = false
    }
}
