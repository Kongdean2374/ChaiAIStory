import Foundation

public struct NarrativeRange: Codable, Equatable, Sendable {
    public var minimum: Int
    public var maximum: Int
    public init(minimum: Int = 150, maximum: Int = 250) { self.minimum = minimum; self.maximum = maximum }
    public func validate() throws {
        guard (20...2000).contains(minimum), (minimum...2000).contains(maximum) else {
            throw StoryError.invalid("正文長度需為 20–2000 個漢字，最少不能大於最多。")
        }
    }
    public static func legacy(_ length: Int) -> Self {
        let center = min(1600, max(30, length))
        return .init(minimum: max(20, center * 3 / 4), maximum: min(2000, center * 5 / 4))
    }
    public var preferred: ClosedRange<Int> {
        (minimum + (maximum - minimum) * 4 / 10)...(minimum + (maximum - minimum) * 7 / 10)
    }
    public var label: String { "\(minimum)～\(maximum) 字" }
    public var prompt: String {
        "全部 narrative[].text 正文合計 \(minimum)～\(maximum) 個漢字，優先約 \(preferred.lowerBound)～\(preferred.upperBound) 字。只計 Unicode 漢字（含擴展字）；標點、引號、空白、英文、數字、符號不計，choices/玩家行動/JSON/秘密不計。不要總貼著下限；用有意義的動作、對話、主角感受與下一步情境補足，禁止重複灌水或全知劇透。"
    }
}
public struct NarrativeReport: Codable, Equatable, Sendable {
    public var expected: NarrativeRange
    public var actual: Int
    public var repairCount: Int
    public var exception: String?
}
public struct NarrativeRevision: Codable, Sendable {
    public var narrative: [VisibleText]
    public init(narrative: [VisibleText]) { self.narrative = narrative }
}
public enum NarrativePolicy {
    public static func count(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { result, scalar in
            let v = scalar.value
            let han = (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v)
                || (0xF900...0xFAFF).contains(v) || (0x20000...0x2EE5F).contains(v)
                || (0x2F800...0x2FA1F).contains(v) || (0x30000...0x323AF).contains(v) || v == 0x3007
            return result + (han ? 1 : 0)
        }
    }
    public static func report(_ candidate: StoryTurnResponse, base: GameSession, repairCount: Int = 0) throws -> NarrativeReport {
        let next = try RuleValidator.apply(candidate, to: base)
        let range = base.settings.effectiveNarrativeRange
        try range.validate()
        let exception: String?
        if candidate.disposition == .rejected_invalid_request { exception = "拒絕行動" }
        else if next.dead { exception = "人生結局" }
        else if !base.world.condition.conscious && !next.world.condition.conscious { exception = "持續昏迷的感知片段" }
        else { exception = nil }
        return .init(expected: range, actual: candidate.narrative.reduce(0) { $0 + count($1.text) }, repairCount: repairCount, exception: exception)
    }
    public static func requiresRevision(_ report: NarrativeReport) -> Bool {
        report.exception == nil && !(report.expected.minimum...report.expected.maximum).contains(report.actual)
    }
    public static func validate(_ candidate: StoryTurnResponse, base: GameSession, repairCount: Int = 0) throws -> NarrativeReport {
        let result = try report(candidate, base: base, repairCount: repairCount)
        guard (0...1).contains(repairCount), !requiresRevision(result) else {
            throw StoryError.invalid("正文篇幅未達設定：預期 \(result.expected.label)，實際 \(result.actual) 字。本輪未儲存。")
        }
        return result
    }
    /// A revision can only replace prose. World commands, choices, reveals and continuity remain byte-equivalent.
    public static func revise(_ original: StoryTurnResponse, with revision: NarrativeRevision, base: GameSession) throws -> StoryTurnResponse {
        var candidate = original
        candidate.narrative = revision.narrative
        _ = try validate(candidate, base: base, repairCount: 1)
        return candidate
    }
    public static func outputBudget(range: NarrativeRange, model: String, opening: Bool = false, revision: Bool = false) -> Int {
        let reasoning = model.hasPrefix("o") || model.hasPrefix("gpt-5") || model.hasPrefix("gpt-6")
        let overhead = revision ? 1500 : opening ? 7500 : 4500
        return min(revision ? 12000 : 18000, max(3000, min(2000, max(20, range.maximum)) * 4 + overhead + (reasoning ? 2000 : 0)))
    }
}
