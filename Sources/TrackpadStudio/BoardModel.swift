import AppKit

/// Drawing tools only, in sidebar order. Text is a one-shot action (`t`), not
/// a mode — committing text must leave the active tool untouched.
enum BoardTool: CaseIterable {
    case pen
    case eraser
    case line
    case rectangle
    case ellipse
    case arrow

    var name: String {
        switch self {
        case .pen: return "Pen"
        case .eraser: return "Eraser"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .arrow: return "Arrow"
        }
    }

    var statusName: String {
        name.lowercased()
    }

    /// Optional keyboard shortcut. The numbers predate the eraser and keep
    /// their old meaning.
    var shortcut: String {
        switch self {
        case .pen: return "1"
        case .line: return "2"
        case .rectangle: return "3"
        case .ellipse: return "4"
        case .arrow: return "5"
        case .eraser: return "e"
        }
    }

    static func forShortcut(_ key: String) -> BoardTool? {
        allCases.first { $0.shortcut == key }
    }
}

struct BoardStrokeSample {
    let point: CGPoint
    let width: CGFloat
}

enum BoardElement {
    case stroke(samples: [BoardStrokeSample], color: NSColor)
    case line(start: CGPoint, end: CGPoint, width: CGFloat, color: NSColor)
    case rectangle(rect: CGRect, width: CGFloat, color: NSColor)
    case ellipse(rect: CGRect, width: CGFloat, color: NSColor)
    case arrow(start: CGPoint, end: CGPoint, width: CGFloat, color: NSColor)
    case text(origin: CGPoint, string: String, fontSize: CGFloat, color: NSColor)
    case image(rect: CGRect, image: NSImage)
}

final class BoardModel {
    static let minimumZoom: CGFloat = 0.2
    static let maximumZoom: CGFloat = 8.0

    private static let panLimit: CGFloat = 1_000_000

    private(set) var elements: [BoardElement] = []
    private(set) var zoom: CGFloat = 1
    private(set) var pan: CGPoint = .zero
    private(set) var hasCreatedContent = false

    func canvasToView(_ point: CGPoint, in viewBounds: CGRect) -> CGPoint {
        let center = CGPoint(x: viewBounds.midX, y: viewBounds.midY)
        return CGPoint(
            x: center.x + (point.x - center.x) * zoom + pan.x,
            y: center.y + (point.y - center.y) * zoom + pan.y
        )
    }

    func viewToCanvas(_ point: CGPoint, in viewBounds: CGRect) -> CGPoint {
        let center = CGPoint(x: viewBounds.midX, y: viewBounds.midY)
        return CGPoint(
            x: center.x + (point.x - center.x - pan.x) / zoom,
            y: center.y + (point.y - center.y - pan.y) / zoom
        )
    }

