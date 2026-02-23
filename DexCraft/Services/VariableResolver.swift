import Foundation

struct VariableResolutionResult: Equatable {
    let detected: [String]
    let resolvedText: String
    let unfilled: [String]
}

final class VariableResolver {
    private let variableRegex = try! NSRegularExpression(pattern: #"\{([A-Za-z_][A-Za-z0-9_]*)\}"#)

    func detect(in text: String) -> [String] {
        let matches = variableRegex.matches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )

        var ordered: [String] = []
        var seen = Set<String>()

        for match in matches {
            guard
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: text)
            else {
                continue
            }

            let name = String(text[range])
            if seen.insert(name).inserted {
                ordered.append(name)
            }
        }

        return ordered
    }

    func resolve(text: String, values: [String: String]) -> VariableResolutionResult {
        let matches = variableRegex.matches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )

        var detected: [String] = []
        var detectedSet = Set<String>()
        var unfilled: [String] = []
        var unfilledSet = Set<String>()
        var resolved = ""
        var cursor = text.startIndex

        for match in matches {
            guard
                match.numberOfRanges > 1,
                let tokenRange = Range(match.range, in: text),
                let nameRange = Range(match.range(at: 1), in: text)
            else {
                continue
            }

            resolved += String(text[cursor..<tokenRange.lowerBound])
            let name = String(text[nameRange])

            if detectedSet.insert(name).inserted {
                detected.append(name)
            }

            if let value = values[name] {
                resolved += value
            } else {
                resolved += String(text[tokenRange])
                if unfilledSet.insert(name).inserted {
                    unfilled.append(name)
                }
            }

            cursor = tokenRange.upperBound
        }

        resolved += String(text[cursor...])

        return VariableResolutionResult(
            detected: detected,
            resolvedText: resolved,
            unfilled: unfilled
        )
    }
}
