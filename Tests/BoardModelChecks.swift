import AppKit

/// Run with: swiftc Sources/TrackpadStudio/BoardModel.swift Tests/BoardModelChecks.swift -o /tmp/board-model-checks && /tmp/board-model-checks
@main
struct BoardModelChecks {
    static func line(_ x: CGFloat) -> BoardElement {
        .line(start: CGPoint(x: x, y: 0), end: CGPoint(x: x, y: 100), width: 2, color: .white)
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func main() {
        let model = BoardModel()
        model.append(line(10))
        model.append(line(30))
        model.append(line(50))
        // A fast sweep crosses two strokes between sample positions.
        model.erase(from: CGPoint(x: 0, y: 40), to: CGPoint(x: 40, y: 40), radius: 2)
        check(model.elements.count == 1, "Fast sweep must hit both crossed strokes")
        model.commitErase()
        model.undo()
        check(model.elements.count == 3, "One undo restores the whole eraser gesture")
        if case let .line(start, _, _, _) = model.elements[1] {
            check(start.x == 30, "Erase undo preserves stacking order")
        } else { preconditionFailure("Wrong element order") }

        model.clear()
        check(model.elements.isEmpty, "Clear empties the board")
        model.undo()
        check(model.elements.count == 3, "Clear must be undoable")
        model.undo()
        check(model.elements.count == 2, "History before clear remains intact")

        model.erase(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 80), radius: 1)
        model.cancelErase()
        check(model.elements.count == 2, "Cancelling erasure restores content")
        model.erase(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 80), radius: 1)
        model.undo()
        check(model.elements.count == 2, "Undo during erase must not remove a previous edit")

        model.erase(from: CGPoint(x: 300, y: 10), to: CGPoint(x: 300, y: 80), radius: 1)
        model.commitErase()
        model.undo()
        check(model.elements.count == 1, "Empty erasure must not add an undo step")

        let box = BoardElement.rectangle(rect: CGRect(x: 0, y: 0, width: 100, height: 100), width: 2, color: .white)
        let oval = BoardElement.ellipse(rect: CGRect(x: 0, y: 0, width: 100, height: 100), width: 2, color: .white)
        let center = CGPoint(x: 50, y: 50)
        for shape in [box, oval] {
            check(!BoardModel.sweep(from: center, to: center, radius: 10, touches: shape), "Empty shape interior must not erase its outline")
            check(BoardModel.sweep(from: CGPoint(x: -20, y: 50), to: center, radius: 2, touches: shape), "Sweep across an outline must erase it")
        }
        let arrow = BoardElement.arrow(start: .zero, end: CGPoint(x: 100, y: 0), width: 2, color: .white)
        let headPoint = CGPoint(x: 88, y: 7)
        check(BoardModel.sweep(from: headPoint, to: headPoint, radius: 1, touches: arrow), "Arrowhead geometry must erase too")
        check(BoardModel.segmentDistance(CGPoint(x: 0, y: 5), CGPoint(x: 10, y: 5), CGPoint(x: 5, y: 0), CGPoint(x: 5, y: 10)) == 0, "Crossing segments must intersect")

        let originalCount = model.elements.count
        model.replaceAll(with: .image(rect: CGRect(x: 0, y: 0, width: 100, height: 100), image: NSImage(size: NSSize(width: 100, height: 100))))
        model.clear()
        model.undo()
        model.undo()
        check(model.elements.count == originalCount, "Replace and clear history compose correctly")

        let viewport = CGRect(x: 0, y: 0, width: 900, height: 600)
        model.zoom(by: 4, in: viewport)
        model.pan(by: CGPoint(x: 100, y: -40))
        let viewPoint = model.canvasToView(center, in: viewport)
        let back = model.viewToCanvas(viewPoint, in: viewport)
        check(hypot(back.x - center.x, back.y - center.y) < 0.001, "Eraser coordinates must round-trip at zoom and pan")
        // A 10 screen-point eraser reaches 2.5 canvas points at 4x zoom.
        let near = CGPoint(x: 13, y: 40)
        check(BoardModel.sweep(from: near, to: near, radius: 10 / model.zoom, touches: line(10)), "Zoom-scaled eraser reach includes stroke thickness")
        let far = CGPoint(x: 15, y: 40)
        check(!BoardModel.sweep(from: far, to: far, radius: 10 / model.zoom, touches: line(10)), "Eraser must not expand incorrectly when zoomed")
        print("Board model checks passed: erase sweeps, outline geometry, cancellation, history, clear, replace, zoom and pan.")
    }
}