    func canvasToView(_ rect: CGRect, in viewBounds: CGRect) -> CGRect {
        let a = canvasToView(rect.origin, in: viewBounds)
        let b = canvasToView(
            CGPoint(x: rect.maxX, y: rect.maxY),
            in: viewBounds
        )
        return CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    /// One undo step. Every mutation of `elements` goes through history, so
    /// undo is always the exact inverse of the most recent step.
    private enum Edit {
        case appended
        /// Original indices, ascending — reinserting in order rebuilds the board.
        case removed([(index: Int, element: BoardElement)])
        case replaced([BoardElement])
    }

    /// An eraser gesture in progress: the board as it was when the gesture
    /// began, and which of those elements the sweep has touched so far.
    private struct EraseSession {
        let original: [BoardElement]
        var removed: Set<Int> = []
    }

    private var history: [Edit] = []
    private var eraseSession: EraseSession?

    var canUndo: Bool { !history.isEmpty || !(eraseSession?.removed.isEmpty ?? true) }
    var isErasing: Bool { eraseSession != nil }

    func append(_ element: BoardElement) {
        commitErase()
        elements.append(element)
        history.append(.appended)
        hasCreatedContent = true
    }

    /// AI redraw: swaps the whole board for one image element as a single
    /// operation — one ⌘Z brings the replaced drawing back.
    func replaceAll(with element: BoardElement) {
        commitErase()
        history.append(.replaced(elements))
        elements = [element]
        hasCreatedContent = true
    }

    /// Undoable. Clearing an empty board records nothing.
    func clear() {
        commitErase()
        guard !elements.isEmpty else { return }
        history.append(.replaced(elements))
        elements.removeAll()
    }

    /// An active erase is itself the current edit. Restore it without also
    /// undoing the edit that came before it.
    @discardableResult
    func undo() -> Bool {
        let cancelledErase = !(eraseSession?.removed.isEmpty ?? true)
        cancelErase()
        if cancelledErase { return true }
        guard let edit = history.popLast() else { return false }
        switch edit {
        case .appended:
            elements.removeLast()
        case let .removed(entries):
            for entry in entries {
                elements.insert(entry.element, at: min(entry.index, elements.count))
            }
        case let .replaced(previous):
            elements = previous
        }
        return true
    }

    // MARK: Eraser

    /// Removes every element the eraser touches while sweeping from `start`
    /// to `end` (canvas space, `radius` in canvas units). The whole sweep
    /// segment is tested, so a fast move cannot skip over a thin stroke.
    /// The first call opens a gesture; nothing is recorded until
    /// `commitErase()`.
    @discardableResult
    func erase(from start: CGPoint, to end: CGPoint, radius: CGFloat) -> Bool {
        var session = eraseSession ?? EraseSession(original: elements)
        var changed = false
        for index in session.original.indices
            where !session.removed.contains(index)
            && Self.sweep(from: start, to: end, radius: radius,
                          touches: session.original[index]) {
            session.removed.insert(index)
            changed = true
        }
        eraseSession = session
        if changed {
            elements = session.original.enumerated()
                .filter { !session.removed.contains($0.offset) }
                .map(\.element)
        }
        return changed
    }

    /// Ends the gesture as ONE undo step. Erasing only empty board records
    /// nothing.
    func commitErase() {
        guard let session = eraseSession else { return }
        eraseSession = nil
        guard !session.removed.isEmpty else { return }
        history.append(.removed(
            session.removed.sorted().map { ($0, session.original[$0]) }
        ))
    }

    /// Abandons the gesture and puts back everything it removed.
    func cancelErase() {
        guard let session = eraseSession else { return }
        eraseSession = nil
        elements = session.original
    }

    /// Applies a scale step while keeping the canvas point under the view center fixed.
    func zoom(by factor: CGFloat, in viewBounds: CGRect) {
        guard factor.isFinite, factor > 0 else { return }

        let viewCenter = CGPoint(x: viewBounds.midX, y: viewBounds.midY)
        let anchoredCanvasPoint = viewToCanvas(viewCenter, in: viewBounds)
        let requestedZoom = zoom * factor
        zoom = min(Self.maximumZoom, max(Self.minimumZoom, requestedZoom))

        pan = clampedPan(
            CGPoint(
                x: -(anchoredCanvasPoint.x - viewCenter.x) * zoom,
                y: -(anchoredCanvasPoint.y - viewCenter.y) * zoom
            )
        )
    }

    /// Simultaneous zoom + pan: scales by `factor`, then translates so `anchor`
    /// (a canvas point) lands exactly on `viewPoint`. Because the pan is derived
    /// from the post-clamp zoom, a clamped zoom cannot accumulate drift.
    func navigate(
        scale factor: CGFloat,
        anchor: CGPoint,
        to viewPoint: CGPoint,
        in viewBounds: CGRect
    ) {
        guard factor.isFinite, factor > 0,
              anchor.x.isFinite, anchor.y.isFinite,
              viewPoint.x.isFinite, viewPoint.y.isFinite else { return }

        zoom = min(Self.maximumZoom, max(Self.minimumZoom, zoom * factor))

        let center = CGPoint(x: viewBounds.midX, y: viewBounds.midY)
        pan = clampedPan(
            CGPoint(
                x: viewPoint.x - center.x - (anchor.x - center.x) * zoom,
                y: viewPoint.y - center.y - (anchor.y - center.y) * zoom
            )
        )
    }

    func pan(by delta: CGPoint) {
        guard delta.x.isFinite, delta.y.isFinite else { return }
        pan = clampedPan(
            CGPoint(x: pan.x + delta.x, y: pan.y + delta.y)
        )
    }

    /// Topmost element under `canvasPoint`, using the same drawn-geometry
    /// rules as the eraser.
    func hitTest(_ canvasPoint: CGPoint, tolerance: CGFloat = 6) -> Int? {
        elements.indices.reversed().first {
            Self.sweep(from: canvasPoint, to: canvasPoint,
                       radius: tolerance, touches: elements[$0])
        }
    }

    private func clampedPan(_ proposed: CGPoint) -> CGPoint {
        CGPoint(
            x: min(Self.panLimit, max(-Self.panLimit, proposed.x)),
            y: min(Self.panLimit, max(-Self.panLimit, proposed.y))
        )
    }

    /// Whether a round eraser of `radius`, swept along start→end, touches
    /// what the element actually draws. Strokes, lines, arrows and shape
    /// OUTLINES count; the empty inside of a rectangle or ellipse does not.
    /// Text and images are solid boxes.
    static func sweep(
        from start: CGPoint,
        to end: CGPoint,
        radius: CGFloat,
        touches element: BoardElement
    ) -> Bool {
        let radius = max(0, radius)

        func near(_ path: [CGPoint], halfWidth: CGFloat) -> Bool {
            let reach = radius + max(0, halfWidth)
            guard let first = path.first else { return false }
            guard path.count > 1 else {
                return distanceFromSegment(first, start: start, end: end) <= reach
            }
            return zip(path, path.dropFirst()).contains {
                segmentDistance(start, end, $0.0, $0.1) <= reach
            }
        }

        switch element {
        case let .stroke(samples, _):
            guard let first = samples.first else { return false }
            if samples.count == 1 {
                return near([first.point], halfWidth: first.width / 2)
            }
            return zip(samples, samples.dropFirst()).contains { pair in
                near([pair.0.point, pair.1.point],
                     halfWidth: max(pair.0.width, pair.1.width) / 2)
            }

        case let .line(a, b, width, _):
            return near([a, b], halfWidth: width / 2)

        case let .arrow(a, b, width, _):
            // Same head geometry as the renderer, in canvas units.
            let length = distance(a, b)
            var parts = [[a, b]]
            if length > .ulpOfOne {
                let angle = atan2(b.y - a.y, b.x - a.x)
                let head = min(14, length * 0.45)
                for spread in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                    parts.append([b, CGPoint(
                        x: b.x - cos(angle + spread) * head,
                        y: b.y - sin(angle + spread) * head
                    )])
                }
            }
            return parts.contains { near($0, halfWidth: width / 2) }

        case let .rectangle(rect, width, _):
            return near(outline(of: rect.standardized), halfWidth: width / 2)

        case let .ellipse(rect, width, _):
            return near(ellipseOutline(in: rect.standardized), halfWidth: width / 2)

        case let .text(origin, string, fontSize, _):
            let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
            let size = (string as NSString).size(withAttributes: [.font: font])
            return sweep(from: start, to: end, radius: radius,
                         touchesSolid: CGRect(origin: origin, size: size))

        case let .image(rect, _):
            return sweep(from: start, to: end, radius: radius,
                         touchesSolid: rect.standardized)
        }
    }

