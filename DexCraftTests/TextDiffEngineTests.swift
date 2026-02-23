import XCTest

final class TextDiffEngineTests: XCTestCase {
    private let engine = TextDiffEngine()

    func testIdentical() {
        let old = "a\nb\nc"
        let new = "a\nb\nc"

        let diff = engine.diff(old: old, new: new)

        XCTAssertEqual(
            diff,
            [
                DiffLine(text: "a", kind: .unchanged),
                DiffLine(text: "b", kind: .unchanged),
                DiffLine(text: "c", kind: .unchanged)
            ]
        )
    }

    func testInsertMiddle() {
        let old = "a\nc"
        let new = "a\nb\nc"

        let diff = engine.diff(old: old, new: new)

        XCTAssertEqual(
            diff,
            [
                DiffLine(text: "a", kind: .unchanged),
                DiffLine(text: "b", kind: .added),
                DiffLine(text: "c", kind: .unchanged)
            ]
        )
    }

    func testDeleteMiddle() {
        let old = "a\nb\nc"
        let new = "a\nc"

        let diff = engine.diff(old: old, new: new)

        XCTAssertEqual(
            diff,
            [
                DiffLine(text: "a", kind: .unchanged),
                DiffLine(text: "b", kind: .removed),
                DiffLine(text: "c", kind: .unchanged)
            ]
        )
    }

    func testReplaceLine() {
        let old = "a\nb\nc"
        let new = "a\nB\nc"

        let diff = engine.diff(old: old, new: new)

        XCTAssertEqual(
            diff,
            [
                DiffLine(text: "a", kind: .unchanged),
                DiffLine(text: "b", kind: .removed),
                DiffLine(text: "B", kind: .added),
                DiffLine(text: "c", kind: .unchanged)
            ]
        )
    }

    func testEmptyLinesPreserved() {
        let old = "a\n\nb"
        let new = "a\nb"

        let diff = engine.diff(old: old, new: new)

        XCTAssertEqual(
            diff,
            [
                DiffLine(text: "a", kind: .unchanged),
                DiffLine(text: "", kind: .removed),
                DiffLine(text: "b", kind: .unchanged)
            ]
        )
    }
}
