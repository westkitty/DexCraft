import Foundation

enum DiffKind: Equatable {
    case unchanged
    case added
    case removed
}

struct DiffLine: Equatable {
    let text: String
    let kind: DiffKind
}

struct TextDiffEngine {
    func diff(old: String, new: String) -> [DiffLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        let oldCount = oldLines.count
        let newCount = newLines.count

        // LCS table over suffixes: lcs[i][j] = LCS length of old[i...] and new[j...].
        var lcs = Array(
            repeating: Array(repeating: 0, count: newCount + 1),
            count: oldCount + 1
        )

        if oldCount > 0, newCount > 0 {
            for i in stride(from: oldCount - 1, through: 0, by: -1) {
                for j in stride(from: newCount - 1, through: 0, by: -1) {
                    if oldLines[i] == newLines[j] {
                        lcs[i][j] = lcs[i + 1][j + 1] + 1
                    } else {
                        lcs[i][j] = max(lcs[i + 1][j], lcs[i][j + 1])
                    }
                }
            }
        }

        var results: [DiffLine] = []
        results.reserveCapacity(oldCount + newCount)

        var i = 0
        var j = 0

        while i < oldCount, j < newCount {
            if oldLines[i] == newLines[j] {
                results.append(DiffLine(text: oldLines[i], kind: .unchanged))
                i += 1
                j += 1
                continue
            }

            let removeScore = lcs[i + 1][j]
            let addScore = lcs[i][j + 1]

            // Deterministic tie-breaker: prefer removals before additions.
            if removeScore >= addScore {
                results.append(DiffLine(text: oldLines[i], kind: .removed))
                i += 1
            } else {
                results.append(DiffLine(text: newLines[j], kind: .added))
                j += 1
            }
        }

        while i < oldCount {
            results.append(DiffLine(text: oldLines[i], kind: .removed))
            i += 1
        }

        while j < newCount {
            results.append(DiffLine(text: newLines[j], kind: .added))
            j += 1
        }

        return results
    }
}
