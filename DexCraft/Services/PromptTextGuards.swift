import Foundation

enum PromptSegment: Equatable {
    case text(String)
    case codeFence(String)
}

enum PromptTextGuards {
    static func splitByCodeFences(_ input: String) -> [PromptSegment] {
        guard !input.isEmpty else {
            return [.text("")]
        }

        let lines = splitLinesKeepingNewlines(input)
        var segments: [PromptSegment] = []
        var textBuffer = ""
        var codeBuffer = ""
        var insideFence = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let startsFence = trimmed.hasPrefix("```")

            if insideFence {
                codeBuffer.append(line)
                if startsFence {
                    segments.append(.codeFence(codeBuffer))
                    codeBuffer = ""
                    insideFence = false
                }
                continue
            }

            if startsFence {
                if !textBuffer.isEmpty {
                    segments.append(.text(textBuffer))
                    textBuffer = ""
                }
                codeBuffer = line
                insideFence = true
            } else {
                textBuffer.append(line)
            }
        }

        if insideFence {
            // Fail-safe: keep unmatched opening fence untouched to end of input.
            segments.append(.codeFence(codeBuffer))
        }

        if !textBuffer.isEmpty {
            segments.append(.text(textBuffer))
        }

        return segments.isEmpty ? [.text(input)] : segments
    }

    static func transformTextSegments(_ segments: [PromptSegment], _ transform: (String) -> String) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text):
                return transform(text)
            case .codeFence(let code):
                return code
            }
        }
        .joined()
    }

    private static func splitLinesKeepingNewlines(_ input: String) -> [String] {
        var lines: [String] = []
        var current = ""

        for character in input {
            current.append(character)
            if character == "\n" {
                lines.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            lines.append(current)
        }

        return lines
    }
}
