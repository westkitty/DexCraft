import Foundation
import NaturalLanguage

struct HeuristicScoringWeights: Codable, Equatable {
    var outputFormat: Int
    var deliverables: Int
    var constraints: Int
    var successCriteria: Int
    var scopeBounds: Int
    var questions: Int
    var examplesPerUnit: Int
    var tokenPenaltyBase: Int
    var contradictionPenalty: Int
    var unresolvedPlaceholderPenalty: Int
    var domainPackBonus: Int
    var qualityGateBonus: Int

    static let defaults = HeuristicScoringWeights(
        outputFormat: 20,
        deliverables: 15,
        constraints: 10,
        successCriteria: 10,
        scopeBounds: 8,
        questions: 5,
        examplesPerUnit: 5,
        tokenPenaltyBase: -8,
        contradictionPenalty: -8,
        unresolvedPlaceholderPenalty: -6,
        domainPackBonus: 7,
        qualityGateBonus: 8
    )

    func clamped() -> HeuristicScoringWeights {
        HeuristicScoringWeights(
            outputFormat: clamp(outputFormat, min: 5, max: 30),
            deliverables: clamp(deliverables, min: 5, max: 28),
            constraints: clamp(constraints, min: 4, max: 22),
            successCriteria: clamp(successCriteria, min: 4, max: 22),
            scopeBounds: clamp(scopeBounds, min: 3, max: 16),
            questions: clamp(questions, min: 0, max: 16),
            examplesPerUnit: clamp(examplesPerUnit, min: 0, max: 10),
            tokenPenaltyBase: clamp(tokenPenaltyBase, min: -22, max: -2),
            contradictionPenalty: clamp(contradictionPenalty, min: -24, max: -4),
            unresolvedPlaceholderPenalty: clamp(unresolvedPlaceholderPenalty, min: -14, max: -2),
            domainPackBonus: clamp(domainPackBonus, min: 0, max: 16),
            qualityGateBonus: clamp(qualityGateBonus, min: 0, max: 18)
        )
    }

    var signature: String {
        [
            outputFormat,
            deliverables,
            constraints,
            successCriteria,
            scopeBounds,
            questions,
            examplesPerUnit,
            tokenPenaltyBase,
            contradictionPenalty,
            unresolvedPlaceholderPenalty,
            domainPackBonus,
            qualityGateBonus
        ]
        .map(String.init)
        .joined(separator: ":")
    }

    private func clamp(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}

struct HeuristicOptimizationContext {
    let target: PromptTarget
    let scenario: ScenarioProfile
    let historyPrompts: [String]
    let localWeights: HeuristicScoringWeights?

    init(
        target: PromptTarget = .claude,
        scenario: ScenarioProfile = .generalAssistant,
        historyPrompts: [String] = [],
        localWeights: HeuristicScoringWeights? = nil
    ) {
        self.target = target
        self.scenario = scenario
        self.historyPrompts = historyPrompts
        self.localWeights = localWeights
    }
}

struct HeuristicOptimizationResult {
    let optimizedText: String
    let selectedCandidateTitle: String
    let score: Int
    let breakdown: [String: Int]
    let warnings: [String]
    let tunedWeights: HeuristicScoringWeights?
}

enum HeuristicPromptOptimizer {
    private static let maxCandidateCount = 16
    private static let resultCache = OptimizationCache(capacity: 64)

    private struct Candidate {
        let title: String
        let text: String
        let transforms: [TransformKey]
    }

    private enum TransformKey: String {
        case canonicalize = "Canonicalize headings/order"
        case contradictionRepair = "Repair contradictions"
        case sentenceRewrite = "Sentence-level rewrite"
        case deliverablesInference = "Infer deliverables"
        case outputFormat = "Add output format"
        case successCriteria = "Add success criteria"
        case scopeBounds = "Add scope bounds"
        case questions = "Add clarifying questions"
        case domainPack = "Apply domain pack"
        case qualityGate = "Apply quality gate"
        case dedupe = "Dedupe/normalize whitespace"
    }

    private enum SectionKey: Int, CaseIterable {
        case goal
        case context
        case constraints
        case deliverables
        case outputFormat
        case questions
        case successCriteria

        var headingTitle: String {
            switch self {
            case .goal: return "Goal"
            case .context: return "Context"
            case .constraints: return "Constraints"
            case .deliverables: return "Deliverables"
            case .outputFormat: return "Output Format"
            case .questions: return "Questions"
            case .successCriteria: return "Success Criteria"
            }
        }
    }

    private struct HeadingBlock {
        let title: String
        let key: SectionKey?
        var body: [String]
    }

    private struct ScoreResult {
        let score: Int
        let breakdown: [String: Int]
        let warnings: [String]
    }

    private struct GapProfile {
        let needsCanonicalization: Bool
        let needsContradictionRepair: Bool
        let needsSentenceRewrite: Bool
        let needsDeliverables: Bool
        let needsOutputFormat: Bool
        let needsSuccessCriteria: Bool
        let needsScopeBounds: Bool
        let needsQuestions: Bool
        let needsDomainPack: Bool
        let needsQualityGate: Bool
        let needsDedupe: Bool

        var hasAnyGap: Bool {
            needsCanonicalization ||
                needsContradictionRepair ||
                needsSentenceRewrite ||
                needsDeliverables ||
                needsOutputFormat ||
                needsSuccessCriteria ||
                needsScopeBounds ||
                needsQuestions ||
                needsDomainPack ||
                needsQualityGate ||
                needsDedupe
        }
    }

    private enum PromptIntent {
        case creativeStory
        case gameDesign
        case softwareBuild
        case general
    }

    private struct StructuralDelta {
        let gain: Int
        let growthRatio: Double
        let meaningful: Bool
    }

    private struct DomainPolicy {
        let requiredKeywords: [String]
        let requiredSectionsForAmbiguity: [SectionKey]
        let supplementalSections: [(title: String, body: [String])]
    }

    private enum WeightSource {
        case defaults
        case local
        case learned
    }

    private struct WeightResolution {
        let weights: HeuristicScoringWeights
        let source: WeightSource
    }

    private final class OptimizationCache {
        private let capacity: Int
        private let lock = NSLock()
        private var values: [String: HeuristicOptimizationResult] = [:]
        private var order: [String] = []

        init(capacity: Int) {
            self.capacity = max(4, capacity)
        }

        func value(for key: String) -> HeuristicOptimizationResult? {
            lock.lock()
            defer { lock.unlock() }
            guard let value = values[key] else { return nil }
            if let index = order.firstIndex(of: key) {
                order.remove(at: index)
                order.append(key)
            }
            return value
        }

        func insert(_ value: HeuristicOptimizationResult, for key: String) {
            lock.lock()
            defer { lock.unlock() }

            if values[key] != nil {
                values[key] = value
                if let index = order.firstIndex(of: key) {
                    order.remove(at: index)
                }
                order.append(key)
                return
            }

            values[key] = value
            order.append(key)

            while order.count > capacity {
                let evicted = order.removeFirst()
                values.removeValue(forKey: evicted)
            }
        }
    }

