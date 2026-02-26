import XCTest

final class VariableResolverTests: XCTestCase {
    private let resolver = VariableResolver()

    func testDetectOrderAndUniqueness() {
        let text = "Hello {name}. Order {order_id}. Thanks {name}."

        let detected = resolver.detect(in: text)

        XCTAssertEqual(detected, ["name", "order_id"])
    }

    func testSubstitute() {
        let text = "Hello {name}. Order {order_id}. Thanks {name}."

        let result = resolver.resolve(
            text: text,
            values: [
                "name": "Ada",
                "order_id": "123"
            ]
        )

        XCTAssertEqual(result.resolvedText, "Hello Ada. Order 123. Thanks Ada.")
        XCTAssertEqual(result.unfilled, [])
    }

    func testMissingVariableLeavesToken() {
        let text = "Hello {name}. Order {order_id}. Thanks {name}."

        let result = resolver.resolve(
            text: text,
            values: ["name": "Ada"]
        )

        XCTAssertEqual(result.resolvedText, "Hello Ada. Order {order_id}. Thanks Ada.")
        XCTAssertEqual(result.unfilled, ["order_id"])
    }

    func testAdjacentTokens() {
        let text = "{a}{b}{a}"

        let result = resolver.resolve(
            text: text,
            values: [
                "a": "X",
                "b": "Y"
            ]
        )

        XCTAssertEqual(result.resolvedText, "XYX")
        XCTAssertEqual(result.detected, ["a", "b"])
    }

    func testDetectSupportsDashesAndNumbers() {
        let text = "{user_name} {project-id} {A_B-C} {2fa-token}"

        let detected = resolver.detect(in: text)

        XCTAssertEqual(detected, ["user_name", "project-id", "A_B-C", "2fa-token"])
    }

    func testBlankAndWhitespaceValuesRemainUnfilled() {
        let text = "Do X for {client} and {date} and {time}"

        let result = resolver.resolve(
            text: text,
            values: [
                "client": "Acme",
                "date": "",
                "time": "   "
            ]
        )

        XCTAssertEqual(result.resolvedText, "Do X for Acme and {date} and {time}")
        XCTAssertEqual(result.unfilled, ["date", "time"])
    }
}
