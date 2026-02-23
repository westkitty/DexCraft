import XCTest

final class StructuredPreviewBuilderTests: XCTestCase {
    func testPlainTextOutput() {
        let draft = Draft(
            goal: "A",
            context: "B",
            constraints: ["C1", "C2"],
            deliverables: ["D1"]
        )

        let preview = buildPreview(draft: draft, format: .plainText)

        XCTAssertEqual(
            preview,
            """
            Goal:
            A

            Context:
            B

            Constraints:
            - C1
            - C2

            Deliverables:
            - D1
            """
        )
    }

    func testJSONDeterministicKeys() throws {
        struct JSONPreviewPayload: Codable, Equatable {
            let goal: String
            let context: String
            let constraints: [String]
            let deliverables: [String]
        }

        let draft = Draft(
            goal: "A",
            context: "B",
            constraints: ["C1", "C2"],
            deliverables: ["D1"]
        )

        let preview = buildPreview(draft: draft, format: .json)
        let data = try XCTUnwrap(preview.data(using: .utf8))
        let decoded = try JSONDecoder().decode(JSONPreviewPayload.self, from: data)

        XCTAssertEqual(
            decoded,
            JSONPreviewPayload(
                goal: "A",
                context: "B",
                constraints: ["C1", "C2"],
                deliverables: ["D1"]
            )
        )
    }

    func testMarkdownHeadings() {
        let draft = Draft(
            goal: "A",
            context: "B",
            constraints: ["C1"],
            deliverables: ["D1"]
        )

        let preview = buildPreview(draft: draft, format: .markdown)

        XCTAssertTrue(preview.contains("## Goal"))
        XCTAssertTrue(preview.contains("## Constraints"))
        XCTAssertTrue(preview.contains("- C1"))
    }

    func testPreviewTrimsAndDropsEmptyListItems() throws {
        let draft = Draft(
            goal: " A ",
            context: " B ",
            constraints: ["  C1  ", "", "   "],
            deliverables: ["  D1  ", "  "]
        )

        let plainText = buildPreview(draft: draft, format: .plainText)
        XCTAssertTrue(plainText.contains("- C1"))
        XCTAssertFalse(plainText.contains("- C1 "))
        XCTAssertFalse(plainText.contains("\n- \n"))

        struct JSONPreviewPayload: Codable, Equatable {
            let goal: String
            let context: String
            let constraints: [String]
            let deliverables: [String]
        }

        let json = buildPreview(draft: draft, format: .json)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(JSONPreviewPayload.self, from: data)
        XCTAssertEqual(decoded.constraints, ["C1"])
        XCTAssertEqual(decoded.deliverables, ["D1"])
    }
}