    private static func sweep(
        from start: CGPoint,
        to end: CGPoint,
        radius: CGFloat,
        touchesSolid rect: CGRect
    ) -> Bool {
        if rect.contains(start) || rect.contains(end) { return true }
        let edges = outline(of: rect)
        return zip(edges, edges.dropFirst()).contains {
            segmentDistance(start, end, $0.0, $0.1) <= radius
        }
    }

    /// Closed polyline around a rectangle.
    private static func outline(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY),
        ]
    }

    /// Closed polygon close enough to the drawn oval: ~4 canvas units per
    /// side, so the chord error stays well under a line width.
    private static func ellipseOutline(in rect: CGRect) -> [CGPoint] {
        let rx = rect.width / 2
        let ry = rect.height / 2
        let perimeter = 2 * CGFloat.pi * max(rx, ry)
        let count = max(24, min(720, Int((perimeter / 4).rounded(.up))))
        return (0...count).map { i in
            let t = CGFloat(i) / CGFloat(count) * 2 * .pi
            return CGPoint(x: rect.midX + cos(t) * rx, y: rect.midY + sin(t) * ry)
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Shortest distance between segments p1–p2 and q1–q2 (0 if they cross).
    static func segmentDistance(
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ q1: CGPoint,
        _ q2: CGPoint
    ) -> CGFloat {
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        let d1 = cross(q1, q2, p1)
        let d2 = cross(q1, q2, p2)
        let d3 = cross(p1, p2, q1)
        let d4 = cross(p1, p2, q2)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)),
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return 0
        }
        return min(
            min(distanceFromSegment(p1, start: q1, end: q2),
                distanceFromSegment(p2, start: q1, end: q2)),
            min(distanceFromSegment(q1, start: p1, end: p2),
                distanceFromSegment(q2, start: p1, end: p2))
        )
    }

    private static func distanceFromSegment(
        _ point: CGPoint,
        start: CGPoint,
        end: CGPoint
    ) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > .ulpOfOne else { return distance(point, start) }

        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy)
            / lengthSquared
        let t = min(1, max(0, projection))
        let nearest = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return distance(point, nearest)
    }
}