    private enum RegexBank {
        static let headingPrefix = try! NSRegularExpression(pattern: #"^#{1,6}\s*"#, options: [])
        static let leadingBullet = try! NSRegularExpression(pattern: #"^\s*(?:\d+\.|[-*])\s+"#, options: [])
        static let trailingWhitespace = try! NSRegularExpression(pattern: #"\s+$"#, options: [])
        static let internalWhitespace = try! NSRegularExpression(pattern: #"[ \t]{2,}"#, options: [])
        static let normalizedWhitespace = try! NSRegularExpression(pattern: #"\s+"#, options: [])
        static let actionObject = try! NSRegularExpression(
            pattern: #"\b(fix|implement|refactor|write|create|update|remove|migrate|optimize|document|test|benchmark|deploy|analyze|summarize|research|design|build)\b\s+([^\n\.,;:]{2,120})"#,
            options: [.caseInsensitive]
        )
        static let aboutSubject = try! NSRegularExpression(
            pattern: #"\babout\s+([^\n\.,;:]{2,120})"#,
            options: [.caseInsensitive]
        )
        static let whereTheme = try! NSRegularExpression(
            pattern: #"\bwhere\s+([^\n\.;:]{2,140})"#,
            options: [.caseInsensitive]
        )

        static let sentenceReplacements: [(regex: NSRegularExpression, replacement: String)] = [
            (try! NSRegularExpression(pattern: #"(?<!\w)could you(?!\w)"#, options: [.caseInsensitive]), ""),
            (try! NSRegularExpression(pattern: #"(?<!\w)can you(?!\w)"#, options: [.caseInsensitive]), ""),
            (try! NSRegularExpression(pattern: #"(?<!\w)please(?!\w)"#, options: [.caseInsensitive]), ""),
            (try! NSRegularExpression(pattern: #"(?<!\w)try to(?!\w)"#, options: [.caseInsensitive]), ""),
            (try! NSRegularExpression(pattern: #"(?<!\w)if possible(?!\w)"#, options: [.caseInsensitive]), "when required"),
            (try! NSRegularExpression(pattern: #"(?<!\w)maybe(?!\w)"#, options: [.caseInsensitive]), ""),
            (try! NSRegularExpression(pattern: #"(?<!\w)possibly(?!\w)"#, options: [.caseInsensitive]), ""),
            (try! NSRegularExpression(pattern: #"(?<!\w)ideally(?!\w)"#, options: [.caseInsensitive]), "required"),
            (try! NSRegularExpression(pattern: #"(?<!\w)might(?!\w)"#, options: [.caseInsensitive]), "must"),
            (try! NSRegularExpression(pattern: #"(?<!\w)should probably(?!\w)"#, options: [.caseInsensitive]), "must"),
            (try! NSRegularExpression(pattern: #"(?<!\w)best effort(?!\w)"#, options: [.caseInsensitive]), "strictly follow requirements"),
            (try! NSRegularExpression(pattern: #"(?<!\w)as needed(?!\w)"#, options: [.caseInsensitive]), "when required"),
            (try! NSRegularExpression(pattern: #"(?<!\w)and so on(?!\w)"#, options: [.caseInsensitive]), "with explicit items only"),
            (try! NSRegularExpression(pattern: #"(?<!\w)etc\.?"#, options: [.caseInsensitive]), "with explicit items only")
        ]

        static let contradictionReplacements: [(regex: NSRegularExpression, replacement: String)] = [
            (try! NSRegularExpression(pattern: #"(?<!\w)(search online|browse the web|web research|internet research)(?!\w)"#, options: [.caseInsensitive]), "use provided/local sources only"),
            (try! NSRegularExpression(pattern: #"(?<!\w)(exhaustive|comprehensive|in its entirety|full detail)(?!\w)"#, options: [.caseInsensitive]), "scope-complete"),
            (try! NSRegularExpression(pattern: #"(?<!\w)(write code|implement|patch)(?!\w)"#, options: [.caseInsensitive]), "provide a non-code implementation plan")
        ]
    }

    static func optimize(_ baselinePrompt: String) -> HeuristicOptimizationResult {
        optimize(baselinePrompt, context: HeuristicOptimizationContext())
    }

    static func optimize(_ baselinePrompt: String, context: HeuristicOptimizationContext) -> HeuristicOptimizationResult {
        let baseline = baselinePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = baseline.isEmpty ? baselinePrompt : baseline
        let originalFenceCount = PromptTextGuards.splitByCodeFences(input).reduce(into: 0) { result, segment in
            if case .codeFence = segment { result += 1 }
        }

        if input.isEmpty {
            return HeuristicOptimizationResult(
                optimizedText: input,
                selectedCandidateTitle: "0 Baseline",
                score: 0,
                breakdown: [:],
                warnings: [],
                tunedWeights: nil
            )
        }

        let weightResolution = resolveWeights(for: context)
        let weights = weightResolution.weights.clamped()
        let cacheKey = buildCacheKey(input: input, context: context, weights: weights)

        if let cached = resultCache.value(for: cacheKey) {
            return cached
        }

        let baselineAnalysis = PromptHeuristics.analyze(input, originalCodeFenceBlocks: originalFenceCount)
        let domainPolicy = domainPolicy(for: context)
        let baselineKnownSectionCount = parseBlocks(from: input).blocks.reduce(into: 0) { count, block in
            if block.key != nil { count += 1 }
        }
        let baselineUnderspecified = isUnderspecifiedPrompt(
            input: input,
            analysis: baselineAnalysis,
            knownSectionCount: baselineKnownSectionCount
        )
        let gaps = detectGaps(input: input, analysis: baselineAnalysis, context: context, policy: domainPolicy)

        if !gaps.hasAnyGap {
            let baselineScore = scoreCandidate(
                analysis: baselineAnalysis,
                text: input,
                underspecifiedHint: baselineUnderspecified,
                weights: weights,
                context: context,
                policy: domainPolicy
            )
            let result = HeuristicOptimizationResult(
                optimizedText: input,
                selectedCandidateTitle: "0 Baseline",
                score: baselineScore.score,
                breakdown: baselineScore.breakdown,
                warnings: baselineScore.warnings,
                tunedWeights: weightResolution.source == .defaults ? nil : weights
            )
            resultCache.insert(result, for: cacheKey)
            return result
        }

        let transformPlans = buildTransformPlans(from: gaps)
        var candidates: [Candidate] = [Candidate(title: "0 Baseline", text: input, transforms: [])]
        var seenFingerprints = Set<String>([fingerprint(input)])

        for plan in transformPlans {
            guard candidates.count < maxCandidateCount else { break }
            let transformed = applyTransforms(
                plan,
                to: input,
                context: context,
                policy: domainPolicy,
                underspecifiedHint: baselineUnderspecified
            )
            let trimmed = transformed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let printKey = fingerprint(trimmed)
            guard seenFingerprints.insert(printKey).inserted else { continue }

            let title = "\(candidates.count) " + plan.map(\.rawValue).joined(separator: " + ")
            candidates.append(Candidate(title: title, text: trimmed, transforms: plan))
        }

        var scored: [(candidate: Candidate, score: ScoreResult, analysis: PromptAnalysis)] = []
        scored.reserveCapacity(candidates.count)

        for candidate in candidates {
            let analysis = PromptHeuristics.analyze(candidate.text, originalCodeFenceBlocks: originalFenceCount)
            let score = scoreCandidate(
                analysis: analysis,
                text: candidate.text,
                underspecifiedHint: baselineUnderspecified,
                weights: weights,
                context: context,
                policy: domainPolicy
            )
            scored.append((candidate, score, analysis))
        }

        guard let baselineScored = scored.first else {
            let fallback = HeuristicOptimizationResult(
                optimizedText: input,
                selectedCandidateTitle: "0 Baseline",
                score: 0,
                breakdown: [:],
                warnings: [],
                tunedWeights: weightResolution.source == .defaults ? nil : weights
            )
            resultCache.insert(fallback, for: cacheKey)
            return fallback
        }

        var bestIndex = 0
        for index in scored.indices {
            if scored[index].score.score > scored[bestIndex].score.score {
                bestIndex = index
            }
        }

        var selected = scored[bestIndex]
        var warnings = selected.score.warnings

        let delta = structuralDelta(
            baselineText: baselineScored.candidate.text,
            baseline: baselineScored.analysis,
            candidateText: selected.candidate.text,
            candidate: selected.analysis,
            context: context,
            policy: domainPolicy
        )

        if !shouldPromote(best: selected, baseline: baselineScored, delta: delta) {
            if bestIndex != 0 {
                warnings.append(
                    "Anti-regression fallback: baseline retained due to insufficient structural gain (best=\(selected.score.score), baseline=\(baselineScored.score.score), gain=\(delta.gain))."
                )
            }
            selected = baselineScored
        }

        if baselineAnalysis.scopeLeak && !selected.analysis.hasScopeBounds {
            warnings.append("Scope leak terms remain; consider tightening bounds explicitly.")
        }

        let result = HeuristicOptimizationResult(
            optimizedText: selected.candidate.text,
            selectedCandidateTitle: selected.candidate.title,
            score: selected.score.score,
            breakdown: selected.score.breakdown,
            warnings: dedupePreservingOrder(warnings),
            tunedWeights: weightResolution.source == .defaults ? nil : weights
        )

        resultCache.insert(result, for: cacheKey)
        return result
    }

    static func learnWeights(from historyPrompts: [String]) -> HeuristicScoringWeights? {
        let sample = Array(historyPrompts.prefix(50))
        guard sample.count >= 5 else { return nil }

        var missingOutput = 0
        var missingDeliverables = 0
        var missingScopeBounds = 0
        var contradictionCount = 0
        var highTokenCount = 0

        for prompt in sample {
            let analysis = PromptHeuristics.analyze(prompt, originalCodeFenceBlocks: 0)
            if !(analysis.hasOutputFormatHeading || analysis.hasOutputTemplate) {
                missingOutput += 1
            }
            if !analysis.hasEnumeratedDeliverables {
                missingDeliverables += 1
            }
            if analysis.scopeLeak && !analysis.hasScopeBounds {
                missingScopeBounds += 1
            }
            if !analysis.contradictions.isEmpty {
                contradictionCount += analysis.contradictions.count
            }
            if analysis.tokenEstimate > 900 {
                highTokenCount += 1
            }
        }

        let total = Double(sample.count)
        var tuned = HeuristicScoringWeights.defaults

        tuned.outputFormat += Int((Double(missingOutput) / total) * 8.0)
        tuned.deliverables += Int((Double(missingDeliverables) / total) * 8.0)
        tuned.scopeBounds += Int((Double(missingScopeBounds) / total) * 5.0)
        tuned.tokenPenaltyBase -= Int((Double(highTokenCount) / total) * 5.0)
        tuned.contradictionPenalty -= Int((Double(contradictionCount) / total) * 6.0)

        return tuned.clamped()
    }

    private static func resolveWeights(for context: HeuristicOptimizationContext) -> WeightResolution {
        if let local = context.localWeights?.clamped() {
            return WeightResolution(weights: local, source: .local)
        }

        if let learned = learnWeights(from: context.historyPrompts) {
            return WeightResolution(weights: learned, source: .learned)
        }

        return WeightResolution(weights: .defaults, source: .defaults)
    }

    private static func buildCacheKey(
        input: String,
        context: HeuristicOptimizationContext,
        weights: HeuristicScoringWeights
    ) -> String {
        "\(context.target.rawValue)|\(context.scenario.rawValue)|\(context.historyPrompts.count)|\(weights.signature)|\(input)"
    }

    private static func detectGaps(
        input: String,
        analysis: PromptAnalysis,
        context: HeuristicOptimizationContext,
        policy: DomainPolicy
    ) -> GapProfile {
        let intent = inferIntent(from: input)
        let ambiguous = analysis.ambiguityCount >= 2 || analysis.isVagueGoal
        let parsedBlocks = parseBlocks(from: input).blocks
        let knownSectionCount = parsedBlocks.reduce(into: 0) { count, block in
            if block.key != nil { count += 1 }
        }
        let underspecified = isUnderspecifiedPrompt(
            input: input,
            analysis: analysis,
            knownSectionCount: knownSectionCount
        )
        let weakDeliverables = hasWeakDeliverables(in: input)
        let hasKnownHeadings = parsedBlocks.contains(where: { $0.key != nil })
        let needsCanonicalization = hasKnownHeadings && !isLikelyCanonicalOrder(input)
        let needsSentenceRewrite = analysis.ambiguityCount > 0 || containsHedgingLexicon(in: input)
        let needsDedupe = hasDuplicateNormalizedLines(in: input)

        let domainMissing = !policy.requiredKeywords.isEmpty && !containsAllKeywords(policy.requiredKeywords, in: input)
        let missingGateSection = policy.requiredSectionsForAmbiguity.contains { key in
            !containsHeading(key.headingTitle, in: input)
        }
        let outputNeedsUpgrade = needsOutputFormatUpgrade(in: input, context: context, intent: intent)
        let shouldAskQuestions = shouldInsertQuestions(for: intent)

        return GapProfile(
            needsCanonicalization: needsCanonicalization,
            needsContradictionRepair: !analysis.contradictions.isEmpty,
            needsSentenceRewrite: needsSentenceRewrite,
            needsDeliverables: !analysis.hasEnumeratedDeliverables || weakDeliverables,
            needsOutputFormat: !(analysis.hasOutputFormatHeading || analysis.hasOutputTemplate) || outputNeedsUpgrade,
            needsSuccessCriteria: (ambiguous || underspecified) && !analysis.hasSuccessCriteriaHeading,
            needsScopeBounds: analysis.scopeLeak && !analysis.hasScopeBounds,
            needsQuestions: shouldAskQuestions && (ambiguous || underspecified) && !analysis.hasQuestionsHeading,
            needsDomainPack: domainMissing,
            needsQualityGate: (ambiguous || underspecified) && missingGateSection,
            needsDedupe: needsDedupe
        )
    }

    private static func buildTransformPlans(from gaps: GapProfile) -> [[TransformKey]] {
        var ordered: [TransformKey] = []

        if gaps.needsContradictionRepair { ordered.append(.contradictionRepair) }
        if gaps.needsSentenceRewrite { ordered.append(.sentenceRewrite) }
        if gaps.needsCanonicalization { ordered.append(.canonicalize) }
        if gaps.needsDeliverables { ordered.append(.deliverablesInference) }
        if gaps.needsOutputFormat { ordered.append(.outputFormat) }
        if gaps.needsSuccessCriteria { ordered.append(.successCriteria) }
        if gaps.needsScopeBounds { ordered.append(.scopeBounds) }
        if gaps.needsQuestions { ordered.append(.questions) }
        if gaps.needsDomainPack { ordered.append(.domainPack) }
        if gaps.needsQualityGate { ordered.append(.qualityGate) }
        if gaps.needsDedupe { ordered.append(.dedupe) }

        var plans: [[TransformKey]] = ordered.map { [$0] }

        let structuralBundle = ordered.filter {
            [.contradictionRepair, .sentenceRewrite, .deliverablesInference, .outputFormat, .scopeBounds, .questions, .successCriteria, .domainPack, .qualityGate, .dedupe].contains($0)
        }

        if !structuralBundle.isEmpty {
            plans.append(structuralBundle)
        }

        let formatBundle = ordered.filter {
            [.deliverablesInference, .outputFormat, .successCriteria, .questions, .qualityGate].contains($0)
        }
        if formatBundle.count >= 2 {
            plans.append(formatBundle)
        }

        if ordered.contains(.domainPack) {
            var domainPlan: [TransformKey] = [.domainPack]
            if ordered.contains(.qualityGate) { domainPlan.append(.qualityGate) }
            if ordered.contains(.deliverablesInference) { domainPlan.append(.deliverablesInference) }
            if ordered.contains(.outputFormat) { domainPlan.append(.outputFormat) }
            plans.append(domainPlan)
        }

        return Array(plans.prefix(maxCandidateCount - 1))
    }

    private static func applyTransforms(
        _ transforms: [TransformKey],
        to input: String,
        context: HeuristicOptimizationContext,
        policy: DomainPolicy,
        underspecifiedHint: Bool
    ) -> String {
        guard !transforms.isEmpty else { return input }

        var text = input
        for transform in transforms {
            switch transform {
            case .canonicalize:
                text = canonicalizeCandidate(text)
            case .contradictionRepair:
                text = contradictionRepairCandidate(text)
            case .sentenceRewrite:
                text = sentenceRewriteCandidate(text)
            case .deliverablesInference:
                text = deliverablesCandidate(text, context: context)
            case .outputFormat:
                text = outputFormatCandidate(text, context: context)
            case .successCriteria:
                text = successCriteriaCandidate(text, underspecifiedHint: underspecifiedHint)
            case .scopeBounds:
                text = scopeBoundsCandidate(text)
            case .questions:
                text = questionsCandidate(text, underspecifiedHint: underspecifiedHint)
            case .domainPack:
                text = domainPackCandidate(text, context: context, policy: policy)
            case .qualityGate:
                text = qualityGateCandidate(text, context: context, policy: policy)
            case .dedupe:
                text = dedupeCandidate(text)
            }
        }

        return text
    }

    private static func scoreCandidate(
        analysis: PromptAnalysis,
        text: String,
        underspecifiedHint: Bool,
        weights: HeuristicScoringWeights,
        context: HeuristicOptimizationContext,
        policy: DomainPolicy
    ) -> ScoreResult {
        var score = 0
        var breakdown: [String: Int] = [:]
        var warnings: [String] = []
        let underspecified = underspecifiedHint
        let intent = inferIntent(from: text)

        if analysis.hasOutputFormatHeading || analysis.hasOutputTemplate {
            score += weights.outputFormat
            breakdown["output_format"] = weights.outputFormat
        } else {
            let penalty = -max(4, weights.outputFormat / 2)
            score += penalty
            breakdown["missing_output_format"] = penalty
        }

        if intent == .creativeStory || intent == .gameDesign {
            if needsOutputFormatUpgrade(in: text, context: context, intent: intent) {
                let penalty = -max(3, weights.outputFormat / 3)
                score += penalty
                breakdown["generic_output_contract_for_creative"] = penalty
            } else {
                score += 3
                breakdown["creative_output_contract"] = 3
            }
        }

        if analysis.hasEnumeratedDeliverables {
            score += weights.deliverables
            breakdown["enumerated_deliverables"] = weights.deliverables
        } else {
            let penalty = -max(4, weights.deliverables / 2)
            score += penalty
            breakdown["missing_deliverables"] = penalty
        }

        if hasWeakDeliverables(in: text) {
            let penalty = -max(4, weights.deliverables / 3)
            score += penalty
            breakdown["weak_deliverables"] = penalty
        }

        if analysis.hasConstraintsHeading && analysis.hasStrongConstraintMarkers {
            score += weights.constraints
            breakdown["strong_constraints"] = weights.constraints
        }

        let ambiguous = analysis.ambiguityCount >= 2 || analysis.isVagueGoal
        if (ambiguous || underspecified) && analysis.hasSuccessCriteriaHeading {
            score += weights.successCriteria
            breakdown["success_criteria_for_ambiguity"] = weights.successCriteria
        } else if underspecified {
            let penalty = -max(3, weights.successCriteria / 2)
            score += penalty
            breakdown["missing_success_criteria_underspecified"] = penalty
        }

        if analysis.scopeLeak && analysis.hasScopeBounds {
            score += weights.scopeBounds
            breakdown["scope_bounded"] = weights.scopeBounds
        }

        if (ambiguous || underspecified) && analysis.hasQuestionsHeading {
            score += weights.questions
            breakdown["questions_for_ambiguity"] = weights.questions
        } else if underspecified {
            let penalty = -max(2, weights.questions / 2)
            score += penalty
            breakdown["missing_questions_underspecified"] = penalty
        }

        let exampleBonus = min(12, analysis.examplesCount * weights.examplesPerUnit)
        if exampleBonus > 0 {
            score += exampleBonus
            breakdown["examples"] = exampleBonus
        }

        if containsAllKeywords(policy.requiredKeywords, in: text) {
            score += weights.domainPackBonus
            breakdown["domain_pack"] = weights.domainPackBonus
        }

        if !policy.requiredSectionsForAmbiguity.contains(where: { !containsHeading($0.headingTitle, in: text) }) {
            score += weights.qualityGateBonus
            breakdown["quality_gate"] = weights.qualityGateBonus
        }

        if analysis.tokenEstimate > 900 {
            let scaledPenalty = weights.tokenPenaltyBase - min(12, ((analysis.tokenEstimate - 900) / 300) * 2)
            score += scaledPenalty
            breakdown["token_penalty"] = scaledPenalty
            warnings.append("Token estimate is high: \(analysis.tokenEstimate).")
        }

        if !analysis.contradictions.isEmpty {
            score += weights.contradictionPenalty
            breakdown["contradictions"] = weights.contradictionPenalty
            warnings.append(contentsOf: analysis.contradictions)
        }

        if PromptHeuristics.usesCurlyVariablePlaceholders && analysis.unresolvedPlaceholderCount > 0 {
            score += weights.unresolvedPlaceholderPenalty
            breakdown["unresolved_placeholders"] = weights.unresolvedPlaceholderPenalty
            warnings.append("Unresolved placeholders detected: \(analysis.unresolvedPlaceholderCount).")
        }

        if context.scenario == .jsonStructuredOutput && !text.localizedCaseInsensitiveContains("json") {
            score -= 6
            breakdown["json_mismatch"] = -6
        }

        return ScoreResult(score: score, breakdown: breakdown, warnings: dedupePreservingOrder(warnings))
    }

    private static func structuralDelta(
        baselineText: String,
        baseline: PromptAnalysis,
        candidateText: String,
        candidate: PromptAnalysis,
        context: HeuristicOptimizationContext,
        policy: DomainPolicy
    ) -> StructuralDelta {
        var gain = 0
        let baselineIntent = inferIntent(from: baselineText)
        let baselineKnownSectionCount = parseBlocks(from: baselineText).blocks.reduce(into: 0) { count, block in
            if block.key != nil { count += 1 }
        }
        let baselineUnderspecified = isUnderspecifiedPrompt(
            input: baselineText,
            analysis: baseline,
            knownSectionCount: baselineKnownSectionCount
        )

        if !(baseline.hasOutputFormatHeading || baseline.hasOutputTemplate) && (candidate.hasOutputFormatHeading || candidate.hasOutputTemplate) {
            gain += 2
        }
        if (baselineIntent == .creativeStory || baselineIntent == .gameDesign) {
            let baselineNeedsUpgrade = needsOutputFormatUpgrade(in: baselineText, context: context, intent: baselineIntent)
            let candidateNeedsUpgrade = needsOutputFormatUpgrade(in: candidateText, context: context, intent: baselineIntent)
            if baselineNeedsUpgrade && !candidateNeedsUpgrade {
                gain += 2
            }
        }

        if !baseline.hasEnumeratedDeliverables && candidate.hasEnumeratedDeliverables {
            gain += 2
        }

        if (baseline.ambiguityCount >= 2 || baseline.isVagueGoal || baselineUnderspecified) {
            if !baseline.hasSuccessCriteriaHeading && candidate.hasSuccessCriteriaHeading {
                gain += 1
            }
            if !baseline.hasQuestionsHeading && candidate.hasQuestionsHeading {
                gain += 1
            }
        }

        if baseline.scopeLeak && !baseline.hasScopeBounds && candidate.hasScopeBounds {
            gain += 1
        }

        if !baseline.contradictions.isEmpty && candidate.contradictions.count < baseline.contradictions.count {
            gain += 2
        }

        if containsAllKeywords(policy.requiredKeywords, in: candidateText) && !containsAllKeywords(policy.requiredKeywords, in: baselineText) {
            gain += 2
        }

        let baselineMissingSections = policy.requiredSectionsForAmbiguity.reduce(into: 0) { count, key in
            if !containsHeading(key.headingTitle, in: baselineText) { count += 1 }
        }
        let candidateMissingSections = policy.requiredSectionsForAmbiguity.reduce(into: 0) { count, key in
            if !containsHeading(key.headingTitle, in: candidateText) { count += 1 }
        }
        if candidateMissingSections < baselineMissingSections {
            gain += min(3, baselineMissingSections - candidateMissingSections)
        }

        let baseLength = max(1, baselineText.count)
        let growthRatio = Double(candidateText.count) / Double(baseLength)
        let meaningful = gain >= 2

        return StructuralDelta(gain: gain, growthRatio: growthRatio, meaningful: meaningful)
    }

    private static func shouldPromote(
        best: (candidate: Candidate, score: ScoreResult, analysis: PromptAnalysis),
        baseline: (candidate: Candidate, score: ScoreResult, analysis: PromptAnalysis),
        delta: StructuralDelta
    ) -> Bool {
        guard best.candidate.title != "0 Baseline" else { return true }

        let scoreGain = best.score.score - baseline.score.score
        if scoreGain < 1 {
            return false
        }

        if !delta.meaningful {
            return false
        }

        if delta.growthRatio > 1.8 && delta.gain < 2 {
            return false
        }

        return true
    }

    private static func canonicalizeCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            canonicalizeSections(in: text)
        }
    }

    private static func contradictionRepairCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            let analysis = PromptHeuristics.analyze(text, originalCodeFenceBlocks: 0)
            guard !analysis.contradictions.isEmpty else { return text }

            let shielded = PromptHeuristics.shieldProtectedLiterals(in: text)
            var edited = shielded.shielded

            for replacement in RegexBank.contradictionReplacements {
                edited = replacement.regex.stringByReplacingMatches(
                    in: edited,
                    options: [],
                    range: NSRange(edited.startIndex..<edited.endIndex, in: edited),
                    withTemplate: replacement.replacement
                )
            }

            if analysis.contradictions.contains(where: { $0.localizedCaseInsensitiveContains("concise") }) {
                edited = appendSection(
                    to: edited,
                    title: "Constraints",
                    body: ["- Keep output concise while remaining scope-complete."]
                )
            }

            if analysis.contradictions.contains(where: { $0.localizedCaseInsensitiveContains("No-browsing") }) {
                edited = appendSection(
                    to: edited,
                    title: "Constraints",
                    body: ["- Use provided/local sources only; do not browse online sources."]
                )
            }

            if analysis.contradictions.contains(where: { $0.localizedCaseInsensitiveContains("No-code") }) {
                edited = appendSection(
                    to: edited,
                    title: "Deliverables",
                    body: [
                        "1. Provide a non-code implementation plan.",
                        "2. Provide validation steps without executable code."
                    ]
                )
            }

            return PromptHeuristics.restoreProtectedLiterals(in: edited, table: shielded.table)
        }
    }

    private static func sentenceRewriteCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            let shielded = PromptHeuristics.shieldProtectedLiterals(in: text)
            let rewritten = rewriteSentences(in: shielded.shielded)
            return PromptHeuristics.restoreProtectedLiterals(in: rewritten, table: shielded.table)
        }
    }

    private static func deliverablesCandidate(_ input: String, context: HeuristicOptimizationContext) -> String {
        transformPreservingCodeFences(input) { text in
            let analysis = PromptHeuristics.analyze(text, originalCodeFenceBlocks: 0)
            let needsUpgrade = !analysis.hasEnumeratedDeliverables || hasWeakDeliverables(in: text)
            guard needsUpgrade else { return text }

            let inferred = inferDeliverables(from: text, context: context)
            if containsHeading("Deliverables", in: text) {
                return replaceSectionBody(in: text, title: "Deliverables", body: inferred)
            }

            return appendSection(to: text, title: "Deliverables", body: inferred)
        }
    }

    private static func outputFormatCandidate(_ input: String, context: HeuristicOptimizationContext) -> String {
        transformPreservingCodeFences(input) { text in
            let analysis = PromptHeuristics.analyze(text, originalCodeFenceBlocks: 0)
            let intent = inferIntent(from: text)
            let desiredLines = outputFormatLines(for: context, text: text)
            let needsUpgrade = needsOutputFormatUpgrade(in: text, context: context, intent: intent)

            if analysis.hasOutputFormatHeading || analysis.hasOutputTemplate {
                if needsUpgrade {
                    return replaceSectionBody(in: text, title: "Output Format", body: desiredLines)
                }
                return text
            }

            return appendSection(to: text, title: "Output Format", body: desiredLines)
        }
    }

    private static func successCriteriaCandidate(_ input: String, underspecifiedHint: Bool) -> String {
        transformPreservingCodeFences(input) { text in
            let analysis = PromptHeuristics.analyze(text, originalCodeFenceBlocks: 0)
            let intent = inferIntent(from: text)
            let knownSectionCount = parseBlocks(from: text).blocks.reduce(into: 0) { count, block in
                if block.key != nil { count += 1 }
            }
            let underspecified = underspecifiedHint || isUnderspecifiedPrompt(
                input: text,
                analysis: analysis,
                knownSectionCount: knownSectionCount
            )
            let needsCriteria = (analysis.ambiguityCount > 0 || analysis.isVagueGoal || underspecified) && !analysis.hasSuccessCriteriaHeading
            guard needsCriteria else { return text }

            return appendSection(
                to: text,
                title: "Success Criteria",
                body: successCriteriaLines(for: intent)
            )
        }
    }

    private static func scopeBoundsCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            let analysis = PromptHeuristics.analyze(text, originalCodeFenceBlocks: 0)
            guard analysis.scopeLeak && !analysis.hasScopeBounds else { return text }

            return appendSection(
                to: text,
                title: "Constraints",
                body: [
                    "- Limit work to the explicit request only.",
                    "- Do not expand scope to unrelated systems or files.",
                    "- Avoid optional extras unless explicitly requested."
                ]
            )
        }
    }

    private static func questionsCandidate(_ input: String, underspecifiedHint: Bool) -> String {
        transformPreservingCodeFences(input) { text in
            let analysis = PromptHeuristics.analyze(text, originalCodeFenceBlocks: 0)
            let intent = inferIntent(from: text)
            guard shouldInsertQuestions(for: intent) else { return text }
            let knownSectionCount = parseBlocks(from: text).blocks.reduce(into: 0) { count, block in
                if block.key != nil { count += 1 }
            }
            let underspecified = underspecifiedHint || isUnderspecifiedPrompt(
                input: text,
                analysis: analysis,
                knownSectionCount: knownSectionCount
            )
            let needsQuestions = (analysis.ambiguityCount >= 2 || analysis.isVagueGoal || underspecified) && !analysis.hasQuestionsHeading
            guard needsQuestions else { return text }

            return appendSection(
                to: text,
                title: "Questions",
                body: [
                    "- What is the exact target output and intended audience?",
                    "- What constraints (time, tools, style, depth) are mandatory?",
                    "- What should be considered out of scope?"
                ]
            )
        }
    }

    private static func domainPackCandidate(
        _ input: String,
        context: HeuristicOptimizationContext,
        policy: DomainPolicy
    ) -> String {
        transformPreservingCodeFences(input) { text in
            var output = text
            for section in policy.supplementalSections {
                output = appendSection(to: output, title: section.title, body: section.body)
            }

            if context.target == .perplexity {
                output = appendSection(
                    to: output,
                    title: "Constraints",
                    body: ["- Cite primary sources with direct URLs for factual claims."]
                )
            }

            if context.target == .agenticIDE {
                output = appendMissingSections(
                    to: output,
                    sections: [
                        ("Proposed File Changes", [
                            "1. List files to modify with short rationale.",
                            "2. Keep patch scope minimal and deterministic."
                        ]),
                        ("Validation Commands", [
                            "1. Run focused tests first.",
                            "2. Run full suite only if focused tests pass."
                        ])
                    ]
                )
            }

            return output
        }
    }

    private static func qualityGateCandidate(
        _ input: String,
        context: HeuristicOptimizationContext,
        policy: DomainPolicy
    ) -> String {
        transformPreservingCodeFences(input) { text in
            var output = text
            let intent = inferIntent(from: text)
            let goalSeed = extractGoalSeed(from: text)
            let inferredDeliverables = inferDeliverables(from: text, context: context)

            for key in policy.requiredSectionsForAmbiguity {
                if containsHeading(key.headingTitle, in: output) {
                    continue
                }

                switch key {
                case .goal:
                    output = appendSection(to: output, title: key.headingTitle, body: [goalSeed])
                case .constraints:
                    output = appendSection(
                        to: output,
                        title: key.headingTitle,
                        body: constraintLines(for: intent)
                    )
                case .deliverables:
                    output = appendSection(to: output, title: key.headingTitle, body: inferredDeliverables)
                case .outputFormat:
                    output = appendSection(to: output, title: key.headingTitle, body: outputFormatLines(for: context, text: output))
                case .questions:
                    output = appendSection(
                        to: output,
                        title: key.headingTitle,
                        body: [
                            "- Which acceptance checks are mandatory?",
                            "- Which files/systems are strictly out of scope?"
                        ]
                    )
                case .successCriteria:
                    output = appendSection(
                        to: output,
                        title: key.headingTitle,
                        body: successCriteriaLines(for: intent)
                    )
                case .context:
                    output = appendSection(to: output, title: key.headingTitle, body: ["Use only the context provided in this prompt."])
                }
            }

            return output
        }
    }

    private static func dedupeCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            let lines = text.components(separatedBy: .newlines)
            var seen = Set<String>()
            var output: [String] = []
            var previousWasBlank = false

            for line in lines {
                let trimmedTrailing = RegexBank.trailingWhitespace.stringByReplacingMatches(
                    in: line,
                    options: [],
                    range: NSRange(line.startIndex..<line.endIndex, in: line),
                    withTemplate: ""
                )
                let stripped = trimmedTrailing.trimmingCharacters(in: .whitespacesAndNewlines)

                if stripped.isEmpty {
                    if !previousWasBlank {
                        output.append("")
                    }
                    previousWasBlank = true
                    continue
                }

                previousWasBlank = false
                let normalized = RegexBank.normalizedWhitespace.stringByReplacingMatches(
                    in: stripped.lowercased(),
                    options: [],
                    range: NSRange(stripped.startIndex..<stripped.endIndex, in: stripped),
                    withTemplate: " "
                )

                if seen.insert(normalized).inserted {
                    output.append(trimmedTrailing)
                }
            }

            return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func transformPreservingCodeFences(_ input: String, transform: (String) -> String) -> String {
        let segments = PromptTextGuards.splitByCodeFences(input)
        var rebuilt = ""

        for index in segments.indices {
            let previous = index > 0 ? segments[index - 1] : nil
            let next = index + 1 < segments.count ? segments[index + 1] : nil

            switch segments[index] {
            case .codeFence(let code):
                var safeCode = code
                if !rebuilt.isEmpty && !rebuilt.hasSuffix("\n") {
                    rebuilt.append("\n")
                }
                if case .text(let nextText)? = next, !nextText.hasPrefix("\n"), !safeCode.hasSuffix("\n") {
                    safeCode.append("\n")
                }
                rebuilt.append(safeCode)
            case .text(let text):
                var transformed = transform(text)
                if case .codeFence? = next, !transformed.hasSuffix("\n") {
                    transformed.append("\n")
                }
                if case .codeFence? = previous, !transformed.hasPrefix("\n") {
                    transformed = "\n" + transformed
                }
                rebuilt.append(transformed)
            }
        }

        return rebuilt
    }

    private static func rewriteSentences(in text: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var output = ""
        var cursor = text.startIndex

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if cursor < range.lowerBound {
                output.append(contentsOf: text[cursor..<range.lowerBound])
            }

            let sentence = String(text[range])
            output.append(rewriteSentence(sentence))
            cursor = range.upperBound
            return true
        }

        if cursor < text.endIndex {
            output.append(contentsOf: text[cursor..<text.endIndex])
        }

        return output
    }

    private static func rewriteSentence(_ sentence: String) -> String {
        var rewritten = sentence

        for replacement in RegexBank.sentenceReplacements {
            let fullRange = NSRange(rewritten.startIndex..<rewritten.endIndex, in: rewritten)
            rewritten = replacement.regex.stringByReplacingMatches(
                in: rewritten,
                options: [],
                range: fullRange,
                withTemplate: replacement.replacement
            )
        }

        return normalizeSentenceWhitespace(rewritten)
    }

    private static func normalizeSentenceWhitespace(_ text: String) -> String {
        let condensed = RegexBank.internalWhitespace.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: " "
        )

        return condensed
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " :", with: ":")
            .replacingOccurrences(of: " ;", with: ";")
            .replacingOccurrences(of: "  ", with: " ")
    }

    private static func inferDeliverables(from text: String, context: HeuristicOptimizationContext) -> [String] {
        let nonCodeText = PromptTextGuards.splitByCodeFences(text).compactMap { segment -> String? in
            if case let .text(value) = segment { return value }
            return nil
        }
        .joined(separator: "\n")
        let intent = inferIntent(from: nonCodeText)

        if let intentDeliverables = intentSpecificDeliverables(for: intent, sourceText: nonCodeText) {
            var numbered: [String] = []
            for (index, item) in intentDeliverables.prefix(3).enumerated() {
                numbered.append("\(index + 1). \(item)")
            }
            return numbered
        }

        let compact = nonCodeText.replacingOccurrences(of: "\n", with: " ")
        let range = NSRange(compact.startIndex..<compact.endIndex, in: compact)
        let matches = RegexBank.actionObject.matches(in: compact, options: [], range: range)

        var items: [String] = []
        for match in matches {
            guard
                let verbRange = Range(match.range(at: 1), in: compact),
                let objectRange = Range(match.range(at: 2), in: compact)
            else {
                continue
            }

            let verb = String(compact[verbRange]).lowercased()
            var object = String(compact[objectRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            object = object.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:"))

            guard !object.isEmpty else { continue }
            let candidate = "\(capitalized(verb)) \(object)."
            items.append(candidate)

            if items.count >= 3 {
                break
            }
        }

        if items.isEmpty {
            items = defaultDeliverables(for: context)
        }

        let validationLine = "Provide deterministic validation evidence for each major requirement."
        var merged = dedupePreservingOrder(items + defaultDeliverables(for: context))
        if !merged.contains(validationLine) {
            merged.append(validationLine)
        }
        while merged.count < 3 {
            merged.append(validationLine)
        }

        var numbered: [String] = []
        for (index, item) in merged.prefix(3).enumerated() {
            numbered.append("\(index + 1). \(item)")
        }

        return numbered
    }

    private static func defaultDeliverables(for context: HeuristicOptimizationContext) -> [String] {
        switch context.scenario {
        case .cliAssistant:
            return [
                "Provide exact copy/paste shell commands in execution order.",
                "Mark any optional command as explicit optional follow-up.",
                "Include a deterministic verification command sequence."
            ]
        case .jsonStructuredOutput:
            return [
                "Return one valid JSON object that matches the required schema.",
                "Keep key names stable and deterministic.",
                "Include validation notes only as JSON fields when requested."
            ]
        case .ideCodingAssistant:
            return [
                "Produce an ordered plan and targeted patch summary.",
                "List exact tests to add/update.",
                "Provide deterministic validation commands."
            ]
        default:
            return [
                "Provide the primary requested artifact.",
                "Provide ordered implementation steps.",
                "Provide validation evidence for completion."
            ]
        }
    }

    private static func outputFormatLines(for context: HeuristicOptimizationContext, text: String) -> [String] {
        let intent = inferIntent(from: text)
        if context.scenario == .generalAssistant {
            switch intent {
            case .creativeStory:
                return [
                    "Use sections in this order: Title, Story.",
                    "Story must contain a clear beginning, middle, and ending.",
                    "Keep the narration concrete and avoid meta commentary."
                ]
            case .gameDesign:
                return [
                    "Use sections in this order: Concept, Rules, Visual Theme, Interaction Flow, Edge Cases.",
                    "Define deterministic win, draw, and invalid-move behavior.",
                    "Explicitly map cat/dog marks to player turns and board state."
                ]
            case .softwareBuild, .general:
                break
            }
        }
        return outputFormatLines(for: context)
    }

    private static func outputFormatLines(for context: HeuristicOptimizationContext) -> [String] {
        switch context.scenario {
        case .jsonStructuredOutput:
            return [
                "Return JSON only.",
                "No markdown, no prose, no code fences.",
                "Use a stable object schema with deterministic key order."
            ]
        case .cliAssistant:
            return [
                "Return shell commands only unless explanation is explicitly requested.",
                "Commands must be copy/paste runnable.",
                "Use at most one shell comment line when a note is unavoidable."
            ]
        case .ideCodingAssistant:
            return [
                "Use markdown headings in this order: Plan, Unified Diff, Tests, Validation Commands.",
                "Keep patch scope minimal and deterministic.",
                "List exact files and test commands."
            ]
        case .toolUsingAgent:
            return [
                "Use sections: Plan, Tool Calls, Observations, Final Output.",
                "Emit tool calls only when required data is missing.",
                "Use explicit argument payloads for every tool call."
            ]
        default:
            return [
                "Use this markdown template exactly:",
                "1. Summary: <one paragraph>",
                "2. Deliverables:",
                "   - <item 1>",
                "   - <item 2>",
                "3. Validation:",
                "   - <check 1>",
                "   - <check 2>"
            ]
        }
    }

    private static func domainPolicy(for context: HeuristicOptimizationContext) -> DomainPolicy {
        var keywords: [String] = []
        var sections: [SectionKey] = [.goal, .constraints, .deliverables, .outputFormat, .successCriteria]
        var supplements: [(title: String, body: [String])] = []

        switch context.scenario {
        case .cliAssistant:
            keywords += ["shell commands only", "copy/paste runnable"]
            supplements.append(("Constraints", [
                "- Return shell commands only unless explanation is requested.",
                "- Keep commands deterministic and executable as written."
            ]))
        case .jsonStructuredOutput:
            keywords += ["json", "no markdown"]
            supplements.append(("Output Format", [
                "Return JSON only.",
                "No markdown, no prose, no code fences."
            ]))
        case .ideCodingAssistant:
            keywords += ["Unified Diff", "Validation Commands"]
            supplements.append(("Deliverables", [
                "1. Plan with deterministic ordered steps.",
                "2. Unified Diff limited to touched files.",
                "3. Tests and validation commands."
            ]))
        case .researchSummarization:
            keywords += ["Citations", "Confidence"]
            supplements.append(("Output Format", [
                "Use sections: Summary, Citations, Confidence.",
                "Citations must include source URLs.",
                "Assign confidence labels: High/Medium/Low."
            ]))
        case .toolUsingAgent:
            keywords += ["Plan", "Tool Calls", "Final Output"]
            sections.append(.questions)
            supplements.append(("Output Format", [
                "Use sections: Plan, Tool Calls, Observations, Final Output.",
                "Keep each tool call explicit and minimal."
            ]))
        case .longformWriting:
            keywords += ["outline", "narrative continuity"]
            supplements.append(("Success Criteria", [
                "- Includes coherent outline and narrative continuity.",
                "- Maintains tone consistency across sections."
            ]))
        default:
            keywords += ["deterministic", "validation"]
        }

        switch context.target {
        case .perplexity:
            keywords += ["primary sources", "URL"]
            supplements.append(("Constraints", [
                "- Cite primary sources with direct URLs.",
                "- Separate confirmed facts from assumptions."
            ]))
        case .agenticIDE:
            keywords += ["Proposed File Changes", "Validation Commands"]
            supplements.append(("Proposed File Changes", [
                "1. List touched files and purpose.",
                "2. Keep edits minimal and reversible."
            ]))
        case .claude, .geminiChatGPT:
            break
        }

        return DomainPolicy(
            requiredKeywords: dedupePreservingOrder(keywords),
            requiredSectionsForAmbiguity: dedupeSectionKeysPreservingOrder(sections),
            supplementalSections: supplements
        )
    }

    private static func parseBlocks(from text: String) -> (preamble: [String], blocks: [HeadingBlock]) {
        let lines = text.components(separatedBy: .newlines)
        var preamble: [String] = []
        var blocks: [HeadingBlock] = []
        var currentHeading: HeadingBlock?

        func flushCurrent() {
            guard let currentHeading else { return }
            blocks.append(currentHeading)
        }

        for line in lines {
            if let heading = parseHeading(line) {
                flushCurrent()
                currentHeading = HeadingBlock(title: heading.title, key: heading.key, body: [])
                if !heading.inlineValue.isEmpty {
                    currentHeading?.body.append(heading.inlineValue)
                }
                continue
            }

            if currentHeading != nil {
                currentHeading?.body.append(line)
            } else {
                preamble.append(line)
            }
        }

        flushCurrent()
        return (preamble, blocks)
    }

    private static func parseHeading(_ line: String) -> (title: String, key: SectionKey?, inlineValue: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutHashes = stripHeadingHashes(trimmed)
        let normalized = withoutHashes.lowercased()

        let mapping: [(aliases: [String], key: SectionKey)] = [
            (["goal", "objective", "task"], .goal),
            (["context"], .context),
            (["constraints", "constraint"], .constraints),
            (["deliverables", "deliverable"], .deliverables),
            (["output format", "output contract", "format"], .outputFormat),
            (["questions", "clarifying questions"], .questions),
            (["success criteria", "acceptance criteria"], .successCriteria)
        ]

        for item in mapping {
            for alias in item.aliases {
                if normalized == alias {
                    return (item.key.headingTitle, item.key, "")
                }

                let prefix = "\(alias):"
                if normalized.hasPrefix(prefix) {
                    let inlineStart = withoutHashes.index(withoutHashes.startIndex, offsetBy: prefix.count)
                    let inlineValue = withoutHashes[inlineStart...].trimmingCharacters(in: .whitespacesAndNewlines)
                    return (item.key.headingTitle, item.key, inlineValue)
                }
            }
        }

        if trimmed.hasPrefix("#") {
            return (withoutHashes, nil, "")
        }

        return nil
    }

    private static func stripHeadingHashes(_ text: String) -> String {
        RegexBank.headingPrefix.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: ""
        )
    }

    private static func canonicalizeSections(in text: String) -> String {
        let parsed = parseBlocks(from: text)
        var known: [SectionKey: [String]] = [:]
        var unknown: [HeadingBlock] = []

        for block in parsed.blocks {
            if let key = block.key {
                known[key, default: []].append(contentsOf: block.body)
            } else {
                unknown.append(block)
            }
        }

        let preambleContent = parsed.preamble.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !preambleContent.isEmpty {
            if known[.goal, default: []].isEmpty {
                known[.goal] = [preambleContent]
            } else if known[.context, default: []].isEmpty {
                known[.context] = [preambleContent]
            } else {
                unknown.insert(HeadingBlock(title: "Context", key: nil, body: [preambleContent]), at: 0)
            }
        }

        var rendered: [String] = []

        for key in SectionKey.allCases {
            let bodyLines = cleanBodyLines(known[key] ?? [])
            guard !bodyLines.isEmpty else { continue }
            rendered.append(renderSection(title: key.headingTitle, body: bodyLines))
        }

        for block in unknown {
            let bodyLines = cleanBodyLines(block.body)
            guard !bodyLines.isEmpty else { continue }
            rendered.append(renderSection(title: block.title, body: bodyLines))
        }

        let candidate = rendered.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? text : candidate
    }

    private static func appendSection(to text: String, title: String, body: [String]) -> String {
        let cleaned = cleanBodyLines(body)
        guard !cleaned.isEmpty else { return text }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let section = renderSection(title: title, body: cleaned)

        if trimmed.isEmpty {
            return section
        }

        if containsHeading(title, in: trimmed) {
            return mergeIntoExistingSection(in: trimmed, title: title, lines: cleaned)
        }

        return trimmed + "\n\n" + section
    }

    private static func appendMissingSections(
        to text: String,
        sections: [(title: String, body: [String])]
    ) -> String {
        var output = text
        for section in sections {
            if !containsHeading(section.title, in: output) {
                output = appendSection(to: output, title: section.title, body: section.body)
            }
        }
        return output
    }

    private static func mergeIntoExistingSection(in text: String, title: String, lines: [String]) -> String {
        guard !lines.isEmpty else { return text }

        let parsed = parseBlocks(from: text)
        var rendered: [String] = []
        let target = normalizeHeading(title)

        if !parsed.preamble.isEmpty {
            rendered.append(parsed.preamble.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var mergedAny = false

        for block in parsed.blocks {
            let normalizedTitle = normalizeHeading(block.title)
            if normalizedTitle == target {
                let mergedBody = dedupePreservingOrder(cleanBodyLines(block.body) + lines)
                rendered.append(renderSection(title: block.title, body: mergedBody))
                mergedAny = true
            } else {
                let body = cleanBodyLines(block.body)
                if !body.isEmpty {
                    rendered.append(renderSection(title: block.title, body: body))
                }
            }
        }

        if !mergedAny {
            rendered.append(renderSection(title: title, body: lines))
        }

        return rendered
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceSectionBody(in text: String, title: String, body: [String]) -> String {
        let cleanedBody = cleanBodyLines(body)
        guard !cleanedBody.isEmpty else { return text }

        let parsed = parseBlocks(from: text)
        let target = normalizeHeading(title)
        var rendered: [String] = []
        var replaced = false

        if !parsed.preamble.isEmpty {
            let preamble = parsed.preamble.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !preamble.isEmpty {
                rendered.append(preamble)
            }
        }

        for block in parsed.blocks {
            let normalizedTitle = normalizeHeading(block.title)
            if normalizedTitle == target {
                rendered.append(renderSection(title: block.title, body: cleanedBody))
                replaced = true
            } else {
                let existingBody = cleanBodyLines(block.body)
                if !existingBody.isEmpty {
                    rendered.append(renderSection(title: block.title, body: existingBody))
                }
            }
        }

        if !replaced {
            rendered.append(renderSection(title: title, body: cleanedBody))
        }

        return rendered
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func renderSection(title: String, body: [String]) -> String {
        "### \(title)\n" + body.joined(separator: "\n")
    }

    private static func cleanBodyLines(_ body: [String]) -> [String] {
        let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return text.components(separatedBy: .newlines)
    }

    private static func extractGoalSeed(from text: String) -> String {
        let nonCodeText = PromptTextGuards.splitByCodeFences(text).compactMap { segment -> String? in
            if case let .text(value) = segment { return value }
            return nil
        }
        .joined(separator: "\n")

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = nonCodeText

        var firstSentence: String?
        tokenizer.enumerateTokens(in: nonCodeText.startIndex..<nonCodeText.endIndex) { range, _ in
            let candidate = nonCodeText[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                firstSentence = candidate
                return false
            }
            return true
        }

        return firstSentence ?? "Clarify the exact task and required output before execution."
    }

    private static func isLikelyCanonicalOrder(_ text: String) -> Bool {
        let parsed = parseBlocks(from: text)
        let indices = parsed.blocks.compactMap { $0.key?.rawValue }
        guard indices.count > 1 else { return true }
        return indices == indices.sorted()
    }

    private static func hasDuplicateNormalizedLines(in text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        var seen = Set<String>()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let normalized = trimmed.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            if !seen.insert(normalized).inserted {
                return true
            }
        }

        return false
    }

    private static func isUnderspecifiedPrompt(
        input: String,
        analysis: PromptAnalysis,
        knownSectionCount: Int
    ) -> Bool {
        let compactLength = input.trimmingCharacters(in: .whitespacesAndNewlines).count
        let shortPrompt =
            compactLength <= 220 ||
            analysis.tokenEstimate <= 120 ||
            analysis.goalLine.trimmingCharacters(in: .whitespacesAndNewlines).count <= 80
        let limitedStructure = knownSectionCount <= 3
        let hasCoreGaps =
            !analysis.hasConstraintsHeading ||
            !analysis.hasSuccessCriteriaHeading ||
            !analysis.hasQuestionsHeading
        let shortGoalSeed = extractGoalSeed(from: input).count <= 100

        return shortPrompt && limitedStructure && hasCoreGaps && shortGoalSeed
    }

    private static func hasWeakDeliverables(in text: String) -> Bool {
        let parsed = parseBlocks(from: text)
        guard let deliverablesBlock = parsed.blocks.first(where: { $0.key == .deliverables }) else {
            return false
        }

        let lines = cleanBodyLines(deliverablesBlock.body)
        let numberedLines = lines.filter { line in
            RegexBank.leadingBullet.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..<line.endIndex, in: line)
            ) != nil
        }

        if numberedLines.count < 3 {
            return true
        }

        let goalSeed = normalizeDeliverableForComparison(extractGoalSeed(from: text))
        if goalSeed.isEmpty { return false }

        return numberedLines.contains { line in
            let normalized = normalizeDeliverableForComparison(line)
            return normalized == goalSeed || normalized.contains(goalSeed) || goalSeed.contains(normalized)
        }
    }

    private static func normalizeDeliverableForComparison(_ value: String) -> String {
        let strippedBullet = RegexBank.leadingBullet.stringByReplacingMatches(
            in: value,
            options: [],
            range: NSRange(value.startIndex..<value.endIndex, in: value),
            withTemplate: ""
        )
        return strippedBullet
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".:;,-")))
            .lowercased()
    }

    private static func inferIntent(from text: String) -> PromptIntent {
        let lowered = text.lowercased()
        let hasStoryCue = ["story", "narrative", "short story", "plot", "character arc"].contains(where: lowered.contains)
        if hasStoryCue {
            return .creativeStory
        }

        let hasGameCue = ["tic-tac-toe", "board game", "game rules", "gameplay", "x's", "o's", "chess"].contains(where: lowered.contains)
        if hasGameCue && ["design", "spec", "mechanic", "rules"].contains(where: lowered.contains) {
            return .gameDesign
        }

        let hasSoftwareCue = [
            "build", "implement", "refactor", "fix", "patch", "test", "app", "api", "function", "class", "script",
            "repository", "file", "code", "swift", "python", "javascript", "react", "cli", "game"
        ]
        .contains(where: lowered.contains)
        if hasSoftwareCue {
            return .softwareBuild
        }

        return .general
    }

    private static func shouldInsertQuestions(for intent: PromptIntent) -> Bool {
        switch intent {
        case .creativeStory, .gameDesign:
            return false
        case .softwareBuild, .general:
            return true
        }
    }

    private static func needsOutputFormatUpgrade(
        in text: String,
        context: HeuristicOptimizationContext,
        intent: PromptIntent
    ) -> Bool {
        guard intent == .creativeStory || intent == .gameDesign else { return false }
        let parsed = parseBlocks(from: text)
        guard let block = parsed.blocks.first(where: { $0.key == .outputFormat }) else { return false }

        let current = cleanBodyLines(block.body).joined(separator: " ").lowercased()
        if current.isEmpty { return true }

        let genericCues = [
            "return only the requested sections",
            "execution-oriented",
            "avoid conversational filler",
            "do not include extra sections beyond this contract"
        ]
        if genericCues.contains(where: current.contains) {
            return true
        }

        let signature: String
        switch intent {
        case .creativeStory:
            signature = "title, story"
        case .gameDesign:
            signature = "concept, rules, visual theme"
        case .softwareBuild, .general:
            return false
        }

        let desiredPrefix = outputFormatLines(for: context, text: text).first?.lowercased() ?? ""
        return !current.contains(signature) && !desiredPrefix.isEmpty && !current.contains(desiredPrefix)
    }

    private static func intentSpecificDeliverables(for intent: PromptIntent, sourceText: String) -> [String]? {
        switch intent {
        case .creativeStory:
            let subject = extractPhrase(regex: RegexBank.aboutSubject, in: sourceText) ?? "the requested subject"
            return [
                "Write one complete story about \(subject) with a clear beginning, middle, and ending.",
                "Maintain a consistent narrative voice and include concrete sensory detail.",
                "Provide a title and end with a resolved outcome tied to the central conflict."
            ]
        case .gameDesign:
            let theme = extractPhrase(regex: RegexBank.whereTheme, in: sourceText) ?? "cat/dog-themed player marks"
            return [
                "Define the game objective, board setup, turn order, and win/draw conditions.",
                "Specify how \(theme) are represented across the board and turns.",
                "Provide two example game states plus one edge-case rule clarification."
            ]
        case .softwareBuild, .general:
            return nil
        }
    }

    private static func extractPhrase(regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let captured = text[captureRange]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        return captured.isEmpty ? nil : captured
    }

    private static func constraintLines(for intent: PromptIntent) -> [String] {
        switch intent {
        case .creativeStory:
            return [
                "- Keep tone, tense, and point of view consistent.",
                "- Avoid meta commentary about the writing process.",
                "- Keep character and setting details internally consistent."
            ]
        case .gameDesign:
            return [
                "- Rules must be deterministic and unambiguous.",
                "- Define turn order, legal moves, and termination conditions explicitly.",
                "- Keep cat/dog mark mapping consistent in every example."
            ]
        case .softwareBuild, .general:
            return [
                "- Keep behavior deterministic and reproducible.",
                "- Preserve fenced code blocks and protected literals exactly."
            ]
        }
    }

    private static func successCriteriaLines(for intent: PromptIntent) -> [String] {
        switch intent {
        case .creativeStory:
            return [
                "- Story includes a clear beginning, middle, and ending.",
                "- Narrative voice and tense remain consistent throughout.",
                "- Ending resolves the main conflict without contradictions."
            ]
        case .gameDesign:
            return [
                "- Rules are complete, consistent, and testable.",
                "- Theme mapping (cats/dogs) is explicit and consistently applied.",
                "- Examples validate standard play and at least one edge case."
            ]
        case .softwareBuild, .general:
            return [
                "- Every requested section is present and complete.",
                "- Instructions are specific, testable, and unambiguous.",
                "- Output follows the required structure exactly."
            ]
        }
    }

    private static func containsHedgingLexicon(in text: String) -> Bool {
        let lowered = text.lowercased()
        let needles = ["maybe", "if possible", "try to", "possibly", "ideally", "might", "best effort", "etc"]
        return needles.contains(where: lowered.contains)
    }

    private static func containsHeading(_ heading: String, in text: String) -> Bool {
        let normalizedHeading = normalizeHeading(heading)
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            guard let parsed = parseHeading(line) else { continue }
            if normalizeHeading(parsed.title) == normalizedHeading {
                return true
            }
        }
        return false
    }

    private static func normalizeHeading(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
    }

    private static func containsAllKeywords(_ keywords: [String], in text: String) -> Bool {
        guard !keywords.isEmpty else { return true }
        let lowered = text.lowercased()
        return keywords.allSatisfy { lowered.contains($0.lowercased()) }
    }

    private static func capitalized(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }

    private static func dedupeSectionKeysPreservingOrder(_ values: [SectionKey]) -> [SectionKey] {
        var seen = Set<Int>()
        var ordered: [SectionKey] = []
        for value in values {
            if seen.insert(value.rawValue).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }

    private static func dedupePreservingOrder<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        var ordered: [T] = []
        for value in values {
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }

    private static func fingerprint(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
